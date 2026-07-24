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
import ballerina/lang.regexp;
import ballerina/lang.'string as strings;

# Converts a Ballerina package name into the display name used by connector catalog metadata.
#
# + connectorName - Package name from the [package] section of Ballerina.toml
# + return - Name keyword with a title-cased display name and normalized separators
public function formatConnectorDisplayName(string connectorName) returns string {
    string normalized = regexp:replaceAll(re `[._-]+`, connectorName, " ").trim();
    string[] words = regexp:split(re `\s+`, normalized);
    string[] titleCasedWords = [];

    foreach string word in words {
        if word.length() > 0 {
            titleCasedWords.push(word.substring(0, 1).toUpperAscii() + word.substring(1).toLowerAscii());
        }
    }

    string displayName = strings:'join(" ", ...titleCasedWords);
    if displayName.length() == 0 {
        return "";
    }

    return "Name/" + displayName;
}

public function executeDocumentGeneration(string connectorPath, string[] excluded = []) returns error? {

    if excluded.indexOf("examples") is () {
        check generateIndividualExampleReadmes(connectorPath);
        check generateExamplesReadme(connectorPath);
    }
    if excluded.indexOf("client") is () {
        check generateMainReadme(connectorPath);
        check generateBallerinaReadme(connectorPath);
    }
    if excluded.indexOf("tests") is () {
        check generateTestsReadme(connectorPath);
    }
    if excluded.indexOf("metadata") is () {
        check generateKeywords(connectorPath);
    }

    utils:logInfo("✓ documentation generated");
}

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
        "generate-metadata" => {
            check genKeywords(connectorPath);
        }
        _ => {
            utils:logError(string `unknown doc command: '${command}'`);
            printUsage();
        }
    }
}

function generateAllReadmes(string connectorPath, string[] excluded) returns error? {
    utils:logVerbose("generating documentation files");

    if excluded.indexOf("examples") is () {
        check generateIndividualExampleReadmes(connectorPath);
        check generateExamplesReadme(connectorPath);
    }
    if excluded.indexOf("client") is () {
        check generateMainReadme(connectorPath);
        check generateBallerinaReadme(connectorPath);
    }
    if excluded.indexOf("tests") is () {
        check generateTestsReadme(connectorPath);
    }
    if excluded.indexOf("metadata") is () {
        check generateKeywords(connectorPath);
    }

    utils:logInfo(string `✓ documentation generated at ${connectorPath}/`);
}

function genBallerinaReadme(string connectorPath) returns error? {
    check generateIndividualExampleReadmes(connectorPath);
    error? result = generateBallerinaReadme(connectorPath);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ README: ${connectorPath}/ballerina/README.md`);
}

function genTestsReadme(string connectorPath) returns error? {
    error? result = generateTestsReadme(connectorPath);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ README: ${connectorPath}/ballerina/tests/README.md`);
}

function genExamplesReadme(string connectorPath) returns error? {
    check generateIndividualExampleReadmes(connectorPath);
    error? result = generateExamplesReadme(connectorPath);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ README: ${connectorPath}/examples/README.md`);
}

function genIndividualExampleReadmes(string connectorPath) returns error? {
    error? result = generateIndividualExampleReadmes(connectorPath);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ example docs: ${connectorPath}/examples/*/*.md`);
}

function genMainReadme(string connectorPath) returns error? {
    error? result = generateMainReadme(connectorPath);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ README: ${connectorPath}/README.md`);
}

function genKeywords(string connectorPath) returns error? {
    error? result = generateKeywords(connectorPath);
    if result is error {
        utils:logError(string `keyword generation failed: ${result.message()}`);
        return result;
    }
}

function printUsage() {
    io:fprintln(io:stderr, "Documentation Generator");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE");
    io:fprintln(io:stderr, "  bal connector openapi generate-docs generate-all <connector-path> [-q|-v]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "COMMANDS");
    io:fprintln(io:stderr, "  generate-all                 Generate all documentation");
    io:fprintln(io:stderr, "  generate-ballerina           Generate module README");
    io:fprintln(io:stderr, "  generate-tests               Generate tests README");
    io:fprintln(io:stderr, "  generate-examples            Generate examples README");
    io:fprintln(io:stderr, "  generate-individual-examples Generate individual example documentation");
    io:fprintln(io:stderr, "  generate-main                Generate root README");
    io:fprintln(io:stderr, "  generate-metadata            Generate Ballerina.toml marketplace and display-name keywords");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ENVIRONMENT");
    io:fprintln(io:stderr, "  ANTHROPIC_API_KEY    Required for AI-powered documentation");
}
