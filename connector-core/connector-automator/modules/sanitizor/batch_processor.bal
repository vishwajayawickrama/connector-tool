// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.
import ballerina/io;
import ballerina/lang.runtime;

import wso2/connector_automator.utils;

configurable RetryConfig retryConfig = {};

public function generateDescriptionsBatchWithRetry(DescriptionRequest[] requests, string apiContext, RetryConfig? config = ()) returns BatchDescriptionResponse[]|error {
    RetryConfig retryConf = config ?: retryConfig;

    int attempt = 0;
    while attempt <= retryConf.maxRetries {
        BatchDescriptionResponse[]|error result = generateDescriptionsBatch(requests, apiContext);

        if result is BatchDescriptionResponse[] {
            if attempt > 0 {
                utils:logVerbose(string `batch description generation succeeded after retry (attempt ${attempt})`);
            }
            return result;
        } else {
            if attempt == retryConf.maxRetries {
                utils:logError(string `batch description generation failed after all retries (${retryConf.maxRetries}): ${result.message()}`);
                return result;
            }

            if !isRetryableError(result) {
                utils:logError(string `non-retryable error in batch description generation: ${result.message()}`);
                return result;
            }

            decimal delay = calculateBackoffDelay(attempt, retryConf);
            utils:logVerbose(string `batch description generation failed, retrying (attempt ${attempt + 1}/${retryConf.maxRetries}, delay ${delay}s)`);
            runtime:sleep(delay);
            attempt += 1;
        }
    }

    return error("Unexpected error in retry logic");
}

public function generateOperationIdsBatchWithRetry(OperationIdRequest[] requests, string apiContext, string[] existingOperationIds, RetryConfig? config = ()) returns BatchOperationIdResponse[]|error {
    RetryConfig retryConf = config ?: retryConfig;

    int attempt = 0;
    while attempt <= retryConf.maxRetries {
        BatchOperationIdResponse[]|error result = generateOperationIdsBatch(requests, apiContext, existingOperationIds);

        if result is BatchOperationIdResponse[] {
            error? validationResult = validateOperationIdBatchResponses(requests, result);
            if validationResult is () {
                if attempt > 0 {
                    utils:logVerbose(string `batch operationId generation succeeded after retry (attempt ${attempt})`);
                }
                return result;
            }
            result = validationResult;
        }

        if result is error {
            if attempt == retryConf.maxRetries {
                utils:logError(string `batch operationId generation failed after all retries (${retryConf.maxRetries}): ${result.message()}`);
                return result;
            }

            if !isRetryableError(result) {
                utils:logError(string `non-retryable error in batch operationId generation: ${result.message()}`);
                return result;
            }

            decimal delay = calculateBackoffDelay(attempt, retryConf);
            utils:logVerbose(string `batch operationId generation failed, retrying (attempt ${attempt + 1}/${retryConf.maxRetries}, delay ${delay}s)`);
            runtime:sleep(delay);
            attempt += 1;
        } else {
            return error("Unexpected operationId batch validation state");
        }
    }

    return error("Unexpected error in retry logic");
}

public function generateSchemaNamesBatchWithRetry(SchemaRenameRequest[] requests, string apiContext, string[] existingNames, RetryConfig? config = ()) returns BatchRenameResponse[]|error {
    RetryConfig retryConf = config ?: retryConfig;

    int attempt = 0;
    while attempt <= retryConf.maxRetries {
        BatchRenameResponse[]|error result = generateSchemaNamesBatch(requests, apiContext, existingNames);

        if result is BatchRenameResponse[] {
            if attempt > 0 {
                utils:logVerbose(string `batch schema naming succeeded after retry (attempt ${attempt})`);
            }
            return result;
        } else {
            if attempt == retryConf.maxRetries {
                utils:logError(string `batch schema naming failed after all retries (${retryConf.maxRetries}): ${result.message()}`);
                return result;
            }

            if !isRetryableError(result) {
                utils:logError(string `non-retryable error in batch schema naming: ${result.message()}`);
                return result;
            }

            decimal delay = calculateBackoffDelay(attempt, retryConf);
            utils:logVerbose(string `batch schema naming failed, retrying (attempt ${attempt + 1}/${retryConf.maxRetries}, delay ${delay}s)`);
            runtime:sleep(delay);
            attempt += 1;
        }
    }

    return error("Unexpected error in retry logic");
}

public function addMissingDescriptionsBatchWithRetry(string specFilePath, RetryConfig? config = ()) returns DescriptionEnhancementResult|error {
    utils:logVerbose(string `processing spec for missing descriptions: ${specFilePath} (batch size ${BATCH_SIZE})`);

    json|error specResult = io:fileReadJson(specFilePath);
    if specResult is error {
        return error("Failed to read OpenAPI spec file", specResult);
    }

    json specJson = specResult;
    int descriptionsAdded = 0;

    if specJson is map<json> {
        map<json> specMap = <map<json>>specJson;
        string apiContext = extractApiContext(specJson);

        DescriptionRequest[] allRequests = [];
        map<string|string[]> requestToLocationMap = {};

        json|error componentsResult = specMap.get("components");
        if componentsResult is map<json> {
            json|error schemasResult = componentsResult.get("schemas");
            if schemasResult is map<json> {
                map<json> schemas = <map<json>>schemasResult;

                foreach string schemaName in schemas.keys() {
                    json|error schemaResult = schemas.get(schemaName);
                    if schemaResult is map<json> {
                        map<json> schemaMap = <map<json>>schemaResult;
                        collectDescriptionRequests(schemaMap, schemaName, [], allRequests, requestToLocationMap, specJson);
                    }
                }
            }
        }

        collectParameterDescriptionRequests(specJson, allRequests, requestToLocationMap);
        collectOperationDescriptionRequests(specJson, allRequests, requestToLocationMap);

        int totalRequests = allRequests.length();
        utils:logVerbose(string `collected ${totalRequests} description requests`);

        int totalBatches = 0;
        int failedBatches = 0;
        int startIdx = 0;
        while startIdx < totalRequests {
            int endIdx = startIdx + BATCH_SIZE;
            if endIdx > totalRequests {
                endIdx = totalRequests;
            }

            DescriptionRequest[] batch = allRequests.slice(startIdx, endIdx);
            int batchNum = (startIdx / BATCH_SIZE) + 1;
            totalBatches += 1;
            utils:logVerbose(string `processing descriptions batch ${batchNum} (${batch.length()} items)`);

            BatchDescriptionResponse[]|error batchResult = generateDescriptionsBatchWithRetry(batch, apiContext, config);
            if batchResult is BatchDescriptionResponse[] {
                utils:logVerbose(string `batch ${batchNum} complete (${batchResult.length()} descriptions)`);

                foreach BatchDescriptionResponse response in batchResult {
                    string|string[]? location = requestToLocationMap[response.id];
                    error? updateResult = ();
                    boolean dispatched = false;

                    if location is string[] {
                        // Schema/property description — segment-array location
                        dispatched = true;
                        json|error componentsResult2 = specMap.get("components");
                        if componentsResult2 is map<json> {
                            json|error schemasResult2 = componentsResult2.get("schemas");
                            if schemasResult2 is map<json> {
                                updateResult = updateDescriptionInSpec(<map<json>>schemasResult2, location, response.description);
                            }
                        }
                    } else if location is string {
                        dispatched = true;
                        if location.startsWith("paths.") && location.includes("parameters[name=") {
                            json|error pathsResult = specMap.get("paths");
                            if pathsResult is map<json> {
                                updateResult = updateParameterDescriptionInSpec(<map<json>>pathsResult, location, response.description);
                            }
                        } else if location.startsWith("paths.") && location.includes(".responses.") && location.endsWith(".description") {
                            json|error pathsResult = specMap.get("paths");
                            if pathsResult is map<json> {
                                updateResult = updateResponseDescriptionInSpec(<map<json>>pathsResult, location, response.description);
                            }
                        } else if location.startsWith("paths.") && !location.includes(".properties.") && !location.includes(".responses.") {
                            json|error pathsResult = specMap.get("paths");
                            if pathsResult is map<json> {
                                updateResult = updateOperationDescriptionInSpec(<map<json>>pathsResult, location, response.description);
                            }
                        }
                    }

                    if dispatched {
                        if updateResult is () {
                            descriptionsAdded += 1;
                        } else {
                            utils:logError(string `failed to apply description for ${response.id}: ${updateResult.message()}`);
                        }
                    }
                }
            } else {
                failedBatches += 1;
                utils:logError(string `descriptions batch ${batchNum} failed after all retries: ${batchResult.message()}`);
            }
            startIdx += BATCH_SIZE;
        }

        if totalBatches > 0 && failedBatches == totalBatches {
            return error(string `all ${totalBatches} description batches failed — spec not updated`);
        }
        if failedBatches > 0 {
            utils:logWarn(string `${failedBatches}/${totalBatches} description batches failed — results are partial`);
        }
    }

    check writeJsonAtomically(specFilePath, specJson);

    return {descriptionsAdded: descriptionsAdded, summariesAdded: 0};
}

public function improveOperationSummariesBatchWithRetry(string specFilePath, RetryConfig? config = ()) returns int|error {
    utils:logVerbose(string `processing spec for operation summaries: ${specFilePath} (batch size ${BATCH_SIZE})`);

    json|error specResult = io:fileReadJson(specFilePath);
    if specResult is error {
        return error("Failed to read OpenAPI spec file", specResult);
    }

    json specJson = specResult;
    int summariesImproved = 0;

    if specJson is map<json> {
        map<json> specMap = <map<json>>specJson;
        string apiContext = extractApiContext(specJson);

        DescriptionRequest[] allRequests = [];
        map<string> requestToLocationMap = {};

        collectOperationSummaryRequests(specJson, allRequests, requestToLocationMap);

        int totalRequests = allRequests.length();
        utils:logVerbose(string `collected ${totalRequests} summary requests`);

        int totalBatches = 0;
        int failedBatches = 0;
        int startIdx = 0;
        while startIdx < totalRequests {
            int endIdx = startIdx + BATCH_SIZE;
            if endIdx > totalRequests {
                endIdx = totalRequests;
            }

            DescriptionRequest[] batch = allRequests.slice(startIdx, endIdx);
            int batchNum = (startIdx / BATCH_SIZE) + 1;
            totalBatches += 1;
            utils:logVerbose(string `processing summaries batch ${batchNum} (${batch.length()} items)`);

            BatchDescriptionResponse[]|error batchResult = generateDescriptionsBatchWithRetry(batch, apiContext, config);
            if batchResult is BatchDescriptionResponse[] {
                utils:logVerbose(string `batch ${batchNum} complete (${batchResult.length()} summaries)`);

                foreach BatchDescriptionResponse response in batchResult {
                    string? location = requestToLocationMap[response.id];
                    if location is string {
                        json|error pathsResult = specMap.get("paths");
                        if pathsResult is map<json> {
                            error? updateResult = updateOperationSummaryInSpec(<map<json>>pathsResult, location, response.description);
                            if updateResult is () {
                                summariesImproved += 1;
                            } else {
                                utils:logError(string `failed to apply summary for ${response.id}: ${updateResult.message()}`);
                            }
                        }
                    }
                }
            } else {
                failedBatches += 1;
                utils:logError(string `summaries batch ${batchNum} failed after all retries: ${batchResult.message()}`);
            }
            startIdx += BATCH_SIZE;
        }

        if totalBatches > 0 && failedBatches == totalBatches {
            return error(string `all ${totalBatches} summary batches failed — spec not updated`);
        }
        if failedBatches > 0 {
            utils:logWarn(string `${failedBatches}/${totalBatches} summary batches failed — results are partial`);
        }
    }

    check writeJsonAtomically(specFilePath, specJson);

    return summariesImproved;
}
