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

import ballerina/io;
import ballerina/os;

public function executeDocGen(string command, string connectorPath, string[] excluded = []) returns error? {
    utils:logVerbose(string `command: ${command}, connector: ${connectorPath}`);

    match command {
        "generate-all" => {
            check generateAllReadmes(connectorPath, excluded);
        }
        "generate-ballerina" => {
            check genBallerinaReadme(connectorPath);
        }
        "generate-tests" => {
            check genTestsReadme(connectorPath);
        }
        "generate-examples" => {
            check genExamplesReadme(connectorPath);
        }
        "generate-individual-examples" => {
            check genIndividualExampleReadmes(connectorPath);
        }
        "generate-main" => {
            check genMainReadme(connectorPath);
        }
        _ => {
            utils:logError(string `unknown doc command: '${command}'`);
            printUsage();
        }
    }
}

function generateAllReadmes(string connectorPath, string[] excluded) returns error? {
    check validateApiKey();
    check initDocumentationGenerator();
    utils:logVerbose("✓ AI generator initialized");

    utils:logVerbose("generating documentation files");

    if excluded.indexOf("client") is () {
        check generateMainReadme(connectorPath);
        check generateBallerinaReadme(connectorPath);
    }
    if excluded.indexOf("tests") is () {
        check generateTestsReadme(connectorPath);
    }
    if excluded.indexOf("examples") is () {
        check generateExamplesReadme(connectorPath);
        check generateIndividualExampleReadmes(connectorPath);
    }

    utils:logInfo(string `✓ documentation generated at ${connectorPath}/`);
}

function genBallerinaReadme(string connectorPath) returns error? {
    check validateApiKey();
    check initDocumentationGenerator();

    error? result = generateBallerinaReadme(connectorPath);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ README: ${connectorPath}/ballerina/README.md`);
}

function genTestsReadme(string connectorPath) returns error? {
    check validateApiKey();
    check initDocumentationGenerator();

    error? result = generateTestsReadme(connectorPath);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ README: ${connectorPath}/ballerina/tests/README.md`);
}

function genExamplesReadme(string connectorPath) returns error? {
    check validateApiKey();
    check initDocumentationGenerator();

    error? result = generateExamplesReadme(connectorPath);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ README: ${connectorPath}/examples/README.md`);
}

function genIndividualExampleReadmes(string connectorPath) returns error? {
    check validateApiKey();
    check initDocumentationGenerator();

    error? result = generateIndividualExampleReadmes(connectorPath);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ READMEs: ${connectorPath}/examples/*/README.md`);
}

function genMainReadme(string connectorPath) returns error? {
    check validateApiKey();
    check initDocumentationGenerator();

    error? result = generateMainReadme(connectorPath);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ README: ${connectorPath}/README.md`);
}

function validateApiKey() returns error? {
    string? apiKey = os:getEnv("ANTHROPIC_API_KEY");
    if apiKey is () || apiKey.trim().length() == 0 {
        return error("ANTHROPIC_API_KEY not configured");
    }
}

function printUsage() {
    io:fprintln(io:stderr, "Documentation Generator");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE");
    io:fprintln(io:stderr, "  bal connector openapi generate-docs generate-all <connector-path> [-q|-v]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "COMMANDS");
    io:fprintln(io:stderr, "  generate-all                 Generate all READMEs");
    io:fprintln(io:stderr, "  generate-ballerina           Generate module README");
    io:fprintln(io:stderr, "  generate-tests               Generate tests README");
    io:fprintln(io:stderr, "  generate-examples            Generate examples README");
    io:fprintln(io:stderr, "  generate-individual-examples Generate example READMEs");
    io:fprintln(io:stderr, "  generate-main                Generate root README");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ENVIRONMENT");
    io:fprintln(io:stderr, "  ANTHROPIC_API_KEY    Required for AI-powered documentation");
}
