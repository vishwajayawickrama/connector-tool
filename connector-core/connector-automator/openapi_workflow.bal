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
    boolean interactive = interactiveArg == "interactive";
    string[] excluded = excludedStages.length() == 0 ? [] : re`,`.split(excludedStages);

    utils:logVerbose(string `spec: ${openApiSpec}`, level);
    utils:logVerbose(string `output: ${outputDir}`, level);
    utils:logVerbose(string `spec-dir: ${specDir}`, level);
    utils:logVerbose(string `examples-dir: ${examplesDir}`, level);

    if excluded.length() > 0 {
        utils:logInfo(string `skipping stages: ${string:'join(", ", ...excluded)}`, level);
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
        error? applyResult = sanitizor:applySanitations(sanitationsPath, openApiSpec, level);
        if applyResult is error {
            utils:logWarn(string `could not apply recorded sanitations — continuing: ${applyResult.message()}`, level);
        } else {
            utils:logInfo("✓ recorded sanitations applied", level);
        }
    }

    // Stage 1: Sanitize
    if excluded.indexOf("sanitize") is () {
        step += 1;
        utils:logStep(step, total, "Sanitizing OpenAPI Specification", level);
        error? sanitizeResult = sanitizor:executeSanitizor(openApiSpec, specDir, level);
        if sanitizeResult is error {
            utils:logError(string `sanitization failed: ${sanitizeResult.message()}`);
            return sanitizeResult;
        }
        utils:logInfo("✓ sanitization complete", level);
        error? sanitationsDocResult = sanitizor:generateSanitationsDoc(openApiSpec, sanitizedSpec, specDir, level);
        if sanitationsDocResult is error {
            utils:logWarn(string `could not refresh sanitations.md: ${sanitationsDocResult.message()}`, level);
        }
        if interactive && step < total {
            if !interactivePause(sanitizedSpec, level) {
                utils:logInfo("Stopped at user request.", level);
                return;
            }
        }
    } else {
        utils:logVerbose("skipping sanitize (excluded)", level);
    }

    // Stage 2: Generating and validating the client.
    if excluded.indexOf("client") is () {
        step += 1;
        utils:logStep(step, total, "Generating Ballerina Client", level);
        error? clientResult = client_generator:executeClientGen(sanitizedSpec, clientPath, level, customOptions = toolOptions);
        if clientResult is error {
            utils:logWarn(string `client generation failed: ${clientResult.message()} — continuing`, level);
        } else {
            utils:logInfo("✓ client generated", level);
        }

        utils:CommandResult buildResult = utils:executeBalBuild(clientPath, level);
        if utils:hasCompilationErrors(buildResult) {
            utils:logWarn("client has compilation errors — attempting auto-fix", level);
            code_fixer:FixResult|code_fixer:BallerinaFixerError fixResult = code_fixer:fixAllErrors(clientPath, level, true);
            if fixResult is code_fixer:FixResult && fixResult.errorsFixed > 0 {
                utils:logVerbose(string `auto-fixed ${fixResult.errorsFixed} compilation error${fixResult.errorsFixed == 1 ? "" : "s"}`, level);
            }
            utils:CommandResult revalidateResult = utils:executeBalBuild(clientPath, level);
            if utils:hasCompilationErrors(revalidateResult) {
                utils:logError("build validation failed: client still has compilation errors after auto-fix");
                utils:logError(string `inspect the generated client at: ${clientPath}`);
                return error(string `client build failed: ${revalidateResult.stderr}`);
            }
        }
        utils:logInfo("✓ client built and validated", level);
        if interactive && step < total {
            if !interactivePause(outputDir, level) {
                utils:logInfo("Stopped at user request.", level);
                return;
            }
        }
    } else {
        utils:logVerbose("skipping client (excluded)", level);
    }

    // Stage 3: Generating tests.
    if excluded.indexOf("tests") is () {
        step += 1;
        utils:logStep(step, total, "Generating Tests", level);
        error? testResult = test_generator:executeOpenApiTestGen(outputDir, sanitizedSpec, level);
        if testResult is error {
            utils:logWarn(string `test generation failed: ${testResult.message()} — continuing`, level);
        } else {
            utils:logInfo("✓ tests generated", level);
        }
        if interactive && step < total {
            if !interactivePause(string `${outputDir}/tests/`, level) {
                utils:logInfo("Stopped at user request.", level);
                return;
            }
        }
    } else {
        utils:logVerbose("skipping tests (excluded)", level);
    }

    // Stage 4: Examples
    if excluded.indexOf("examples") is () {
        step += 1;
        utils:logStep(step, total, "Generating Examples", level);
        error? exampleResult = example_generator:executeExampleGen(outputDir, examplesDir, level);
        if exampleResult is error {
            utils:logWarn(string `example generation failed: ${exampleResult.message()} — continuing`, level);
        } else {
            utils:logInfo("✓ examples generated", level);
        }
        if interactive && step < total {
            if !interactivePause(examplesDir, level) {
                utils:logInfo("Stopped at user request.", level);
                return;
            }
        }
    } else {
        utils:logVerbose("skipping examples (excluded)", level);
    }

    // Stage 5: Docs (non-fatal)
    if excluded.indexOf("docs") is () {
        step += 1;
        utils:logStep(step, total, "Generating Documentation", level);
        error? docResult = document_generator:executeDocGen("generate-all", outputDir, excluded, level);
        if docResult is error {
            utils:logWarn(string `documentation generation failed: ${docResult.message()}`, level);
        } else {
            utils:logInfo("✓ documentation generated", level);
        }
    } else {
        utils:logVerbose("skipping docs (excluded)", level);
    }

    utils:logCompletion(outputDir, level);
}

// Pauses the pipeline and prompts the user to review the artifact at the given path.
// Returns true to continue, false to stop.
function interactivePause(string artifact, utils:LogLevel level) returns boolean {
    io:fprintln(io:stderr, string `    → Review: ${artifact}`);
    io:fprint(io:stderr, "  Continue? [y/N]: ");
    string|io:Error input = io:readln();
    if input is io:Error {
        utils:logWarn("could not read input — stopping", level);
        return false;
    }
    string answer = (<string>input).trim().toLowerAscii();
    return answer == "y" || answer == "yes";
}
