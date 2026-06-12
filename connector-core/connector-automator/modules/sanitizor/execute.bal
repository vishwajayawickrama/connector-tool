import wso2/connector_automator.utils;

import ballerina/file;
import ballerina/io;
import ballerina/regex;
import ballerina/yaml;

public function executeSanitizor(string inputSpecPath, string outputDir, utils:LogLevel logLevel = "normal", boolean autoYes = false) returns error? {
    utils:logVerbose(string `input: ${inputSpecPath}`, logLevel);
    utils:logVerbose(string `output: ${outputDir}/docs/spec/aligned_ballerina_openapi.json`, logLevel);

    if !getUserConfirmation("\nProceed with sanitization?", autoYes) {
        utils:logInfo("✗ operation cancelled", logLevel);
        return;
    }

    LLMServiceError? llmInitResult = initLLMService(logLevel);
    if llmInitResult is LLMServiceError {
        utils:logWarn(string `AI service not available — only programmatic fixes will be applied (${llmInitResult.message()})`, logLevel);
        if !getUserConfirmation("Continue without AI-powered features?", autoYes) {
            utils:logError("operation cancelled: check ANTHROPIC_API_KEY");
            return;
        }
    } else {
        utils:logInfo("✓ AI service initialized", logLevel);
    }

    // Step 1: Flatten
    utils:logVerbose("flattening OpenAPI specification", logLevel);
    string flattenedSpecPath = outputDir + "/docs/spec";
    error? createDirResult = file:createDir(flattenedSpecPath, file:RECURSIVE);
    if createDirResult is error {
        return error("Failed to create output directory: " + flattenedSpecPath + ", reason: " + createDirResult.message());
    }
    utils:CommandResult flattenResult = utils:executeBalFlatten(inputSpecPath, flattenedSpecPath);
    if !utils:isCommandSuccessfull(flattenResult) {
        utils:logWarn(string `flatten operation failed: ${flattenResult.stderr.trim()}`, logLevel);
        if !getUserConfirmation("Continue despite flatten failure?", autoYes) {
            return error("Flatten operation failed: " + flattenResult.stderr);
        }
    } else {
        utils:logVerbose("✓ spec flattened", logLevel);
    }

    // Step 2: Align
    utils:logVerbose("aligning OpenAPI specification", logLevel);
    string alignedSpecPath = outputDir + "/docs/spec";

    string flattenedSpec;
    if isYamlFormat(inputSpecPath) {
        string yamlFlattenedSpec = flattenedSpecPath + "/flattened_openapi.yaml";
        string ymlFlattenedSpec = flattenedSpecPath + "/flattened_openapi.yml";
        boolean|file:Error yamlExists = file:test(yamlFlattenedSpec, file:EXISTS);
        if yamlExists is boolean && yamlExists {
            flattenedSpec = yamlFlattenedSpec;
        } else {
            boolean|file:Error ymlExists = file:test(ymlFlattenedSpec, file:EXISTS);
            if ymlExists is boolean && ymlExists {
                flattenedSpec = ymlFlattenedSpec;
            } else {
                flattenedSpec = yamlFlattenedSpec;
            }
        }
    } else {
        flattenedSpec = flattenedSpecPath + "/flattened_openapi.json";
    }

    utils:CommandResult alignResult = utils:executeBalAlign(flattenedSpec, alignedSpecPath);
    if !utils:isCommandSuccessfull(alignResult) {
        utils:logWarn(string `align operation failed: ${alignResult.stderr.trim()}`, logLevel);
        if !getUserConfirmation("Continue despite align failure?", autoYes) {
            return error("Align operation failed: " + alignResult.stderr);
        }
    } else {
        utils:logVerbose("✓ spec aligned", logLevel);
    }

    if isYamlFormat(inputSpecPath) {
        utils:logVerbose("converting aligned YAML spec to JSON", logLevel);
        error? conversionResult = convertAlignedYamlToJson(alignedSpecPath, logLevel);
        if conversionResult is error {
            utils:logWarn(string `YAML to JSON conversion failed: ${conversionResult.message()}`, logLevel);
            if !getUserConfirmation("Continue despite conversion failure?", autoYes) {
                return error("YAML to JSON conversion failed: " + conversionResult.message());
            }
        } else {
            utils:logVerbose("✓ YAML spec converted to JSON", logLevel);
        }
    }

    string alignedSpec = alignedSpecPath + "/aligned_ballerina_openapi.json";

    // Step 3: OperationId generation
    if !getUserConfirmation("Proceed with operationId generation?", autoYes) {
        utils:logVerbose("skipping operationId generation", logLevel);
    } else {
        utils:logVerbose("generating missing operationIds", logLevel);
        int|LLMServiceError operationIdResult = addMissingOperationIdsBatchWithRetry(alignedSpec, 15, logLevel);
        if operationIdResult is LLMServiceError {
            utils:logWarn(string `operationId generation failed: ${operationIdResult.message()}`, logLevel);
            if !getUserConfirmation("Continue despite operationId generation failure?", autoYes) {
                return error("OperationId generation failed: " + operationIdResult.message());
            }
        } else {
            utils:logInfo(string `  added ${operationIdResult} missing operationId${operationIdResult == 1 ? "" : "s"}`, logLevel);
        }
    }

    // Step 4: Schema renaming
    if !getUserConfirmation("Proceed with schema renaming?", autoYes) {
        utils:logVerbose("skipping schema renaming", logLevel);
    } else {
        utils:logVerbose("renaming InlineResponse schemas", logLevel);
        int|LLMServiceError schemaRenameResult = renameInlineResponseSchemasBatchWithRetry(alignedSpec, 8, logLevel);
        if schemaRenameResult is LLMServiceError {
            utils:logWarn(string `schema renaming failed: ${schemaRenameResult.message()}`, logLevel);
            if !getUserConfirmation("Continue despite schema renaming failure?", autoYes) {
                return error("Schema renaming failed: " + schemaRenameResult.message());
            }
        } else {
            utils:logInfo(string `  renamed ${schemaRenameResult} schema${schemaRenameResult == 1 ? "" : "s"} to meaningful names`, logLevel);
        }
    }

    // Step 5: Documentation enhancement
    if !getUserConfirmation("Proceed with documentation enhancement?", autoYes) {
        utils:logVerbose("skipping documentation enhancement", logLevel);
    } else {
        utils:logVerbose("enhancing field descriptions", logLevel);
        int|LLMServiceError descriptionsResult = addMissingDescriptionsBatchWithRetry(alignedSpec, 20, logLevel);
        if descriptionsResult is LLMServiceError {
            utils:logWarn(string `documentation enhancement failed: ${descriptionsResult.message()}`, logLevel);
            if !getUserConfirmation("Continue despite documentation enhancement failure?", autoYes) {
                return error("Documentation fix failed: " + descriptionsResult.message());
            }
        } else {
            utils:logInfo(string `  added ${descriptionsResult} missing description${descriptionsResult == 1 ? "" : "s"}`, logLevel);
        }
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
    string trimmedInput = userInput.trim().toLowerAscii();
    return trimmedInput == "y" || trimmedInput == "Y" || trimmedInput == "yes";
}

function isYamlFormat(string filePath) returns boolean {
    string lowerPath = filePath.toLowerAscii();
    return lowerPath.endsWith(".yaml") || lowerPath.endsWith(".yml");
}

function convertAlignedYamlToJson(string alignedSpecPath, utils:LogLevel logLevel = "normal") returns error? {
    string yamlAlignedSpec = alignedSpecPath + "/aligned_ballerina_openapi.yaml";
    string jsonAlignedSpec = alignedSpecPath + "/aligned_ballerina_openapi.json";

    boolean|file:Error yamlExists = file:test(yamlAlignedSpec, file:EXISTS);
    if yamlExists is file:Error || !yamlExists {
        string ymlAlignedSpec = alignedSpecPath + "/aligned_ballerina_openapi.yml";
        boolean|file:Error ymlExists = file:test(ymlAlignedSpec, file:EXISTS);
        if ymlExists is file:Error || !ymlExists {
            utils:logVerbose(string `no YAML aligned spec found to convert at ${yamlAlignedSpec}`, logLevel);
            return;
        }
        yamlAlignedSpec = ymlAlignedSpec;
    }

    string|io:Error yamlContent = io:fileReadString(yamlAlignedSpec);
    if yamlContent is io:Error {
        return error("Failed to read YAML aligned spec file: " + yamlContent.message());
    }

    json|yaml:Error jsonData = yaml:readString(yamlContent);

    if jsonData is yaml:Error {
        utils:logVerbose(string `Ballerina YAML parser failed, trying yq fallback: ${jsonData.message()}`, logLevel);

        string escapedPath = "'" + regex:replaceAll(yamlAlignedSpec, "'", "'\\\\''") + "'";

        utils:CommandResult yqResult = utils:executeCommand(
            string `yq -o=json '.' ${escapedPath}`,
            ".",
            logLevel
        );

        if utils:isCommandSuccessfull(yqResult) && yqResult.stdout.length() > 0 {
            io:Error? writeResult = io:fileWriteString(jsonAlignedSpec, yqResult.stdout);
            if writeResult is io:Error {
                return error("Failed to write JSON aligned spec file: " + writeResult.message());
            }
            utils:logVerbose("converted YAML to JSON via yq", logLevel);
            return;
        }

        string stdinFile = yamlAlignedSpec + ".stdin_tmp";
        io:Error? stdinWriteResult = io:fileWriteString(stdinFile, yamlContent);
        if stdinWriteResult is () {
            string escapedStdinFile = "'" + regex:replaceAll(stdinFile, "'", "'\\\\''") + "'";
            utils:CommandResult pythonResult = utils:executeCommand(
                string `python3 -c 'import sys,yaml,json; print(json.dumps(yaml.safe_load(sys.stdin), indent=2))' < ${escapedStdinFile}`,
                ".",
                logLevel
            );
            do { check file:remove(stdinFile); } on fail { }

            if utils:isCommandSuccessfull(pythonResult) && pythonResult.stdout.length() > 0 {
                io:Error? writeResult = io:fileWriteString(jsonAlignedSpec, pythonResult.stdout);
                if writeResult is io:Error {
                    return error("Failed to write JSON aligned spec file: " + writeResult.message());
                }
                utils:logVerbose("converted YAML to JSON via Python", logLevel);
                return;
            }
        }

        return error("Failed to parse YAML content: " + jsonData.message() +
            ". Fallback tools (yq, python) also failed or not available.");
    }

    io:Error? writeResult = io:fileWriteJson(jsonAlignedSpec, jsonData);
    if writeResult is io:Error {
        return error("Failed to write JSON aligned spec file: " + writeResult.message());
    }

    utils:logVerbose("✓ converted YAML aligned spec to JSON", logLevel);
    return;
}

function fileExists(string filePath) returns boolean {
    boolean|file:Error exists = file:test(filePath, file:EXISTS);
    return exists is boolean ? exists : false;
}

function printUsage() {
    io:fprintln(io:stderr, "OpenAPI Sanitizor");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE");
    io:fprintln(io:stderr, "  bal connector openapi sanitize -i <input-spec> -o <output-dir> [-q|-v]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ENVIRONMENT");
    io:fprintln(io:stderr, "  ANTHROPIC_API_KEY    Required for AI-powered enhancements");
}
