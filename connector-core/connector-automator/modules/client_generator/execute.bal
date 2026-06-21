import wso2/connector_automator.utils;

import ballerina/io;

public function executeClientGen(string specPath, string outputDir, utils:LogLevel logLevel = "normal",
        OpenAPIToolOptions? customOptions = ()) returns error? {
    utils:logVerbose(string `spec: ${specPath}`, logLevel);
    utils:logVerbose(string `output: ${outputDir}`, logLevel);

    utils:CommandResult result = executeBalClientGenerate(specPath, outputDir, customOptions, logLevel);

    if !utils:isCommandSuccessfull(result) {
        if result.compilationErrors.length() > 0 {
            foreach utils:CmdCompilationError err in result.compilationErrors {
                utils:logVerbose(string `  ${err.fileName}:${err.line}:${err.column} — ${err.message}`, logLevel);
            }
        }
        return error("client generation failed: " + result.stderr);
    }
}

public function generateBallerinaClient(string specPath, string outputDir, ClientGeneratorConfig config, utils:LogLevel logLevel = "normal") returns error? {
    utils:logVerbose("generating Ballerina client code", logLevel);

    utils:CommandResult generateResult = executeBalClientGenerate(specPath, outputDir, config.toolOptions, logLevel);

    if !utils:isCommandSuccessfull(generateResult) {
        if generateResult.compilationErrors.length() > 0 {
            foreach utils:CmdCompilationError err in generateResult.compilationErrors {
                utils:logVerbose(string `  ${err.fileName}:${err.line}:${err.column} — ${err.message}`, logLevel);
            }
        }
        return error("client generation failed: " + generateResult.stderr);
    }

    utils:logInfo(string `✓ client generated at: ${outputDir}`, logLevel);
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
