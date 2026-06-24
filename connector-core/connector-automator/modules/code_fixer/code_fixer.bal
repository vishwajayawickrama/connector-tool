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
import ballerina/lang.array;
import ballerina/lang.regexp;
import ballerina/os;

import wso2/connector_automator.utils;

configurable int maxIterations = 3;
configurable boolean enableLLMResponseLogs = false;
configurable string llmResponseLogDirName = ".code_fixer_llm_logs";

function executeBalBuild(string projectPath, boolean isFinalCheck = false)
        returns record {|boolean success; string stdout; string stderr;|}|error {
    record {|int exitCode; string stdout; string stderr;|}|error commandResult =
        executeShellCommand(projectPath, "bal build");
    if commandResult is error {
        return commandResult;
    }

    if !isFinalCheck && commandResult.exitCode != 0 {
        utils:logVerbose("bal build failed; attempting AI-driven fixes...");
    }

    return {
        success: commandResult.exitCode == 0,
        stdout: commandResult.stdout,
        stderr: commandResult.stderr
    };
}

function isCommandSuccessfull(record {|boolean success; string stdout; string stderr;|} result) returns boolean {
    return result.success;
}

// Parse compilation errors from build output (only ERRORs)
public function parseCompilationErrors(string stderr) returns CompilationError[] {
    CompilationError[] errors = [];
    string[] lines = regexp:split(re `\n`, stderr);

    foreach string line in lines {
        // Handle only ERROR messages
        if (line.includes("ERROR [") && line.includes(")]")) {
            string severity = "ERROR";
            string prefix = severity + " [";

            int? startBracket = line.indexOf(prefix);
            int? endBracket = line.indexOf(")]", startBracket ?: 0);

            if startBracket is int && endBracket is int {
                // Extract the part between prefix and ")]"
                string errorPart = line.substring(startBracket + prefix.length(), endBracket);

                // Find the last occurrence of ":(" to split filename from coordinates
                int? coordStart = errorPart.lastIndexOf(":(");

                if coordStart is int {
                    string filePath = errorPart.substring(0, coordStart);
                    string coordinates = errorPart.substring(coordStart + 2);

                    // Parse coordinates - format can be (line:col) or (line:col,endLine:endCol)
                    string[] coordParts = regexp:split(re `,`, coordinates);
                    if coordParts.length() > 0 {
                        // Get the first coordinate pair (line:col)
                        string[] lineCol = regexp:split(re `:`, coordParts[0]);
                        if lineCol.length() >= 2 {
                            int|error lineNum = int:fromString(lineCol[0]);
                            int|error col = int:fromString(lineCol[1]);

                            // Extract message - everything after ")]" plus 2 for ") "
                            string message = line.substring(endBracket + 2).trim();

                            if lineNum is int && col is int {
                                CompilationError compilationError = {
                                    filePath: filePath,
                                    line: lineNum,
                                    severity: severity,
                                    column: col,
                                    message: message,
                                    language: "ballerina",
                                    sourceTool: "bal"
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

public function parseJavaCompilationErrors(string stderr, string projectPath = "") returns CompilationError[] {
    CompilationError[] errors = [];
    string[] lines = regexp:split(re `\n`, stderr);

    int i = 0;
    while i < lines.length() {
        string line = lines[i].trim();

        int? errorTokenIndex = line.indexOf(": error:");
        if errorTokenIndex is int {
            string locationPart = line.substring(0, errorTokenIndex);
            string messagePart = line.substring(errorTokenIndex + 8).trim();

            int lineNumber = 1;
            int columnNumber = 1;
            string filePath = locationPart;

            int? lastColon = locationPart.lastIndexOf(":");
            if lastColon is int {
                string possibleLineNumber = locationPart.substring(lastColon + 1);
                int|error parsedLine = int:fromString(possibleLineNumber);
                if parsedLine is int {
                    lineNumber = parsedLine;
                    filePath = locationPart.substring(0, lastColon);
                }
            }

            string fullMessage = messagePart;
            int lookahead = i + 1;
            int consumed = 0;
            while lookahead < lines.length() && consumed < 6 {
                string nextLine = lines[lookahead].trim();
                if nextLine.startsWith("symbol:") || nextLine.startsWith("location:") {
                    fullMessage = string `${fullMessage} | ${nextLine}`;
                }
                if nextLine.length() > 0 && nextLine.endsWith("error:") {
                    break;
                }
                lookahead += 1;
                consumed += 1;
            }

            string normalizedFilePath = normalizeDiagnosticPath(filePath, projectPath);

            if isBackupArtifactPath(normalizedFilePath) {
                i += 1;
                continue;
            }

            CompilationError compilationError = {
                filePath: normalizedFilePath,
                line: lineNumber,
                column: columnNumber,
                message: fullMessage,
                severity: "ERROR",
                language: "java",
                sourceTool: "gradle"
            };
            errors.push(compilationError);
        } else {
            string lowerLine = line.toLowerAscii();
            int? javaMarker = line.indexOf(".java:");
            int? genericErrorIndex = lowerLine.indexOf("error");
            if javaMarker is int && genericErrorIndex is int {
                string filePath = line.substring(0, javaMarker + 5);
                string afterJava = line.substring(javaMarker + 6);

                int lineNumber = 1;
                int? nextColon = afterJava.indexOf(":");
                if nextColon is int {
                    string possibleLine = afterJava.substring(0, nextColon);
                    int|error parsedLine = int:fromString(possibleLine);
                    if parsedLine is int {
                        lineNumber = parsedLine;
                    }
                }

                string normalizedFilePath = normalizeDiagnosticPath(filePath, projectPath);
                if isBackupArtifactPath(normalizedFilePath) {
                    i += 1;
                    continue;
                }
                string fullMessage = line.substring(genericErrorIndex).trim();
                if fullMessage.length() == 0 {
                    fullMessage = "Compilation error";
                }

                CompilationError compilationError = {
                    filePath: normalizedFilePath,
                    line: lineNumber,
                    column: 1,
                    message: fullMessage,
                    severity: "ERROR",
                    language: "java",
                    sourceTool: "gradle"
                };
                errors.push(compilationError);
            }
        }

        i += 1;
    }

    return errors;
}

function normalizeDiagnosticPath(string filePath, string projectPath) returns string {
    if projectPath.trim().length() == 0 {
        return filePath;
    }

    string normalizedRoot = projectPath.endsWith("/") ? projectPath : string `${projectPath}/`;
    if filePath.startsWith(normalizedRoot) {
        return filePath.substring(normalizedRoot.length());
    }

    return filePath;
}

function isBackupArtifactPath(string path) returns boolean {
    string lower = path.toLowerAscii();
    return lower.includes("_backup.") || lower.endsWith(".backup") || lower.endsWith(".bak");
}

function isEligibleBallerinaSourcePath(string path) returns boolean {
    string lower = path.toLowerAscii();
    if !lower.endsWith(".bal") {
        return false;
    }
    if isBackupArtifactPath(lower) {
        return false;
    }
    if lower.startsWith("target/") || lower.includes("/target/") || lower.startsWith("build/") ||
        lower.includes("/build/") {
        return false;
    }
    return lower.endsWith("client.bal") || lower.endsWith("types.bal") || lower.endsWith("main.bal") || lower.endsWith("test.bal")
        || lower.endsWith("mock_server.bal");
}

function isInteropClassNotFoundError(CompilationError err) returns boolean {
    string message = err.message.toUpperAscii();
    return message.includes("CLASS_NOT_FOUND") || message.includes("'ORG.BALLERINAX") ||
        message.includes("JBALLERINA.JAVA");
}

function executeShellCommand(string workingDir, string shellCommand) returns record {|int exitCode; string stdout; string stderr;|}|error {
    string stdoutFile = ".code_fixer.stdout.log";
    string stderrFile = ".code_fixer.stderr.log";
    string stdoutPath = check file:joinPath(workingDir, stdoutFile);
    string stderrPath = check file:joinPath(workingDir, stderrFile);

    string script = string `cd "$0" && ${shellCommand} > "$1" 2> "$2"`;
    os:Process process = check os:exec({
                                           value: "bash",
                                           arguments: ["-c", script, workingDir, stdoutFile, stderrFile]
                                       });

    int exitCode = check process.waitForExit();

    string stdout = "";
    string|io:Error stdoutRead = io:fileReadString(stdoutPath);
    if stdoutRead is string {
        stdout = stdoutRead;
    }

    string stderr = "";
    string|io:Error stderrRead = io:fileReadString(stderrPath);
    if stderrRead is string {
        stderr = stderrRead;
    }

    check cleanupCommandLogs(stdoutPath, stderrPath);

    return {
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr
    };
}

function cleanupCommandLogs(string stdoutPath, string stderrPath) returns error? {
    boolean stdoutExists = check file:test(stdoutPath, file:EXISTS);
    if stdoutExists {
        check file:remove(stdoutPath);
    }

    boolean stderrExists = check file:test(stderrPath, file:EXISTS);
    if stderrExists {
        check file:remove(stderrPath);
    }
}

function runGradleBuild(string projectPath)
        returns record {|boolean success; string stdout; string stderr;|}|error {
    // Generated native/ dirs don't have their own gradlew; it lives one level up (project root).
    // Detect that case and run Gradle from the project root so the wrapper is found.
    string buildRoot = projectPath;
    string gradlewInCurrent = check file:joinPath(projectPath, "gradlew");
    boolean hasLocalGradlew = check file:test(gradlewInCurrent, file:EXISTS);
    if !hasLocalGradlew {
        string parentDir = resolveParentDirectory(projectPath);
        string gradlewInParent = check file:joinPath(parentDir, "gradlew");
        boolean hasParentGradlew = check file:test(gradlewInParent, file:EXISTS);
        if hasParentGradlew {
            buildRoot = parentDir;
            utils:logVerbose(string `gradlew not found in projectPath, elevated build root to parent: ${buildRoot}`);
        }
    }
    utils:logVerbose(string `Running Gradle build: ${buildRoot}`);

    string jdkEnvPrefix = "if [ -x /usr/lib/jvm/java-21-openjdk-amd64/bin/javac ]; then export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64; " +
        "elif command -v javac >/dev/null 2>&1; then export JAVA_HOME=\"$(dirname $(dirname $(readlink -f $(command -v javac))))\"; fi; " +
        "if [ -n \"$JAVA_HOME\" ]; then export PATH=\"$JAVA_HOME/bin:$PATH\"; fi; " +
        "gradleJvmArg=\"\"; if [ -n \"$JAVA_HOME\" ]; then gradleJvmArg=\"-Dorg.gradle.java.home=$JAVA_HOME\"; fi; ";
    string buildCommand = jdkEnvPrefix + "if [ -x ./gradlew ]; then ./gradlew $gradleJvmArg clean build --console=plain --no-daemon; " +
        "elif [ -x ../../sdkanalyzer/native/gradlew ]; then ../../sdkanalyzer/native/gradlew -p . $gradleJvmArg clean build --console=plain --no-daemon; " +
        "elif [ -x /usr/bin/gradle ]; then /usr/bin/gradle $gradleJvmArg clean build --console=plain --no-daemon; " +
        "elif command -v gradle >/dev/null 2>&1; then gradle $gradleJvmArg clean build --console=plain --no-daemon; " +
        "else echo 'Gradle executable not found (checked ./gradlew, ../../sdkanalyzer/native/gradlew, gradle in PATH)' >&2; exit 127; fi";

    record {|int exitCode; string stdout; string stderr;|}|error commandResult =
        executeShellCommand(buildRoot, buildCommand);
    if commandResult is error {
        return commandResult;
    }

    boolean buildSuccess = commandResult.exitCode == 0;
    if buildSuccess {
        utils:logVerbose(string `Gradle build succeeded: ${buildRoot}`);
    } else {
        utils:logVerbose(string `Gradle build failed (exit ${commandResult.exitCode}): ${buildRoot}`);
        utils:logVerbose("Gradle build failed; attempting Java-native fixes...");
    }

    return {
        success: buildSuccess,
        stdout: commandResult.stdout,
        stderr: commandResult.stderr
    };
}

public function fixJavaNativeAdaptorErrors(string projectPath,
        boolean autoYes = true, int iterationLimit = maxIterations)
        returns FixResult|BallerinaFixerError {
    if !utils:isAIServiceInitialized() {
        error? initResult = utils:initAIService();
        if initResult is error {
            return error BallerinaFixerError("Failed to initialize AI service", initResult);
        }
    }

    FixResult result = {
        success: false,
        errorsFixed: 0,
        errorsRemaining: 0,
        appliedFixes: [],
        remainingFixes: []
    };

    utils:logVerbose(string `Starting Java native fixer: ${projectPath} (limit=${iterationLimit})`);

    error? preCleanupError = cleanupFixerBackups(projectPath);
    if preCleanupError is error {
        utils:logWarn(string `Failed to clean stale backup files: ${preCleanupError.message()}`);
    }

    int iteration = 1;
    CompilationError[] previousErrors = [];
    int initialErrorCount = 0;
    boolean initialErrorCountSet = false;

    while iteration <= iterationLimit {
        utils:logVerbose(string `[iteration ${iteration}/${iterationLimit}] Java fix loop`);
        record {|boolean success; string stdout; string stderr;|}|error buildResult = runGradleBuild(projectPath);
        if buildResult is error {
            return error BallerinaFixerError("Failed to run Gradle build", buildResult);
        }

        if buildResult.success {
            utils:logVerbose(string `Java native fixer complete — build succeeded: ${projectPath}`);
            result.success = true;
            result.errorsRemaining = 0;
            result.javaErrorsRemaining = 0;
            result.errorsFixed = initialErrorCount;
            result.javaErrorsFixed = initialErrorCount;
            return result;
        }

        string diagnostics = string `${buildResult.stderr}\n${buildResult.stdout}`;
        CompilationError[] currentErrors = parseJavaCompilationErrors(diagnostics, projectPath);

        if currentErrors.length() == 0 {
            utils:logWarn("Gradle build failed but no parseable Java errors found (non-javac failure)");
            result.errorsRemaining = 1;
            result.javaErrorsRemaining = 1;
            result.success = false;
            string diagnosticsSummary = summarizeDiagnostics(diagnostics);
            result.remainingFixes.push(string `Gradle build failed but no parseable Java diagnostics were found (non-javac/gradle-level failure). ${diagnosticsSummary}`);
            return result;
        }

        if !initialErrorCountSet {
            initialErrorCount = currentErrors.length();
            initialErrorCountSet = true;
            utils:logVerbose(string `Java compile errors detected: ${initialErrorCount}`);
        }

        if iteration > 1 && currentErrors.length() >= previousErrors.length() {
            boolean sameErrors = checkIfErrorsAreSame(currentErrors, previousErrors);
            if sameErrors {
                utils:logVerbose(string `No progress — same Java errors persist, stopping (iteration ${iteration})`);
                result.remainingFixes.push(string `Iteration ${iteration}: No progress - same Java errors persist`);
                break;
            }
        }

        previousErrors = currentErrors.clone();
        map<CompilationError[]> errorsByFile = groupErrorsByFile(currentErrors);
        boolean anyFixApplied = false;
        int generatedFixCount = 0;

        foreach string filePath in errorsByFile.keys() {
            CompilationError[] fileErrors = errorsByFile.get(filePath);
            FixResponse|error fixResponse = fixFileWithLLM(projectPath, filePath, fileErrors);
            if fixResponse is error {
                utils:logVerbose(string `Failed to generate fix for Java file ${filePath}: ${fixResponse.message()}`);
                result.remainingFixes.push(string `Iteration ${iteration}: Failed to fix Java file ${filePath}: ${fixResponse.message()}`);
                continue;
            }
            generatedFixCount += 1;

            boolean shouldApplyFix = autoYes;
            if shouldApplyFix {
                boolean|error applyResult = applyFix(projectPath, filePath, fixResponse.fixedCode);
                if applyResult is error {
                    result.remainingFixes.push(string `Iteration ${iteration}: Failed to apply fix to ${filePath}: ${applyResult.message()}`);
                    continue;
                }

                anyFixApplied = true;
                result.appliedFixes.push(string `Fixed Java ${filePath} (${fileErrors.length()} error${fileErrors.length() == 1 ? "" : "s"})`);
            }
        }

        if !autoYes {
            result.success = false;
            result.errorsRemaining = currentErrors.length();
            result.javaErrorsRemaining = currentErrors.length();
            result.errorsFixed = 0;
            result.javaErrorsFixed = 0;
            if generatedFixCount > 0 {
                result.remainingFixes.push(string `Iteration ${iteration}: Report-only mode - fixes were generated but not applied`);
            }
            return result;
        }

        if !anyFixApplied {
            utils:logWarn(string `no Java fixes applied in iteration ${iteration}, stopping`);
            result.remainingFixes.push(string `Iteration ${iteration}: No Java fixes applied`);
            break;
        }

        iteration += 1;
    }

    record {|boolean success; string stdout; string stderr;|}|error finalBuild = runGradleBuild(projectPath);
    if finalBuild is error {
        return error BallerinaFixerError("Failed to run final Gradle build", finalBuild);
    }

    if finalBuild.success {
        utils:logVerbose(string `Java native fixer complete — all errors resolved: ${projectPath}`);
        result.success = true;
        result.errorsRemaining = 0;
        result.javaErrorsRemaining = 0;
        result.errorsFixed = initialErrorCount;
        result.javaErrorsFixed = initialErrorCount;
    } else {
        CompilationError[] remainingErrors = parseJavaCompilationErrors(string `${finalBuild.stderr}\n${finalBuild.stdout}`, projectPath);
        if remainingErrors.length() == 0 {
            result.errorsRemaining = 1;
            result.javaErrorsRemaining = 1;
            result.errorsFixed = 0;
            result.javaErrorsFixed = 0;
            string finalDiagnostics = string `${finalBuild.stderr}\n${finalBuild.stdout}`;
            string diagnosticsSummary = summarizeDiagnostics(finalDiagnostics);
            result.remainingFixes.push(string `Final Gradle build still failed but diagnostics were not parseable as Java compile errors. ${diagnosticsSummary}`);
        } else {
            result.errorsRemaining = remainingErrors.length();
            result.javaErrorsRemaining = remainingErrors.length();
            int fixedCount = initialErrorCountSet ? initialErrorCount - remainingErrors.length() : 0;
            result.errorsFixed = fixedCount > 0 ? fixedCount : 0;
            result.javaErrorsFixed = result.errorsFixed;
            utils:logVerbose(string `Java native fixer complete — errors remain: fixed=${result.errorsFixed} remaining=${result.errorsRemaining}`);
        }
    }

    error? postCleanupError = cleanupFixerBackups(projectPath);
    if postCleanupError is error {
        utils:logWarn(string `Failed to clean backup files: ${postCleanupError.message()}`);
    }

    return result;
}

function summarizeDiagnostics(string diagnostics) returns string {
    string[] lines = regexp:split(re `\n`, diagnostics);
    string[] nonEmptyLines = [];
    foreach string line in lines {
        string trimmed = line.trim();
        if trimmed.length() > 0 {
            nonEmptyLines.push(trimmed);
            if nonEmptyLines.length() == 12 {
                break;
            }
        }
    }

    if nonEmptyLines.length() == 0 {
        return "No diagnostic output captured";
    }

    return string `Diagnostic sample: ${string:'join(" | ", ...nonEmptyLines)}`;
}

// Group errors by file path
public function groupErrorsByFile(CompilationError[] errors) returns map<CompilationError[]> {
    map<CompilationError[]> grouped = {};

    foreach CompilationError err in errors {
        if !grouped.hasKey(err.filePath) {
            grouped[err.filePath] = [];
        }
        grouped.get(err.filePath).push(err);
    }
    return grouped;
}

// Prepare error context string
function prepareErrorContext(CompilationError[] errors) returns string {
    string[] errorStrings = errors.'map(function(CompilationError err) returns string {
        return string `Line ${err.line}, Column ${err.column}: ${err.severity} - ${err.message}`;
    });
    return string:'join("\n", ...errorStrings);
}

function getTypeContextForFile(string projectPath, string filePath) returns string {
    string[] contextParts = [];
    string|io:Error typesContent = io:fileReadString(projectPath + "/types.bal");
    if typesContent is string {
        contextParts.push("FULL TYPES DEFINITIONS (types.bal):\n" + typesContent);
    }
    if filePath.includes("mock") {
        string|io:Error mockTypes = io:fileReadString(projectPath + "/modules/mock.server/types.bal");
        if mockTypes is string {
            contextParts.push("MOCK TYPES DEFINITIONS:\n" + mockTypes);
        }
    }
    string|io:Error clientContent = io:fileReadString(projectPath + "/client.bal");
    if clientContent is string {
        contextParts.push("FULL CLIENT IMPLEMENTATION (client.bal):\n" + clientContent);
    }
    return string:'join("\n\n---\n\n", ...contextParts);
}

function buildFixHistoryContext(FixAttempt[] attempts) returns string {
    string[] historyLines = [];
    foreach FixAttempt attempt in attempts {
        historyLines.push(string `Iteration ${attempt.iteration}: ${attempt.appliedFix}`);
    }
    return string:'join("\n", ...historyLines);
}

function describeCodeChange(CompilationError[] errors) returns string {
    string[] summaries = [];
    foreach CompilationError err in errors {
        string shortMessage = err.message.length() > 80 ?
            err.message.substring(0, 77) + "..." : err.message;
        summaries.push(string `Line ${err.line}: ${shortMessage}`);
    }
    return string:'join("; ", ...summaries);
}

function inferErrorLanguage(CompilationError[] errors) returns string {
    if errors.length() == 0 {
        return "ballerina";
    }

    string language = errors[0].language.trim().toLowerAscii();
    if language == "java" {
        return "java";
    }
    return "ballerina";
}

// Fix errors in a single file
public function fixFileWithLLM(string projectPath, string filePath, CompilationError[] errors,
        FixAttempt[] previousAttempts = []) returns FixResponse|error {
    utils:logVerbose(string `Analyzing ${filePath} (${errors.length()} error${errors.length() == 1 ? "" : "s"})`);

    // Check if AI service is initialized
    if !utils:isAIServiceInitialized() {
        return error("AI service not initialized. Please set ANTHROPIC_API_KEY.");
    }

    // Construct full file path
    string fullFilePath = check file:joinPath(projectPath, filePath);

    // Validate file exists
    boolean exists = check file:test(fullFilePath, file:EXISTS);
    if !exists {
        return error(string `File does not exist: ${fullFilePath}`);
    }

    // Read file content
    string|io:Error fileContent = io:fileReadString(fullFilePath);
    if fileContent is io:Error {
        utils:logWarn(string `✗ Failed to read ${filePath}`);
        return fileContent;
    }

    string language = inferErrorLanguage(errors);
    utils:logVerbose(string `fixing ${filePath} (${language}, ${errors.length()} errors)`);
    if language == "java" {
        // Try deterministic (pattern-based) fixes first
        string|() deterministicCandidate = applyDeterministicJavaCompileFixes(fileContent, errors);
        if deterministicCandidate is string {
            error? deterministicValidationError = validateJavaFixCandidate(fileContent, <string>deterministicCandidate,
                    filePath, errors.length());
            if deterministicValidationError is () {
                utils:logVerbose(string `Java fix applied via deterministic pattern: ${filePath}`);
                utils:logInfo(string `✓ Fixed ${filePath} using deterministic pattern`);
                return {
                    success: true,
                    fixedCode: <string>deterministicCandidate,
                    explanation: "Fixed using deterministic Java compile fallback"
                };
            }
        }

        // LLM-based targeted patch
        int attempt = 1;
        int maxJavaAttempts = 3;
        string lastValidationFailure = "";
        string lastRawResponse = "";
        utils:logVerbose(string `attempting LLM-based Java fix: ${filePath} (max ${maxJavaAttempts} attempts)`);

        while attempt <= maxJavaAttempts {
            string prompt = createJavaFixPrompt(fileContent, errors, filePath, lastValidationFailure,
                    lastRawResponse, attempt);

            string|error llmResponse = utils:callAI(prompt);
            if llmResponse is error {
                utils:logWarn(string `✗ AI call failed for ${filePath}: ${llmResponse.message()}`);
                return error(string `LLM call failed: ${llmResponse.message()}`);
            }

            error? rawLogError = writeLLMResponseLog(projectPath, filePath, attempt, "raw-response", llmResponse);
            if rawLogError is error {
                utils:logWarn(string `⚠  Log write failed: ${rawLogError.message()}`);
            }

            // Parse JSON edit operations from LLM response
            string normalizedJson = normalizeJsonResponse(llmResponse);
            JavaEditOperation[]|error editOps = parseJavaEditOperations(normalizedJson);
            if editOps is error {
                lastValidationFailure = string `Failed to parse JSON edits: ${editOps.message()}`;
                lastRawResponse = llmResponse;
                utils:logVerbose(string `LLM edit parse failed: ${filePath} attempt=${attempt}: ${editOps.message()}`);
                error? parseLogError = writeLLMResponseLog(projectPath, filePath, attempt,
                        "parse-failure", lastValidationFailure);
                if parseLogError is error {
                    utils:logWarn(string `⚠  Log write failed: ${parseLogError.message()}`);
                }
                if attempt < maxJavaAttempts {
                    utils:logVerbose(string `⚠  Failed to parse LLM edits for ${filePath}; retrying (${attempt + 1}/${maxJavaAttempts})`);
                }
                attempt += 1;
                continue;
            }

            if editOps.length() == 0 {
                lastValidationFailure = "LLM returned empty edit list";
                lastRawResponse = llmResponse;
                utils:logVerbose(string `LLM returned empty edit list: ${filePath} attempt=${attempt}`);
                if attempt < maxJavaAttempts {
                    utils:logVerbose(string `⚠  LLM returned no edits for ${filePath}; retrying (${attempt + 1}/${maxJavaAttempts})`);
                }
                attempt += 1;
                continue;
            }

            utils:logVerbose(string `LLM returned ${editOps.length()} edit operations: ${filePath} attempt=${attempt}`);

            // Apply edits to the original file content
            string|error patchedCode = applyJavaEditOperations(fileContent, editOps);
            if patchedCode is error {
                lastValidationFailure = string `Failed to apply edits: ${patchedCode.message()}`;
                lastRawResponse = llmResponse;
                utils:logVerbose(string `edit application failed: ${filePath} attempt=${attempt}: ${patchedCode.message()}`);
                if attempt < maxJavaAttempts {
                    utils:logVerbose(string `⚠  Edit application failed for ${filePath}; retrying (${attempt + 1}/${maxJavaAttempts})`);
                }
                attempt += 1;
                continue;
            }

            // Log the patched result
            error? patchedLogError = writeLLMResponseLog(projectPath, filePath, attempt,
                    "patched-result", patchedCode);
            if patchedLogError is error {
                utils:logWarn(string `⚠  Log write failed: ${patchedLogError.message()}`);
            }

            // Validate the patched result
            error? patchValidationError = validateJavaFixCandidate(fileContent, patchedCode, filePath,
                    errors.length());
            if patchValidationError is () {
                utils:logVerbose(string `Java fix applied via LLM patch: ${filePath} attempt=${attempt} edits=${editOps.length()}`);
                utils:logInfo(string `✓ Fixed ${filePath} using LLM patch (${editOps.length()} edit${editOps.length() == 1 ? "" : "s"})`);
                return {
                    success: true,
                    fixedCode: patchedCode,
                    explanation: string `Fixed using AI patch (${editOps.length()} edits)`
                };
            }

            // If validation failed due to too-many-lines, try localized merge fallback
            string validationMsg = (<error>patchValidationError).message();
            if validationMsg.includes("changed too many lines") {
                string|() localizedMerge = applyLocalizedJavaMerge(fileContent, patchedCode, errors,
                        windowRadius = 6);
                if localizedMerge is string {
                    error? mergeValidation = validateJavaFixCandidate(fileContent, localizedMerge, filePath,
                            errors.length());
                    if mergeValidation is () {
                        utils:logVerbose(string `Java fix applied via localized merge: ${filePath} attempt=${attempt}`);
                        utils:logInfo(string `✓ Fixed ${filePath} using localized merge (${editOps.length()} edit${editOps.length() == 1 ? "" : "s"})`);
                        return {
                            success: true,
                            fixedCode: localizedMerge,
                            explanation: string `Fixed using AI patch with localized merge (${editOps.length()} edits)`
                        };
                    }
                }
                // Also try structural safe merge
                string|() structuralMerge = applyStructuralSafeJavaMerge(fileContent, patchedCode, errors,
                        windowRadius = 6);
                if structuralMerge is string {
                    error? structuralValidation = validateJavaFixCandidate(fileContent, structuralMerge, filePath,
                            errors.length());
                    if structuralValidation is () {
                        utils:logVerbose(string `Java fix applied via structural merge: ${filePath} attempt=${attempt}`);
                        utils:logInfo(string `✓ Fixed ${filePath} using structural merge (${editOps.length()} edit${editOps.length() == 1 ? "" : "s"})`);
                        return {
                            success: true,
                            fixedCode: structuralMerge,
                            explanation: string `Fixed using AI patch with structural merge (${editOps.length()} edits)`
                        };
                    }
                }
            }

            lastValidationFailure = validationMsg;
            lastRawResponse = llmResponse;
            string validationSummary = string `attempt=${attempt}\n` +
                string `editsCount=${editOps.length()}\n` +
                string `validationError=${lastValidationFailure}\n` +
                string `balancedBraces=${hasBalancedJavaBraces(patchedCode)}\n`;
            error? validationLogError = writeLLMResponseLog(projectPath, filePath, attempt,
                    "validation-result", validationSummary);
            if validationLogError is error {
                utils:logWarn(string `⚠  Log write failed: ${validationLogError.message()}`);
            }

            utils:logVerbose(string `patch validation failed: ${filePath} attempt=${attempt}: ${lastValidationFailure}`);
            if attempt < maxJavaAttempts {
                utils:logVerbose(string `⚠  Patch validation failed for ${filePath}: ${lastValidationFailure}; retrying (${attempt + 1}/${maxJavaAttempts})`);
            }
            attempt += 1;
        }

        utils:logVerbose(string `all Java LLM fix attempts exhausted: ${filePath} attempts=${maxJavaAttempts}`);
        utils:logWarn(string `✗ All ${maxJavaAttempts} Java fix attempts failed for ${filePath}`);
        return error(string `Java fix failed after ${maxJavaAttempts} attempts for ${filePath}: ${lastValidationFailure}`);
    }

    utils:logVerbose(string `attempting LLM-based Ballerina fix: ${filePath} (${errors.length()} errors)`);
    string typeContext = (filePath.includes("test") || filePath.includes("mock")) ?
        getTypeContextForFile(projectPath, filePath) : "";
    string prompt = createFixPromptWithHistory(fileContent, errors, filePath, typeContext,
            buildFixHistoryContext(previousAttempts));

    string|error llmResponse = utils:callAI(prompt);
    if llmResponse is error {
        utils:logVerbose(string `LLM call failed for Ballerina fix: ${filePath}: ${llmResponse.message()}`);
        utils:logWarn(string `✗ AI failed to generate fix for ${filePath}`);
        return error(string `LLM failed to generate fix: ${llmResponse.message()}`);
    }

    string normalizedResponse = normalizeCodeResponse(llmResponse);

    utils:logVerbose(string `Ballerina fix generated via LLM: ${filePath}`);
    utils:logInfo(string `✓ Generated fix for ${filePath}`);

    return {
        success: true,
        fixedCode: normalizedResponse,
        explanation: "Fixed using AI"
    };
}

function normalizeCodeResponse(string responseText) returns string {
    string trimmed = responseText.trim();
    if !trimmed.startsWith("```") {
        return trimmed;
    }

    string[] lines = regexp:split(re `\n`, trimmed);
    if lines.length() < 2 {
        return trimmed;
    }

    int startIndex = 0;
    if lines[0].trim().startsWith("```") {
        startIndex = 1;
    }

    int endIndexExclusive = lines.length();
    if lines[lines.length() - 1].trim() == "```" {
        endIndexExclusive = lines.length() - 1;
    }

    if startIndex >= endIndexExclusive {
        return trimmed;
    }

    string[] bodyLines = [];
    foreach int i in startIndex ..< endIndexExclusive {
        bodyLines.push(lines[i]);
    }

    return string:'join("\n", ...bodyLines).trim();
}

// Java patch-based edit types and functions

function normalizeJsonResponse(string responseText) returns string {
    string trimmed = responseText.trim();

    // Strip markdown code fences if present
    if trimmed.startsWith("```") {
        string[] lines = regexp:split(re `\n`, trimmed);
        int startIndex = 1;
        int endIndexExclusive = lines.length();
        if lines[lines.length() - 1].trim() == "```" {
            endIndexExclusive = lines.length() - 1;
        }
        string[] bodyLines = [];
        foreach int i in startIndex ..< endIndexExclusive {
            bodyLines.push(lines[i]);
        }
        trimmed = string:'join("\n", ...bodyLines).trim();
    }

    // Find the JSON array boundaries
    int? arrayStart = trimmed.indexOf("[");
    int? arrayEnd = trimmed.lastIndexOf("]");
    if arrayStart is int && arrayEnd is int && arrayEnd > arrayStart {
        return trimmed.substring(arrayStart, arrayEnd + 1);
    }

    return trimmed;
}

function parseJavaEditOperations(string jsonText) returns JavaEditOperation[]|error {
    json|error parsed = jsonText.fromJsonString();
    if parsed is error {
        return error(string `Invalid JSON: ${parsed.message()}`);
    }

    if parsed !is json[] {
        return error("Expected JSON array of edit operations");
    }

    json[] editsArray = <json[]>parsed;
    if editsArray.length() == 0 {
        return [];
    }

    JavaEditOperation[] ops = [];
    foreach json editJson in editsArray {
        json|error startLineJson = editJson.startLine;
        json|error endLineJson = editJson.endLine;
        json|error replacementJson = editJson.replacement;

        if startLineJson is error || endLineJson is error || replacementJson is error {
            return error("Edit operation missing required fields (startLine, endLine, replacement)");
        }

        int|error startLine = int:fromString(startLineJson.toString());
        int|error endLine = int:fromString(endLineJson.toString());

        if startLine is error || endLine is error {
            return error("startLine/endLine must be integers");
        }

        if startLine < 1 || endLine < startLine {
            return error(string `Invalid line range: ${startLine}-${endLine}`);
        }

        string[] replacementLines = [];
        if replacementJson is json[] {
            foreach json lineJson in <json[]>replacementJson {
                string line = <string>lineJson;
                replacementLines.push(line);
            }
        } else {
            return error("replacement must be a JSON array of strings");
        }

        ops.push({
            startLine: startLine,
            endLine: endLine,
            replacement: replacementLines
        });
    }

    // Sort by startLine descending so we apply from bottom to top (avoids line-number shifts)
    int i = 0;
    while i < ops.length() - 1 {
        int j = i + 1;
        while j < ops.length() {
            if ops[j].startLine > ops[i].startLine {
                JavaEditOperation temp = ops[i];
                ops[i] = ops[j];
                ops[j] = temp;
            }
            j += 1;
        }
        i += 1;
    }

    // Check for overlapping ranges
    int k = 0;
    while k < ops.length() - 1 {
        if ops[k].startLine <= ops[k + 1].endLine {
            return error(string `Overlapping edit ranges: ${ops[k + 1].startLine}-${ops[k + 1].endLine} and ${ops[k].startLine}-${ops[k].endLine}`);
        }
        k += 1;
    }

    return ops;
}

function applyJavaEditOperations(string originalCode, JavaEditOperation[] ops) returns string|error {
    string[] lines = regexp:split(re `\n`, originalCode);
    int totalLines = lines.length();

    // ops are sorted descending by startLine, so apply from bottom to top
    foreach JavaEditOperation op in ops {
        if op.startLine < 1 || op.endLine > totalLines {
            return error(string `Edit range ${op.startLine}-${op.endLine} out of bounds (file has ${totalLines} lines)`);
        }

        // Build new lines array: before + replacement + after
        string[] newLines = [];

        // Lines before the edit range
        foreach int idx in 0 ..< (op.startLine - 1) {
            newLines.push(lines[idx]);
        }

        // Replacement lines
        foreach string replacementLine in op.replacement {
            newLines.push(replacementLine);
        }

        // Lines after the edit range
        foreach int idx in op.endLine ..< totalLines {
            newLines.push(lines[idx]);
        }

        lines = newLines;
        totalLines = lines.length();
    }

    return string:'join("\n", ...lines);
}

function writeLLMResponseLog(string projectPath, string filePath, int attempt, string phase, string content) returns error? {
    if !enableLLMResponseLogs {
        return;
    }

    string logDirPath = check file:joinPath(projectPath, llmResponseLogDirName);
    boolean logDirExists = check file:test(logDirPath, file:EXISTS);
    if !logDirExists {
        check file:createDir(logDirPath);
    }

    string safeFilePath = sanitizeForLogFileName(filePath);
    string safePhase = sanitizeForLogFileName(phase);
    string logFileName = string `${safeFilePath}.attempt-${attempt}.${safePhase}.log`;
    string logPath = check file:joinPath(logDirPath, logFileName);

    io:Error? writeResult = io:fileWriteString(logPath, content, io:OVERWRITE);
    if writeResult is io:Error {
        return writeResult;
    }

    utils:logVerbose(string `↳ LLM log: ${logPath}`);
}

function sanitizeForLogFileName(string input) returns string {
    string value = regexp:replaceAll(re `[\\/:\s]`, input, "_");
    return value;
}

function applyDeterministicJavaCompileFixes(string originalCode, CompilationError[] errors) returns string|() {
    string[] lines = regexp:split(re `\n`, originalCode);
    if lines.length() == 0 {
        return;
    }

    string[] updatedLines = lines.clone();
    boolean changed = false;

    foreach CompilationError err in errors {
        string message = err.message.toLowerAscii();
        int errorLine = err.line;

        if message.includes("unreported exception") && message.includes("must be caught or declared to be thrown") {
            boolean fixedInterface = false;
            foreach int i in 0 ..< updatedLines.length() {
                string trimmed = updatedLines[i].trim();
                if trimmed == "Object call() throws Exception;" {
                    string ws = getLeadingWhitespace(updatedLines[i]);
                    updatedLines[i] = string `${ws}Object call() throws Exception;`;
                    fixedInterface = true;
                    break;
                }
            }

            if !fixedInterface {
                boolean addedCatch = false;
                int searchStart = errorLine - 1;
                if searchStart < 0 {
                    searchStart = 0;
                }
                int searchEnd = errorLine + 10;
                if searchEnd > updatedLines.length() {
                    searchEnd = updatedLines.length();
                }
                foreach int i in searchStart ..< searchEnd {
                    string trimmed = updatedLines[i].trim();
                    if trimmed.startsWith("} catch (") && !trimmed.includes("Exception e") {
                        int braceCount = 0;
                        boolean foundOpenBrace = false;
                        int insertAfter = i;
                        foreach int j in i ..< searchEnd {
                            string jLine = updatedLines[j];
                            byte[] jBytes = jLine.toBytes();
                            foreach byte b in jBytes {
                                if b == 123 { // {
                                    braceCount += 1;
                                    foundOpenBrace = true;
                                }
                                if b == 125 { // }
                                    braceCount -= 1;
                                }
                            }
                            if foundOpenBrace && braceCount == 0 {
                                insertAfter = j;
                                break;
                            }
                        }

                        string insertAfterTrimmed = updatedLines[insertAfter].trim();
                        if insertAfterTrimmed == "}" {
                            string insertWs = getLeadingWhitespace(updatedLines[insertAfter]);
                            updatedLines[insertAfter] = string `${insertWs}} catch (Exception e) {`;
                            string[] newLines = [];
                            foreach int n in 0 ... insertAfter {
                                newLines.push(updatedLines[n]);
                            }
                            newLines.push(string `${insertWs}    return createError("unexpected error: " + e.getMessage(), e);`);
                            newLines.push(string `${insertWs}}`);
                            foreach int n in (insertAfter + 1) ..< updatedLines.length() {
                                newLines.push(updatedLines[n]);
                            }
                            updatedLines = newLines;
                            addedCatch = true;
                            changed = true;
                        }
                        break;
                    }
                }

                if !addedCatch {
                    int tryLine = -1;
                    foreach int i in 0 ..< errorLine {
                        int reverseIdx = errorLine - 1 - i;
                        if reverseIdx < 0 {
                            break;
                        }
                        string trimmed = updatedLines[reverseIdx].trim();
                        if trimmed.startsWith("try {") || trimmed == "try {" {
                            tryLine = reverseIdx;
                            break;
                        }
                    }

                    if tryLine >= 0 {
                        int braceCount = 0;
                        boolean inTry = false;
                        int lastCatchClose = -1;
                        foreach int i in tryLine ..< updatedLines.length() {
                            string jLine = updatedLines[i];
                            byte[] jBytes = jLine.toBytes();
                            foreach byte b in jBytes {
                                if b == 123 {
                                    braceCount += 1;
                                    inTry = true;
                                }
                                if b == 125 {
                                    braceCount -= 1;
                                }
                            }
                            if inTry && braceCount == 0 {
                                lastCatchClose = i;
                                break;
                            }
                        }

                        if lastCatchClose > 0 {
                            string ws = getLeadingWhitespace(updatedLines[lastCatchClose]);
                            string[] newLines = [];
                            foreach int n in 0 ..< lastCatchClose {
                                newLines.push(updatedLines[n]);
                            }
                            newLines.push(string `${ws}} catch (Exception e) {`);
                            newLines.push(string `${ws}    return createError("unexpected error: " + e.getMessage(), e);`);
                            newLines.push(string `${ws}}`);
                            foreach int n in (lastCatchClose + 1) ..< updatedLines.length() {
                                newLines.push(updatedLines[n]);
                            }
                            updatedLines = newLines;
                            changed = true;
                        }
                    }
                }
            }
        }

    }

    if !changed {
        return;
    }

    string result = string:'join("\n", ...updatedLines);
    if !hasBalancedJavaBraces(result) {
        return;
    }

    return result;
}

function getLeadingWhitespace(string line) returns string {
    byte[] bytes = line.toBytes();
    int idx = 0;
    while idx < bytes.length() {
        byte b = bytes[idx];
        if b == 32 || b == 9 {
            idx += 1;
            continue;
        }
        break;
    }

    if idx == 0 {
        return "";
    }

    return line.substring(0, idx);
}

function validateJavaFixCandidate(string originalCode, string fixedCode, string filePath, int errorCount = 1) returns error? {
    if fixedCode.trim().length() == 0 {
        return error(string `LLM produced empty Java content for ${filePath}`);
    }

    string originalPackage = extractJavaPackageLine(originalCode);
    string fixedPackage = extractJavaPackageLine(fixedCode);
    if originalPackage.length() > 0 && originalPackage != fixedPackage {
        return error(string `LLM changed package declaration for ${filePath}`);
    }

    string originalClass = extractJavaClassName(originalCode);
    string fixedClass = extractJavaClassName(fixedCode);
    if originalClass.length() > 0 && originalClass != fixedClass {
        return error(string `LLM changed class name for ${filePath}`);
    }

    int originalMethodCount = countMethodAnchors(originalCode);
    int fixedMethodCount = countMethodAnchors(fixedCode);
    if originalMethodCount > 0 && fixedMethodCount < originalMethodCount / 2 {
        return error(string `LLM output dropped too many methods for ${filePath}`);
    }

    int originalLength = originalCode.length();
    int fixedLength = fixedCode.length();
    if originalLength > 0 && fixedLength < (originalLength * 7 / 10) {
        return error(string `LLM output appears truncated for ${filePath}`);
    }

    if !hasBalancedJavaBraces(fixedCode) {
        return error(string `LLM output has unbalanced braces for ${filePath}`);
    }

    if !fixedCode.trim().endsWith("}") {
        return error(string `LLM output appears incomplete at file end for ${filePath}`);
    }

    int changedLineCount = countChangedLineCount(originalCode, fixedCode);
    int maxAllowedChanges = errorCount * 12;
    if maxAllowedChanges < 24 {
        maxAllowedChanges = 24;
    }
    if changedLineCount > maxAllowedChanges {
        return error(string `LLM output changed too many lines (${changedLineCount}) for ${filePath}`);
    }
}

function countChangedLineCount(string originalCode, string fixedCode) returns int {
    string[] originalLines = regexp:split(re `\n`, originalCode);
    string[] fixedLines = regexp:split(re `\n`, fixedCode);

    int maxLineCount = originalLines.length();
    if fixedLines.length() > maxLineCount {
        maxLineCount = fixedLines.length();
    }

    int changedLines = 0;
    foreach int i in 0 ..< maxLineCount {
        string originalLine = i < originalLines.length() ? originalLines[i] : "";
        string fixedLine = i < fixedLines.length() ? fixedLines[i] : "";
        if originalLine != fixedLine {
            changedLines += 1;
        }
    }

    return changedLines;
}

function applyLocalizedJavaMerge(string originalCode, string candidateCode, CompilationError[] errors,
        int windowRadius = 4) returns string|() {
    if candidateCode.trim().length() == 0 {
        return;
    }

    string[] originalLines = regexp:split(re `\n`, originalCode);
    string[] candidateLines = regexp:split(re `\n`, candidateCode);
    if candidateLines.length() == 0 {
        return;
    }

    string[] mergedLines = originalLines.clone();
    boolean changed = false;
    int maxLineCount = mergedLines.length();
    if candidateLines.length() > maxLineCount {
        maxLineCount = candidateLines.length();
    }

    foreach CompilationError err in errors {
        int errorLine = err.line;
        if errorLine <= 0 {
            continue;
        }

        int startLine = errorLine - windowRadius;
        if startLine < 1 {
            startLine = 1;
        }

        int endLine = errorLine + windowRadius;
        if endLine > maxLineCount {
            endLine = maxLineCount;
        }

        foreach int lineNum in startLine ... endLine {
            int index = lineNum - 1;
            string candidateLine = index < candidateLines.length() ? candidateLines[index] : "";
            if index < mergedLines.length() {
                if mergedLines[index] != candidateLine {
                    mergedLines[index] = candidateLine;
                    changed = true;
                }
            }
        }
    }

    if !changed {
        return;
    }

    return string:'join("\n", ...mergedLines);
}

function applyStructuralSafeJavaMerge(string originalCode, string candidateCode, CompilationError[] errors,
        int windowRadius = 4) returns string|() {
    if candidateCode.trim().length() == 0 {
        return;
    }

    string[] originalLines = regexp:split(re `\n`, originalCode);
    string[] candidateLines = regexp:split(re `\n`, candidateCode);
    if candidateLines.length() == 0 {
        return;
    }

    string[] mergedLines = originalLines.clone();
    boolean changed = false;
    int maxLineCount = mergedLines.length();
    if candidateLines.length() < maxLineCount {
        maxLineCount = candidateLines.length();
    }

    foreach CompilationError err in errors {
        int errorLine = err.line;
        if errorLine <= 0 {
            continue;
        }

        int startLine = errorLine - windowRadius;
        if startLine < 1 {
            startLine = 1;
        }

        int endLine = errorLine + windowRadius;
        if endLine > maxLineCount {
            endLine = maxLineCount;
        }

        foreach int lineNum in startLine ... endLine {
            int index = lineNum - 1;
            if index >= mergedLines.length() || index >= candidateLines.length() {
                continue;
            }

            string originalLine = mergedLines[index];
            string candidateLine = candidateLines[index];
            if originalLine == candidateLine {
                continue;
            }

            if !isStructuralSafeReplacement(originalLine, candidateLine) {
                continue;
            }

            mergedLines[index] = candidateLine;
            changed = true;
        }
    }

    if !changed {
        return;
    }

    string mergedCode = string:'join("\n", ...mergedLines);
    if !hasBalancedJavaBraces(mergedCode) {
        return;
    }

    return mergedCode;
}

function isStructuralSafeReplacement(string originalLine, string candidateLine) returns boolean {
    string originalTrimmed = originalLine.trim();
    string candidateTrimmed = candidateLine.trim();

    if originalTrimmed.startsWith("package ") || candidateTrimmed.startsWith("package ") {
        return false;
    }

    if originalTrimmed.startsWith("import ") || candidateTrimmed.startsWith("import ") {
        return false;
    }

    if originalLine.includes(" class ") || candidateLine.includes(" class ") {
        return false;
    }

    if originalLine.includes(" interface ") || candidateLine.includes(" interface ") {
        return false;
    }

    if originalLine.includes(" enum ") || candidateLine.includes(" enum ") {
        return false;
    }

    if originalLine.includes("{") || originalLine.includes("}") || candidateLine.includes("{") ||
        candidateLine.includes("}") {
        return false;
    }

    int originalBracketDelta = getCharDelta(originalLine, 40, 41);
    int candidateBracketDelta = getCharDelta(candidateLine, 40, 41);
    if originalBracketDelta != candidateBracketDelta {
        return false;
    }

    return true;
}

function getCharDelta(string line, byte openByte, byte closeByte) returns int {
    int balance = 0;
    byte[] bytes = line.toBytes();
    foreach byte b in bytes {
        if b == openByte {
            balance += 1;
        } else if b == closeByte {
            balance -= 1;
        }
    }
    return balance;
}

function hasBalancedJavaBraces(string sourceCode) returns boolean {
    int balance = 0;
    byte[] bytes = sourceCode.toBytes();
    foreach byte b in bytes {
        if b == 123 {
            balance += 1;
        } else if b == 125 {
            balance -= 1;
            if balance < 0 {
                return false;
            }
        }
    }
    return balance == 0;
}

function extractJavaPackageLine(string sourceCode) returns string {
    string[] lines = regexp:split(re `\n`, sourceCode);
    foreach string line in lines {
        string trimmed = line.trim();
        if trimmed.startsWith("package ") && trimmed.endsWith(";") {
            return trimmed;
        }
    }
    return "";
}

function extractJavaClassName(string sourceCode) returns string {
    string[] lines = regexp:split(re `\n`, sourceCode);
    foreach string line in lines {
        string trimmed = line.trim();
        if trimmed.includes(" class ") {
            string[] parts = regexp:split(re `\s+`, trimmed);
            int i = 0;
            while i < parts.length() {
                if parts[i] == "class" && i + 1 < parts.length() {
                    string classToken = parts[i + 1].trim();
                    if classToken.endsWith("{") {
                        return classToken.substring(0, classToken.length() - 1).trim();
                    }
                    return classToken;
                }
                i += 1;
            }
        }
    }
    return "";
}

function countMethodAnchors(string sourceCode) returns int {
    string[] lines = regexp:split(re `\n`, sourceCode);
    int count = 0;
    foreach string line in lines {
        string trimmed = line.trim();
        if trimmed.startsWith("public static ") && trimmed.includes("(") {
            count += 1;
        }
    }
    return count;
}

// Apply fix to file
public function applyFix(string projectPath, string filePath, string fixedCode) returns boolean|error {
    string fullFilePath = check file:joinPath(projectPath, filePath);

    // Create backup
    string|io:Error originalContent = io:fileReadString(fullFilePath);
    if originalContent is io:Error {
        return originalContent;
    }

    string backupPath = getBackupPath(fullFilePath);
    io:Error? backupResult = io:fileWriteString(backupPath, originalContent, io:OVERWRITE);
    if backupResult is io:Error {
        utils:logWarn(string `⚠  Failed to create backup for ${filePath}`);
        return backupResult;
    }

    // Apply fix
    io:Error? writeResult = io:fileWriteString(fullFilePath, fixedCode, io:OVERWRITE);
    if writeResult is io:Error {
        utils:logWarn(string `✗ Failed to apply fix to ${filePath}`);

        // Attempt to restore from backup
        io:Error? restoreResult = io:fileWriteString(fullFilePath, originalContent, io:OVERWRITE);
        if restoreResult is io:Error {
            utils:logWarn(string `⚠  Failed to restore original content for ${filePath}`);
        } else {
            do {
                check file:remove(backupPath);
            } on fail {
            }
        }
        return writeResult;
    }

    utils:logVerbose(string `✓ Applied fix to ${filePath}`);
    do {
        check file:remove(backupPath);
    } on fail {
    }
    return true;
}

function resolveParentDirectory(string dirPath) returns string {
    string normalized = dirPath.endsWith("/") ? dirPath.substring(0, dirPath.length() - 1) : dirPath;
    int? lastSlash = normalized.lastIndexOf("/");
    if lastSlash is int && lastSlash > 0 {
        return normalized.substring(0, lastSlash);
    }
    if lastSlash is int && lastSlash == 0 {
        return "/";
    }
    return ".";
}

function getBackupPath(string fullFilePath) returns string {
    int? lastSlash = fullFilePath.lastIndexOf("/");
    int? lastDot = fullFilePath.lastIndexOf(".");

    boolean hasExtension = lastDot is int && (lastSlash is () || <int>lastDot > <int>lastSlash);
    if hasExtension {
        int dotIndex = <int>lastDot;
        string base = fullFilePath.substring(0, dotIndex);
        string ext = fullFilePath.substring(dotIndex);
        return string `${base}_backup${ext}.bak`;
    }

    return fullFilePath + "_backup.bak";
}

function cleanupFixerBackups(string projectPath) returns error? {
    boolean exists = check file:test(projectPath, file:EXISTS);
    if !exists {
        return;
    }
    int count = check removeBackupFilesRecursive(projectPath);
    if count > 0 {
        utils:logVerbose(string `Removed ${count} stale backup artifact(s)`);
    }
}

function removeBackupFilesRecursive(string dir) returns int|error {
    file:MetaData[] entries = check file:readDir(dir);
    int count = 0;
    foreach file:MetaData entry in entries {
        if entry.dir {
            count += check removeBackupFilesRecursive(entry.absPath);
        } else if isBackupArtifactPath(entry.absPath) {
            check file:remove(entry.absPath);
            count += 1;
        }
    }
    return count;
}

// Main function to fix all errors in a project
public function fixAllErrors(string projectPath, boolean autoYes = false) returns FixResult|BallerinaFixerError {
    // Initialize AI service if not already initialized
    if !utils:isAIServiceInitialized() {
        error? initResult = utils:initAIService();
        if initResult is error {
            return error BallerinaFixerError("Failed to initialize AI service", initResult);
        }
    }

    FixResult result = {
        success: false,
        errorsFixed: 0,
        errorsRemaining: 0,
        appliedFixes: [],
        remainingFixes: []
    };

    utils:logVerbose(string `Starting Ballerina fixer: ${projectPath}`);

    error? preCleanupError = cleanupFixerBackups(projectPath);
    if preCleanupError is error {
        utils:logWarn(string `Failed to clean stale backup files: ${preCleanupError.message()}`);
    }

    int iteration = 1;
    CompilationError[] previousErrors = [];
    int initialErrorCount = 0;
    boolean initialErrorCountSet = false;
    map<FixAttempt[]> fileFixHistory = {};

    utils:logVerbose("Starting error fixing process...");

    while iteration <= maxIterations {
        utils:logVerbose(string `[Iteration ${iteration}/${maxIterations}] Building project...`);

        // Build the project and get diagnostics
        record {|boolean success; string stdout; string stderr;|}|error buildResultOrError = executeBalBuild(projectPath);
        if buildResultOrError is error {
            return error BallerinaFixerError("Failed to execute bal build", buildResultOrError);
        }
        record {|boolean success; string stdout; string stderr;|} buildResult = buildResultOrError;

        if isCommandSuccessfull(buildResult) {
            result.success = true;
            result.errorsRemaining = 0;

            if iteration == 1 {
                result.errorsFixed = 0;
                utils:logVerbose(string `Ballerina project builds cleanly — no errors to fix: ${projectPath}`);
                utils:logInfo("✓ Project builds successfully (no errors to fix)");
            } else {
                result.errorsFixed = initialErrorCount;
                utils:logVerbose(string `Ballerina fixer complete — all errors resolved: ${projectPath} (fixed=${initialErrorCount})`);
                utils:logInfo("✓ All compilation errors resolved!");
            }
            return result;
        }

        // Parse errors from build output
        string diagnostics = string `${buildResult.stderr}\n${buildResult.stdout}`;
        CompilationError[] parsedErrors = parseCompilationErrors(diagnostics);
        CompilationError[] currentErrors = [];
        foreach CompilationError parsedError in parsedErrors {
            if isEligibleBallerinaSourcePath(parsedError.filePath) {
                currentErrors.push(parsedError);
            }
        }

        if currentErrors.length() > 0 {
            boolean allInteropErrors = true;
            foreach CompilationError currentError in currentErrors {
                if !isInteropClassNotFoundError(currentError) {
                    allInteropErrors = false;
                    break;
                }
            }

            if allInteropErrors {
                utils:logVerbose(string `Ballerina errors are interop CLASS_NOT_FOUND — Java native build likely failed, skipping (${currentErrors.length()} errors)`);
                result.success = false;
                result.errorsRemaining = currentErrors.length();
                result.remainingFixes.push("Ballerina errors are interop CLASS_NOT_FOUND errors from missing/failed Java native build; skipping .bal AI rewrite");
                return result;
            }
        }

        if currentErrors.length() == 0 {
            utils:logWarn("Ballerina build still failed outside the fixer allowlist");
            result.success = false;
            result.errorsRemaining = parsedErrors.length() > 0 ? parsedErrors.length() : 1;
            result.errorsFixed = initialErrorCountSet ? initialErrorCount : 0;
            result.remainingFixes.push(string `Build still fails outside the fixer allowlist. ${summarizeDiagnostics(diagnostics)}`);
            return result;
        }

        // Set initial error count for tracking progress
        if !initialErrorCountSet {
            initialErrorCount = currentErrors.length();
            initialErrorCountSet = true;
            utils:logVerbose(string `Ballerina compile errors detected: ${initialErrorCount}`);
            utils:logVerbose(string `Found ${initialErrorCount} compilation error${initialErrorCount == 1 ? "" : "s"}`);
        }

        // Check progress
        if iteration > 1 {
            int progressMade = previousErrors.length() - currentErrors.length();

            if progressMade > 0 {
                utils:logVerbose(string `Progress: Fixed ${progressMade} error${progressMade == 1 ? "" : "s"}`);
            } else if currentErrors.length() >= previousErrors.length() {
                boolean sameErrors = checkIfErrorsAreSame(currentErrors, previousErrors);
                if sameErrors {
                    utils:logVerbose(string `no progress — same Ballerina errors persist, stopping (iteration ${iteration})`);
                    utils:logWarn("⚠  No progress made - same errors persist");
                    result.remainingFixes.push(string `Iteration ${iteration}: No progress - same errors persist`);
                    break;
                }
            }
        }

        // Store current errors for next iteration comparison
        previousErrors = currentErrors.clone();
        result.errorsRemaining = currentErrors.length();

        // Group errors by file
        map<CompilationError[]> errorsByFile = groupErrorsByFile(currentErrors);

        utils:logVerbose(string `Processing ${errorsByFile.keys().length()} file${errorsByFile.keys().length() == 1 ? "" : "s"}...`);

        boolean anyFixApplied = false;

        // Process each file
        foreach string filePath in errorsByFile.keys() {
            CompilationError[] fileErrors = errorsByFile.get(filePath);

            FixAttempt[] previousAttempts = fileFixHistory.hasKey(filePath) ? fileFixHistory.get(filePath) : [];
            FixResponse|error fixResponse = fixFileWithLLM(projectPath, filePath, fileErrors,
                    previousAttempts);
            if fixResponse is error {
                utils:logVerbose(string `⚠  Could not generate fix for ${filePath}: ${fixResponse.message()}`);
                result.remainingFixes.push(string `Iteration ${iteration}: Failed to fix ${filePath}: ${fixResponse.message()}`);
                continue;
            }

            string[] errorMessages = fileErrors.'map(function(CompilationError err) returns string {
                return err.message;
            });
            FixAttempt fixAttempt = {
                iteration: iteration,
                errorMessages,
                appliedFix: describeCodeChange(fileErrors)
            };
            if !fileFixHistory.hasKey(filePath) {
                fileFixHistory[filePath] = [];
            }
            fileFixHistory.get(filePath).push(fixAttempt);

            // Show fix to user and ask for confirmation
            boolean shouldApplyFix = false;

            if autoYes {
                shouldApplyFix = true;
                utils:logVerbose(string `Auto-applying fix to ${filePath} [${fileErrors.length()} error${fileErrors.length() == 1 ? "" : "s"}]`);
            } else {
                // Show the fix to user
                io:fprintln(io:stderr, "");
                io:fprintln(io:stderr, string `Fix for ${filePath}:`);
                io:fprintln(io:stderr, "  Errors:");
                foreach CompilationError err in fileErrors {
                    io:fprintln(io:stderr, string `    Line ${err.line}: ${err.message}`);
                }
                io:fprintln(io:stderr, "");
                io:fprintln(io:stderr, "  Proposed solution:");
                io:fprintln(io:stderr, "```ballerina");
                io:fprintln(io:stderr, fixResponse.fixedCode);
                io:fprintln(io:stderr, "```");
                io:fprintln(io:stderr, "");

                io:fprint(io:stderr, "Apply this fix? (y/n): ");
                string|io:Error userInput = io:readln();
                if userInput is io:Error {
                    io:fprintln(io:stderr, "  ⚠  Failed to read input - skipping fix");
                    continue;
                }

                string trimmedInput = userInput.trim().toLowerAscii();
                shouldApplyFix = trimmedInput == "y" || trimmedInput == "yes";

                if shouldApplyFix {
                    io:fprintln(io:stderr, "  ✓ Fix approved");
                } else {
                    io:fprintln(io:stderr, "  ✗ Fix declined");
                }
            }

            if shouldApplyFix {
                // Apply the fix
                boolean|error applyResult = applyFix(projectPath, filePath, fixResponse.fixedCode);
                if applyResult is error {
                    utils:logWarn(string `✗ Failed to apply fix: ${applyResult.message()}`);
                    result.remainingFixes.push(string `Iteration ${iteration}: Failed to apply fix to ${filePath}: ${applyResult.message()}`);
                    continue;
                }

                anyFixApplied = true;
                result.appliedFixes.push(string `Fixed ${filePath} (${fileErrors.length()} error${fileErrors.length() == 1 ? "" : "s"})`);
            } else {
                result.remainingFixes.push(string `User declined fix for ${filePath}`);
            }
        }

        // If no fixes were applied, break to avoid infinite loop
        if !anyFixApplied {
            utils:logWarn("⚠  No fixes were applied - stopping iterations");
            result.remainingFixes.push(string `Iteration ${iteration}: No fixes applied - stopping iterations`);
            break;
        }

        iteration += 1;
    }

    // Final status check
    if iteration > maxIterations {
        utils:logWarn(string `⚠  Reached maximum iterations (${maxIterations})`);
        result.remainingFixes.push(string `Maximum iterations (${maxIterations}) reached`);
    }

    // Final build check
    utils:logInfo("Running final build check...");

    record {|boolean success; string stdout; string stderr;|}|error finalBuildResultOrError = executeBalBuild(projectPath,
            isFinalCheck = true); // suppress "attempting AI-driven fixes" message on final check
    if finalBuildResultOrError is error {
        return error BallerinaFixerError("Failed to execute final bal build", finalBuildResultOrError);
    }
    record {|boolean success; string stdout; string stderr;|} finalBuildResult = finalBuildResultOrError;

    if isCommandSuccessfull(finalBuildResult) {
        result.success = true;
        result.errorsRemaining = 0;
        result.errorsFixed = initialErrorCount;
        utils:logInfo("✓ Final build successful - all errors resolved!");
    } else {
        string finalDiagnostics = string `${finalBuildResult.stderr}\n${finalBuildResult.stdout}`;
        CompilationError[] parsedRemainingErrors = parseCompilationErrors(finalDiagnostics);
        CompilationError[] remainingErrors = [];
        foreach CompilationError parsedError in parsedRemainingErrors {
            if isEligibleBallerinaSourcePath(parsedError.filePath) {
                remainingErrors.push(parsedError);
            }
        }
        result.errorsRemaining = remainingErrors.length();
        int fixedCount = initialErrorCount - remainingErrors.length();
        result.errorsFixed = fixedCount > 0 ? fixedCount : 0;

        utils:logWarn(string `⚠  ${remainingErrors.length()} error${remainingErrors.length() == 1 ? "" : "s"} still remain`);
        if remainingErrors.length() <= 5 {
            utils:logInfo("Remaining errors:");
            foreach CompilationError err in remainingErrors {
                utils:logInfo(string `  ${err.filePath}:${err.line} - ${err.message}`);
            }
        }
    }

    error? postCleanupError = cleanupFixerBackups(projectPath);
    if postCleanupError is error {
        utils:logWarn(string `Failed to clean backup files: ${postCleanupError.message()}`);
    }

    // Print summary
    if utils:getLogLevel() != "quiet" && (result.appliedFixes.length() > 0 || !result.success) {
        printFixingSummary(result, iteration - 1);
    }

    return result;
}

// Print a user-friendly summary of the fixing process
function printFixingSummary(FixResult result, int totalIterations) {
    // Create separator using array concatenation
    string[] separatorChars = [];
    int i = 0;
    while i < 50 {
        separatorChars.push("-");
        i += 1;
    }
    string sep = string:'join("", ...separatorChars);

    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, sep);
    io:fprintln(io:stderr, "ERROR FIXING SUMMARY");
    io:fprintln(io:stderr, sep);

    io:fprintln(io:stderr, string `Iterations: ${totalIterations}`);
    io:fprintln(io:stderr, string `Fixed     : ${result.errorsFixed} error${result.errorsFixed == 1 ? "" : "s"}`);
    io:fprintln(io:stderr, string `Remaining : ${result.errorsRemaining} error${result.errorsRemaining == 1 ? "" : "s"}`);

    if result.success {
        io:fprintln(io:stderr, "Status    : ✓ All errors resolved");
    } else {
        io:fprintln(io:stderr, "Status    : ⚠  Some errors remain");
    }

    if result.appliedFixes.length() > 0 {
        io:fprintln(io:stderr, "");
        io:fprintln(io:stderr, "Applied fixes:");
        foreach string fix in result.appliedFixes {
            io:fprintln(io:stderr, string `  • ${fix}`);
        }
    }

    if result.remainingFixes.length() > 0 && result.errorsRemaining > 0 {
        io:fprintln(io:stderr, "");
        io:fprintln(io:stderr, "Manual intervention may be required for remaining errors.");
    }

    io:fprintln(io:stderr, sep);
}

// Helper function to check if two error arrays contain the same errors
function checkIfErrorsAreSame(CompilationError[] current, CompilationError[] previous) returns boolean {
    if current.length() != previous.length() {
        return false;
    }

    // Sort both arrays by file path and line number for comparison
    CompilationError[] sortedCurrent = current.sort(array:ASCENDING, key = isolated function(CompilationError err) returns string {
        return string `${err.filePath}:${err.line}:${err.column}`;
    });

    CompilationError[] sortedPrevious = previous.sort(array:ASCENDING, key = isolated function(CompilationError err) returns string {
        return string `${err.filePath}:${err.line}:${err.column}`;
    });

    // Compare each error
    foreach int i in 0 ..< sortedCurrent.length() {
        CompilationError currentErr = sortedCurrent[i];
        CompilationError previousErr = sortedPrevious[i];

        if currentErr.filePath != previousErr.filePath ||
            currentErr.line != previousErr.line ||
            currentErr.column != previousErr.column ||
            currentErr.message != previousErr.message {
            return false;
        }
    }

    return true;
}
