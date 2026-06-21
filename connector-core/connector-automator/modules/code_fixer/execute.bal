import wso2/connector_automator.utils;

import ballerina/io;

public function executeCodeFixer(string connectorPath) returns error? {
    utils:logVerbose(string `project: ${connectorPath}`);

    FixResult|BallerinaFixerError result = fixAllErrors(connectorPath, true);

    if result is FixResult {
        if result.success {
            if result.errorsFixed == 0 {
                utils:logInfo("✓ no errors found — project already compiles");
            } else {
                utils:logInfo(string `✓ fixed ${result.errorsFixed} error${result.errorsFixed == 1 ? "" : "s"}`);
            }
        } else {
            utils:logWarn(string `partial success: fixed ${result.errorsFixed}, ${result.errorsRemaining} remain — manual intervention may be required`);
            if utils:getLogLevel() == "verbose" && result.remainingFixes.length() > 0 {
                foreach string issue in result.remainingFixes {
                    utils:logVerbose(string `  remaining: ${issue}`);
                }
            }
        }
    } else {
        utils:logError(string `code fixer failed: ${result.message()}`);
        return result;
    }
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
    return userInput.trim().toLowerAscii() is "y"|"yes";
}

function printUsage() {
    io:fprintln(io:stderr, "Code Error Fixer");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE");
    io:fprintln(io:stderr, "  bal connector openapi fix-code <connector-path> [-q|-v]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ENVIRONMENT");
    io:fprintln(io:stderr, "  ANTHROPIC_API_KEY    Required for AI-powered fixes");
}
