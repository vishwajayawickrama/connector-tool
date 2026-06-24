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

import ballerina/io;

import wso2/connector_automator.client_generator as client_generator;
import wso2/connector_automator.code_fixer as code_fixer;
import wso2/connector_automator.document_generator as document_generator;
import wso2/connector_automator.example_generator as example_generator;
import wso2/connector_automator.sanitizor as sanitizor;
import wso2/connector_automator.test_generator as test_generator;
import wso2/connector_automator.utils;

public function runOpenApiGenerationWorkflow(string openApiSpec, string outputDir, string logLevel,
        string examplesDir, string excludedStages, string specDir, string license = "", string tags = "",
        string operations = "", string clientMethod = "", string interactiveArg = "") returns error? {

    utils:LogLevel level = logLevel == "quiet" ? "quiet" : logLevel == "verbose" ? "verbose" : "normal";
    utils:initLogLevel(level);
    boolean interactive = interactiveArg == "interactive";
    string[] excluded = excludedStages.length() == 0 ? [] : re`,`.split(excludedStages);

    utils:logVerbose(string `spec: ${openApiSpec}`);
    utils:logVerbose(string `output: ${outputDir}`);
    utils:logVerbose(string `spec-dir: ${specDir}`);
    utils:logVerbose(string `examples-dir: ${examplesDir}`);

    if excluded.length() > 0 {
        utils:logInfo(string `skipping stages: ${string:'join(", ", ...excluded)}`);
    }

    string[] allStages = ["sanitize", "client", "tests", "examples", "docs"];
    int total = allStages.filter(s => excluded.indexOf(s) is ()).length();
    int step = 0;

    string sanitizedSpec = string `${specDir}/aligned_ballerina_openapi.json`;
    string sanitationsPath = string `${specDir}/sanitations.md`;
    string clientPath = outputDir;

    client_generator:OpenAPIToolOptions? toolOptions = ();
    if license != "" || tags != "" || operations != "" || clientMethod != "" {
        client_generator:OpenAPIToolOptions opts = {};
        if license != "" {
            opts.license = license;
        }
        if tags != "" {
            opts.tags = re`,`.split(tags);
        }
        if operations != "" {
            opts.operations = re`,`.split(operations);
        }
        if clientMethod != "" {
            opts.clientMethod = clientMethod == "remote" ? "remote" : "resource";
        }
        toolOptions = opts;
    }

    // Pre-step: apply recorded sanitations to the incoming spec, if any exist (non-fatal)
    if excluded.indexOf("sanitize") is () {
        error? applyResult = sanitizor:applySanitations(sanitationsPath, openApiSpec);
        if applyResult is error {
            utils:logWarn(string `could not apply recorded sanitations — continuing: ${applyResult.message()}`);
        } else {
            utils:logInfo("✓ recorded sanitations applied");
        }
    }

    // Stage 1: Sanitize
    if excluded.indexOf("sanitize") is () {
        step += 1;
        utils:logStep(step, total, "Sanitizing OpenAPI Specification");
        error? sanitizeResult = sanitizor:executeSanitizor(openApiSpec, specDir);
        if sanitizeResult is error {
            utils:logError(string `sanitization failed: ${sanitizeResult.message()}`);
            return sanitizeResult;
        }
        utils:logInfo("✓ sanitization complete");
        error? sanitationsDocResult = sanitizor:generateSanitationsDoc(openApiSpec, sanitizedSpec, specDir);
        if sanitationsDocResult is error {
            utils:logWarn(string `could not refresh sanitations.md: ${sanitationsDocResult.message()}`);
        }
        if interactive && step < total {
            if !interactivePause(sanitizedSpec) {
                utils:logInfo("Stopped at user request.");
                return;
            }
        }
    } else {
        utils:logVerbose("skipping sanitize (excluded)");
    }

    // Stage 2: Generating and validating the client.
    if excluded.indexOf("client") is () {
        step += 1;
        utils:logStep(step, total, "Generating Ballerina Client");
        error? clientResult = client_generator:executeClientGen(sanitizedSpec, clientPath, customOptions = toolOptions);
        if clientResult is error {
            utils:logWarn(string `client generation failed: ${clientResult.message()} — continuing`);
        } else {
            utils:logInfo("✓ client generated");
        }

        utils:CommandResult buildResult = utils:executeBalBuild(clientPath);
        if utils:hasCompilationErrors(buildResult) {
            utils:logWarn("client has compilation errors — attempting auto-fix");
            code_fixer:FixResult|code_fixer:BallerinaFixerError fixResult = code_fixer:fixAllErrors(clientPath, true);
            if fixResult is code_fixer:FixResult && fixResult.errorsFixed > 0 {
                utils:logVerbose(string `auto-fixed ${fixResult.errorsFixed} compilation error${fixResult.errorsFixed == 1 ? "" : "s"}`);
            }
            utils:CommandResult revalidateResult = utils:executeBalBuild(clientPath);
            if utils:hasCompilationErrors(revalidateResult) {
                utils:logError("build validation failed: client still has compilation errors after auto-fix");
                utils:logError(string `inspect the generated client at: ${clientPath}`);
                return error(string `client build failed: ${revalidateResult.stderr}`);
            }
        }
        utils:logInfo("✓ client built and validated");
        if interactive && step < total {
            if !interactivePause(outputDir) {
                utils:logInfo("Stopped at user request.");
                return;
            }
        }
    } else {
        utils:logVerbose("skipping client (excluded)");
    }

    // Stage 3: Generating tests.
    if excluded.indexOf("tests") is () {
        step += 1;
        utils:logStep(step, total, "Generating Tests");
        error? testResult = test_generator:executeOpenApiTestGen(outputDir, sanitizedSpec);
        if testResult is error {
            utils:logWarn(string `test generation failed: ${testResult.message()} — continuing`);
        } else {
            utils:logInfo("✓ tests generated");
        }
        if interactive && step < total {
            if !interactivePause(string `${outputDir}/tests/`) {
                utils:logInfo("Stopped at user request.");
                return;
            }
        }
    } else {
        utils:logVerbose("skipping tests (excluded)");
    }

    // Stage 4: Examples
    if excluded.indexOf("examples") is () {
        step += 1;
        utils:logStep(step, total, "Generating Examples");
        error? exampleResult = example_generator:executeExampleGen(outputDir, examplesDir);
        if exampleResult is error {
            utils:logWarn(string `example generation failed: ${exampleResult.message()} — continuing`);
        } else {
            utils:logInfo("✓ examples generated");
        }
        if interactive && step < total {
            if !interactivePause(examplesDir) {
                utils:logInfo("Stopped at user request.");
                return;
            }
        }
    } else {
        utils:logVerbose("skipping examples (excluded)");
    }

    // Stage 5: Docs (non-fatal)
    if excluded.indexOf("docs") is () {
        step += 1;
        utils:logStep(step, total, "Generating Documentation");
        error? docResult = document_generator:executeDocGen("generate-all", outputDir, excluded);
        if docResult is error {
            utils:logWarn(string `documentation generation failed: ${docResult.message()}`);
        } else {
            utils:logInfo("✓ documentation generated");
        }
    } else {
        utils:logVerbose("skipping docs (excluded)");
    }

    utils:logCompletion(outputDir);
}

// Pauses the pipeline and prompts the user to review the artifact at the given path.
// Returns true to continue, false to stop.
function interactivePause(string artifact) returns boolean {
    io:fprintln(io:stderr, string `    → Review: ${artifact}`);
    io:fprint(io:stderr, "  Continue? [y/N]: ");
    string|io:Error input = io:readln();
    if input is io:Error {
        utils:logWarn("could not read input — stopping");
        return false;
    }
    string answer = (<string>input).trim().toLowerAscii();
    return answer == "y" || answer == "yes";
}
