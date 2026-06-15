import wso2/connector_automator.utils;

import ballerina/lang.regexp;
import ballerina/os;

// Unified entry point: dispatches to OpenAPI (mock + live) or SDK (live only) test generation.
public function executeTestGen(string workflowType, string connectorPath, string specPath, utils:LogLevel logLevel = "normal") returns error? {
    match workflowType {
        "openapi" => {
            return executeOpenApiTestGen(connectorPath, specPath, logLevel);
        }
        "sdk" => {
            return executeSdkTestGen(connectorPath, specPath, logLevel);
        }
        _ => {
            return error(string `Unknown workflow type: '${workflowType}'. Use 'openapi' or 'sdk'.`);
        }
    }
}

// SDK live-test execution flow (no mock server; live API tests only).
function executeSdkTestGen(string connectorPath, string specPath, utils:LogLevel logLevel) returns error? {
    utils:logVerbose(string `connector: ${connectorPath}`, logLevel);
    utils:logVerbose(string `spec: ${specPath}`, logLevel);

    check validateApiKey();

    utils:logVerbose("initializing AI service", logLevel);
    error? initResult = utils:initAIService(logLevel);
    if initResult is error {
        utils:logError(string `AI initialization failed: ${initResult.message()}`);
        return initResult;
    }
    utils:logVerbose("✓ AI service initialized", logLevel);

    utils:logVerbose("preparing live test operation scope", logLevel);
    int operationCount = check sdkCountOperationsInSpec(specPath);
    string[]? selectedOperationIds = ();

    if operationCount > SDK_MAX_OPERATIONS {
        string operationsList = check sdkSelectOperationsUsingAI(specPath, logLevel);
        string[] rawIds = regexp:split(re `,`, operationsList);
        string[] trimmedIds = [];
        foreach string id in rawIds {
            string trimmedId = id.trim();
            if trimmedId.length() > 0 {
                trimmedIds.push(trimmedId);
            }
        }
        selectedOperationIds = trimmedIds;
        utils:logVerbose(string `selected ${trimmedIds.length()} operations`, logLevel);
    }
    utils:logVerbose("✓ operation scope prepared", logLevel);

    utils:logVerbose("generating live test file", logLevel);
    error? testGenResult = sdkGenerateTestFile(connectorPath, selectedOperationIds, logLevel);
    if testGenResult is error {
        utils:logError(string `test file generation failed: ${testGenResult.message()}`);
        return testGenResult;
    }
    utils:logVerbose("✓ test file generated", logLevel);

    utils:logVerbose("fixing compilation errors", logLevel);
    error? fixResult = sdkFixTestFileErrors(connectorPath, logLevel);
    if fixResult is error {
        utils:logWarn(string `some compilation errors remain: ${fixResult.message()} — manual intervention may be required`, logLevel);
    } else {
        utils:logVerbose("✓ compilation errors fixed", logLevel);
    }

    utils:logInfo(string `✓ SDK tests generated at ${connectorPath}/ballerina/tests/`, logLevel);
}

// OpenAPI workflow: mock server + live tests.
public function executeOpenApiTestGen(string connectorPath, string specPath, utils:LogLevel logLevel = "normal") returns error? {
    utils:logVerbose(string `connector: ${connectorPath}`, logLevel);
    utils:logVerbose(string `spec: ${specPath}`, logLevel);

    check validateApiKey();

    utils:logVerbose("initializing AI service", logLevel);
    error? initResult = utils:initAIService(logLevel);
    if initResult is error {
        utils:logError(string `AI initialization failed: ${initResult.message()}`);
        return initResult;
    }
    utils:logVerbose("✓ AI service initialized", logLevel);

    utils:logVerbose("setting up mock server module", logLevel);
    error? mockSetupResult = setupMockServerModule(connectorPath, logLevel);
    if mockSetupResult is error {
        utils:logError(string `mock server setup failed: ${mockSetupResult.message()}`);
        return mockSetupResult;
    }
    utils:logVerbose("✓ mock server module set up", logLevel);

    utils:logVerbose("generating mock server implementation", logLevel);
    error? mockGenResult = generateMockServer(connectorPath, specPath, logLevel);
    if mockGenResult is error {
        utils:logError(string `mock server generation failed: ${mockGenResult.message()}`);
        return mockGenResult;
    }

    int operationCount = check countOperationsInSpec(specPath);
    string[]? selectedOperationIds = ();

    if operationCount > MAX_OPERATIONS {
        string operationsList = check selectOperationsUsingAI(specPath, logLevel);
        string[] rawIds = regexp:split(re `,`, operationsList);
        string[] trimmedIds = [];
        foreach string id in rawIds {
            string trimmedId = id.trim();
            if trimmedId.length() > 0 {
                trimmedIds.push(trimmedId);
            }
        }
        selectedOperationIds = trimmedIds;
        utils:logVerbose(string `selected ${trimmedIds.length()} operations`, logLevel);
    }
    utils:logVerbose("✓ mock server implementation generated", logLevel);

    string ballerinaDir = check utils:resolveBallerinaDir(connectorPath);
    string mockServerPath = ballerinaDir + "/modules/mock.server/mock_server.bal";
    string typesPath = ballerinaDir + "/modules/mock.server/types.bal";

    utils:logVerbose("completing mock server template", logLevel);
    error? completeResult = completeMockServer(mockServerPath, typesPath, logLevel);
    if completeResult is error {
        utils:logError(string `mock server completion failed: ${completeResult.message()}`);
        return completeResult;
    }
    utils:logVerbose("✓ mock server template completed", logLevel);

    utils:logVerbose("generating test file", logLevel);
    error? testGenResult = generateTestFile(connectorPath, selectedOperationIds, logLevel);
    if testGenResult is error {
        utils:logError(string `test file generation failed: ${testGenResult.message()}`);
        return testGenResult;
    }
    utils:logVerbose("✓ test file generated", logLevel);

    utils:logVerbose("fixing compilation errors", logLevel);
    error? fixResult = fixTestFileErrors(connectorPath, logLevel);
    if fixResult is error {
        utils:logWarn(string `some compilation errors remain: ${fixResult.message()} — manual intervention may be required`, logLevel);
    } else {
        utils:logVerbose("✓ compilation errors fixed", logLevel);
    }

    utils:logInfo(string `✓ tests generated at ${connectorPath}/ballerina/tests/`, logLevel);
}

function validateApiKey() returns error? {
    string|error apiKey = os:getEnv("ANTHROPIC_API_KEY");
    if apiKey is error {
        return error("ANTHROPIC_API_KEY not configured");
    }
}
