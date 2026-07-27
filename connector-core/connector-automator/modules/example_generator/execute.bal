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
import ballerina/lang.runtime;

import wso2/connector_automator.utils;

public function executeExampleGen(string connectorPath, string examplesDir = "") returns error? {
    string resolvedExamplesDir = examplesDir.length() > 0 ? examplesDir : connectorPath + "/examples";
    utils:logVerbose(string `connector: ${connectorPath}`);
    utils:logVerbose(string `examples output: ${resolvedExamplesDir}`);

    utils:logVerbose("analyzing connector");
    ConnectorDetails|error details = analyzeConnector(connectorPath);
    if details is error {
        utils:logError(string `connector analysis failed: ${details.message()}`);
        return details;
    }
    utils:logInfo(string `✓ connector: ${details.connectorName} (${details.apiCount} operations)`);

    utils:logVerbose("initializing AI generator");
    error? initResult = initExampleGenerator();
    if initResult is error {
        utils:logError(string `AI initialization failed: ${initResult.message()}`);
        return error("AI generator initialization failed: " + initResult.message());
    }
    utils:logVerbose("✓ AI generator initialized");

    utils:logVerbose("packing connector to local repo");
    error? packResult = packAndPushConnector(connectorPath);
    if packResult is error {
        utils:logError(string `failed to prepare connector: ${packResult.message()}`);
        return packResult;
    }
    utils:logVerbose("✓ connector packed");

    int numExamples = numberOfExamples(details.apiCount);
    utils:logVerbose(string `generating ${numExamples} example${numExamples == 1 ? "" : "s"}`);

    string[] usedFunctionNames = [];
    string[] generatedExampleNames = [];
    int successCount = 0;

    foreach int i in 1 ... numExamples {
        utils:logVerbose(string `[example ${i}/${numExamples}] generating use case`);

        json|error useCaseResponse = generateUseCaseAndFunctions(details, usedFunctionNames);
        if useCaseResponse is error {
            utils:logWarn(string `failed to generate use case for example ${i}: ${useCaseResponse.message()}`);
            continue;
        }

        string useCase = check useCaseResponse.useCase.ensureType();
        json functionNamesJson = check useCaseResponse.requiredFunctions.ensureType();
        string[] functionNames = [];

        if functionNamesJson is json[] {
            foreach json item in functionNamesJson {
                if item is string {
                    functionNames.push(item);
                }
            }
        } else {
            utils:logWarn(string `invalid function list for example ${i} — skipping`);
            continue;
        }

        usedFunctionNames.push(...functionNames);
        utils:logVerbose(string `  use case selected (${functionNames.length()} operations)`);

        string|error targetedContext = extractTargetedContext(details, functionNames);
        if targetedContext is error {
            utils:logWarn(string `failed to extract context for example ${i}: ${targetedContext.message()}`);
            continue;
        }

        string|error generatedCode = generateExampleCode(details, useCase, targetedContext);
        if generatedCode is error {
            utils:logWarn(string `failed to generate code for example ${i}: ${generatedCode.message()}`);
            continue;
        }

        string|error exampleNameResult = generateExampleName(useCase);
        string baseName;
        if exampleNameResult is error {
            utils:logVerbose(string `  name generation failed, using fallback: ${exampleNameResult.message()}`);
            baseName = "example_" + i.toString();
        } else {
            baseName = normalizeExampleName(exampleNameResult);
            if baseName.length() == 0 {
                baseName = "example_" + i.toString();
            }
        }

        string|error uniqueNameResult = resolveUniqueExampleName(
                resolvedExamplesDir, baseName, generatedExampleNames);
        if uniqueNameResult is error {
            utils:logWarn(string `failed to resolve name for example ${i}: ${uniqueNameResult.message()}`);
            continue;
        }
        string exampleName = uniqueNameResult;

        error? writeResult = writeExampleToFile(resolvedExamplesDir, exampleName, useCase, generatedCode,
                details.connectorOrg, details.connectorName, details.connectorVersion, details.connectorDistribution);
        if writeResult is error {
            utils:logWarn(string `failed to write example ${i}: ${writeResult.message()}`);
            continue;
        }
        generatedExampleNames.push(exampleName);

        runtime:sleep(10);

        string exampleDir = resolvedExamplesDir + "/" + exampleName;
        error? fixResult = fixExampleCode(exampleDir, exampleName);
        if fixResult is error {
            utils:logWarn(string `compilation fix failed for ${exampleName}: ${fixResult.message()} — may need manual review`);
        } else {
            utils:logVerbose(string `  ✓ compilation errors fixed`);
        }

        successCount += 1;
        utils:logInfo(string `✓ example ${i}/${numExamples}: ${exampleName}`);
    }

    if successCount < numExamples {
        utils:logWarn(string `${successCount}/${numExamples} examples succeeded`);
    } else {
        utils:logInfo(string `✓ all ${numExamples} example${numExamples == 1 ? "" : "s"} generated at ${resolvedExamplesDir}/`);
    }
}

function resolveUniqueExampleName(string examplesDir, string baseName,
        string[] reservedNames) returns string|error {
    string candidate = baseName;
    int suffix = 2;
    while reservedNames.indexOf(candidate) is int ||
            check file:test(examplesDir + "/" + candidate, file:EXISTS) {
        candidate = baseName + "_" + suffix.toString();
        suffix += 1;
    }
    return candidate;
}

function getExistingExampleDirectories(string examplesPath) returns string[]|error {
    boolean examplesExist = check file:test(examplesPath, file:EXISTS);
    if !examplesExist {
        return [];
    }

    file:MetaData[] exampleEntries = check file:readDir(examplesPath);
    string[] exampleNames = [];

    foreach file:MetaData entry in exampleEntries {
        if entry.dir {
            int? lastSlash = entry.absPath.lastIndexOf("/");
            string exampleName = lastSlash is int ? entry.absPath.substring(lastSlash + 1) : entry.absPath;

            string mainBalPath = entry.absPath + "/main.bal";
            string ballerinaTomlPath = entry.absPath + "/Ballerina.toml";
            boolean hasMain = check file:test(mainBalPath, file:EXISTS);
            boolean hasBallerinaToml = check file:test(ballerinaTomlPath, file:EXISTS);
            if hasMain && hasBallerinaToml {
                exampleNames.push(exampleName);
            }
        }
    }

    return exampleNames;
}

public function cleanupExistingExamples(string examplesPath) returns ExampleCleanupResult|error {
    ExampleCleanupResult result = {removed: 0, failures: []};
    if !(check file:test(examplesPath, file:EXISTS)) {
        return result;
    }
    file:MetaData[] entries = check file:readDir(examplesPath);
    foreach file:MetaData entry in entries {
        if entry.dir {
            boolean hasMain = check file:test(entry.absPath + "/main.bal", file:EXISTS);
            boolean hasBallerinaToml = check file:test(entry.absPath + "/Ballerina.toml", file:EXISTS);
            if hasMain && hasBallerinaToml {
                error? removeResult = file:remove(entry.absPath, file:RECURSIVE);
                if removeResult is error {
                    result.failures.push(string `${entry.absPath}: ${removeResult.message()}`);
                } else {
                    result.removed += 1;
                }
            }
        }
    }
    if result.removed > 0 {
        utils:logInfo(string `✓ removed ${result.removed} existing use-case example${result.removed == 1 ? "" : "s"}`);
    }
    return result;
}

public function repairExistingExamples(string connectorPath, string examplesPath) returns ExampleRepairResult|error {
    string[] exampleNames = check getExistingExampleDirectories(examplesPath);
    ExampleRepairResult result = {total: exampleNames.length(), repaired: 0, failures: []};
    if exampleNames.length() == 0 {
        utils:logVerbose("no retained use-case examples found");
        return result;
    }

    check packAndPushConnector(connectorPath);
    foreach string exampleName in exampleNames {
        string examplePath = examplesPath + "/" + exampleName;
        error? fixResult = fixExampleCode(examplePath, exampleName);
        if fixResult is error {
            result.failures.push(string `${exampleName}: ${fixResult.message()}`);
            continue;
        }
        utils:CommandResult buildResult = utils:executeBalBuild(examplePath);
        if utils:hasCompilationErrors(buildResult) {
            result.failures.push(string `${exampleName}: ${buildResult.stderr.trim()}`);
            continue;
        }
        result.repaired += 1;
        utils:logInfo(string `✓ retained example validated: ${exampleName}`);
    }
    return result;
}
