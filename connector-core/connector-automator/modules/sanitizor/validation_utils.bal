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

import ballerina/regex;

// Helper function to generate unique request IDs
function generateRequestId(string schemaName, string path, string requestType) returns string {
    string cleanPath = regex:replaceAll(path, "\\.", "_");
    cleanPath = regex:replaceAll(cleanPath, "\\[", "_");
    cleanPath = regex:replaceAll(cleanPath, "\\]", "_");
    return string `${schemaName}_${requestType}_${cleanPath}`;
}

// Helper function to validate if a generated name is safe for schema naming
function isValidSchemaName(string name) returns boolean {
    // Check basic requirements for a valid schema name
    if (name.length() == 0 || name.length() > 100) {
        return false;
    }

    // Should not contain spaces, special characters that could break JSON
    if (name.includes(" ") || name.includes("\n") || name.includes("\t") ||
        name.includes("\"") || name.includes("'") || name.includes("`") ||
        name.includes("{") || name.includes("}") || name.includes("[") || name.includes("]") ||
        name.includes(",") || name.includes(":") || name.includes(";") ||
        name.includes("?") || name.includes("!") || name.includes("\\") ||
        name.includes("/") || name.includes("<") || name.includes(">")) {
        return false;
    }

    // Should start with uppercase letter (PascalCase)
    string firstChar = name.substring(0, 1);
    if (!(firstChar >= "A" && firstChar <= "Z")) {
        return false;
    }

    // Should only contain alphanumeric characters
    return regex:matches(name, "[A-Z][a-zA-Z0-9]*");
}

// Helper function to check if a name is already taken
function isNameTaken(string name, string[] existingNames, map<string> nameMapping) returns boolean {
    // Check against existing schema names
    foreach string existingName in existingNames {
        if (existingName == name) {
            return true;
        }
    }

    // Check against already mapped names
    foreach string key in nameMapping.keys() {
        string? mappedName = nameMapping[key];
        if (mappedName is string && mappedName == name) {
            return true;
        }
    }

    return false;
}

// Helper function to generate unique request IDs for operationId requests
function generateOperationRequestId(string path, string method) returns string {
    string cleanPath = regex:replaceAll(path, "[^a-zA-Z0-9]", "_");
    return string `${method}_${cleanPath}`;
}

