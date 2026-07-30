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

import ballerina/file;

import wso2/connector_automator.utils;

public function executeSanitizor(string inputSpecPath, string specDir) returns error? {
    utils:logVerbose(string `input: ${utils:getDisplayPath(inputSpecPath)}`);
    utils:logVerbose(string `output: ${utils:getDisplayPath(
                    specDir + "/aligned_ballerina_openapi.json")}`);

    // Step 1: Flatten
    utils:logVerbose("flattening OpenAPI specification");
    string flattenedSpecPath = specDir;
    error? createDirResult = file:createDir(flattenedSpecPath, file:RECURSIVE);
    if createDirResult is error {
        return error("Failed to create output directory: " + flattenedSpecPath + ", reason: " + createDirResult.message());
    }
    utils:CommandResult flattenResult = utils:executeBalFlatten(inputSpecPath, flattenedSpecPath);
    if !utils:isCommandSuccessfull(flattenResult) {
        utils:logWarn(string `flatten operation failed: ${flattenResult.stderr.trim()}`);
    } else {
        utils:logVerbose("  spec flattened");
    }

    // Step 2: Align
    utils:logVerbose("aligning OpenAPI specification");
    string alignedSpecPath = specDir;

    string flattenedSpec;
    if isYamlFormat(inputSpecPath) {
        string yamlFlattenedSpec = flattenedSpecPath + "/flattened_openapi.yaml";
        string ymlFlattenedSpec = flattenedSpecPath + "/flattened_openapi.yml";
        boolean|file:Error yamlExists = file:test(yamlFlattenedSpec, file:EXISTS);
        if yamlExists is boolean && yamlExists {
            flattenedSpec = yamlFlattenedSpec;
        } else {
            boolean|file:Error ymlExists = file:test(ymlFlattenedSpec, file:EXISTS);
            if ymlExists is boolean && ymlExists {
                flattenedSpec = ymlFlattenedSpec;
            } else {
                flattenedSpec = yamlFlattenedSpec;
            }
        }
    } else {
        flattenedSpec = flattenedSpecPath + "/flattened_openapi.json";
    }

    utils:CommandResult alignResult = utils:executeBalAlign(flattenedSpec, alignedSpecPath);
    if !utils:isCommandSuccessfull(alignResult) {
        utils:logWarn(string `align operation failed: ${alignResult.stderr.trim()}`);
    } else {
        utils:logVerbose("  spec aligned");
    }

    if isYamlFormat(inputSpecPath) {
        utils:logVerbose("converting aligned YAML spec to JSON");
        error? conversionResult = convertAlignedYamlToJson(alignedSpecPath);
        if conversionResult is error {
            utils:logWarn(string `YAML to JSON conversion failed: ${conversionResult.message()}`);
            return error("YAML to JSON conversion failed: " + conversionResult.message());
        }
        utils:logVerbose("  YAML spec converted to JSON");
    }

    string alignedSpec = alignedSpecPath + "/aligned_ballerina_openapi.json";
    string aiMappingsPath = specDir + "/ai-mappings.json";

    // Step 3: Add missing descriptions
    utils:logVerbose("enhancing field descriptions");
    DescriptionEnhancementResult|error descriptionsResult = addMissingDescriptionsBatchWithRetry(alignedSpec);
    if descriptionsResult is error {
        utils:logWarn(string `description enhancement failed: ${descriptionsResult.message()}`);
    } else {
        utils:logInfo(string `  added ${descriptionsResult.descriptionsAdded} missing description${descriptionsResult.descriptionsAdded == 1 ? "" : "s"}`);
    }

    // Step 4: Improve operation summaries (uses descriptions added in Step 3 as context)
    utils:logVerbose("improving operation summaries");
    int|error summariesResult = improveOperationSummariesBatchWithRetry(alignedSpec);
    if summariesResult is error {
        utils:logWarn(string `summary improvement failed: ${summariesResult.message()}`);
    } else {
        utils:logInfo(string `  updated ${summariesResult} operation summar${summariesResult == 1 ? "y" : "ies"}`);
    }

    // Step 5: Improve operationIds (uses descriptions and summaries from Steps 3-4 as context)
    utils:logVerbose("improving operationIds");
    OperationIdImprovementResult|error operationIdResult = improveOperationIdsBatchWithRetry(alignedSpec, aiMappingsPath);
    if operationIdResult is error {
        return error("OperationId improvement failed", operationIdResult);
    } else {
        utils:logInfo(string `  improved ${operationIdResult.operationIdsChanged} operationId${operationIdResult.operationIdsChanged == 1 ? "" : "s"}`);
        if operationIdResult.operationsPending > 0 {
            utils:logWarn(string `  ${operationIdResult.operationsPending} operationId${operationIdResult.operationsPending == 1 ? "" : "s"} pending after ${operationIdResult.failedBatches} failed batch${operationIdResult.failedBatches == 1 ? "" : "es"}`);
        }
    }

    // Step 6: Stable schema-name improvement
    utils:logVerbose("improving schema names");
    SchemaNameImprovementResult|error schemaRenameResult = improveSchemaNamesBatchWithRetry(alignedSpec, aiMappingsPath);
    if schemaRenameResult is error {
        return error("Schema-name improvement failed", schemaRenameResult);
    } else {
        utils:logInfo(string `  improved ${schemaRenameResult.schemasRenamed} schema name${schemaRenameResult.schemasRenamed == 1 ? "" : "s"}`);
    }
}
