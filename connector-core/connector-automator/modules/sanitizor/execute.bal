import wso2/connector_automator.utils;

import ballerina/file;
import ballerina/io;
import ballerina/regex;
import ballerina/yaml;

public function executeSanitizor(string inputSpecPath, string specDir) returns error? {
    utils:logVerbose(string `input: ${inputSpecPath}`);
    utils:logVerbose(string `output: ${specDir}/aligned_ballerina_openapi.json`);

    LLMServiceError? llmInitResult = initLLMService();
    if llmInitResult is LLMServiceError {
        utils:logWarn(string `AI service not available — only programmatic fixes will be applied (${llmInitResult.message()})`);
    } else {
        utils:logInfo("✓ AI service initialized");
    }

    // Step 1: Flatten
    utils:logVerbose("flattening OpenAPI specification");
    string flattenedSpecPath = specDir;
    error? createDirResult = file:createDir(flattenedSpecPath, file:RECURSIVE);
    if createDirResult is error {
        return error("Failed to create output directory: " + flattenedSpecPath + ", reason: " + createDirResult.message());
    }
    utils:CommandResult flattenResult = utils:executeBalFlatten(inputSpecPath, flattenedSpecPath);
    if !utils:isCommandSuccessfull(flattenResult) {
        utils:logWarn(string `flatten operation failed: ${flattenResult.stderr.trim()}`);
    } else {
        utils:logVerbose("✓ spec flattened");
    }

    // Step 2: Align
    utils:logVerbose("aligning OpenAPI specification");
    string alignedSpecPath = specDir;

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
        utils:logWarn(string `align operation failed: ${alignResult.stderr.trim()}`);
    } else {
        utils:logVerbose("✓ spec aligned");
    }

    if isYamlFormat(inputSpecPath) {
        utils:logVerbose("converting aligned YAML spec to JSON");
        error? conversionResult = convertAlignedYamlToJson(alignedSpecPath);
        if conversionResult is error {
            utils:logWarn(string `YAML to JSON conversion failed: ${conversionResult.message()}`);
            return error("YAML to JSON conversion failed: " + conversionResult.message());
        }
        utils:logVerbose("✓ YAML spec converted to JSON");
    }

    string alignedSpec = alignedSpecPath + "/aligned_ballerina_openapi.json";

    // Step 3: OperationId generation
    utils:logVerbose("generating missing operationIds");
    int|LLMServiceError operationIdResult = addMissingOperationIdsBatchWithRetry(alignedSpec, 15);
    if operationIdResult is LLMServiceError {
        utils:logWarn(string `operationId generation failed: ${operationIdResult.message()}`);
    } else {
        utils:logInfo(string `  added ${operationIdResult} missing operationId${operationIdResult == 1 ? "" : "s"}`);
    }

    // Step 4: Schema renaming
    utils:logVerbose("renaming InlineResponse schemas");
    int|LLMServiceError schemaRenameResult = renameInlineResponseSchemasBatchWithRetry(alignedSpec, 8);
    if schemaRenameResult is LLMServiceError {
        utils:logWarn(string `schema renaming failed: ${schemaRenameResult.message()}`);
    } else {
        utils:logInfo(string `  renamed ${schemaRenameResult} schema${schemaRenameResult == 1 ? "" : "s"} to meaningful names`);
    }

    // Step 5: Documentation enhancement
    utils:logVerbose("enhancing field descriptions and operation summaries");
    DescriptionEnhancementResult|LLMServiceError descriptionsResult = addMissingDescriptionsBatchWithRetry(alignedSpec, 20);
    if descriptionsResult is LLMServiceError {
        utils:logWarn(string `documentation enhancement failed: ${descriptionsResult.message()}`);
    } else {
        utils:logInfo(string `  added ${descriptionsResult.descriptionsAdded} missing description${descriptionsResult.descriptionsAdded == 1 ? "" : "s"}, updated ${descriptionsResult.summariesAdded} operation summar${descriptionsResult.summariesAdded == 1 ? "y" : "ies"}`);
    }
}

function isYamlFormat(string filePath) returns boolean {
    string lowerPath = filePath.toLowerAscii();
    return lowerPath.endsWith(".yaml") || lowerPath.endsWith(".yml");
}

function convertAlignedYamlToJson(string alignedSpecPath) returns error? {
    string yamlAlignedSpec = alignedSpecPath + "/aligned_ballerina_openapi.yaml";
    string jsonAlignedSpec = alignedSpecPath + "/aligned_ballerina_openapi.json";

    boolean|file:Error yamlExists = file:test(yamlAlignedSpec, file:EXISTS);
    if yamlExists is file:Error || !yamlExists {
        string ymlAlignedSpec = alignedSpecPath + "/aligned_ballerina_openapi.yml";
        boolean|file:Error ymlExists = file:test(ymlAlignedSpec, file:EXISTS);
        if ymlExists is file:Error || !ymlExists {
            utils:logVerbose(string `no YAML aligned spec found to convert at ${yamlAlignedSpec}`);
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
        // Ballerina's YAML parser rejects backtick (U+0060) in plain scalars (YAML 1.1
        // reserved indicator). Replace with underscore (U+005F): single-quote/asterisk/
        // double-quote all introduce new YAML token errors; space and underscore are safe.
        // `name` → _name_ preserves the code-span intent without breaking the parser.
        int[] sanitizedCodePoints = from int cp in yamlContent.toCodePointInts()
            select (cp == 96 ? 95 : cp);
        string|error sanitizedContent = string:fromCodePointInts(sanitizedCodePoints);
        if sanitizedContent is string {
            json|yaml:Error retryData = yaml:readString(sanitizedContent);
            if retryData is json {
                io:Error? retryWrite = io:fileWriteJson(jsonAlignedSpec, retryData);
                if retryWrite is io:Error {
                    return error("Failed to write JSON aligned spec file: " + retryWrite.message());
                }
                utils:logVerbose("✓ converted YAML to JSON (backtick replacement applied)");
                return;
            }
        }

        utils:logVerbose(string `Ballerina YAML parser failed, trying yq fallback: ${jsonData.message()}`);

        string escapedPath = "'" + regex:replaceAll(yamlAlignedSpec, "'", "'\\\\''") + "'";

        utils:CommandResult yqResult = utils:executeCommand(
            string `yq -o=json '.' ${escapedPath}`,
            "."
        );

        if utils:isCommandSuccessfull(yqResult) && yqResult.stdout.length() > 0 {
            io:Error? writeResult = io:fileWriteString(jsonAlignedSpec, yqResult.stdout);
            if writeResult is io:Error {
                return error("Failed to write JSON aligned spec file: " + writeResult.message());
            }
            utils:logVerbose("converted YAML to JSON via yq");
            return;
        }

        string stdinFile = yamlAlignedSpec + ".stdin_tmp";
        io:Error? stdinWriteResult = io:fileWriteString(stdinFile, yamlContent);
        if stdinWriteResult is () {
            string escapedStdinFile = "'" + regex:replaceAll(stdinFile, "'", "'\\\\''") + "'";
            utils:CommandResult pythonResult = utils:executeCommand(
                string `python3 -c 'import sys,yaml,json; print(json.dumps(yaml.safe_load(sys.stdin), indent=2))' < ${escapedStdinFile}`,
                "."
            );
            do { check file:remove(stdinFile); } on fail { }

            if utils:isCommandSuccessfull(pythonResult) && pythonResult.stdout.length() > 0 {
                io:Error? writeResult = io:fileWriteString(jsonAlignedSpec, pythonResult.stdout);
                if writeResult is io:Error {
                    return error("Failed to write JSON aligned spec file: " + writeResult.message());
                }
                utils:logVerbose("converted YAML to JSON via Python");
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

    utils:logVerbose("✓ converted YAML aligned spec to JSON");
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
