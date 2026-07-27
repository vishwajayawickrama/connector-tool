// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/io;
import ballerina/lang.array;

import wso2/connector_automator.utils;

function getHttpMethods() returns string[] {
    return ["get", "post", "put", "delete", "patch", "head", "options", "trace"];
}

function parseOperationIdMappings(map<json> aiMappingsDocument) returns map<map<string>>|error {
    if !aiMappingsDocument.hasKey("operationIds") {
        return {};
    }

    json|error operationIdsResult = aiMappingsDocument.get("operationIds");
    if !(operationIdsResult is map<json>) {
        return error("Invalid AI mappings file: operationIds must be a JSON object");
    }

    string[] httpMethods = getHttpMethods();
    map<map<string>> parsedMappings = {};
    foreach string path in operationIdsResult.keys() {
        json|error pathMappingsResult = operationIdsResult.get(path);
        if !(pathMappingsResult is map<json>) {
            return error(string `Invalid operationId mapping for '${path}': methods must be a JSON object`);
        }

        map<string> methodMappings = {};
        foreach string method in pathMappingsResult.keys() {
            if httpMethods.indexOf(method) is () {
                return error(string `Invalid operationId mapping for '${path}': unsupported method '${method}'`);
            }
            json|error operationIdResult = pathMappingsResult.get(method);
            if !(operationIdResult is string) || operationIdResult.trim().length() == 0 {
                return error(string `Invalid operationId mapping for '${method} ${path}': operationId must be a non-empty string`);
            }
            methodMappings[method] = operationIdResult.trim();
        }
        parsedMappings[path] = methodMappings;
    }
    return parsedMappings;
}

function restorePersistedOperationIds(map<json> paths,
        map<map<string>> persistedMappings) returns map<map<string>>|error {
    map<map<string>> activeMappings = {};
    map<string> targetOwners = {};
    string[] httpMethods = getHttpMethods();

    foreach string path in paths.keys() {
        json|error pathItemResult = paths.get(path);
        if !(pathItemResult is map<json>) {
            continue;
        }
        map<string>? persistedMethods = persistedMappings[path];
        if persistedMethods is () {
            continue;
        }

        map<json> pathItem = pathItemResult;
        foreach string method in httpMethods {
            if !pathItem.hasKey(method) {
                continue;
            }
            string? persistedId = persistedMethods[method];
            if persistedId is () {
                continue;
            }

            string? existingOwner = targetOwners[persistedId];
            if existingOwner is string {
                return error(string `Invalid AI operationId mappings: '${existingOwner}' and '${method} ${path}' both map to '${persistedId}'`);
            }
            check updateOperationIdInSpec(paths, path, method, persistedId);
            targetOwners[persistedId] = string `${method} ${path}`;
            putOperationIdMapping(activeMappings, path, method, persistedId);
        }
    }
    return activeMappings;
}

function validateOperationIdBatchResponses(OperationIdRequest[] requests,
        BatchOperationIdResponse[] responses) returns error? {
    map<boolean> expected = {};
    foreach OperationIdRequest request in requests {
        expected[request.id] = true;
    }

    map<boolean> received = {};
    foreach BatchOperationIdResponse response in responses {
        if !expected.hasKey(response.id) {
            return error(string `Invalid batch operationId response: unexpected request ID '${response.id}'`);
        }
        if received.hasKey(response.id) {
            return error(string `Invalid batch operationId response: duplicate request ID '${response.id}'`);
        }
        if response.operationId.trim().length() == 0 {
            return error(string `Invalid batch operationId response: empty operationId for '${response.id}'`);
        }
        received[response.id] = true;
    }
    if received.length() != requests.length() {
        return error(string `Invalid batch operationId response: received ${received.length()} decisions for ${requests.length()} requests`);
    }
}

function buildSortedOperationIdMappings(map<map<string>> currentMappings) returns map<json> {
    map<json> sortedMappings = {};
    string[] paths = currentMappings.keys().sort(array:ASCENDING);
    string[] httpMethods = getHttpMethods();
    foreach string path in paths {
        map<string>? currentMethods = currentMappings[path];
        if currentMethods is map<string> {
            map<json> sortedMethods = {};
            foreach string method in httpMethods {
                string? operationId = currentMethods[method];
                if operationId is string {
                    sortedMethods[method] = operationId;
                }
            }
            sortedMappings[path] = sortedMethods;
        }
    }
    return sortedMappings;
}

function putOperationIdMapping(map<map<string>> mappings, string path, string method, string operationId) {
    map<string> methodMappings = mappings[path] ?: {};
    methodMappings[method] = operationId;
    mappings[path] = methodMappings;
}

function collectPersistedOperationIds(map<map<string>> mappings) returns string[] {
    string[] operationIds = [];
    foreach string path in mappings.keys() {
        map<string>? methodMappings = mappings[path];
        if methodMappings is map<string> {
            foreach string method in getHttpMethods() {
                string? operationId = methodMappings[method];
                if operationId is string {
                    operationIds.push(operationId);
                }
            }
        }
    }
    return operationIds;
}

function warnOnDuplicateOperationIds(map<json> paths) {
    map<string[]> seenIds = {};
    foreach string path in paths.keys() {
        json|error pathItemResult = paths.get(path);
        if pathItemResult is map<json> {
            foreach string method in getHttpMethods() {
                if pathItemResult.hasKey(method) {
                    json|error operationResult = pathItemResult.get(method);
                    if operationResult is map<json> {
                        json|error operationIdResult = operationResult.get("operationId");
                        if operationIdResult is string {
                            string[] locations = seenIds[operationIdResult] ?: [];
                            locations.push(string `${method.toUpperAscii()} ${path}`);
                            seenIds[operationIdResult] = locations;
                        }
                    }
                }
            }
        }
    }

    foreach string operationId in seenIds.keys() {
        string[] locations = seenIds[operationId] ?: [];
        if locations.length() > 1 {
            utils:logWarn(string `duplicate operationId "${operationId}" at: ${string:'join(", ", ...locations)}`);
        }
    }
}

# Review all previously unseen operation IDs and persist stable decisions.
#
# + specFilePath - Aligned OpenAPI JSON file to update
# + aiMappingsFilePath - Stable AI-generated mappings file
# + config - Optional AI retry configuration
# + return - Operation-ID processing counts or an error
public function improveOperationIdsBatchWithRetry(string specFilePath, string aiMappingsFilePath, RetryConfig? config = ()) returns OperationIdImprovementResult|error {

    map<json> aiMappingsDocument = check readAiMappingsDocument(aiMappingsFilePath);
    map<map<string>> persistedMappings = check parseOperationIdMappings(aiMappingsDocument);

    json specResult = check io:fileReadJson(specFilePath);
    if !(specResult is map<json>) {
        return error("spec is not a valid JSON object");
    }
    map<json> specMap = specResult;

    json|error pathsResult = specMap.get("paths");
    if !(pathsResult is map<json>) {
        return error("No paths section found in OpenAPI spec");
    }
    map<json> paths = pathsResult;
    map<map<string>> currentMappings = check restorePersistedOperationIds(paths, persistedMappings);
    int mappingsReused = 0;
    foreach string path in currentMappings.keys() {
        map<string>? methodMappings = currentMappings[path];
        if methodMappings is map<string> {
            mappingsReused += methodMappings.length();
        }
    }

    string[] reservedOperationIds = collectPersistedOperationIds(currentMappings);
    OperationIdRequest[] requests = [];
    map<OperationLocation> requestLocations = {};
    string apiContext = extractApiContext(specMap);
    collectOperationIdRequests(paths, requests, requestLocations, apiContext, currentMappings);

    map<OperationIdRequest> requestsById = {};
    foreach OperationIdRequest request in requests {
        requestsById[request.id] = request;
    }

    int operationsReviewed = 0;
    int operationIdsChanged = 0;
    int operationsPending = 0;
    int failedBatches = 0;
    int totalBatches = 0;
    int startIdx = 0;
    while startIdx < requests.length() {
        int endIdx = startIdx + BATCH_SIZE;
        if endIdx > requests.length() {
            endIdx = requests.length();
        }
        OperationIdRequest[] batch = requests.slice(startIdx, endIdx);
        int batchNum = (startIdx / BATCH_SIZE) + 1;
        totalBatches += 1;
        utils:logVerbose(string `processing operationId batch ${batchNum} (${batch.length()} operations)`);

        BatchOperationIdResponse[]|error batchResult = generateOperationIdsBatchWithRetry(
                batch, apiContext, reservedOperationIds, config);
        if batchResult is BatchOperationIdResponse[] {
            foreach BatchOperationIdResponse response in batchResult {
                OperationLocation? location = requestLocations[response.id];
                OperationIdRequest? request = requestsById[response.id];
                if location is OperationLocation && request is OperationIdRequest {
                    string requestedId = response.operationId.trim();
                    string finalId = requestedId;
                    int counter = 1;
                    while reservedOperationIds.indexOf(finalId) is int {
                        finalId = requestedId + counter.toString();
                        counter += 1;
                    }
                    check updateOperationIdInSpec(paths, location.path, location.method, finalId);
                    putOperationIdMapping(currentMappings, location.path, location.method, finalId);
                    reservedOperationIds.push(finalId);
                    operationsReviewed += 1;
                    if request.currentOperationId is () || request.currentOperationId != finalId {
                        operationIdsChanged += 1;
                    }
                }
            }
        } else {
            failedBatches += 1;
            operationsPending += batch.length();
            utils:logError(string `operationId batch ${batchNum} failed after all retries: ${batchResult.message()}`);
        }
        startIdx = endIdx;
    }

    if totalBatches > 0 && failedBatches == totalBatches {
        return error(string `all ${totalBatches} operationId batches failed — spec and mappings not updated`);
    }
    if failedBatches > 0 {
        utils:logWarn(string `${failedBatches}/${totalBatches} operationId batches failed — results are partial`);
    }

    warnOnDuplicateOperationIds(paths);
    aiMappingsDocument["operationIds"] = buildSortedOperationIdMappings(currentMappings);
    map<json> preparedMappingsDocument = prepareAiMappingsDocumentForWrite(aiMappingsDocument);
    check writeJsonAtomically(aiMappingsFilePath, preparedMappingsDocument);
    check writeJsonAtomically(specFilePath, specMap);

    return {
        mappingsReused,
        operationsReviewed,
        operationIdsChanged,
        operationsPending,
        failedBatches
    };
}
