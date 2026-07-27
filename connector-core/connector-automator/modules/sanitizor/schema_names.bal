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

# Review all previously unseen component schema names and persist stable decisions.
#
# + specFilePath - Aligned OpenAPI JSON file to update
# + aiMappingsFilePath - Stable AI-generated name mappings file
# + config - Optional AI retry configuration
# + return - Schema-name processing counts or an error
public function improveSchemaNamesBatchWithRetry(string specFilePath, string aiMappingsFilePath, RetryConfig? config = ()) returns SchemaNameImprovementResult|error {

    // Read persisted AI mappings and extract schema-name mappings, if any.
    map<json> aiMappingsDocument = check readAiMappingsDocument(aiMappingsFilePath);
    map<json> persistedMappings = {};
    if aiMappingsDocument.hasKey("schemaNames") {
        json|error schemaNamesResult = aiMappingsDocument.get("schemaNames");
        if !(schemaNamesResult is map<json>) {
            return error("Invalid AI mappings file: schemaNames must be a JSON object");
        }
        persistedMappings = schemaNamesResult;
    }

    // Read the OpenAPI spec
    json|error specResult = io:fileReadJson(specFilePath);
    if specResult is error {
        return error("Failed to read OpenAPI spec file", specResult);
    }
    if !(specResult is map<json>) {
        return error("spec is not a valid JSON object");
    }
    map<json> specMap = <map<json>>specResult;

    map<map<json>> schemas = {};
    map<json>? components = ();
    if specMap.hasKey("components") {
        json|error componentsResult = specMap.get("components");
        if !(componentsResult is map<json>) {
            return error("Invalid components section in OpenAPI spec");
        }
        map<json> componentsMap = <map<json>>componentsResult;
        components = componentsMap;
        if componentsMap.hasKey("schemas") {
            json|error schemasResult = componentsMap.get("schemas");
            if !(schemasResult is map<json>) {
                return error("Invalid components.schemas section in OpenAPI spec");
            }
            map<json> schemaDefinitions = schemasResult;
            foreach string schemaName in schemaDefinitions.keys() {
                json|error schemaDefinitionResult = schemaDefinitions.get(schemaName);
                if !(schemaDefinitionResult is map<json>) {
                    return error(string `Invalid schema definition for '${schemaName}': expected a JSON object`);
                }
                schemas[schemaName] = schemaDefinitionResult;
            }
        }
    }

    int reused = 0;
    map<string> reusedMappings = {};
    SchemaRenameRequest[] requests = [];
    string[] reusedNames = [];
    string apiContext = extractApiContext(specMap);
    foreach string schemaName in schemas.keys() {
        if persistedMappings.hasKey(schemaName) {
            json|error mappedResult = persistedMappings.get(schemaName);
            if !(mappedResult is string) {
                return error(string `Invalid schema mapping for '${schemaName}': improved name must be a string`);
            }
            string mappedName = mappedResult;
            string improvedName = mappedName.trim();
            if !isValidSchemaName(improvedName) {
                return error(string `Invalid schema mapping: '${schemaName}' -> '${improvedName}'`);
            }
            reusedMappings[schemaName] = improvedName;
            reusedNames.push(improvedName);
            reused += 1;
            continue;
        }

        map<json> schemaDefinition = schemas.get(schemaName);
        requests.push({
            originalName: schemaName,
            schemaDefinition: schemaDefinition.toJsonString(),
            usageContext: extractSchemaUsageContext(schemaName, specMap)
        });
    }

    string[] reservedNames = schemas.keys();
    foreach string target in reusedNames {
        if reservedNames.indexOf(target) is () {
            reservedNames.push(target);
        }
    }

    // Create AI mapping with batch retry.
    map<string> aiMappings = {};
    int reviewed = 0;
    int startIdx = 0;
    while startIdx < requests.length() {
        int endIdx = startIdx + BATCH_SIZE;
        if endIdx > requests.length() {
            endIdx = requests.length();
        }
        SchemaRenameRequest[] batch = requests.slice(startIdx, endIdx);
        BatchRenameResponse[]|error responseResult = generateSchemaNamesBatchWithRetry(
                batch, apiContext, reservedNames, config);
        if responseResult is error {
            return error(string `Schema naming batch ${(startIdx / BATCH_SIZE) + 1} failed`, responseResult);
        }

        map<boolean> expected = {};
        foreach SchemaRenameRequest request in batch {
            expected[request.originalName] = true;
        }
        map<boolean> received = {};
        foreach BatchRenameResponse response in responseResult {
            string originalName = response.originalName;
            string improvedName = response.newName.trim();
            if !expected.hasKey(originalName) {
                return error(string `AI returned an unexpected schema name '${originalName}'`);
            }
            if received.hasKey(originalName) {
                return error(string `AI returned schema '${originalName}' more than once`);
            }
            if !isValidSchemaName(improvedName) {
                return error(string `AI returned invalid schema name '${improvedName}' for '${originalName}'`);
            }
            if improvedName != originalName && reservedNames.indexOf(improvedName) is int {
                return error(string `AI returned conflicting schema name '${improvedName}' for '${originalName}'`);
            }
            received[originalName] = true;
            aiMappings[originalName] = improvedName;
            reservedNames.push(improvedName);
            reviewed += 1;
        }
        if received.length() != batch.length() {
            return error(string `AI returned ${received.length()} schema names for a batch of ${batch.length()}`);
        }
        startIdx = endIdx;
    }

    // Merge reused and AI-generated mappings.
    map<string> currentMappings = reusedMappings;
    foreach string originalName in aiMappings.keys() {
        string? improvedName = aiMappings[originalName];
        if improvedName is string {
            currentMappings[originalName] = improvedName;
        }
    }

    // Validate the complete target namespace after all schema-name decisions are merged.
    map<string> targetOwners = {};
    foreach string schemaName in schemas.keys() {
        string targetName = currentMappings[schemaName] ?: schemaName;
        string? existingOwner = targetOwners[targetName];
        if existingOwner is string {
            return error(string `Invalid AI schema-name mappings: '${existingOwner}' and '${schemaName}' both map to '${targetName}'`);
        }
        targetOwners[targetName] = schemaName;
    }

    // Update the spec with current mapping.
    int renamed = 0;
    foreach string schemaName in schemas.keys() {
        string? improvedName = currentMappings[schemaName];
        if improvedName is string {
            if improvedName != schemaName {
                renamed += 1;
            }
        }
    }

    map<json> updatedSpec = specMap;
    if components is map<json> && currentMappings.length() > 0 {
        map<map<json>> renamedSchemas = {};
        foreach string schemaName in schemas.keys() {
            map<json> schemaDefinition = schemas.get(schemaName);
            string targetName = currentMappings[schemaName] ?: schemaName;
            renamedSchemas[targetName] = schemaDefinition;
        }
        components["schemas"] = renamedSchemas;
        specMap["components"] = components;
        updatedSpec = updateSchemaReferences(specMap, currentMappings);
    }

    map<json> mappingsToPersist = {};
    foreach string originalName in currentMappings.keys() {
        string? improvedName = currentMappings[originalName];
        if improvedName is string {
            mappingsToPersist[originalName] = improvedName;
        }
    }
    string[] mappingNames = mappingsToPersist.keys().sort(array:ASCENDING);
    map<json> sortedMappings = {};
    foreach string name in mappingNames {
        json? improvedName = mappingsToPersist[name];
        if improvedName is string {
            sortedMappings[name] = improvedName;
        }
    }
    aiMappingsDocument["schemaNames"] = sortedMappings;
    map<json> preparedMappingsDocument = prepareAiMappingsDocumentForWrite(aiMappingsDocument);
    check writeJsonAtomically(aiMappingsFilePath, preparedMappingsDocument);
    check writeJsonAtomically(specFilePath, updatedSpec);
    return {mappingsReused: reused, schemasReviewed: reviewed, schemasRenamed: renamed};
}
