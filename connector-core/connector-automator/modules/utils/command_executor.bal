import ballerina/file;
import ballerina/io;
import ballerina/os;
import ballerina/regex;
import ballerina/time;

public function executeCommand(string command, string workingDir, LogLevel logLevel = "normal") returns CommandResult {
    time:Utc startTime = time:utcNow();
    logVerbose(string `executing: ${command}`, logLevel);

    string stdout = "";
    string stderr = "";
    int exitCode = -1;
    boolean success = false;

    if command.trim().length() == 0 {
        stderr = "Empty command string";
        exitCode = 1;
    } else {
        if workingDir.trim().length() > 0 {
            boolean|error dirExists = file:test(workingDir, file:EXISTS);
            if dirExists is error || !dirExists {
                error? createResult = file:createDir(workingDir, file:RECURSIVE);
                if createResult is error {
                    stderr = string `Failed to create working directory: ${createResult.toString()}`;
                    exitCode = 1;
                    success = false;
                } else {
                    logVerbose(string `created working directory: ${workingDir}`, logLevel);
                }
            }
        }

        if stderr == "" {
            string tempDir = "/tmp";
            int timestamp = <int>time:utcNow()[0];
            string stdoutFile = string `${tempDir}/bal_stdout_${timestamp}.txt`;
            string stderrFile = string `${tempDir}/bal_stderr_${timestamp}.txt`;

            string[] commandParts = regex:split(command, " ");
            if commandParts.length() == 0 {
                stderr = "Empty command";
                exitCode = 1;
            } else {
                string redirectedCommand = string `cd "${workingDir}" && ${command} > "${stdoutFile}" 2> "${stderrFile}"`;

                os:Command cmd = {
                    value: "sh",
                    arguments: ["-c", redirectedCommand]
                };

                os:Process|error proc = os:exec(cmd);
                if proc is os:Process {
                    int|error exitResult = proc.waitForExit();
                    if exitResult is int {
                        exitCode = exitResult;
                        success = exitCode == 0;

                        string|io:Error stdoutContent = io:fileReadString(stdoutFile);
                        if stdoutContent is string {
                            stdout = stdoutContent;
                        } else {
                            stdout = "";
                            logVerbose(string `failed to read stdout file: ${stdoutContent.message()}`, logLevel);
                        }

                        string|io:Error stderrContent = io:fileReadString(stderrFile);
                        if stderrContent is string {
                            stderr = stderrContent;
                        } else {
                            stderr = "";
                            logVerbose(string `failed to read stderr file: ${stderrContent.message()}`, logLevel);
                        }

                        file:Error? removeStdout = file:remove(stdoutFile);
                        file:Error? removeStderr = file:remove(stderrFile);
                    } else {
                        stderr = exitResult.toString();
                        exitCode = 1;
                    }
                } else {
                    stderr = proc.toString();
                    exitCode = 1;
                }
            }
        }
    }
    time:Utc endTime = time:utcNow();
    decimal executionTime = <decimal>(endTime[0] - startTime[0]);

    if !success {
        logVerbose(string `command exited ${exitCode}: ${stderr.trim()}`, logLevel);
    }

    CmdCompilationError[] compilationErrors = [];
    if stderr.includes("ERROR [") || stderr.includes("WARNING [") {
        compilationErrors = parseCmdCompilationErrors(stderr);
    }

    return {
        command: command,
        success: success,
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr,
        compilationErrors: compilationErrors,
        executionTime: executionTime
    };
}

public function getDirectoryPath(string filePath) returns string {
    int? lastSlashIndex = filePath.lastIndexOf("/");
    if lastSlashIndex is int {
        return filePath.substring(0, lastSlashIndex);
    }
    return ".";
}

public function parseCmdCompilationErrors(string output) returns CmdCompilationError[] {
    CmdCompilationError[] errors = [];

    string[] lines = regex:split(output, "\n");

    foreach string line in lines {
        if (line.includes("ERROR [") || line.includes("WARNING [")) && line.includes(")]") {
            string errorType = line.includes("ERROR [") ? "ERROR" : "WARNING";
            string prefix = errorType + " [";

            int? startBracket = line.indexOf(prefix);
            int? endBracket = line.indexOf(")]", startBracket ?: 0);

            if startBracket is int && endBracket is int {
                string errorPart = line.substring(startBracket + prefix.length(), endBracket);

                int? coordStart = errorPart.lastIndexOf(":(");

                if coordStart is int {
                    string fileName = errorPart.substring(0, coordStart);
                    string coordinates = errorPart.substring(coordStart + 2);

                    string[] coordParts = regex:split(coordinates, ",");
                    if coordParts.length() > 0 {
                        string[] lineCol = regex:split(coordParts[0], ":");
                        if lineCol.length() >= 2 {
                            int|error lineNum = int:fromString(lineCol[0]);
                            int|error col = int:fromString(lineCol[1]);

                            string message = line.substring(endBracket + 2).trim();

                            if lineNum is int && col is int {
                                CmdCompilationError compilationError = {
                                    fileName: fileName,
                                    line: lineNum,
                                    errorType: errorType,
                                    column: col,
                                    message: message
                                };
                                errors.push(compilationError);
                            }
                        }
                    }
                }
            }
        }
    }
    return errors;
}

public function isCommandSuccessfull(CommandResult result) returns boolean {
    return result.exitCode == 0;
}

public function hasCompilationErrors(CommandResult result) returns boolean {
    if result.exitCode != 0 {
        return true;
    }
    string stderrLower = result.stderr.toLowerAscii();
    boolean hasError = stderrLower.includes("error:") || stderrLower.includes("error [") || stderrLower.includes("compilation failed");
    return hasError;
}

public function getErrorSummary(CmdCompilationError[] errors) returns string {
    if errors.length() == 0 {
        return "No compilation errors";
    }

    map<int> errorByFile = {};

    foreach CmdCompilationError err in errors {
        int currentCount = errorByFile[err.fileName] ?: 0;
        errorByFile[err.fileName] = currentCount + 1;
    }

    string[] summaryParts = [];
    foreach string fileName in errorByFile.keys() {
        int count = errorByFile[fileName] ?: 0;
        summaryParts.push(string `${count} errors in ${fileName}`);
    }

    return string `Found ${errors.length()} total compilation errors: ${string:'join(",", ...summaryParts)}`;
}

public function executeBalFlatten(string inputPath, string outputPath) returns CommandResult {
    string command = string `bal openapi flatten -i ${inputPath} -o ${outputPath}`;
    return executeCommand(command, ".");
}

public function executeBalAlign(string inputPath, string outputPath) returns CommandResult {
    string command = string `bal openapi align -i ${inputPath} -o ${outputPath}`;
    return executeCommand(command, ".");
}

public function executeBalClientGenerate(string inputPath, string outputPath) returns CommandResult {
    string command = string `bal openapi -i ${inputPath} --mode client -o ${outputPath}`;
    return executeCommand(command, getDirectoryPath(outputPath));
}

public function executeBalBuild(string projectPath, LogLevel logLevel = "normal") returns CommandResult {
    CommandResult result = executeCommand("bal build", projectPath, logLevel);

    string combinedOutput = result.stdout + "\n" + result.stderr;
    result.compilationErrors = parseCmdCompilationErrors(combinedOutput);

    if result.compilationErrors.length() > 0 {
        result.success = false;
    }

    return result;
}

public function resolveBallerinaDir(string connectorPath) returns string|error {
    if check file:test(connectorPath + "/ballerina/Ballerina.toml", file:EXISTS) {
        return connectorPath + "/ballerina";
    }
    return connectorPath;
}
