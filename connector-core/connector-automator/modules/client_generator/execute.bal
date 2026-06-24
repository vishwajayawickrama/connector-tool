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

public function executeClientGen(string specPath, string outputDir,
        OpenAPIToolOptions? customOptions = ()) returns error? {
    utils:logVerbose(string `spec: ${specPath}`);
    utils:logVerbose(string `output: ${outputDir}`);

    utils:CommandResult result = executeBalClientGenerate(specPath, outputDir, customOptions);

    if !utils:isCommandSuccessfull(result) {
        if result.compilationErrors.length() > 0 {
            foreach utils:CmdCompilationError err in result.compilationErrors {
                utils:logVerbose(string `  ${err.fileName}:${err.line}:${err.column} — ${err.message}`);
            }
        }
        return error("client generation failed: " + result.stderr);
    }
}

public function generateBallerinaClient(string specPath, string outputDir, ClientGeneratorConfig config) returns error? {
    utils:logVerbose("generating Ballerina client code");

    utils:CommandResult generateResult = executeBalClientGenerate(specPath, outputDir, config.toolOptions);

    if !utils:isCommandSuccessfull(generateResult) {
        if generateResult.compilationErrors.length() > 0 {
            foreach utils:CmdCompilationError err in generateResult.compilationErrors {
                utils:logVerbose(string `  ${err.fileName}:${err.line}:${err.column} — ${err.message}`);
            }
        }
        return error("client generation failed: " + generateResult.stderr);
    }

    utils:logInfo(string `✓ client generated at: ${outputDir}`);
}

function printUsage() {
    io:fprintln(io:stderr, "Ballerina Client Generator");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE");
    io:fprintln(io:stderr, "  bal connector openapi generate-client -i <spec> -o <output-dir> [-q|-v]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ENVIRONMENT");
    io:fprintln(io:stderr, "  ANTHROPIC_API_KEY    Required for AI-powered steps");
}
