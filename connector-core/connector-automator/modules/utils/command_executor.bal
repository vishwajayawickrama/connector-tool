// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/file;
import ballerina/io;
import ballerina/lang.regexp;
import ballerina/os;
import ballerina/random;
import ballerina/time;

public function executeCommand(string command, string workingDir, int timeoutSeconds = 1800) returns CommandResult {
    time:Utc startTime = time:utcNow();
    logVerbose(string `executing: ${getDisplayCommand(command)}`);

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
                    logVerbose(string `created working directory: ${getDisplayPath(workingDir)}`);
                }
            }
        }

        if stderr == "" {
            int|random:Error randomResult = random:createIntInRange(0, 2147483647);
            int randomSuffix = randomResult is int ? randomResult : 0;
            string tempDir = string `/tmp/bal_exec_${startTime[0]}_${regexp:replaceAll(re `\.`, startTime[1].toString(), "_")}_${randomSuffix}`;
            error? dirCreated = file:createDir(tempDir, file:RECURSIVE);
            string stdoutFile = string `${tempDir}/stdout.txt`;
            string stderrFile = string `${tempDir}/stderr.txt`;

            string[] commandParts = regexp:split(re ` `, command);
            if commandParts.length() == 0 {
                stderr = "Empty command";
                exitCode = 1;
            } else if dirCreated is error {
                stderr = string `Failed to create temp directory: ${dirCreated.toString()}`;
                exitCode = 1;
            } else {
                // Portable watchdog: start the command in an isolated process group,
                // track an explicit sentinel file when the watchdog fires, and on
                // timeout terminate the group gracefully (SIGTERM) before forcing it
                // (SIGKILL). Exit 124 (GNU timeout convention) when the sentinel
                // confirms the watchdog fired; preserve genuine external kills (OOM).
                string redirectedCommand = string `wd_marker="${tempDir}/.wd_fired" ; set -m ; cd "${workingDir}" && ${command} > "${stdoutFile}" 2> "${stderrFile}" & cmdpid=$! ; set +m ; ( sleep ${timeoutSeconds} ; touch "$wd_marker" ; kill -TERM -- -$cmdpid 2>/dev/null ; sleep 2 ; kill -9 -- -$cmdpid 2>/dev/null ) & wdpid=$! ; wait $cmdpid ; rc=$? ; kill $wdpid 2>/dev/null ; if [ -f "$wd_marker" ]; then exit 124 ; fi ; exit $rc`;

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
                            logVerbose(string `failed to read stdout file: ${stdoutContent.message()}`);
                        }

                        string|io:Error stderrContent = io:fileReadString(stderrFile);
                        if stderrContent is string {
                            stderr = stderrContent;
                        } else {
                            stderr = "";
                            logVerbose(string `failed to read stderr file: ${stderrContent.message()}`);
                        }

                        // Exit 124 = sentinel confirms watchdog fired → timed out.
                        if exitCode == 124 {
                            stderr = string `${stderr}${stderr.trim().length() > 0 ? "\n" : ""}command timed out after ${timeoutSeconds}s`;
                            logWarn(string `command timed out after ${timeoutSeconds}s: ${command}`);
                        }

                        do { check file:remove(stdoutFile); } on fail { }
                        do { check file:remove(stderrFile); } on fail { }
                        do { check file:remove(tempDir, file:RECURSIVE); } on fail { }
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
        logVerbose(string `command exited ${exitCode}: ${stderr.trim()}`);
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
    int? lastBackslashIndex = filePath.lastIndexOf("\\");
    int separatorIndex = -1;
    if lastSlashIndex is int {
        separatorIndex = lastSlashIndex;
    }
    if lastBackslashIndex is int && lastBackslashIndex > separatorIndex {
        separatorIndex = lastBackslashIndex;
    }
    if separatorIndex >= 0 {
        if separatorIndex == 0 {
            return filePath.substring(0, 1);
        }
        if separatorIndex == 2 && filePath.substring(1, 2) == ":" {
            return filePath.substring(0, 3);
        }
        return filePath.substring(0, separatorIndex);
    }
    return ".";
}

public function parseCmdCompilationErrors(string output) returns CmdCompilationError[] {
    CmdCompilationError[] errors = [];

    string[] lines = regexp:split(re `\n`, output);

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

                    string[] coordParts = regexp:split(re `,`, coordinates);
                    if coordParts.length() > 0 {
                        string[] lineCol = regexp:split(re `:`, coordParts[0]);
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

public function executeBalBuild(string projectPath) returns CommandResult {
    CommandResult result = executeCommand("bal build", projectPath);

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
