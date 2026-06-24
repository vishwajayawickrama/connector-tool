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

import ballerina/file;
import ballerina/io;
import ballerina/lang.regexp;

function setupMockServerModule(string connectorPath) returns error? {
    string ballerinaDir = check utils:resolveBallerinaDir(connectorPath);

    utils:logVerbose("adding mock.server module");
    string command = string `bal add mock.server`;

    utils:CommandResult addResult = utils:executeCommand(command, ballerinaDir);
    if !addResult.success {
        return error("Failed to add mock.server module" + addResult.stderr);
    }
    utils:logVerbose("✓ mock.server module added");

    string mockTestDir = ballerinaDir + "/modules/mock.server/tests";
    if check file:test(mockTestDir, file:EXISTS) {
        check file:remove(mockTestDir, file:RECURSIVE);
        utils:logVerbose("removed auto-generated tests directory");
    }

    string mockServerFile = ballerinaDir + "/modules/mock.server/mock.server.bal";
    if check file:test(mockServerFile, file:EXISTS) {
        check file:remove(mockServerFile, file:RECURSIVE);
        utils:logVerbose("removed auto-generated mock.server.bal");
    }
}

function generateMockServer(string connectorPath, string specPath) returns error? {
    string ballerinaDir = check utils:resolveBallerinaDir(connectorPath);
    string mockServerDir = ballerinaDir + "/modules/mock.server";
    int operationCount = check countOperationsInSpec(specPath);
    utils:logVerbose(string `total operations in spec: ${operationCount}`);

    string absSpecPath = check file:getAbsolutePath(specPath);
    string absMockServerDir = check file:getAbsolutePath(mockServerDir);

    string command;

    if operationCount <= MAX_OPERATIONS {
        utils:logVerbose(string `using all ${operationCount} operations`);
        command = string `bal openapi -i ${absSpecPath} -o ${absMockServerDir}`;
    } else {
        utils:logVerbose(string `filtering from ${operationCount} to ${MAX_OPERATIONS} most useful operations`);
        string operationsList = check selectOperationsUsingAI(specPath);
        utils:logVerbose(string `selected operations: ${operationsList}`);
        command = string `bal openapi -i ${absSpecPath} -o ${absMockServerDir} --operations ${operationsList}`;
    }

    utils:CommandResult result = utils:executeCommand(command, ballerinaDir);
    if !result.success {
        return error("Failed to generate mock server using ballerina openAPI tool" + result.stderr);
    }

    string mockServerPathOld = mockServerDir + "/aligned_ballerina_openapi_service.bal";
    string mockServerPathNew = mockServerDir + "/mock_server.bal";
    if check file:test(mockServerPathOld, file:EXISTS) {
        check file:rename(mockServerPathOld, mockServerPathNew);
        utils:logVerbose("renamed mock server file");
    }

    string clientPath = mockServerDir + "/client.bal";
    if check file:test(clientPath, file:EXISTS) {
        check file:remove(clientPath, file:RECURSIVE);
        utils:logVerbose("removed client.bal");
    }
}

function countOperationsInSpec(string specPath) returns int|error {
    string specContent = check io:fileReadString(specPath);
    regexp:RegExp operationIdPattern = re `"operationId"\s*:\s*"[^"]*"`;
    regexp:Span[] matches = operationIdPattern.findAll(specContent);
    return matches.length();
}
