import wso2/connector_automator.utils;

import ballerina/io;
import ballerina/os;

public function executeDocGen(string command, string connectorPath, string[] excluded = [], utils:LogLevel logLevel = "normal") returns error? {
    utils:logVerbose(string `command: ${command}, connector: ${connectorPath}`, logLevel);

    match command {
        "generate-all" => {
            check generateAllReadmes(connectorPath, excluded, logLevel);
        }
        "generate-ballerina" => {
            check genBallerinaReadme(connectorPath, logLevel);
        }
        "generate-tests" => {
            check genTestsReadme(connectorPath, logLevel);
        }
        "generate-examples" => {
            check genExamplesReadme(connectorPath, logLevel);
        }
        "generate-individual-examples" => {
            check genIndividualExampleReadmes(connectorPath, logLevel);
        }
        "generate-main" => {
            check genMainReadme(connectorPath, logLevel);
        }
        _ => {
            utils:logError(string `unknown doc command: '${command}'`);
            printUsage();
        }
    }
}

function generateAllReadmes(string connectorPath, string[] excluded, utils:LogLevel logLevel) returns error? {
    check validateApiKey();
    check initDocumentationGenerator();
    utils:logVerbose("✓ AI generator initialized", logLevel);

    utils:logVerbose("generating documentation files", logLevel);

    if excluded.indexOf("client") is () {
        check generateMainReadme(connectorPath, logLevel);
        check generateBallerinaReadme(connectorPath, logLevel);
    }
    if excluded.indexOf("tests") is () {
        check generateTestsReadme(connectorPath, logLevel);
    }
    if excluded.indexOf("examples") is () {
        check generateExamplesReadme(connectorPath, logLevel);
        check generateIndividualExampleReadmes(connectorPath, logLevel);
    }

    utils:logInfo(string `✓ documentation generated at ${connectorPath}/`, logLevel);
}

function genBallerinaReadme(string connectorPath, utils:LogLevel logLevel) returns error? {
    check validateApiKey();
    check initDocumentationGenerator();

    error? result = generateBallerinaReadme(connectorPath, logLevel);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ README: ${connectorPath}/ballerina/README.md`, logLevel);
}

function genTestsReadme(string connectorPath, utils:LogLevel logLevel) returns error? {
    check validateApiKey();
    check initDocumentationGenerator();

    error? result = generateTestsReadme(connectorPath, logLevel);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ README: ${connectorPath}/ballerina/tests/README.md`, logLevel);
}

function genExamplesReadme(string connectorPath, utils:LogLevel logLevel) returns error? {
    check validateApiKey();
    check initDocumentationGenerator();

    error? result = generateExamplesReadme(connectorPath, logLevel);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ README: ${connectorPath}/examples/README.md`, logLevel);
}

function genIndividualExampleReadmes(string connectorPath, utils:LogLevel logLevel) returns error? {
    check validateApiKey();
    check initDocumentationGenerator();

    error? result = generateIndividualExampleReadmes(connectorPath, logLevel);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ READMEs: ${connectorPath}/examples/*/README.md`, logLevel);
}

function genMainReadme(string connectorPath, utils:LogLevel logLevel) returns error? {
    check validateApiKey();
    check initDocumentationGenerator();

    error? result = generateMainReadme(connectorPath, logLevel);
    if result is error {
        utils:logError(string `README generation failed: ${result.message()}`);
        return result;
    }
    utils:logInfo(string `✓ README: ${connectorPath}/README.md`, logLevel);
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
