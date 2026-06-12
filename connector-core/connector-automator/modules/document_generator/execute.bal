import wso2/connector_automator.utils;

import ballerina/io;
import ballerina/os;

public function executeDocGen(string command, string connectorPath, utils:LogLevel logLevel = "normal") returns error? {
    utils:logVerbose(string `command: ${command}, connector: ${connectorPath}`, logLevel);

    match command {
        "generate-all" => {
            check generateAllReadmes(connectorPath, true, logLevel);
        }
        "generate-ballerina" => {
            check genBallerinaReadme(connectorPath, true, logLevel);
        }
        "generate-tests" => {
            check genTestsReadme(connectorPath, true, logLevel);
        }
        "generate-examples" => {
            check genExamplesReadme(connectorPath, true, logLevel);
        }
        "generate-individual-examples" => {
            check genIndividualExampleReadmes(connectorPath, true, logLevel);
        }
        "generate-main" => {
            check genMainReadme(connectorPath, true, logLevel);
        }
        _ => {
            utils:logError(string `unknown doc command: '${command}'`);
            printUsage();
        }
    }
}

function generateAllReadmes(string connectorPath, boolean autoYes, utils:LogLevel logLevel) returns error? {
    if !getUserConfirmation("Proceed with documentation generation?", autoYes) {
        utils:logInfo("skipping documentation generation", logLevel);
        return;
    }

    check validateApiKey();
    check initDocumentationGenerator();
    utils:logVerbose("✓ AI generator initialized", logLevel);

    utils:logVerbose("generating documentation files", logLevel);
    check generateAllDocumentation(connectorPath, logLevel);

    utils:logInfo(string `✓ documentation generated at ${connectorPath}/`, logLevel);
}

function genBallerinaReadme(string connectorPath, boolean autoYes, utils:LogLevel logLevel) returns error? {
    if !getUserConfirmation("Proceed with generation?", autoYes) {
        utils:logInfo("skipping Ballerina README generation", logLevel);
        return;
    }

    check validateApiKey();
    check initDocumentationGenerator();

    error? result = generateBallerinaReadme(connectorPath, logLevel);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ README: ${connectorPath}/ballerina/README.md`, logLevel);
}

function genTestsReadme(string connectorPath, boolean autoYes, utils:LogLevel logLevel) returns error? {
    if !getUserConfirmation("Proceed with generation?", autoYes) {
        utils:logInfo("skipping tests README generation", logLevel);
        return;
    }

    check validateApiKey();
    check initDocumentationGenerator();

    error? result = generateTestsReadme(connectorPath, logLevel);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ README: ${connectorPath}/ballerina/tests/README.md`, logLevel);
}

function genExamplesReadme(string connectorPath, boolean autoYes, utils:LogLevel logLevel) returns error? {
    if !getUserConfirmation("Proceed with generation?", autoYes) {
        utils:logInfo("skipping examples README generation", logLevel);
        return;
    }

    check validateApiKey();
    check initDocumentationGenerator();

    error? result = generateExamplesReadme(connectorPath, logLevel);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ README: ${connectorPath}/examples/README.md`, logLevel);
}

function genIndividualExampleReadmes(string connectorPath, boolean autoYes, utils:LogLevel logLevel) returns error? {
    if !getUserConfirmation("Proceed with generation?", autoYes) {
        utils:logInfo("skipping individual example READMEs generation", logLevel);
        return;
    }

    check validateApiKey();
    check initDocumentationGenerator();

    error? result = generateIndividualExampleReadmes(connectorPath, logLevel);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ READMEs: ${connectorPath}/examples/*/README.md`, logLevel);
}

function genMainReadme(string connectorPath, boolean autoYes, utils:LogLevel logLevel) returns error? {
    if !getUserConfirmation("Proceed with generation?", autoYes) {
        utils:logInfo("skipping root README generation", logLevel);
        return;
    }

    check validateApiKey();
    check initDocumentationGenerator();

    error? result = generateMainReadme(connectorPath, logLevel);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ README: ${connectorPath}/README.md`, logLevel);
}

function getUserConfirmation(string message, boolean autoYes) returns boolean {
    if autoYes {
        return true;
    }
    io:fprint(io:stderr, string `${message} (y/n): `);
    string|io:Error userInput = io:readln();
    if userInput is io:Error {
        return false;
    }
    return userInput.trim().toLowerAscii() is "y"|"yes";
}

function validateApiKey() returns error? {
    string? apiKey = os:getEnv("ANTHROPIC_API_KEY");
    if apiKey is () || apiKey.trim().length() == 0 {
        return error("ANTHROPIC_API_KEY not configured");
    }
}

function printUsage() {
    io:fprintln(io:stderr, "Documentation Generator");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE");
    io:fprintln(io:stderr, "  bal connector openapi generate-docs generate-all <connector-path> [-q|-v]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "COMMANDS");
    io:fprintln(io:stderr, "  generate-all                 Generate all READMEs");
    io:fprintln(io:stderr, "  generate-ballerina           Generate module README");
    io:fprintln(io:stderr, "  generate-tests               Generate tests README");
    io:fprintln(io:stderr, "  generate-examples            Generate examples README");
    io:fprintln(io:stderr, "  generate-individual-examples Generate example READMEs");
    io:fprintln(io:stderr, "  generate-main                Generate root README");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ENVIRONMENT");
    io:fprintln(io:stderr, "  ANTHROPIC_API_KEY    Required for AI-powered documentation");
}
