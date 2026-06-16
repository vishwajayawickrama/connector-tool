import wso2/connector_automator.client_generator as client_generator;
import wso2/connector_automator.code_fixer as code_fixer;
import wso2/connector_automator.document_generator as document_generator;
import wso2/connector_automator.example_generator as example_generator;
import wso2/connector_automator.sanitizor as sanitizor;
import wso2/connector_automator.test_generator as test_generator;
import wso2/connector_automator.utils;

public function runOpenApiGenerationWorkflow(string openApiSpec, string outputDir, string logLevel,
        string examplesDir, string excludedStages, string specDir) returns error? {

    utils:LogLevel level = logLevel == "quiet" ? "quiet" : logLevel == "verbose" ? "verbose" : "normal";
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
    } else {
        utils:logVerbose("skipping sanitize (excluded)", level);
    }

    // Stage 2: Generating and validating the client.
    if excluded.indexOf("client") is () {
        step += 1;
        utils:logStep(step, total, "Generating Ballerina Client", level);
        error? clientResult = client_generator:executeClientGen(sanitizedSpec, clientPath, level);
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
