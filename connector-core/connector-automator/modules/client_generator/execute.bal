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
