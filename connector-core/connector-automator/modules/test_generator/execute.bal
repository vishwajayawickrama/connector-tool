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

import wso2/connector_automator.utils;

import ballerina/lang.regexp;
import ballerina/os;

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

// SDK live-test execution flow (no mock server; live API tests only).
function executeSdkTestGen(string connectorPath, string specPath) returns error? {
    utils:logVerbose(string `connector: ${connectorPath}`);
    utils:logVerbose(string `spec: ${specPath}`);

    check validateApiKey();

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

    check validateApiKey();

    utils:logVerbose("initializing AI service");
    error? initResult = utils:initAIService();
    if initResult is error {
        utils:logError(string `AI initialization failed: ${initResult.message()}`);
        return initResult;
    }
    utils:logVerbose("✓ AI service initialized");

    utils:logVerbose("generating mock server implementation");
    error? mockGenResult = generateMockServer(connectorPath, specPath);
    if mockGenResult is error {
        utils:logError(string `mock server generation failed: ${mockGenResult.message()}`);
        return mockGenResult;
    }

    int operationCount = check countOperationsInSpec(specPath);
    string[]? selectedOperationIds = ();

    if operationCount > MAX_OPERATIONS {
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
    utils:logVerbose("✓ mock server implementation generated");

    string ballerinaDir = check utils:resolveBallerinaDir(connectorPath);
    string mockServerPath = ballerinaDir + "/tests/mock_service.bal";
    string typesPath = ballerinaDir + "/types.bal";

    utils:logVerbose("completing mock server template");
    error? completeResult = completeMockServer(mockServerPath, typesPath);
    if completeResult is error {
        utils:logError(string `mock server completion failed: ${completeResult.message()}`);
        return completeResult;
    }
    utils:logVerbose("✓ mock server template completed");

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

    utils:logInfo(string `✓ tests generated at ${connectorPath}/ballerina/tests/`);
}

function validateApiKey() returns error? {
    string apiKey = os:getEnv("ANTHROPIC_API_KEY");
    if apiKey.length() == 0 {
        return error("ANTHROPIC_API_KEY not configured");
    }
}
