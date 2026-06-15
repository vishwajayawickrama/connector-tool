import wso2/connector_automator.client_generator as client_generator;
import wso2/connector_automator.code_fixer as code_fixer;
import wso2/connector_automator.document_generator as document_generator;
import wso2/connector_automator.example_generator as example_generator;
import wso2/connector_automator.sanitizor as sanitizor;
import wso2/connector_automator.test_generator as test_generator;
import wso2/connector_automator.utils;

public function runOpenApiWorkflow(string openApiSpec, string outputDir, string logLevel, string examplesDir) returns error? {
    utils:LogLevel level = logLevel == "quiet" ? "quiet" : logLevel == "verbose" ? "verbose" : "normal";
    return executeOpenApiPipeline(openApiSpec, outputDir, examplesDir, level);
}

function executeOpenApiPipeline(string openApiSpec, string outputDir, string examplesDir, utils:LogLevel logLevel = "normal") returns error? {
    utils:logVerbose(string `spec: ${openApiSpec}`, logLevel);
    utils:logVerbose(string `output: ${outputDir}`, logLevel);
    
    // Stage 1: Sanitizing the spec.
    utils:logStep(1, 6, "Sanitizing OpenAPI Specification", logLevel);
    error? sanitizeResult = sanitizor:executeSanitizor(openApiSpec, outputDir, logLevel);
    if sanitizeResult is error {
        utils:logError(string `sanitization failed: ${sanitizeResult.message()}`);
        return sanitizeResult;
    }
    utils:logInfo("✓ sanitization complete", logLevel);
    error? sanitationsDocResult = sanitizor:generateSanitationsDoc(
        openApiSpec, string `${outputDir}/docs/spec/aligned_ballerina_openapi.json`, outputDir, logLevel);
    if sanitationsDocResult is error {
        utils:logWarn(string `could not generate sanitations.md: ${sanitationsDocResult.message()}`, logLevel);
    }
    
    // Stage 2: Generating the client.
    utils:logStep(2, 6, "Generating Ballerina Client", logLevel);
    string sanitizedSpec = string `${outputDir}/docs/spec/aligned_ballerina_openapi.json`;
    string clientPath = outputDir;
    error? clientResult = client_generator:executeClientGen(sanitizedSpec, clientPath, logLevel);
    if clientResult is error {
        utils:logWarn(string `client generation failed: ${clientResult.message()} — continuing`, logLevel);
    } else {
        utils:logInfo("✓ client generated", logLevel);
    }

    // Stage 3: Building and validating the client.
    utils:logStep(3, 6, "Building and Validating Client", logLevel);
    utils:CommandResult buildResult = utils:executeBalBuild(clientPath, logLevel);
    if utils:hasCompilationErrors(buildResult) {
        utils:logWarn("client has compilation errors — attempting auto-fix", logLevel);
        code_fixer:FixResult|code_fixer:BallerinaFixerError fixResult = code_fixer:fixAllErrors(clientPath, logLevel, true);
        if fixResult is code_fixer:FixResult && fixResult.errorsFixed > 0 {
            utils:logVerbose(string `auto-fixed ${fixResult.errorsFixed} compilation error${fixResult.errorsFixed == 1 ? "" : "s"}`, logLevel);
        }
        utils:CommandResult revalidateResult = utils:executeBalBuild(clientPath, logLevel);
        if utils:hasCompilationErrors(revalidateResult) {
            utils:logError("build validation failed: client still has compilation errors after auto-fix");
            utils:logError(string `inspect the generated client at: ${clientPath}`);
            return error(string `client build failed: ${revalidateResult.stderr}`);
        }
    }
    utils:logInfo("✓ client built and validated", logLevel);

    // Stage 4: Generating tests.
    utils:logStep(4, 6, "Generating Tests", logLevel);
    error? testResult = test_generator:executeOpenApiTestGen(outputDir, sanitizedSpec, logLevel);
    if testResult is error {
        utils:logWarn(string `test generation failed: ${testResult.message()} — continuing`, logLevel);
    } else {
        utils:logInfo("✓ tests generated", logLevel);
    }

    // Stage 5: Generating examples.
    utils:logStep(5, 6, "Generating Examples", logLevel);
    error? exampleResult = example_generator:executeExampleGen(outputDir, examplesDir, logLevel);
    if exampleResult is error {
        utils:logWarn(string `example generation failed: ${exampleResult.message()} — continuing`, logLevel);
    } else {
        utils:logInfo("✓ examples generated", logLevel);
    }

    // Stage 6: Generating documentation.
    utils:logStep(6, 6, "Generating Documentation", logLevel);
    error? docResult = document_generator:executeDocGen("generate-all", outputDir, logLevel);
    if docResult is error {
        utils:logWarn(string `documentation generation failed: ${docResult.message()}`, logLevel);
    } else {
        utils:logInfo("✓ documentation generated", logLevel);
    }

    utils:logCompletion(outputDir, logLevel);
}
