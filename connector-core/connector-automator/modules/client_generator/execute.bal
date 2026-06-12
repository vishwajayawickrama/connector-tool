import wso2/connector_automator.utils;

import ballerina/io;

public function executeClientGen(string specPath, string outputDir, utils:LogLevel logLevel = "normal") returns error? {
    utils:logVerbose(string `spec: ${specPath}`, logLevel);
    utils:logVerbose(string `output: ${outputDir}`, logLevel);

    utils:CommandResult result = executeBalClientGenerate(specPath, outputDir, (), logLevel);

    if !utils:isCommandSuccessfull(result) {
        if result.compilationErrors.length() > 0 {
            foreach utils:CmdCompilationError err in result.compilationErrors {
                utils:logVerbose(string `  ${err.fileName}:${err.line}:${err.column} — ${err.message}`, logLevel);
            }
        }
        return error("client generation failed: " + result.stderr);
    }
}

# Generate Ballerina client with full config (used from main.bal interactive path).
public function generateBallerinaClient(string specPath, string outputDir, ClientGeneratorConfig config, utils:LogLevel logLevel = "normal") returns error? {
    if !getUserConfirmation("Proceed with Ballerina client generation?", config.autoYes) {
        utils:logInfo("skipping client generation", logLevel);
        return;
    }

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

function getUserConfirmation(string message, boolean autoYes = false) returns boolean {
    if autoYes {
        return true;
    }
    io:fprint(io:stderr, string `${message} (y/n): `);
    string|io:Error userInput = io:readln();
    if userInput is io:Error {
        return false;
    }
    string trimmedInput = userInput.trim().toLowerAscii();
    return trimmedInput == "y" || trimmedInput == "Y" || trimmedInput == "yes";
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
