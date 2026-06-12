import wso2/connector_automator.utils;

import ballerina/file;
import ballerina/io;
import ballerina/lang.regexp;

function setupMockServerModule(string connectorPath, utils:LogLevel logLevel = "normal") returns error? {
    string ballerinaDir = check utils:resolveBallerinaDir(connectorPath);

    utils:logVerbose("adding mock.server module", logLevel);
    string command = string `bal add mock.server`;

    utils:CommandResult addResult = utils:executeCommand(command, ballerinaDir, logLevel);
    if !addResult.success {
        return error("Failed to add mock.server module" + addResult.stderr);
    }
    utils:logVerbose("✓ mock.server module added", logLevel);

    string mockTestDir = ballerinaDir + "/modules/mock.server/tests";
    if check file:test(mockTestDir, file:EXISTS) {
        check file:remove(mockTestDir, file:RECURSIVE);
        utils:logVerbose("removed auto-generated tests directory", logLevel);
    }

    string mockServerFile = ballerinaDir + "/modules/mock.server/mock.server.bal";
    if check file:test(mockServerFile, file:EXISTS) {
        check file:remove(mockServerFile, file:RECURSIVE);
        utils:logVerbose("removed auto-generated mock.server.bal", logLevel);
    }
}

function generateMockServer(string connectorPath, string specPath, utils:LogLevel logLevel = "normal") returns error? {
    string ballerinaDir = check utils:resolveBallerinaDir(connectorPath);
    string mockServerDir = ballerinaDir + "/modules/mock.server";
    int operationCount = check countOperationsInSpec(specPath);
    utils:logVerbose(string `total operations in spec: ${operationCount}`, logLevel);

    string absSpecPath = check file:getAbsolutePath(specPath);
    string absMockServerDir = check file:getAbsolutePath(mockServerDir);

    string command;

    if operationCount <= MAX_OPERATIONS {
        utils:logVerbose(string `using all ${operationCount} operations`, logLevel);
        command = string `bal openapi -i ${absSpecPath} -o ${absMockServerDir}`;
    } else {
        utils:logVerbose(string `filtering from ${operationCount} to ${MAX_OPERATIONS} most useful operations`, logLevel);
        string operationsList = check selectOperationsUsingAI(specPath);
        utils:logVerbose(string `selected operations: ${operationsList}`, logLevel);
        command = string `bal openapi -i ${absSpecPath} -o ${absMockServerDir} --operations ${operationsList}`;
    }

    utils:CommandResult result = utils:executeCommand(command, ballerinaDir, logLevel);
    if !result.success {
        return error("Failed to generate mock server using ballerina openAPI tool" + result.stderr);
    }

    string mockServerPathOld = mockServerDir + "/aligned_ballerina_openapi_service.bal";
    string mockServerPathNew = mockServerDir + "/mock_server.bal";
    if check file:test(mockServerPathOld, file:EXISTS) {
        check file:rename(mockServerPathOld, mockServerPathNew);
        utils:logVerbose("renamed mock server file", logLevel);
    }

    string clientPath = mockServerDir + "/client.bal";
    if check file:test(clientPath, file:EXISTS) {
        check file:remove(clientPath, file:RECURSIVE);
        utils:logVerbose("removed client.bal", logLevel);
    }
}

function countOperationsInSpec(string specPath) returns int|error {
    string specContent = check io:fileReadString(specPath);
    regexp:RegExp operationIdPattern = re `"operationId"\s*:\s*"[^"]*"`;
    regexp:Span[] matches = operationIdPattern.findAll(specContent);
    return matches.length();
}
