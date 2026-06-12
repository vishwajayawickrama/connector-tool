import connector_automator.utils;

import ballerina/file;
import ballerina/io;
import ballerina/lang.runtime;

public function executeExampleGen(string connectorPath, utils:LogLevel logLevel = "normal", boolean autoYes = false) returns error? {
    utils:logVerbose(string `connector: ${connectorPath}`, logLevel);

    if !getUserConfirmation("Proceed with example generation?", autoYes) {
        utils:logInfo("skipping example generation", logLevel);
        return;
    }

    utils:logVerbose("analyzing connector", logLevel);
    ConnectorDetails|error details = analyzeConnector(connectorPath);
    if details is error {
        utils:logError(string `connector analysis failed: ${details.message()}`);
        return details;
    }
    utils:logInfo(string `✓ connector: ${details.connectorName} (${details.apiCount} operations)`, logLevel);

    utils:logVerbose("initializing AI generator", logLevel);
    error? initResult = initExampleGenerator();
    if initResult is error {
        utils:logError(string `AI initialization failed: ${initResult.message()}`);
        return error("AI generator initialization failed: " + initResult.message());
    }
    utils:logVerbose("✓ AI generator initialized", logLevel);

    utils:logVerbose("packing connector to local repo", logLevel);
    error? packResult = packAndPushConnector(connectorPath, logLevel);
    if packResult is error {
        utils:logError(string `failed to prepare connector: ${packResult.message()}`);
        return packResult;
    }
    utils:logVerbose("✓ connector packed", logLevel);

    int numExamples = numberOfExamples(details.apiCount);
    utils:logVerbose(string `generating ${numExamples} example${numExamples == 1 ? "" : "s"}`, logLevel);

    string[] usedFunctionNames = [];
    int successCount = 0;

    foreach int i in 1 ... numExamples {
        utils:logVerbose(string `[example ${i}/${numExamples}] generating use case`, logLevel);

        json|error useCaseResponse = generateUseCaseAndFunctions(details, usedFunctionNames);
        if useCaseResponse is error {
            utils:logWarn(string `failed to generate use case for example ${i}: ${useCaseResponse.message()}`, logLevel);
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
            utils:logWarn(string `invalid function list for example ${i} — skipping`, logLevel);
            continue;
        }

        usedFunctionNames.push(...functionNames);
        utils:logVerbose(string `  use case selected (${functionNames.length()} operations)`, logLevel);

        string|error targetedContext = extractTargetedContext(details, functionNames);
        if targetedContext is error {
            utils:logWarn(string `failed to extract context for example ${i}: ${targetedContext.message()}`, logLevel);
            continue;
        }

        string|error generatedCode = generateExampleCode(details, useCase, targetedContext);
        if generatedCode is error {
            utils:logWarn(string `failed to generate code for example ${i}: ${generatedCode.message()}`, logLevel);
            continue;
        }

        string|error exampleNameResult = generateExampleName(useCase);
        string exampleName;
        if exampleNameResult is error {
            utils:logVerbose(string `  name generation failed, using fallback: ${exampleNameResult.message()}`, logLevel);
            exampleName = "example_" + i.toString();
        } else {
            exampleName = exampleNameResult;
        }

        error? writeResult = writeExampleToFile(connectorPath, exampleName, useCase, generatedCode,
            details.connectorOrg, details.connectorName, details.connectorVersion, details.connectorDistribution);
        if writeResult is error {
            utils:logWarn(string `failed to write example ${i}: ${writeResult.message()}`, logLevel);
            continue;
        }

        runtime:sleep(10);

        string exampleDir = connectorPath + "/examples/" + exampleName;
        error? fixResult = fixExampleCode(exampleDir, exampleName, logLevel);
        if fixResult is error {
            utils:logWarn(string `compilation fix failed for ${exampleName}: ${fixResult.message()} — may need manual review`, logLevel);
        } else {
            utils:logVerbose(string `  ✓ compilation errors fixed`, logLevel);
        }

        successCount += 1;
        utils:logInfo(string `✓ example ${i}/${numExamples}: ${exampleName}`, logLevel);
    }

    if successCount < numExamples {
        utils:logWarn(string `${successCount}/${numExamples} examples succeeded`, logLevel);
    } else {
        utils:logInfo(string `✓ all ${numExamples} example${numExamples == 1 ? "" : "s"} generated at ${connectorPath}/examples/`, logLevel);
    }
}

function getUserConfirmation(string message, boolean autoYes) returns boolean {
    if autoYes {
        return true;
    }
    io:fprint(io:stderr, string `${message} (y/n): `);
    string|io:Error userInput = io:readln();
    if userInput is io:Error {
        return false;
    }
    return userInput.trim().toLowerAscii() is "y"|"yes";
}

function getExistingExampleDirectories(string connectorPath) returns string[]|error {
    string examplesPath = connectorPath + "/examples";

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
            boolean hasMain = check file:test(mainBalPath, file:EXISTS);
            if hasMain {
                exampleNames.push(exampleName);
            }
        }
    }

    return exampleNames;
}

function cleanupExistingExamples(string connectorPath) returns error? {
    string examplesPath = connectorPath + "/examples";
    boolean examplesExist = check file:test(examplesPath, file:EXISTS);

    if examplesExist {
        check file:remove(examplesPath, file:RECURSIVE);
    }
    return;
}
