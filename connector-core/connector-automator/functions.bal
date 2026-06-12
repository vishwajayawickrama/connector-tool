import wso2/connector_automator.client_generator as client_generator;
import wso2/connector_automator.code_fixer as code_fixer;
import wso2/connector_automator.document_generator as document_generator;
import wso2/connector_automator.example_generator as example_generator;
import wso2/connector_automator.sanitizor as sanitizor;
import wso2/connector_automator.test_generator as test_generator;
import wso2/connector_automator.utils as oautils;

function executeOpenApiPipeline(string openApiSpec, string outputDir, oautils:LogLevel logLevel = "normal") returns error? {
    oautils:logVerbose(string `spec: ${openApiSpec}`, logLevel);
    oautils:logVerbose(string `output: ${outputDir}`, logLevel);

    oautils:logStep(1, 6, "Sanitizing OpenAPI Specification", logLevel);
    error? sanitizeResult = sanitizor:executeSanitizor(openApiSpec, outputDir, logLevel, true);
    if sanitizeResult is error {
        oautils:logError(string `sanitization failed: ${sanitizeResult.message()}`);
        return sanitizeResult;
    }
    oautils:logInfo("✓ sanitization complete", logLevel);
    error? sanitationsDocResult = sanitizor:generateSanitationsDoc(
        openApiSpec, string `${outputDir}/docs/spec/aligned_ballerina_openapi.json`, outputDir, logLevel);
    if sanitationsDocResult is error {
        oautils:logWarn(string `could not generate sanitations.md: ${sanitationsDocResult.message()}`, logLevel);
    }

    oautils:logStep(2, 6, "Generating Ballerina Client", logLevel);
    string sanitizedSpec = string `${outputDir}/docs/spec/aligned_ballerina_openapi.json`;
    string clientPath = outputDir;
    error? clientResult = client_generator:executeClientGen(sanitizedSpec, clientPath, logLevel);
    if clientResult is error {
        oautils:logWarn(string `client generation failed: ${clientResult.message()} — continuing`, logLevel);
    } else {
        oautils:logInfo("✓ client generated", logLevel);
    }

    oautils:logStep(3, 6, "Building and Validating Client", logLevel);
    oautils:CommandResult buildResult = oautils:executeBalBuild(clientPath, logLevel);
    if oautils:hasCompilationErrors(buildResult) {
        oautils:logWarn("client has compilation errors — attempting auto-fix", logLevel);
        code_fixer:FixResult|code_fixer:BallerinaFixerError fixResult = code_fixer:fixAllErrors(clientPath, logLevel, true);
        if fixResult is code_fixer:FixResult && fixResult.errorsFixed > 0 {
            oautils:logVerbose(string `auto-fixed ${fixResult.errorsFixed} compilation error${fixResult.errorsFixed == 1 ? "" : "s"}`, logLevel);
        }
        oautils:CommandResult revalidateResult = oautils:executeBalBuild(clientPath, logLevel);
        if oautils:hasCompilationErrors(revalidateResult) {
            oautils:logError("build validation failed: client still has compilation errors after auto-fix");
            oautils:logError(string `inspect the generated client at: ${clientPath}`);
            return error(string `client build failed: ${revalidateResult.stderr}`);
        }
    }
    oautils:logInfo("✓ client built and validated", logLevel);

    oautils:logStep(4, 6, "Generating Examples", logLevel);
    error? exampleResult = example_generator:executeExampleGen(outputDir, logLevel, true);
    if exampleResult is error {
        oautils:logWarn(string `example generation failed: ${exampleResult.message()} — continuing`, logLevel);
    } else {
        oautils:logInfo("✓ examples generated", logLevel);
    }

    oautils:logStep(5, 6, "Generating Tests", logLevel);
    error? testResult = test_generator:executeTestGen("openapi", outputDir, sanitizedSpec, logLevel);
    if testResult is error {
        oautils:logWarn(string `test generation failed: ${testResult.message()} — continuing`, logLevel);
    } else {
        oautils:logInfo("✓ tests generated", logLevel);
    }

    oautils:logStep(6, 6, "Generating Documentation", logLevel);
    error? docResult = document_generator:executeDocGen("generate-all", outputDir, logLevel);
    if docResult is error {
        oautils:logWarn(string `documentation generation failed: ${docResult.message()}`, logLevel);
    } else {
        oautils:logInfo("✓ documentation generated", logLevel);
    }

    oautils:logCompletion(outputDir, logLevel);
}
