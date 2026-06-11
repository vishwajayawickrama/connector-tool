import ballerina/io;
import wso2/connector_automator.client_generator as client_generator;
import wso2/connector_automator.document_generator as document_generator;
import wso2/connector_automator.example_generator as example_generator;
import wso2/connector_automator.sanitizor as sanitizor;
import wso2/connector_automator.test_generator as test_generator;
import wso2/connector_automator.utils as oautils;

function executeOpenApiPipeline(string openApiSpec, string outputDir) returns error? {
    printOpenApiPipelineHeader(openApiSpec, outputDir, false, false);

    printOpenApiStepHeader(1, "Sanitizing OpenAPI Specification", false);
    error? sanitizeResult = sanitizor:executeSanitizor(openApiSpec, outputDir);
    if sanitizeResult is error {
        io:println(string `Sanitization failed: ${sanitizeResult.message()}`);
        return sanitizeResult;
    }
    io:println("Sanitization completed successfully");
    error? sanitationsDocResult = sanitizor:generateSanitationsDoc(
        openApiSpec, string `${outputDir}/docs/spec/aligned_ballerina_openapi.json`, outputDir, false);
    if sanitationsDocResult is error {
        io:println(string `Could not generate sanitations.md: ${sanitationsDocResult.message()}`);
    }

    printOpenApiStepHeader(2, "Generating Ballerina Client", false);
    string sanitizedSpec = string `${outputDir}/docs/spec/aligned_ballerina_openapi.json`;
    string clientPath = outputDir;
    error? clientResult = client_generator:executeClientGen(sanitizedSpec, clientPath);
    if clientResult is error {
        io:println(string `Client generation failed: ${clientResult.message()}`);
        io:println("Continuing pipeline...");
    } else {
        io:println("Client generation completed successfully");
    }

    printOpenApiStepHeader(3, "Building and Validating Client", false);
    oautils:CommandResult buildResult = oautils:executeBalBuild(clientPath, false);
    if oautils:hasCompilationErrors(buildResult) {
        io:println("Build validation failed: client contains compilation errors");
        io:println("Run 'bal connector openapi fix-code <connector-path>' to resolve, or fix manually");
        return error(string `Client build failed: ${buildResult.stderr}`);
    }
    io:println("Client built and validated successfully");

    // TODO: we shoudl call the code fixer in here to fix any compliation errors in the generated client.

    printOpenApiStepHeader(4, "Generating Examples", false);
    error? exampleResult = example_generator:executeExampleGen(outputDir);
    if exampleResult is error {
        io:println(string `Example generation failed: ${exampleResult.message()}`);
        io:println("Continuing pipeline...");
    } else {
        io:println("Example generation completed successfully");
    }

    printOpenApiStepHeader(5, "Generating Tests", false);
    error? testResult = test_generator:executeTestGen("openapi", outputDir, sanitizedSpec);
    if testResult is error {
        io:println(string `Test generation failed: ${testResult.message()}`);
        io:println("Continuing pipeline...");
    } else {
        io:println("Test generation completed successfully");
    }

    printOpenApiStepHeader(6, "Generating Documentation", false);
    error? docResult = document_generator:executeDocGen("generate-all", outputDir);
    if docResult is error {
        io:println(string `Documentation generation failed: ${docResult.message()}`);
    } else {
        io:println("Documentation generation completed successfully");
    }

    printOpenApiPipelineCompletion(outputDir, false);
}
