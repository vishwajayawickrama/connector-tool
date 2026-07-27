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

import ballerina/lang.regexp;

import wso2/connector_automator.utils;

// Helper function to update description in spec using a segment-array location.
// Segments (e.g. ["User", "properties", "user.name"]) are pre-split so property
// names containing dots navigate correctly.
function updateDescriptionInSpec(map<json> schemas, string[] pathParts, string description) returns error? {
    if pathParts.length() == 0 {
        return error("Empty description location");
    }

    string schemaName = pathParts[0];
    json|error schemaResult = schemas.get(schemaName);
    if !(schemaResult is map<json>) {
        return error("Could not find schema at location: " + schemaName);
    }

    map<json> schemaMap = <map<json>>schemaResult;
    if pathParts.length() == 1 {
        // Schema-level description — modifying the map reference in place
        schemaMap["description"] = description;
        return ();
    }

    return updateNestedDescription(schemaMap, pathParts, 1, description);
}

// Searches a parameter array for a matching entry and updates its description.
// Returns true if a match was found and updated.
function findAndUpdateParam(json[] params, string paramName, string paramIn, string description) returns boolean {
    foreach json param in params {
        if !(param is map<json>) {
            continue;
        }
        map<json> paramMap = <map<json>>param;
        boolean nameMatches = paramMap.hasKey("name") && paramMap.get("name") == paramName;
        boolean inMatches = paramIn == "" || (paramMap.hasKey("in") && paramMap.get("in") == paramIn);
        if nameMatches && inMatches {
            paramMap["description"] = description;
            return true;
        }
    }
    return false;
}

// Helper function to update parameter description in spec
function updateParameterDescriptionInSpec(map<json> paths, string location, string description) returns error? {
    // Parse location: paths.{path}.{method}.parameters[name={paramName}] or parameters[name={paramName},in={paramIn}]
    if !location.startsWith("paths.") {
        return error("Could not find parameter at location: " + location);
    }

    string locationWithoutPrefix = location.substring(6); // Remove "paths."

    // Anchor on ".parameters[" rather than the last dot.
    // Using lastIndexOf(".") would absorb ".{method}" into the path segment because
    // the last dot in "/{path}.{method}.parameters[...]" sits before "parameters", not before the method.
    int? paramsBracketStart = locationWithoutPrefix.indexOf(".parameters[");
    if !(paramsBracketStart is int) {
        return error("Could not find parameter at location: " + location);
    }

    string pathAndMethod = locationWithoutPrefix.substring(0, paramsBracketStart);
    string paramLocation = locationWithoutPrefix.substring(paramsBracketStart + 1); // "parameters[name=...]"

    if !paramLocation.startsWith("parameters[name=") || !paramLocation.endsWith("]") {
        return error("Could not find parameter at location: " + location);
    }

    // Split pathAndMethod → path + method using the last dot
    int? lastDot = pathAndMethod.lastIndexOf(".");
    if !(lastDot is int) {
        return error("Could not find parameter at location: " + location);
    }

    string path = pathAndMethod.substring(0, lastDot);
    string method = pathAndMethod.substring(lastDot + 1);

    string inner = paramLocation.substring(16, paramLocation.length() - 1);
    string paramName = inner;
    string paramIn = "";
    int? commaPos = inner.indexOf(",in=");
    if commaPos is int {
        paramName = inner.substring(0, commaPos);
        paramIn = inner.substring(commaPos + 4);
    }

    json|error pathItem = paths.get(path);
    if !(pathItem is map<json>) {
        return error("Could not find parameter at location: " + location);
    }
    map<json> pathItemMap = <map<json>>pathItem;

    if !pathItemMap.hasKey(method) {
        return error("Could not find parameter at location: " + location);
    }
    json|error operation = pathItemMap.get(method);
    if !(operation is map<json>) {
        return error("Could not find parameter at location: " + location);
    }
    map<json> operationMap = <map<json>>operation;

    // Check operation-level parameters first, then fall back to path-level
    json|error opParams = operationMap.get("parameters");
    if opParams is json[] && findAndUpdateParam(opParams, paramName, paramIn, description) {
        return ();
    }

    json|error pathParams = pathItemMap.get("parameters");
    if pathParams is json[] && findAndUpdateParam(pathParams, paramName, paramIn, description) {
        return ();
    }

    return error("Could not find parameter at location: " + location);
}

// Updates the description of an operation request body.
function updateRequestBodyDescriptionInSpec(map<json> paths, string location, string description) returns error? {
    string suffix = ".requestBody";
    if !location.startsWith("paths.") || !location.endsWith(suffix) {
        return error("Could not find request body at location: " + location);
    }

    string pathAndMethod = location.substring(6, location.length() - suffix.length());
    int? lastDot = pathAndMethod.lastIndexOf(".");
    if !(lastDot is int) {
        return error("Could not find request body at location: " + location);
    }

    string path = pathAndMethod.substring(0, lastDot);
    string method = pathAndMethod.substring(lastDot + 1);
    if !paths.hasKey(path) {
        return error("Could not find request body path at location: " + location);
    }
    json|error pathItemResult = paths.get(path);
    if !(pathItemResult is map<json>) {
        return error("Could not find request body path at location: " + location);
    }
    map<json> pathItem = <map<json>>pathItemResult;
    if !pathItem.hasKey(method) {
        return error("Could not find request body operation at location: " + location);
    }
    json|error operationResult = pathItem.get(method);
    if !(operationResult is map<json>) {
        return error("Could not find request body operation at location: " + location);
    }
    map<json> operation = <map<json>>operationResult;
    if !operation.hasKey("requestBody") {
        return error("Could not find request body at location: " + location);
    }
    json|error requestBodyResult = operation.get("requestBody");
    if !(requestBodyResult is map<json>) {
        return error("Could not find request body at location: " + location);
    }

    map<json> requestBody = <map<json>>requestBodyResult;
    requestBody["description"] = description;
    return ();
}

// Updates the description of an API-key security scheme.
function updateSecuritySchemeDescriptionInSpec(map<json> securitySchemes, string location,
        string description) returns error? {
    string prefix = "components.securitySchemes.";
    if !location.startsWith(prefix) || location.length() == prefix.length() {
        return error("Could not find security scheme at location: " + location);
    }

    string schemeName = location.substring(prefix.length());
    if !securitySchemes.hasKey(schemeName) {
        return error("Could not find security scheme at location: " + location);
    }
    json|error schemeResult = securitySchemes.get(schemeName);
    if !(schemeResult is map<json>) {
        return error("Could not find security scheme at location: " + location);
    }

    map<json> scheme = <map<json>>schemeResult;
    scheme["description"] = description;
    return ();
}

// Helper function to update operation description in spec
function updateOperationDescriptionInSpec(map<json> paths, string location, string description) returns error? {
    // Parse location: paths.{path}.{method}
    if location.startsWith("paths.") {
        string locationWithoutPrefix = location.substring(6); // Remove "paths."

        // Use last dot to split path and method (handles dots inside path)
        int? lastDot = locationWithoutPrefix.lastIndexOf(".");
        if lastDot is int {
            string path = locationWithoutPrefix.substring(0, lastDot);
            string method = locationWithoutPrefix.substring(lastDot + 1);

            json|error pathItem = paths.get(path);
            if pathItem is map<json> {
                map<json> pathItemMap = <map<json>>pathItem;

                if pathItemMap.hasKey(method) {
                    json|error operation = pathItemMap.get(method);
                    if operation is map<json> {
                        map<json> operationMap = <map<json>>operation;
                        operationMap["description"] = description;
                        return ();
                    }
                }
            }
        }
    }

    return error("Could not find operation at location: " + location);
}

// Helper function to update operation summary in spec
function updateOperationSummaryInSpec(map<json> paths, string location, string summary) returns error? {
    // Parse location: paths.{path}.{method}.summary
    if location.startsWith("paths.") && location.endsWith(".summary") {
        string locationWithoutPrefix = location.substring(6); // Remove "paths."
        // Strip trailing ".summary" (8 chars) before the last-dot split, otherwise
        // "summary" itself would be mistaken for the method.
        string pathAndMethod = locationWithoutPrefix.substring(0, locationWithoutPrefix.length() - 8);

        int? lastDot = pathAndMethod.lastIndexOf(".");
        if lastDot is int {
            string path = pathAndMethod.substring(0, lastDot);
            string method = pathAndMethod.substring(lastDot + 1);

            json|error pathItem = paths.get(path);
            if pathItem is map<json> {
                map<json> pathItemMap = <map<json>>pathItem;

                if pathItemMap.hasKey(method) {
                    json|error operation = pathItemMap.get(method);
                    if operation is map<json> {
                        map<json> operationMap = <map<json>>operation;

                        string cappedSummary = summary.trim();
                        if cappedSummary.endsWith(".") {
                            cappedSummary = cappedSummary.substring(0, cappedSummary.length() - 1).trim();
                        }

                        operationMap["summary"] = cappedSummary;
                        return ();
                    }
                }
            }
        }
    }

    return error("Could not find operation at location: " + location);
}

// Recursive helper to safely update nested descriptions
function updateNestedDescription(map<json> current, string[] pathParts, int index, string description) returns error? {
    if index == pathParts.length() {
        // We've reached the target - add description
        current["description"] = description;
        return ();
    }

    string part = pathParts[index];

    if part.includes("[") {
        // Handle array indices like "allOf[0]"
        string[] indexParts = regexp:split(re `\[`, part);
        string arrayName = indexParts[0];
        string indexStr = regexp:replaceAll(re `\]`, indexParts[1], "");
        int|error indexResult = int:fromString(indexStr);

        if indexResult is int {
            json|error arrayResult = current.get(arrayName);
            if arrayResult is json[] {
                json[] array = arrayResult;
                if indexResult < array.length() {
                    json item = array[indexResult];
                    if item is map<json> {
                        return updateNestedDescription(<map<json>>item, pathParts, index + 1, description);
                    } else {
                        return error("Array item at index is not a JSON object: " + part);
                    }
                } else {
                    return error("Array index out of bounds: " + part);
                }
            } else {
                return error("Could not find array field: " + arrayName);
            }
        } else {
            return error("Invalid array index in part: " + part, indexResult);
        }
    } else {
        json|error nextResult = current.get(part);
        if nextResult is map<json> {
            return updateNestedDescription(<map<json>>nextResult, pathParts, index + 1, description);
        } else if nextResult is error {
            return error("Could not find field: " + part, nextResult);
        } else {
            return error("Field is not a JSON object: " + part);
        }
    }
}

# Updates the `operationId` of an operation in an OpenAPI paths map.
#
# + paths - The OpenAPI `paths` object as a mutable JSON map
# + path - The path key as it appears in the spec (e.g. `"/pets/{id}"`)
# + method - The HTTP method in lowercase (e.g. `"get"`, `"delete"`)
# + operationId - The new operation ID to assign
# + return - An error if the operation could not be found
function updateOperationIdInSpec(map<json> paths, string path, string method, string operationId) returns error? {
    json|error pathItem = paths.get(path);
    if pathItem is map<json> {
        map<json> pathItemMap = <map<json>>pathItem;

        if pathItemMap.hasKey(method) {
            json|error operation = pathItemMap.get(method);
            if operation is map<json> {
                map<json> operationMap = <map<json>>operation;
                operationMap["operationId"] = operationId;
                return ();
            }
        }
    }
    return error("Could not find operation at: " + method + " " + path);
}

// Helper function to update schema references throughout a JSON object.
function updateSchemaReferences(map<json> jsonData, map<string> nameMapping) returns map<json> {
    map<json> resultMap = {};

    foreach string key in jsonData.keys() {
        json|error value = jsonData.get(key);
        if value is json {
            if key == "$ref" && value is string {
                string refValue = value;
                if refValue.startsWith("#/components/schemas/") {
                    string schemaName = refValue.substring(21);
                    string? newName = nameMapping[schemaName];
                    if newName is string {
                        string newRef = "#/components/schemas/" + newName;
                        resultMap[key] = newRef;
                        utils:logVerbose(string `updated schema ref: ${refValue} → ${newRef}`);
                    } else {
                        resultMap[key] = value;
                    }
                } else {
                    resultMap[key] = value;
                }
            } else {
                resultMap[key] = updateSchemaReferencesInValue(value, nameMapping);
            }
        }
    }

    return resultMap;
}

// Nested JSON values may be objects, arrays, or primitives.
function updateSchemaReferencesInValue(json jsonData, map<string> nameMapping) returns json {
    if jsonData is map<json> {
        return updateSchemaReferences(jsonData, nameMapping);
    } else if jsonData is json[] {
        json[] resultArray = [];
        foreach json item in jsonData {
            resultArray.push(updateSchemaReferencesInValue(item, nameMapping));
        }
        return resultArray;
    }
    return jsonData;
}

// Helper function to update response description in spec
function updateResponseDescriptionInSpec(map<json> paths, string location, string description) returns error? {
    // Parse location: paths.{path}.{method}.responses.{responseCode}.description
    if location.startsWith("paths.") {
        string locationWithoutPrefix = location.substring(6); // Remove "paths."

        // Split by dots, but be careful with path segments that might contain dots
        string[] locationParts = regexp:split(re `\.`, locationWithoutPrefix);

        if locationParts.length() >= 5 { // minimum: path, method, "responses", responseCode, "description"
            // Last three parts are always "responses", responseCode, "description"
            int responsesIndex = locationParts.length() - 3;
            int responseCodeIndex = locationParts.length() - 2;
            int descriptionIndex = locationParts.length() - 1;

            if locationParts[responsesIndex] == "responses" && locationParts[descriptionIndex] == "description" {
                string responseCode = locationParts[responseCodeIndex];

                // Reconstruct path and method (everything before "responses")
                string[] pathAndMethodParts = locationParts.slice(0, responsesIndex);

                // Last part is method, rest is path
                string method = pathAndMethodParts[pathAndMethodParts.length() - 1];
                string[] pathParts = pathAndMethodParts.slice(0, pathAndMethodParts.length() - 1);
                string path = string:'join(".", ...pathParts);

                json|error pathItem = paths.get(path);
                if pathItem is map<json> {
                    map<json> pathItemMap = <map<json>>pathItem;

                    if pathItemMap.hasKey(method) {
                        json|error operation = pathItemMap.get(method);
                        if operation is map<json> {
                            map<json> operationMap = <map<json>>operation;

                            if operationMap.hasKey("responses") {
                                json|error responsesResult = operationMap.get("responses");
                                if responsesResult is map<json> {
                                    map<json> responses = <map<json>>responsesResult;

                                    if responses.hasKey(responseCode) {
                                        json|error responseResult = responses.get(responseCode);
                                        if responseResult is map<json> {
                                            map<json> response = <map<json>>responseResult;
                                            response["description"] = description;
                                            return ();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    return error("Could not find response at location: " + location);
}
