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

import wso2/connector_automator.code_fixer;
import wso2/connector_automator.utils;

import ballerina/lang.regexp;

// Unified entry point: dispatches to OpenAPI (mock + live) or SDK (live only) test generation.
public function executeTestGen(string workflowType, string connectorPath, string specPath) returns error? {
    match workflowType {
        "openapi" => {
            return executeOpenApiTestGen(connectorPath, specPath);
        }
        "sdk" => {
            return executeSdkTestGen(connectorPath, specPath);
        }
        _ => {
            return error(string `Unknown workflow type: '${workflowType}'. Use 'openapi' or 'sdk'.`);
        }
    }
}

// Runs the generated tests and attempts to repair test failures until they pass or no progress can be made.
public function validateGeneratedTests(string ballerinaDir) returns TestValidationResult|error {
    utils:CommandResult testResult = utils:executeCommand("bal test", ballerinaDir, logFailureDetails = false);
    if testResult.success {
        return {success: true, attempts: 0, stdout: testResult.stdout, stderr: testResult.stderr};
    }

    int attempts = 0;
    string previousDiagnostics = "";
    boolean retryRejectedRepair = false;
    int iterationLimit = code_fixer:getConfiguredMaxIterations();
    while attempts < iterationLimit {
        string diagnostics = string `${testResult.stderr}\n${testResult.stdout}`;
        if attempts > 0 && diagnostics == previousDiagnostics && !retryRejectedRepair {
            utils:logWarn("`bal test` diagnostics did not change — stopping test repair");
            break;
        }
        retryRejectedRepair = false;
        previousDiagnostics = diagnostics;
        attempts += 1;
        string progress = attempts == 1 ? "test validation failed" : "test validation still fails";
        utils:logVerbose(string `${progress}; attempting repair ${attempts}/${iterationLimit}`);

        code_fixer:TestRepairResult|error repairResult =
            code_fixer:fixBalTestFailure(ballerinaDir, testResult, attempts);
        if repairResult is error {
            if repairResult.detail()["retryable"] is boolean {
                retryRejectedRepair = true;
                continue;
            }
            return repairResult;
        }
        if !repairResult.applied {
            utils:logWarn("AI produced no applicable test changes — stopping test repair");
            break;
        }

        testResult = utils:executeCommand("bal test", ballerinaDir, logFailureDetails = false);
        if testResult.success {
            return {success: true, attempts, stdout: testResult.stdout, stderr: testResult.stderr};
        }
    }

    return {success: false, attempts, stdout: testResult.stdout, stderr: testResult.stderr};
}

// SDK live-test execution flow (no mock server; live API tests only).
function executeSdkTestGen(string connectorPath, string specPath) returns error? {
    utils:logVerbose(string `connector: ${connectorPath}`);
    utils:logVerbose(string `spec: ${specPath}`);

    check utils:validateApiKey();

    utils:logVerbose("initializing AI service");
    error? initResult = utils:initAIService();
    if initResult is error {
        utils:logError(string `AI initialization failed: ${initResult.message()}`);
        return initResult;
    }
    utils:logVerbose("✓ AI service initialized");

    utils:logVerbose("preparing live test operation scope");
    int operationCount = check sdkCountOperationsInSpec(specPath);
    string[]? selectedOperationIds = ();

    if operationCount > SDK_MAX_OPERATIONS {
        string operationsList = check sdkSelectOperationsUsingAI(specPath);
        string[] rawIds = regexp:split(re `,`, operationsList);
        string[] trimmedIds = [];
        foreach string id in rawIds {
            string trimmedId = id.trim();
            if trimmedId.length() > 0 {
                trimmedIds.push(trimmedId);
            }
        }
        selectedOperationIds = trimmedIds;
        utils:logVerbose(string `selected ${trimmedIds.length()} operations`);
    }
    utils:logVerbose("✓ operation scope prepared");

    utils:logVerbose("generating live test file");
    error? testGenResult = sdkGenerateTestFile(connectorPath, selectedOperationIds);
    if testGenResult is error {
        utils:logError(string `test file generation failed: ${testGenResult.message()}`);
        return testGenResult;
    }
    utils:logVerbose("✓ test file generated");

    utils:logVerbose("fixing compilation errors");
    error? fixResult = sdkFixTestFileErrors(connectorPath);
    if fixResult is error {
        utils:logWarn(string `some compilation errors remain: ${fixResult.message()} — manual intervention may be required`);
    } else {
        utils:logVerbose("✓ compilation errors fixed");
    }

    utils:logInfo(string `✓ SDK tests generated at ${connectorPath}/ballerina/tests/`);
}

// OpenAPI workflow: mock server + live tests.
public function executeOpenApiTestGen(string connectorPath, string specPath) returns error? {
    utils:logVerbose(string `connector: ${connectorPath}`);
    utils:logVerbose(string `spec: ${specPath}`);

    // AI service validation and intialization.
    check utils:validateApiKey();
    error? initResult = utils:initAIService();
    if initResult is error {
        utils:logError(string `AI initialization failed: ${initResult.message()}`);
        return initResult;
    }

    // Compute operation scope.
    int operationCount = check countOperationsInSpec(specPath);
    string[]? selectedOperationIds = ();
    if operationCount > MAX_OPERATIONS {
        utils:logVerbose(string `spec has ${operationCount} operations — selecting subset for test generation`);
        string operationsList = check selectOperationsUsingAI(specPath);
        string[] rawIds = regexp:split(re `,`, operationsList);
        string[] trimmedIds = [];
        foreach string id in rawIds {
            string trimmedId = id.trim();
            if trimmedId.length() > 0 {
                trimmedIds.push(trimmedId);
            }
        }
        selectedOperationIds = trimmedIds;
        utils:logVerbose(string `selected ${trimmedIds.length()} operations`);
    }

    // Mock server stub generation.
    utils:logVerbose("generating mock server stub");
    error? mockGenResult = generateMockServerStub(connectorPath, specPath, selectedOperationIds);
    if mockGenResult is error {
        utils:logError(string `mock server stub generation failed: ${mockGenResult.message()}`);
        return mockGenResult;
    }
    utils:logVerbose("✓ mock server stub generated");

    string ballerinaDir = check utils:resolveBallerinaDir(connectorPath);
    string mockServerPath = ballerinaDir + "/tests/mock_service.bal";
    string typesPath = ballerinaDir + "/types.bal";

    // Mock server implementation.
    utils:logVerbose("implementing mock server using AI");
    error? completeResult = implementMockServer(mockServerPath, typesPath);
    if completeResult is error {
        utils:logError(string `mock server implementation failed: ${completeResult.message()}`);
        return completeResult;
    }
    utils:logVerbose("✓ mock server implemented");

    // Generating tests.
    utils:logVerbose("generating test file");
    error? testGenResult = generateTestFile(connectorPath, selectedOperationIds);
    if testGenResult is error {
        utils:logError(string `test file generation failed: ${testGenResult.message()}`);
        return testGenResult;
    }
    utils:logVerbose("✓ test file generated");

    utils:logVerbose("fixing compilation errors");
    error? fixResult = fixTestFileErrors(connectorPath);
    if fixResult is error {
        utils:logWarn(string `some compilation errors remain: ${fixResult.message()} — manual intervention may be required`);
    } else {
        utils:logVerbose("✓ compilation errors fixed");
    }

    utils:logInfo(string `✓ tests generated at ${ballerinaDir}/tests/`);
}
