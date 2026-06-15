import ballerina/file;
import ballerina/io;
import ballerina/lang.regexp;
import ballerina/os;
import ballerina/regex;

import wso2/connector_automator.api_specification_generator as generator;
import wso2/connector_automator.client_generator as client_generator;
import wso2/connector_automator.code_fixer as fixer;
import wso2/connector_automator.connector_generator as connector;
import wso2/connector_automator.document_generator as document_generator;
import wso2/connector_automator.example_generator as example_generator;
import wso2/connector_automator.sanitizor as sanitizor;
import wso2/connector_automator.sdkanalyzer as analyzer;
import wso2/connector_automator.test_generator as test_generator;
import wso2/connector_automator.utils as oautils;

const string TEST_JARS_DIR = "test-jars";
const string ANALYZER_OUTPUT_DIR = "modules/sdkanalyzer/output";
const string IR_OUTPUT_DIR = "modules/api_specification_generator/IR-output";
const string SPEC_OUTPUT_DIR = "modules/api_specification_generator/spec-output";
const string CONNECTOR_OUTPUT_DIR = "modules/connector_generator/output";

type WorkflowExecutor function(string[] args) returns error?;
type UsagePrinter function();

type WorkflowCommand record {|
    string name;
    string description;
    WorkflowExecutor execute;
    UsagePrinter printUsage;
|};

public function main(string... args) returns error? {
    if args.length() == 0 {
        printMainUsage();
        return;
    }

    string command = args[0];
    if isHelpArg(command) {
        if args.length() == 1 {
            printMainUsage();
            return;
        }
        return printHelpFor(args.slice(1));
    }

    map<WorkflowCommand> workflows = getWorkflowRegistry();

    if workflows.hasKey(command) {
        WorkflowCommand workflow = workflows.get(command);
        WorkflowExecutor execute = workflow.execute;
        return execute(args.slice(1));
    }

    if args.length() > 1 && isHelpArg(args[1]) {
        return printLegacyCommandUsage(command);
    }

    match command {
        "analyze" => {
            return executeAnalyze(args.slice(1));
        }
        "generate" => {
            return executeGenerate(args.slice(1));
        }
        "connector" => {
            return executeConnector(args.slice(1));
        }
        "fix-code" => {
            return executeFixCode(args.slice(1));
        }
        "fix-report-only" => {
            return executeFixReportOnly(args.slice(1));
        }
        "pipeline" => {
            return executePipeline(args.slice(1));
        }
        "generate-tests" => {
            return executeGenerateTests(args.slice(1));
        }
        "generate-examples" => {
            return executeGenerateExamples(args.slice(1));
        }
        "generate-docs" => {
            return executeGenerateDocs(args.slice(1));
        }
        _ => {
            printMainUsage();
            return error(string `Unknown command: ${command}`);
        }
    }
}

function getWorkflowRegistry() returns map<WorkflowCommand> {
    return {
        sdk: {
            name: "sdk",
            description: "SDK (Java SDK) workflow",
            execute: executeSdkCommand,
            printUsage: printSdkUsage
        },
        openapi: {
            name: "openapi",
            description: "OpenAPI spec workflow",
            execute: executeOpenApiCommand,
            printUsage: printOpenApiUsage
        }
    };
}

function isHelpArg(string arg) returns boolean {
    return arg == "help" || arg == "--help" || arg == "-h";
}

function printHelpFor(string[] args) returns error? {
    if args.length() == 0 {
        printMainUsage();
        return;
    }

    string command = args[0];
    match command {
        "sdk" => {
            if args.length() == 1 {
                printSdkUsage();
                return;
            }
            printSdkSubCommandUsage(args[1]);
            return;
        }
        "openapi" => {
            if args.length() == 1 {
                printOpenApiUsage();
                return;
            }
            printOpenApiSubCommandUsage(args[1]);
            return;
        }
        _ => {
            return printLegacyCommandUsage(command);
        }
    }
}

function printLegacyCommandUsage(string command) returns error? {
    match command {
        "analyze" => {
            printAnalyzeUsage();
        }
        "generate" => {
            printGenerateUsage();
        }
        "connector" => {
            printConnectorUsage();
        }
        "fix-code" => {
            printFixUsage("auto-apply");
        }
        "fix-report-only" => {
            printFixUsage("report-only");
        }
        "pipeline" => {
            printPipelineUsage();
        }
        "generate-tests" => {
            printGenerateTestsUsage();
        }
        "generate-examples" => {
            printGenerateExamplesUsage();
        }
        "generate-docs" => {
            printGenerateDocsUsage();
        }
        _ => {
            printMainUsage();
            return error(string `Unknown command: ${command}`);
        }
    }
}

function executeAnalyze(string[] args) returns error? {
    if args.length() < 2 {
        printAnalyzeUsage();
        return;
    }

    string sdkRef = args[0].trim();
    if sdkRef.length() == 0 {
        return error("Dataset key cannot be empty");
    }

    string outputRoot = toAbsolutePath(args[1].trim());
    if outputRoot.length() == 0 {
        return error("Output directory cannot be empty");
    }

    string analyzerOutputDir = resolveAnalyzerOutputDir(outputRoot);
    string[] flagArgs = args.slice(2);

    AnalyzerFlags flags = parseAnalyzerFlags(flagArgs);

    if isMavenCoordinate(sdkRef) {
        analyzer:AnalyzerConfig analyzerConfig = buildAnalyzerConfig(flagArgs, "", flags.logLevel);

        analyzer:AnalysisResult|analyzer:AnalyzerError analysisResult = analyzer:analyzeJavaSDK(
                sdkRef,
                analyzerOutputDir,
                analyzerConfig
        );

        if analysisResult is analyzer:AnalyzerError {
            oautils:logError(string `Analysis failed: ${analysisResult.message()}`);
            return analysisResult;
        }

        return;
    }

    string datasetKey = sdkRef;
    string sdkJarPath = resolveSdkJarPath(datasetKey);
    string javadocJarPath = resolveJavadocJarPath(datasetKey);

    check ensureFileExists(sdkJarPath, "SDK JAR");
    check ensureFileExists(javadocJarPath, "Javadoc JAR");

    analyzer:AnalyzerConfig analyzerConfig = buildAnalyzerConfig(flagArgs, javadocJarPath, flags.logLevel);

    analyzer:AnalysisResult|analyzer:AnalyzerError analysisResult = analyzer:analyzeJavaSDK(
            sdkJarPath,
            analyzerOutputDir,
            analyzerConfig
    );

    if analysisResult is analyzer:AnalyzerError {
        oautils:logError(string `Analysis failed: ${analysisResult.message()}`);
        return analysisResult;
    }

}

function isMavenCoordinate(string sdkRef) returns boolean {
    if !sdkRef.includes(":") {
        return false;
    }

    if sdkRef.includes("/") || sdkRef.includes("\\") {
        return false;
    }

    string[] parts = regex:split(sdkRef, ":");
    return parts.length() == 2 || parts.length() == 3;
}

function executeGenerate(string[] args) returns error? {
    if args.length() < 1 {
        printGenerateUsage();
        return;
    }

    string outputRoot = toAbsolutePath(args[0].trim());
    if outputRoot.length() == 0 {
        return error("Output directory cannot be empty");
    }

    string analyzerOutputDir = resolveAnalyzerOutputDir(outputRoot);
    check ensureDirectoryExists(analyzerOutputDir, "Analyzer output directory");

    string[] datasetKeys = check listDatasetKeysFromMetadataDir(analyzerOutputDir);
    if datasetKeys.length() == 0 {
        return error(string `No metadata files found in: ${analyzerOutputDir}`);
    }

    string[] flagArgs = args.slice(1);
    oautils:LogLevel logLevel = "normal";
    boolean enableExtendedThinking = true;

    foreach string arg in flagArgs {
        match arg {
            "quiet"|"--quiet"|"-q" => {
                logLevel = "quiet";
            }
            "verbose"|"--verbose"|"-v" => {
                logLevel = "verbose";
            }
            "no-thinking"|"--no-thinking" => {
                enableExtendedThinking = false;
            }
            _ => {
            }
        }
    }

    string apiSpecOutputRoot = resolveApiSpecOutputRoot(outputRoot);

    foreach string datasetKey in datasetKeys {
        string metadataPath = resolveMetadataPath(datasetKey, outputRoot);
        check ensureFileExists(metadataPath, "Metadata JSON");

        generator:GeneratorConfig config = {
            metadataPath: metadataPath,
            outputDir: apiSpecOutputRoot,
            datasetKey: datasetKey,
            quietMode: logLevel == "quiet",
            enableExtendedThinking: enableExtendedThinking
        };

        generator:GeneratorResult|generator:GeneratorError result = generator:generateSpecification(config);
        if result is generator:GeneratorError {
            oautils:logError(string `Generation failed for ${datasetKey}: ${result.message()}`);
            return result;
        }
    }
    
}

function executeConnector(string[] args) returns error? {
    if args.length() < 1 {
        printConnectorUsage();
        return;
    }

    string datasetKey = "";
    string outputRoot = "";
    int flagsStartIndex = 1;

    if looksLikePath(args[0]) {
        outputRoot = toAbsolutePath(args[0].trim());
        string[]|error keys = listDatasetKeysFromMetadataDir(resolveAnalyzerOutputDir(outputRoot));
        if keys is error {
            return error(string `Failed to locate metadata in ${resolveAnalyzerOutputDir(outputRoot)}: ${keys.message()}`);
        }
        if keys.length() == 0 {
            return error(string `Metadata JSON not found: ${resolveAnalyzerOutputDir(outputRoot)}`);
        }
        if keys.length() > 1 {
            return error(string `Multiple metadata files found in ${resolveAnalyzerOutputDir(outputRoot)}. ` +
                "Use: bal tool-id sdk connector <dataset-key> <output-dir>");
        }
        datasetKey = keys[0];
        flagsStartIndex = 1;
    } else {
        datasetKey = args[0].trim();
        if datasetKey.length() == 0 {
            return error("Dataset key cannot be empty");
        }
        if args.length() > 1 && looksLikePath(args[1]) {
            outputRoot = toAbsolutePath(args[1].trim());
            flagsStartIndex = 2;
        }
    }

    string metadataPath = resolveMetadataPath(datasetKey, outputRoot);
    string irPath = resolveIrPath(datasetKey, outputRoot);
    string specPath = resolveSpecPath(datasetKey, outputRoot);

    check ensureFileExists(metadataPath, "Metadata JSON");
    check ensureFileExists(irPath, "IR JSON");
    check ensureFileExists(specPath, "API specification");

    connector:ConnectorGeneratorConfig config = {
        metadataPath: metadataPath,
        irPath: irPath,
        apiSpecPath: specPath,
        outputDir: resolveConnectorOutputPath(datasetKey, outputRoot),
        sdkVersionHint: extractSdkVersionFromDatasetKey(datasetKey)
    };

    oautils:LogLevel connectorLogLevel = parseOpenApiLogLevel(args.slice(flagsStartIndex));
    config.quietMode = connectorLogLevel == "quiet";

    connector:ConnectorGeneratorResult|connector:ConnectorGeneratorError result = connector:generateConnector(config);
    if result is connector:ConnectorGeneratorError {
        oautils:logError(string `Connector generation failed: ${result.message()}`);
        return result;
    }



}

function executeFixCode(string[] args) returns error? {
    return executeFixCommand(args, "auto-apply");
}

function executeGenerateTests(string[] args) returns error? {
    if args.length() < 1 {
        printGenerateTestsUsage();
        return;
    }

    string datasetKey = "";
    string outputRoot = "";
    int flagsStartIndex = 1;

    if looksLikePath(args[0]) {
        outputRoot = toAbsolutePath(args[0].trim());
        string[]|error keys = listDatasetKeysFromMetadataDir(resolveAnalyzerOutputDir(outputRoot));
        if keys is error {
            return error(string `Failed to locate metadata in ${resolveAnalyzerOutputDir(outputRoot)}: ${keys.message()}`);
        }
        if keys.length() == 0 {
            return error(string `Metadata JSON not found: ${resolveAnalyzerOutputDir(outputRoot)}`);
        }
        if keys.length() > 1 {
            return error(string `Multiple metadata files found in ${resolveAnalyzerOutputDir(outputRoot)}. ` +
                "Use: bal tool-id sdk generate-tests <dataset-key> <output-dir>");
        }
        datasetKey = keys[0];
        flagsStartIndex = 1;
    } else {
        datasetKey = args[0].trim();
        if datasetKey.length() == 0 {
            return error("Dataset key cannot be empty");
        }
        if args.length() > 1 && looksLikePath(args[1]) {
            outputRoot = toAbsolutePath(args[1].trim());
            flagsStartIndex = 2;
        }
    }

    string specPath = toAbsolutePath(resolveSpecPath(datasetKey, outputRoot));
    check ensureFileExists(specPath, "API specification");

    string connectorOutputPath = resolveConnectorOutputPath(datasetKey, outputRoot);
    string connectorBallerinaToml = string `${connectorOutputPath}/ballerina/Ballerina.toml`;
    check ensureFileExists(connectorBallerinaToml, "Generated connector output");

    string[] testFlagArgs = args.slice(flagsStartIndex);
    oautils:LogLevel testLogLevel = parseOpenApiLogLevel(testFlagArgs);
    error? genResult = test_generator:executeTestGen("sdk", connectorOutputPath, specPath, testLogLevel);

    return genResult;
}

function executeGenerateExamples(string[] args) returns error? {
    if args.length() < 1 {
        printGenerateExamplesUsage();
        return;
    }

    string datasetKey = "";
    string outputRoot = "";
    int flagsStartIndex = 1;

    if looksLikePath(args[0]) {
        outputRoot = toAbsolutePath(args[0].trim());
        string[]|error keys = listDatasetKeysFromMetadataDir(resolveAnalyzerOutputDir(outputRoot));
        if keys is error {
            return error(string `Failed to locate metadata in ${resolveAnalyzerOutputDir(outputRoot)}: ${keys.message()}`);
        }
        if keys.length() == 0 {
            return error(string `Metadata JSON not found: ${resolveAnalyzerOutputDir(outputRoot)}`);
        }
        if keys.length() > 1 {
            return error(string `Multiple metadata files found in ${resolveAnalyzerOutputDir(outputRoot)}. ` +
                "Use: bal tool-id sdk generate-examples <dataset-key> <output-dir>");
        }
        datasetKey = keys[0];
        flagsStartIndex = 1;
    } else {
        datasetKey = args[0].trim();
        if datasetKey.length() == 0 {
            return error("Dataset key cannot be empty");
        }
        if args.length() > 1 && looksLikePath(args[1]) {
            outputRoot = toAbsolutePath(args[1].trim());
            flagsStartIndex = 2;
        }
    }

    string connectorOutputPath = resolveConnectorOutputPath(datasetKey, outputRoot);
    string connectorBallerinaToml = string `${connectorOutputPath}/ballerina/Ballerina.toml`;
    check ensureFileExists(connectorBallerinaToml, "Generated connector output");

    string[] flagArgs = args.slice(flagsStartIndex);
    oautils:LogLevel exLogLevel = parseOpenApiLogLevel(flagArgs);
    error? exResult = example_generator:executeExampleGen(connectorOutputPath, exLogLevel);

    return exResult;
}

function executeGenerateDocs(string[] args) returns error? {
    if args.length() < 2 {
        printGenerateDocsUsage();
        return;
    }

    string docCommand = args[0].trim();
    string datasetKey = "";
    string outputRoot = "";
    int flagsStartIndex = 2;

    if looksLikePath(args[1]) {
        outputRoot = toAbsolutePath(args[1].trim());
        string[]|error keys = listDatasetKeysFromMetadataDir(resolveAnalyzerOutputDir(outputRoot));
        if keys is error {
            return error(string `Failed to locate metadata in ${resolveAnalyzerOutputDir(outputRoot)}: ${keys.message()}`);
        }
        if keys.length() == 0 {
            return error(string `Metadata JSON not found: ${resolveAnalyzerOutputDir(outputRoot)}`);
        }
        if keys.length() > 1 {
            return error(string `Multiple metadata files found in ${resolveAnalyzerOutputDir(outputRoot)}. ` +
                "Use: bal tool-id sdk generate-docs <output-dir>");
        }
        datasetKey = keys[0];
        flagsStartIndex = 2;
    } else {
        datasetKey = args[1].trim();
        if datasetKey.length() == 0 {
            return error("Dataset key cannot be empty");
        }

        if args.length() > 2 && looksLikePath(args[2]) {
            outputRoot = toAbsolutePath(args[2].trim());
            flagsStartIndex = 3;
        }
    }

    string connectorOutputPath = resolveConnectorOutputPath(datasetKey, outputRoot);
    string connectorBallerinaToml = string `${connectorOutputPath}/ballerina/Ballerina.toml`;
    check ensureFileExists(connectorBallerinaToml, "Generated connector output");

    string[] docFlagArgs = args.slice(flagsStartIndex);
    oautils:LogLevel docLogLevel = parseOpenApiLogLevel(docFlagArgs);
    error? docResult = document_generator:executeDocGen(docCommand, connectorOutputPath, logLevel = docLogLevel);

    return docResult;
}

function printGenerateTestsUsage() {
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "Generate live tests for an SDK-generated connector");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE:");
    io:fprintln(io:stderr, "  bal tool-id sdk generate-tests <output-dir> [options]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ARGUMENTS:");
    io:fprintln(io:stderr, "  <output-dir>  Root directory containing a single SDK-generated connector workspace");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "INPUT:");
    io:fprintln(io:stderr, "  <output-dir>/docs/spec/<dataset-key>_spec.bal");
    io:fprintln(io:stderr, "  <output-dir>/ballerina/... (generated connector)");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OPTIONS:");
    io:fprintln(io:stderr, "  yes, --yes, -y       Auto-confirm prompts");
    io:fprintln(io:stderr, "  quiet, --quiet, -q   Reduce log output");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "EXAMPLE:");
    io:fprintln(io:stderr, "  bal tool-id sdk generate-tests /home/user/SDK-auto-generated-connectors yes quiet");
    io:fprintln(io:stderr, "");
}

function printGenerateExamplesUsage() {
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "Generate examples for an SDK-generated connector");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE:");
    io:fprintln(io:stderr, "  bal tool-id sdk generate-examples <output-dir> [options]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ARGUMENTS:");
    io:fprintln(io:stderr, "  <output-dir>  Root directory containing a single SDK-generated connector workspace");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "INPUT:");
    io:fprintln(io:stderr, "  <output-dir>/ballerina/... (generated connector)");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OUTPUT:");
    io:fprintln(io:stderr, "  <output-dir>/examples/");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OPTIONS:");
    io:fprintln(io:stderr, "  yes, --yes, -y       Auto-confirm prompts");
    io:fprintln(io:stderr, "  quiet, --quiet, -q   Reduce log output");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "EXAMPLE:");
    io:fprintln(io:stderr, "  bal tool-id sdk generate-examples /home/user/SDK-auto-generated-connectors yes quiet");
    io:fprintln(io:stderr, "");
}

function printGenerateDocsUsage() {
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "Generate README documentation for an SDK-generated connector");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE:");
    io:fprintln(io:stderr, "  bal tool-id sdk generate-docs <output-dir> [options]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ARGUMENTS:");
    io:fprintln(io:stderr, "  <output-dir>  Root directory containing a single SDK-generated connector workspace");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OPTIONS:");
    io:fprintln(io:stderr, "  quiet, --quiet, -q   Reduce log output");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "EXAMPLE:");
    io:fprintln(io:stderr, "  bal tool-id sdk generate-docs /home/user/SDK-auto-generated-connectors quiet");
    io:fprintln(io:stderr, "");
}

function executeFixReportOnly(string[] args) returns error? {
    return executeFixCommand(args, "report-only");
}

function executeFixCommand(string[] args, string fixMode) returns error? {
    if args.length() < 1 {
        printFixUsage(fixMode);
        return;
    }

    string datasetKey = "";
    string outputRoot = "";
    int flagsStartIndex = 1;

    if looksLikePath(args[0]) {
        outputRoot = toAbsolutePath(args[0].trim());
        string[]|error keys = listDatasetKeysFromMetadataDir(resolveAnalyzerOutputDir(outputRoot));
        if keys is error {
            return error(string `Failed to locate metadata in ${resolveAnalyzerOutputDir(outputRoot)}: ${keys.message()}`);
        }
        if keys.length() == 0 {
            return error(string `Metadata JSON not found: ${resolveAnalyzerOutputDir(outputRoot)}`);
        }
        if keys.length() > 1 {
            return error(string `Multiple metadata files found in ${resolveAnalyzerOutputDir(outputRoot)}. ` +
                string `Use: bal tool-id sdk ${fixMode == "report-only" ? "fix-report-only" : "fix-code"} <dataset-key> <output-dir>`);
        }
        datasetKey = keys[0];
        flagsStartIndex = 1;
    } else {
        datasetKey = args[0].trim();
        if datasetKey.length() == 0 {
            return error("Dataset key cannot be empty");
        }
        if args.length() > 1 && looksLikePath(args[1]) {
            outputRoot = toAbsolutePath(args[1].trim());
            flagsStartIndex = 2;
        }
    }

    string metadataPath = resolveMetadataPath(datasetKey, outputRoot);
    string irPath = resolveIrPath(datasetKey, outputRoot);
    string specPath = resolveSpecPath(datasetKey, outputRoot);

    check ensureFileExists(metadataPath, "Metadata JSON");
    check ensureFileExists(irPath, "IR JSON");
    check ensureFileExists(specPath, "API specification");

    oautils:LogLevel fixLogLevel = "normal";
    int maxFixIterations = 3;
    boolean autoYes = fixMode != "report-only";
    string connectorOutputPath = resolveConnectorOutputPath(datasetKey, outputRoot);
    string nativeOutputPath = resolveNativeOutputPath(datasetKey, outputRoot);
    string ballerinaOutputPath = string `${connectorOutputPath}/ballerina`;

    check ensureFileExists(string `${nativeOutputPath}/build.gradle`, "Generated connector build.gradle");

    foreach string arg in args.slice(flagsStartIndex) {
        if arg == "quiet" || arg == "--quiet" || arg == "-q" {
            fixLogLevel = "quiet";
        } else if arg == "verbose" || arg == "--verbose" || arg == "-v" {
            fixLogLevel = "verbose";
        } else if arg.startsWith("--fix-iterations=") {
            string val = arg.substring(17);
            int|error parsed = int:fromString(val);
            if parsed is int {
                maxFixIterations = parsed;
            }
        }
    }

    string[] planOperations = fixMode == "report-only"
        ? [
            "Run Java native fixer",
            "Collect Java/native fix status",
            "Report consolidated fix status"
        ]
        : [
            "Run Java native fixer",
            "Run Ballerina client/types fixer",
            "Report consolidated fix status"
        ];

    printCommandPlan(fixMode == "report-only" ? "Fix Report" : "Fix Code", datasetKey,
        planOperations, fixLogLevel);

    fixer:FixResult|fixer:BallerinaFixerError javaFixResultOrError = fixer:fixJavaNativeAdaptorErrors(
            nativeOutputPath,
            fixLogLevel,
            autoYes,
            maxFixIterations
    );

    if javaFixResultOrError is fixer:BallerinaFixerError {
        oautils:logError(string `Code fix failed (Java native): ${javaFixResultOrError.message()}`);
        return javaFixResultOrError;
    }

    fixer:FixResult javaFixResult = javaFixResultOrError;

    fixer:FixResult ballerinaFixResult = {
        success: true,
        errorsFixed: 0,
        errorsRemaining: 0,
        appliedFixes: [],
        remainingFixes: []
    };

    if fixMode != "report-only" {
        check ensureFileExists(string `${ballerinaOutputPath}/Ballerina.toml`, "Generated connector Ballerina.toml");
        fixer:FixResult|fixer:BallerinaFixerError ballerinaFixResultOrError = fixer:fixAllErrors(
                ballerinaOutputPath,
                fixLogLevel,
                autoYes
        );

        if ballerinaFixResultOrError is fixer:BallerinaFixerError {
            oautils:logError(string `Code fix failed (Ballerina client): ${ballerinaFixResultOrError.message()}`);
            return ballerinaFixResultOrError;
        }
        ballerinaFixResult = ballerinaFixResultOrError;
    }

    boolean overallSuccess = javaFixResult.success && ballerinaFixResult.success;
    int totalFixed = javaFixResult.errorsFixed + ballerinaFixResult.errorsFixed;
    int totalRemaining = javaFixResult.errorsRemaining + ballerinaFixResult.errorsRemaining;

    string[] combinedIssues = [];
    foreach string issue in javaFixResult.remainingFixes {
        combinedIssues.push(string `java: ${issue}`);
    }
    foreach string issue in ballerinaFixResult.remainingFixes {
        combinedIssues.push(string `ballerina: ${issue}`);
    }

    string[] details = [
        string `success: ${overallSuccess}`,
        string `fixed: ${totalFixed}`,
        string `remaining: ${totalRemaining}`,
        string `java_remaining: ${javaFixResult.errorsRemaining}`
    ];
    if fixMode != "report-only" {
        details.push(string `ballerina_remaining: ${ballerinaFixResult.errorsRemaining}`);
    }
    if !overallSuccess && combinedIssues.length() > 0 {
        foreach string issue in combinedIssues {
            details.push(string `issue: ${issue}`);
        }
    }
    printCommandSummary(fixMode == "report-only" ? "Fix Report" : "Fix Code", overallSuccess, details, fixLogLevel);
}

function printCommandPlan(string title, string target, string[] operations, oautils:LogLevel logLevel) {
    if logLevel == "quiet" {
        return;
    }

    string sep = createMainSeparator("=", 70);
    io:fprintln(io:stderr, sep);
    io:fprintln(io:stderr, string `${title} Plan`);
    io:fprintln(io:stderr, sep);
    io:fprintln(io:stderr, string `Target: ${target}`);
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "Operations:");
    int i = 0;
    while i < operations.length() {
        io:fprintln(io:stderr, string `  ${i + 1}. ${operations[i]}`);
        i += 1;
    }
    io:fprintln(io:stderr, sep);
}

function printCommandSummary(string title, boolean success, string[] details, oautils:LogLevel logLevel) {
    if logLevel == "quiet" {
        return;
    }
    string sep = createMainSeparator("=", 70);
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, sep);
    io:fprintln(io:stderr, string `${success ? "✓" : "⚠"} ${title} Complete`);
    io:fprintln(io:stderr, sep);
    foreach string detail in details {
        io:fprintln(io:stderr, string `  • ${detail}`);
    }
    io:fprintln(io:stderr, sep);
}

function createMainSeparator(string char, int length) returns string {
    string[] chars = [];
    int i = 0;
    while i < length {
        chars.push(char);
        i += 1;
    }
    return string:'join("", ...chars);
}

function printConnectorUsage() {
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "Generate Ballerina connector artifacts from SDK metadata, IR, and API spec");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE:");
    io:fprintln(io:stderr, "  bal tool-id sdk connector <output-dir> [options]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ARGUMENTS:");
    io:fprintln(io:stderr, "  <output-dir>  Root directory containing generated SDK metadata, IR, and API spec");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OUTPUT:");
    io:fprintln(io:stderr, "  <output-dir>/ballerina/client.bal");
    io:fprintln(io:stderr, "  <output-dir>/ballerina/types.bal");
    io:fprintln(io:stderr, "  <output-dir>/native/... (native adaptor)");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OPTIONS:");
    io:fprintln(io:stderr, "  quiet, --quiet, -q   Reduce log output");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "EXAMPLE:");
    io:fprintln(io:stderr, "  bal tool-id sdk connector /home/user/SDK-auto-generated-connectors");
    io:fprintln(io:stderr, "");
}

function printFixUsage(string fixMode) {
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "Run code fixer on generated connector output (Java native + Ballerina client)");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE:");
    if fixMode == "report-only" {
        io:fprintln(io:stderr, "  bal tool-id sdk fix-report-only <output-dir> [options]");
    } else {
        io:fprintln(io:stderr, "  bal tool-id sdk fix-code <output-dir> [options]");
    }
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ARGUMENTS:");
    io:fprintln(io:stderr, "  <output-dir>  Root directory containing a single SDK-generated connector workspace");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OUTPUT:");
    io:fprintln(io:stderr, "  <output-dir>/ballerina/client.bal");
    io:fprintln(io:stderr, "  <output-dir>/ballerina/types.bal");
    io:fprintln(io:stderr, "  <output-dir>/native/... (native adaptor)");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OPTIONS:");
    io:fprintln(io:stderr, "  --fix-iterations=<n>    Maximum fixer iterations (default: 3)");
    io:fprintln(io:stderr, "  quiet, --quiet, -q      Reduce log output");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "EXAMPLES:");
    io:fprintln(io:stderr, "  bal tool-id sdk fix-code /home/user/SDK-auto-generated-connectors");
    io:fprintln(io:stderr, "  bal tool-id sdk fix-report-only /home/user/SDK-auto-generated-connectors");
    io:fprintln(io:stderr, "");
}

function executePipeline(string[] args) returns error? {
    if args.length() < 2 {
        printPipelineUsage();
        return;
    }

    string datasetKey = args[0].trim();
    if datasetKey.length() == 0 {
        return error("Dataset key cannot be empty");
    }

    string outputRoot = toAbsolutePath(args[1].trim());
    if outputRoot.length() == 0 {
        return error("Output directory cannot be empty");
    }

    string sdkJarPath = resolveSdkJarPath(datasetKey);
    string javadocJarPath = resolveJavadocJarPath(datasetKey);

    check ensureFileExists(sdkJarPath, "SDK JAR");
    check ensureFileExists(javadocJarPath, "Javadoc JAR");

    oautils:LogLevel pipelineLogLevel = "normal";
    boolean autoYes = false;
    boolean runFixCode = true;
    boolean runGenerateTests = true;
    boolean runGenerateExamples = true;
    boolean runGenerateDocs = true;
    string fixMode = "auto-apply";
    int maxFixIterations = 3;
    foreach string arg in args.slice(2) {
        if arg == "quiet" || arg == "--quiet" || arg == "-q" {
            pipelineLogLevel = "quiet";
        } else if arg == "verbose" || arg == "--verbose" || arg == "-v" {
            pipelineLogLevel = "verbose";
        } else if arg == "yes" || arg == "--yes" || arg == "-y" {
            autoYes = true;
        } else if arg == "--fix-code" {
            runFixCode = true;
        } else if arg == "--fix-report-only" {
            runFixCode = true;
            fixMode = "report-only";
        } else if arg == "--skip-fix" {
            runFixCode = false;
        } else if arg == "--skip-tests" {
            runGenerateTests = false;
        } else if arg == "--generate-examples" {
            runGenerateExamples = true;
        } else if arg == "--skip-examples" {
            runGenerateExamples = false;
        } else if arg == "--generate-docs" {
            runGenerateDocs = true;
        } else if arg == "--skip-docs" {
            runGenerateDocs = false;
        } else if arg.startsWith("--fix-iterations=") {
            string value = arg.substring(17);
            int|error parsed = int:fromString(value);
            if parsed is int {
                maxFixIterations = parsed;
            }
        }
    }

    printPipelineModuleHeader("SDK Analyzer", pipelineLogLevel);
    if pipelineLogLevel != "quiet" {
        io:fprintln(io:stderr, string `  → SDK JAR: ${sdkJarPath}`);
        io:fprintln(io:stderr, string `  → Javadoc JAR: ${javadocJarPath}`);
    }

    analyzer:AnalyzerConfig analyzerConfig = buildAnalyzerConfig(args.slice(2), javadocJarPath, pipelineLogLevel);
    analyzer:AnalysisResult|analyzer:AnalyzerError analysisResult = analyzer:analyzeJavaSDK(
            sdkJarPath,
            resolveAnalyzerOutputDir(outputRoot),
            analyzerConfig
    );
    if analysisResult is analyzer:AnalyzerError {
        oautils:logError(string `Analysis failed: ${analysisResult.message()}`);
        return analysisResult;
    }

    string metadataPath = resolveMetadataPath(datasetKey, outputRoot);
    check ensureFileExists(metadataPath, "Metadata JSON");

    check runPipelineStagesForDataset(datasetKey, outputRoot, analysisResult.methodsExtracted, autoYes, pipelineLogLevel,
        runFixCode, runGenerateTests, runGenerateExamples, runGenerateDocs, fixMode, maxFixIterations);
}

function runPipelineStagesForDataset(string datasetKey, string outputRoot, int extractedMethods,
        boolean autoYes, oautils:LogLevel logLevel,
        boolean runFixCode, boolean runGenerateTests, boolean runGenerateExamples, boolean runGenerateDocs,
        string fixMode, int maxFixIterations) returns error? {
    string metadataPath = resolveMetadataPath(datasetKey, outputRoot);
    check ensureFileExists(metadataPath, "Metadata JSON");

    printPipelineModuleHeader("API Specification Generator", logLevel);
    if logLevel != "quiet" {
        io:fprintln(io:stderr, string `  → Metadata: ${metadataPath}`);
    }

    generator:GeneratorConfig genConfig = {
        metadataPath: metadataPath,
        outputDir: resolveApiSpecOutputRoot(outputRoot),
        quietMode: logLevel == "quiet",
        datasetKey: datasetKey
    };

    generator:GeneratorResult|generator:GeneratorError genResult = generator:generateSpecification(genConfig);
    if genResult is generator:GeneratorError {
        oautils:logError(string `Specification generation failed: ${genResult.message()}`);
        return genResult;
    }

    string irPath = resolveIrPath(datasetKey, outputRoot);
    string specPath = resolveSpecPath(datasetKey, outputRoot);
    check ensureFileExists(irPath, "IR JSON");
    check ensureFileExists(specPath, "API specification");

    if !confirmPipelineAfterSpec(datasetKey, metadataPath, irPath, specPath, autoYes, logLevel) {
        return error("Pipeline cancelled by user after API specification generation.");
    }

    printPipelineModuleHeader("Connector Generator", logLevel);
    if logLevel != "quiet" {
        io:fprintln(io:stderr, string `  → IR: ${irPath}`);
        io:fprintln(io:stderr, string `  → API Spec: ${specPath}`);
    }

    connector:ConnectorGeneratorConfig connectorConfig = {
        metadataPath: metadataPath,
        irPath: irPath,
        apiSpecPath: specPath,
        outputDir: resolveConnectorOutputPath(datasetKey, outputRoot),
        quietMode: logLevel == "quiet",
        enableCodeFixing: false,
        fixMode: fixMode,
        maxFixIterations: maxFixIterations,
        sdkVersionHint: extractSdkVersionFromDatasetKey(datasetKey)
    };

    connector:ConnectorGeneratorResult|connector:ConnectorGeneratorError connectorResult =
        connector:generateConnector(connectorConfig);

    if connectorResult is connector:ConnectorGeneratorError {
        oautils:logError(string `Connector generation failed: ${connectorResult.message()}`);
        return connectorResult;
    }

    boolean fixCompleted = false;
    if runFixCode {
        printPipelineModuleHeader("Code Fixer", logLevel);

        string[] fixArgs = [datasetKey, outputRoot];
        if logLevel == "quiet" { fixArgs.push("quiet"); }
        else if logLevel == "verbose" { fixArgs.push("verbose"); }
        if autoYes {
            fixArgs.push("yes");
        }
        error? fixError = executeFixCommand(fixArgs, fixMode);
        if fixError is error {
            return fixError;
        }
        fixCompleted = true;
    }

    boolean examplesCompleted = false;
    if runGenerateExamples {
        printPipelineModuleHeader("Example Generator", logLevel);

        string[] exampleArgs = [datasetKey, outputRoot];
        if autoYes { exampleArgs.push("yes"); }
        if logLevel == "quiet" { exampleArgs.push("quiet"); }
        else if logLevel == "verbose" { exampleArgs.push("verbose"); }

        error? exampleError = executeGenerateExamples(exampleArgs);
        if exampleError is error {
            return exampleError;
        }
        examplesCompleted = true;
    }

    boolean testsCompleted = false;
    if runGenerateTests {
        printPipelineModuleHeader("Test Generator", logLevel);

        string[] testArgs = [datasetKey, outputRoot, "yes"];
        if logLevel == "quiet" { testArgs.push("quiet"); }
        else if logLevel == "verbose" { testArgs.push("verbose"); }
        error? testError = executeGenerateTests(testArgs);
        if testError is error {
            return testError;
        }
        testsCompleted = true;
    }

    boolean docsCompleted = false;
    if runGenerateDocs {
        printPipelineModuleHeader("Document Generator", logLevel);

        string[] docArgs = ["generate-all", datasetKey, outputRoot];
        if autoYes { docArgs.push("yes"); }
        if logLevel == "quiet" { docArgs.push("quiet"); }
        else if logLevel == "verbose" { docArgs.push("verbose"); }

        error? docsError = executeGenerateDocs(docArgs);
        if docsError is error {
            return docsError;
        }
        docsCompleted = true;
    }

    printPipelineFinalSummary(datasetKey, metadataPath, irPath, genResult.specificationPath,
        connectorResult.clientPath, connectorResult.typesPath, connectorResult.nativeAdaptorPath,
        extractedMethods, connectorResult.mappedMethodCount,
        runFixCode, fixCompleted, runGenerateTests, testsCompleted, runGenerateExamples, examplesCompleted,
        runGenerateDocs, docsCompleted,
        connectorResult.codeFixingRan, connectorResult.codeFixingSuccess, logLevel);
}

function printPipelineModuleHeader(string moduleName, oautils:LogLevel logLevel) {
    if logLevel == "quiet" {
        return;
    }

    string sep = createMainSeparator("-", 60);
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, sep);
    io:fprintln(io:stderr, string `Executing module: ${moduleName}`);
    io:fprintln(io:stderr, sep);
}

function confirmPipelineAfterSpec(string datasetKey, string metadataPath, string irPath, string specPath,
        boolean autoYes, oautils:LogLevel logLevel) returns boolean {
    if logLevel == "quiet" || autoYes {
        return true;
    }

    string sep = createMainSeparator("-", 60);
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, sep);
    io:fprintln(io:stderr, "Generated artifacts after API specification generation");
    io:fprintln(io:stderr, sep);
    io:fprintln(io:stderr, string `Dataset: ${datasetKey}`);
    io:fprintln(io:stderr, string `Metadata: ${metadataPath}`);
    io:fprintln(io:stderr, string `IR: ${irPath}`);
    io:fprintln(io:stderr, string `Specification: ${specPath}`);
    io:fprintln(io:stderr, sep);

    return getPipelineUserConfirmation("Continue pipeline with these generated artifacts?");
}

function getPipelineUserConfirmation(string message) returns boolean {
    io:fprint(io:stderr, string `${message} (y/n): `);
    string|io:Error userInput = io:readln();
    if userInput is io:Error {
        return false;
    }
    return userInput.trim().toLowerAscii() is "y"|"yes";
}

function printPipelineFinalSummary(string datasetKey, string metadataPath, string irPath, string specPath,
        string clientPath, string typesPath, string nativePath, int extractedMethods, int mappedMethods,
    boolean runFixCode, boolean fixCompleted, boolean runGenerateTests, boolean testsCompleted,
    boolean runGenerateExamples, boolean examplesCompleted,
    boolean runGenerateDocs, boolean docsCompleted,
        boolean connectorInternalFixRan, boolean connectorInternalFixSuccess, oautils:LogLevel logLevel) {
    if logLevel == "quiet" {
        return;
    }
    string sep = createMainSeparator("=", 70);
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, sep);
    io:fprintln(io:stderr, "Pipeline Summary");
    io:fprintln(io:stderr, sep);
    io:fprintln(io:stderr, string `Dataset: ${datasetKey}`);
    io:fprintln(io:stderr, string `Metadata: ${metadataPath}`);
    io:fprintln(io:stderr, string `IR: ${irPath}`);
    io:fprintln(io:stderr, string `Specification: ${specPath}`);
    io:fprintln(io:stderr, string `Connector client: ${clientPath}`);
    io:fprintln(io:stderr, string `Connector types: ${typesPath}`);
    io:fprintln(io:stderr, string `Native adaptor: ${nativePath}`);
    io:fprintln(io:stderr, string `Methods extracted: ${extractedMethods}`);
    io:fprintln(io:stderr, string `Methods mapped: ${mappedMethods}`);
    io:fprintln(io:stderr, string `Code fixing: ${runFixCode ? (fixCompleted ? "completed" : "failed") : "skipped"}`);
    io:fprintln(io:stderr, string `Example generation: ${runGenerateExamples ? (examplesCompleted ? "completed" : "failed") : "skipped"}`);
    io:fprintln(io:stderr, string `Test generation: ${runGenerateTests ? (testsCompleted ? "completed" : "failed") : "skipped"}`);
    io:fprintln(io:stderr, string `Documentation generation: ${runGenerateDocs ? (docsCompleted ? "completed" : "failed") : "skipped"}`);
    if connectorInternalFixRan {
        io:fprintln(io:stderr, string `Connector-internal code fixing: ${connectorInternalFixSuccess ? "success" : "partial/failed"}`);
    }
    io:fprintln(io:stderr, sep);
}

type AnalyzerFlags record {|
    oautils:LogLevel logLevel;
|};

function parseAnalyzerFlags(string[] args) returns AnalyzerFlags {
    AnalyzerFlags flags = {
        logLevel: "normal"
    };

    foreach string arg in args {
        if arg == "quiet" || arg == "--quiet" || arg == "-q" {
            flags.logLevel = "quiet";
        } else if arg == "verbose" || arg == "--verbose" || arg == "-v" {
            flags.logLevel = "verbose";
        }
    }

    return flags;
}

function buildAnalyzerConfig(string[] args, string javadocJar, oautils:LogLevel logLevel) returns analyzer:AnalyzerConfig {
    analyzer:AnalyzerConfig config = {
        quietMode: logLevel == "quiet"
    };

    if javadocJar.trim().length() > 0 {
        config.javadocPath = javadocJar;
    }

    int i = 0;
    while i < args.length() {
        string arg = args[i];
        match arg {
            "yes"|"--yes"|"-y" => {
                config.autoYes = true;
            }
            "quiet"|"--quiet"|"-q" => {
                config.quietMode = true;
            }
            "include-deprecated"|"--include-deprecated" => {
                config.includeDeprecated = true;
            }
            "include-internal"|"--include-internal" => {
                config.filterInternal = false;
            }
            "include-non-public"|"--include-non-public" => {
                config.includeNonPublic = true;
            }
            "--sources" => {
                if i + 1 < args.length() {
                    config.sourcesPath = args[i + 1];
                    i = i + 1;
                }
            }
            _ => {
                if arg.includes("=") {
                    string[] parts = regex:split(arg, "=");
                    if parts.length() == 2 {
                        string key = parts[0].trim();
                        string value = parts[1].trim();

                        match key {
                            "exclude-packages"|"--exclude-packages" => {
                                if value.length() > 0 {
                                    config.excludePackages = regex:split(value, ",")
                                        .map(pkg => pkg.trim())
                                        .filter(pkg => pkg.length() > 0);
                                }
                            }
                            "include-packages"|"--include-packages" => {
                                if value.length() > 0 {
                                    config.includePackages = regex:split(value, ",")
                                        .map(pkg => pkg.trim())
                                        .filter(pkg => pkg.length() > 0);
                                }
                            }
                            "max-depth"|"--max-depth" => {
                                int|error depth = int:fromString(value);
                                if depth is int {
                                    config.maxDependencyDepth = depth;
                                }
                            }
                            "methods-to-list"|"--methods-to-list" => {
                                int|error methods = int:fromString(value);
                                if methods is int {
                                    config.methodsToList = methods;
                                }
                            }
                            "sources"|"--sources" => {
                                if value.length() > 0 {
                                    config.sourcesPath = value;
                                }
                            }
                            _ => {
                            }
                        }
                    }
                }
            }
        }
        i = i + 1;
    }

    return config;
}

function resolveSdkJarPath(string datasetKey) returns string {
    return string `${TEST_JARS_DIR}/${datasetKey}.jar`;
}

function resolveJavadocJarPath(string datasetKey) returns string {
    return string `${TEST_JARS_DIR}/${datasetKey}-javadoc.jar`;
}

function resolveAnalyzerOutputDir(string outputRoot = "") returns string {
    string root = outputRoot.trim();
    if root.length() == 0 {
        return ANALYZER_OUTPUT_DIR;
    }
    return string `${root}/docs/spec`;
}

function resolveApiSpecOutputRoot(string outputRoot = "") returns string {
    string root = outputRoot.trim();
    if root.length() == 0 {
        return "modules/api_specification_generator/spec-output";
    }
    return string `${root}/docs/spec`;
}

function resolveMetadataPath(string datasetKey, string outputRoot = "") returns string {
    return string `${resolveAnalyzerOutputDir(outputRoot)}/${datasetKey}-metadata.json`;
}

function resolveIrPath(string datasetKey, string outputRoot = "") returns string {
    string specOutputDir = resolveApiSpecOutputRoot(outputRoot);
    return string `${specOutputDir}/${datasetKey}-ir.json`;
}

function resolveSpecPath(string datasetKey, string outputRoot = "") returns string {
    string specOutputDir = resolveApiSpecOutputRoot(outputRoot);
    return string `${specOutputDir}/${datasetKey}_spec.bal`;
}

function extractSdkVersionFromDatasetKey(string datasetKey) returns string {
    string[] parts = regex:split(datasetKey, "-");
    foreach string part in parts.reverse() {
        if regex:matches(part, "^[0-9]+\\.[0-9]+.*") {
            return part;
        }
    }

    return "";
}

function resolveConnectorOutputPath(string datasetKey, string outputRoot = "") returns string {
    string root = outputRoot.trim();
    if root.length() > 0 {
        return root;
    }

    if CONNECTOR_OUTPUT_DIR.startsWith("/") {
        return string `${CONNECTOR_OUTPUT_DIR}/${datasetKey}`;
    }
    string cwd = os:getEnv("PWD");
    return string `${cwd}/${CONNECTOR_OUTPUT_DIR}/${datasetKey}`;
}

function resolveNativeOutputPath(string datasetKey, string outputRoot = "") returns string {
    string connectorOutputPath = resolveConnectorOutputPath(datasetKey, outputRoot);
    return string `${connectorOutputPath}/native`;
}

function ensureDirectoryExists(string dirPath, string dirLabel) returns error? {
    boolean exists = check file:test(dirPath, file:EXISTS);
    if !exists {
        return error(string `${dirLabel} not found: ${dirPath}`);
    }
}

function listDatasetKeysFromMetadataDir(string metadataDir) returns string[]|error {
    file:MetaData[] entries = check file:readDir(metadataDir);
    string[] datasetKeys = [];

    foreach file:MetaData entry in entries {
        if entry.dir {
            continue;
        }

        string fileName = extractFileName(entry.absPath);
        if fileName.endsWith("-metadata.json") {
            datasetKeys.push(fileName.substring(0, fileName.length() - 14));
        }
    }

    return datasetKeys;
}

function extractFileName(string absPath) returns string {
    regexp:RegExp sepPattern = re `/|\\`;
    string[] segments = regexp:split(sepPattern, absPath);
    if segments.length() == 0 {
        return absPath;
    }
    return segments[segments.length() - 1];
}

function looksLikePath(string value) returns boolean {
    string v = value.trim();
    if v.length() == 0 {
        return false;
    }

    if v.startsWith("/") || v.startsWith("./") || v.startsWith("../") || v.startsWith("~") {
        return true;
    }

    return v.includes("/") || v.includes("\\");
}

function toAbsolutePath(string path) returns string {
    string trimmed = path.trim();
    if trimmed.startsWith("/") {
        return trimmed;
    }
    string cwd = os:getEnv("PWD");
    return string `${cwd}/${trimmed}`;
}

function ensureFileExists(string filePath, string fileLabel) returns error? {
    boolean exists = check file:test(filePath, file:EXISTS);
    if !exists {
        return error(string `${fileLabel} not found: ${filePath}`);
    }
}

function executeSdkCommand(string[] args) returns error? {
    if args.length() == 0 {
        printSdkUsage();
        return;
    }

    if isHelpArg(args[0]) {
        if args.length() == 1 {
            printSdkUsage();
            return;
        }
        printSdkSubCommandUsage(args[1]);
        return;
    }

    if args.length() > 1 && isHelpArg(args[1]) {
        printSdkSubCommandUsage(args[0]);
        return;
    }

    if os:getEnv("ANTHROPIC_API_KEY").length() == 0 {
        return error("ANTHROPIC_API_KEY is not set. The SDK workflow requires an Anthropic API key.");
    }

    string subCommand = args[0];
    string[] subArgs = args.slice(1);

    match subCommand {
        "analyze" => {
            return executeAnalyze(subArgs);
        }
        "generate" => {
            return executeGenerate(subArgs);
        }
        "connector" => {
            return executeConnector(subArgs);
        }
        "fix-code" => {
            return executeFixCode(subArgs);
        }
        "fix-report-only" => {
            return executeFixReportOnly(subArgs);
        }
        "pipeline" => {
            return executePipeline(subArgs);
        }
        "generate-tests" => {
            return executeGenerateTests(subArgs);
        }
        "generate-examples" => {
            return executeGenerateExamples(subArgs);
        }
        "generate-docs" => {
            return executeSdkGenerateDocs(subArgs);
        }
        "generate-all" => {
            return executeSdkGenerateAll(subArgs);
        }
        "help" => {
            printSdkUsage();
        }
        _ => {
            printSdkUsage();
            return error(string `Unknown SDK command: ${subCommand}`);
        }
    }
}

function printSdkSubCommandUsage(string subCommand) {
    match subCommand {
        "analyze" => {
            printAnalyzeUsage();
        }
        "generate" => {
            printGenerateUsage();
        }
        "connector" => {
            printConnectorUsage();
        }
        "fix-code" => {
            printFixUsage("auto-apply");
        }
        "fix-report-only" => {
            printFixUsage("report-only");
        }
        "pipeline" => {
            printPipelineUsage();
        }
        "generate-tests" => {
            printGenerateTestsUsage();
        }
        "generate-examples" => {
            printGenerateExamplesUsage();
        }
        "generate-docs" => {
            printGenerateDocsUsage();
        }
        "generate-all" => {
            printGenerateDocsUsage();
        }
        _ => {
            oautils:logError(string `Unknown SDK command: ${subCommand}`);
            printSdkUsage();
        }
    }
}

function executeSdkGenerateDocs(string[] args) returns error? {
    if args.length() < 1 {
        io:fprintln(io:stderr, "Usage: bal tool-id sdk generate-docs <output-dir> [options]");
        return;
    }

    string outputRoot = toAbsolutePath(args[0].trim());
    string[]|error keys = listDatasetKeysFromMetadataDir(resolveAnalyzerOutputDir(outputRoot));
    if keys is error {
        return error(string `Failed to locate metadata in ${resolveAnalyzerOutputDir(outputRoot)}: ${keys.message()}`);
    }
    if keys.length() == 0 {
        return error(string `Metadata JSON not found in: ${resolveAnalyzerOutputDir(outputRoot)}`);
    }
    if keys.length() > 1 {
        return error(string `Multiple metadata files found. Use: bal tool-id sdk generate-docs <output-dir>`);
    }

    string[] docArgs = ["generate-all", keys[0], outputRoot, ...args.slice(1)];
    return executeGenerateDocs(docArgs);
}

function executeSdkGenerateAll(string[] args) returns error? {
    if args.length() < 1 {
        io:fprintln(io:stderr, "Usage: bal tool-id sdk generate-docs <output-dir> [options]");
        return;
    }

    string outputRoot = toAbsolutePath(args[0].trim());
    string[]|error keys = listDatasetKeysFromMetadataDir(resolveAnalyzerOutputDir(outputRoot));
    if keys is error {
        return error(string `Failed to locate metadata in ${resolveAnalyzerOutputDir(outputRoot)}: ${keys.message()}`);
    }
    if keys.length() == 0 {
        return error(string `Metadata JSON not found in: ${resolveAnalyzerOutputDir(outputRoot)}`);
    }
    if keys.length() > 1 {
        return error(string `Multiple metadata files found. Use: bal tool-id sdk generate-docs <output-dir>`);
    }

    string[] docArgs = ["generate-all", keys[0], outputRoot, ...args.slice(1)];
    return executeGenerateDocs(docArgs);
}

function printSdkUsage() {
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "SDK Workflow - Java SDK -> Ballerina Connector");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE:");
    io:fprintln(io:stderr, "  bal tool-id sdk analyze <sdk-ref> <output-dir> [options]");
    io:fprintln(io:stderr, "  bal tool-id sdk pipeline <sdk-ref> <output-dir> [options]");
    io:fprintln(io:stderr, "  bal tool-id sdk generate <output-dir> [options]");
    io:fprintln(io:stderr, "  bal tool-id sdk connector <output-dir> [options]");
    io:fprintln(io:stderr, "  bal tool-id sdk fix-code <output-dir> [options]");
    io:fprintln(io:stderr, "  bal tool-id sdk fix-report-only <output-dir> [options]");
    io:fprintln(io:stderr, "  bal tool-id sdk generate-tests <output-dir> [options]");
    io:fprintln(io:stderr, "  bal tool-id sdk generate-examples <output-dir> [options]");
    io:fprintln(io:stderr, "  bal tool-id sdk generate-docs <output-dir> [options]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "COMMANDS:");
    io:fprintln(io:stderr, "  analyze          Analyze a Java SDK reference and write metadata");
    io:fprintln(io:stderr, "  pipeline         Run analyze, spec/IR, connector, fix, tests, examples, and docs");
    io:fprintln(io:stderr, "  generate         Generate API spec + IR from metadata");
    io:fprintln(io:stderr, "  connector        Generate Ballerina connector artifacts");
    io:fprintln(io:stderr, "  fix-code         Fix Java native + Ballerina compilation errors");
    io:fprintln(io:stderr, "  fix-report-only  Run fixer diagnostics without applying fixes");
    io:fprintln(io:stderr, "  generate-tests   Generate live integration tests");
    io:fprintln(io:stderr, "  generate-examples Generate code examples");
    io:fprintln(io:stderr, "  generate-docs    Generate all documentation");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OPTIONS:");
    io:fprintln(io:stderr, "  quiet, --quiet, -q   Reduce log output");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "EXAMPLE:");
    io:fprintln(io:stderr, "  bal tool-id sdk analyze s3-2.4.0 /home/user/SDK-auto-generated-connectors");
    io:fprintln(io:stderr, "  bal tool-id sdk pipeline s3-2.4.0 /home/user/SDK-auto-generated-connectors");
    io:fprintln(io:stderr, "  bal tool-id sdk generate-tests /home/user/SDK-auto-generated-connectors/module-s3");
    io:fprintln(io:stderr, "");
}

function executeOpenApiCommand(string[] args) returns error? {
    if args.length() == 0 {
        printOpenApiUsage();
        return;
    }

    if isHelpArg(args[0]) {
        if args.length() == 1 {
            printOpenApiUsage();
            return;
        }
        printOpenApiSubCommandUsage(args[1]);
        return;
    }

    if args.length() > 1 && isHelpArg(args[1]) {
        printOpenApiSubCommandUsage(args[0]);
        return;
    }

    if os:getEnv("ANTHROPIC_API_KEY").length() == 0 {
        oautils:logWarn("ANTHROPIC_API_KEY is not set — AI-powered steps (sanitize, generate-tests, generate-examples, generate-docs) will fail", "normal");
    }

    string subCommand = args[0];
    string[] subArgs = args.slice(1);
    oautils:LogLevel logLevel = parseOpenApiLogLevel(subArgs);
    string[] positional = parseOpenApiPositionalArgs(subArgs);

    match subCommand {
        "sanitize" => {
            if positional.length() < 2 {
                io:fprintln(io:stderr, "sanitize: requires <spec-path> <output-dir>");
                return;
            }
            return sanitizor:executeSanitizor(positional[0], positional[1], logLevel);
        }
        "generate-client" => {
            if positional.length() < 2 {
                io:fprintln(io:stderr, "generate-client: requires <spec-path> <output-dir>");
                return;
            }
            return client_generator:executeClientGen(positional[0], positional[1], logLevel);
        }
        "generate-tests" => {
            if positional.length() < 2 {
                io:fprintln(io:stderr, "generate-tests: requires <connector-path> <spec-path>");
                return;
            }
            return test_generator:executeTestGen("openapi", positional[0], positional[1], logLevel);
        }
        "generate-examples" => {
            if positional.length() < 1 {
                io:fprintln(io:stderr, "generate-examples: requires <connector-path>");
                return;
            }
            return example_generator:executeExampleGen(positional[0], logLevel);
        }
        "generate-docs" => {
            if positional.length() < 2 {
                io:fprintln(io:stderr, "generate-docs: requires <doc-command> <connector-path>");
                return;
            }
            return document_generator:executeDocGen(positional[0], positional[1], logLevel = logLevel);
        }
        "generate-all" => {
            if positional.length() < 1 {
                io:fprintln(io:stderr, "generate-all: requires <connector-path>");
                return;
            }
            return document_generator:executeDocGen("generate-all", positional[0], logLevel = logLevel);
        }
        "fix-code" => {
            if positional.length() < 1 {
                io:fprintln(io:stderr, "fix-code: requires <connector-path>");
                return;
            }
            return fixer:executeCodeFixer(positional[0], logLevel);
        }
        "pipeline" => {
            return runOpenApiPipeline(subArgs);
        }
        "help" => {
            printOpenApiUsage();
        }
        _ => {
            printOpenApiUsage();
            return error(string `Unknown OpenAPI command: ${subCommand}`);
        }
    }
}

function parseOpenApiLogLevel(string[] args) returns oautils:LogLevel {
    foreach string arg in args {
        if arg == "-q" || arg == "--quiet" || arg == "quiet" {
            return "quiet";
        }
        if arg == "-v" || arg == "--verbose" || arg == "verbose" {
            return "verbose";
        }
    }
    return "normal";
}

// Extract positional args (non-flag values). Also resolves -i/-o flag values.
function parseOpenApiPositionalArgs(string[] args) returns string[] {
    string[] positional = [];
    int i = 0;
    while i < args.length() {
        string arg = args[i];
        if arg == "-i" || arg == "-o" || arg == "--input" || arg == "--output" {
            if i + 1 < args.length() {
                positional.push(args[i + 1]);
                i += 2;
                continue;
            }
        } else if !arg.startsWith("-") && arg != "quiet" && arg != "verbose" && arg != "regenerate" {
            positional.push(arg);
        }
        i += 1;
    }
    return positional;
}

function printOpenApiSubCommandUsage(string subCommand) {
    match subCommand {
        "pipeline" => {
            printOpenApiPipelineUsage();
        }
        "sanitize" => {
            printOpenApiSanitizeUsage();
        }
        "generate-client" => {
            printOpenApiGenerateClientUsage();
        }
        "fix-code" => {
            printOpenApiFixCodeUsage();
        }
        "generate-tests" => {
            printOpenApiGenerateTestsUsage();
        }
        "generate-examples" => {
            printOpenApiGenerateExamplesUsage();
        }
        "generate-docs" => {
            printOpenApiGenerateDocsUsage();
        }
        "generate-all" => {
            printOpenApiGenerateDocsUsage();
        }
        _ => {
            oautils:logError(string `Unknown OpenAPI command: ${subCommand}`);
            printOpenApiUsage();
        }
    }
}

function runOpenApiPipeline(string[] args) returns error? {
    if args.length() < 2 {
        io:fprintln(io:stderr, "Usage: bal connector openapi pipeline <openapi-spec> <output-dir> [-q|-v]");
        return;
    }

    string openApiSpec = args[0];
    string outputDir = args[1];
    string[] pipelineOptions = args.slice(2);

    oautils:LogLevel logLevel = parseOpenApiLogLevel(pipelineOptions);
    boolean regenerate = false;

    foreach string option in pipelineOptions {
        if option == "regenerate" {
            regenerate = true;
        }
    }

    if regenerate {
        return runOpenApiRegenerationPipeline(openApiSpec, outputDir, logLevel);
    }

    printOpenApiPipelineHeader(openApiSpec, outputDir, logLevel, false);

    printOpenApiStepHeader(1, "Sanitizing OpenAPI Specification", logLevel);
    string defaultSpecDir = string `${outputDir}/docs/spec`;
    error? sanitizeResult = sanitizor:executeSanitizor(openApiSpec, defaultSpecDir, logLevel);
    if sanitizeResult is error {
        oautils:logError(string `sanitization failed: ${sanitizeResult.message()}`);
        return sanitizeResult;
    }
    oautils:logInfo("✓ sanitization complete", logLevel);
    error? sanitationsDocResult = sanitizor:generateSanitationsDoc(
        openApiSpec, string `${defaultSpecDir}/aligned_ballerina_openapi.json`, defaultSpecDir, logLevel);
    if sanitationsDocResult is error {
        oautils:logWarn(string `could not generate sanitations.md: ${sanitationsDocResult.message()}`, logLevel);
    }

    printOpenApiStepHeader(2, "Generating Ballerina Client", logLevel);
    string sanitizedSpec = string `${defaultSpecDir}/aligned_ballerina_openapi.json`;
    string clientPath = string `${outputDir}/ballerina`;
    error? clientResult = client_generator:executeClientGen(sanitizedSpec, clientPath, logLevel);
    if clientResult is error {
        oautils:logWarn(string `client generation failed: ${clientResult.message()} — continuing`, logLevel);
    } else {
        oautils:logInfo("✓ client generated", logLevel);
    }

    printOpenApiStepHeader(3, "Building and Validating Client", logLevel);
    oautils:CommandResult buildResult = oautils:executeBalBuild(clientPath, logLevel);
    if oautils:hasCompilationErrors(buildResult) {
        oautils:logError("build validation failed: client contains compilation errors");
        oautils:logError("run 'bal connector openapi fix-code <connector-path>' to resolve");
        return error(string `client build failed: ${buildResult.stderr}`);
    }
    oautils:logInfo("✓ client built and validated", logLevel);

    printOpenApiStepHeader(4, "Generating Examples", logLevel);
    error? exampleResult = example_generator:executeExampleGen(outputDir, logLevel);
    if exampleResult is error {
        oautils:logWarn(string `example generation failed: ${exampleResult.message()} — continuing`, logLevel);
    } else {
        oautils:logInfo("✓ examples generated", logLevel);
    }

    printOpenApiStepHeader(5, "Generating Tests", logLevel);
    error? testResult = test_generator:executeOpenApiTestGen(outputDir, sanitizedSpec, logLevel);
    if testResult is error {
        oautils:logWarn(string `test generation failed: ${testResult.message()} — continuing`, logLevel);
    } else {
        oautils:logInfo("✓ tests generated", logLevel);
    }

    printOpenApiStepHeader(6, "Generating Documentation", logLevel);
    error? docResult = document_generator:executeDocGen("generate-all", outputDir, logLevel = logLevel);
    if docResult is error {
        oautils:logWarn(string `documentation generation failed: ${docResult.message()}`, logLevel);
    } else {
        oautils:logInfo("✓ documentation generated", logLevel);
    }

    printOpenApiPipelineCompletion(outputDir, logLevel);
}

function runOpenApiRegenerationPipeline(string openApiSpec, string outputDir, oautils:LogLevel logLevel) returns error? {
    printOpenApiPipelineHeader(openApiSpec, outputDir, logLevel, true);

    error? initResult = oautils:initAIService(logLevel);
    if initResult is error {
        oautils:logWarn("AI service unavailable before sanitations — continuing with available parsing", logLevel);
    }

    string regenSpecDir = string `${outputDir}/docs/spec`;
    string sanitationsPath = string `${regenSpecDir}/sanitations.md`;
    error? applyResult = sanitizor:applySanitations(sanitationsPath, openApiSpec, logLevel);
    if applyResult is error {
        oautils:logWarn(string `could not apply recorded sanitations: ${applyResult.message()} — continuing`, logLevel);
    } else {
        oautils:logInfo("✓ recorded sanitations applied", logLevel);
    }

    printOpenApiStepHeader(1, "Sanitizing OpenAPI Specification", logLevel);
    error? sanitizeResult = sanitizor:executeSanitizor(openApiSpec, regenSpecDir, logLevel);
    if sanitizeResult is error {
        return sanitizeResult;
    }

    string sanitizedSpec = string `${regenSpecDir}/aligned_ballerina_openapi.json`;
    error? sanitationsDocResult = sanitizor:generateSanitationsDoc(openApiSpec, sanitizedSpec, regenSpecDir, logLevel);
    if sanitationsDocResult is error {
        oautils:logWarn(string `could not refresh sanitations.md: ${sanitationsDocResult.message()}`, logLevel);
    }

    printOpenApiStepHeader(2, "Regenerating Ballerina Client", logLevel);
    string clientPath = string `${outputDir}/ballerina`;
    error? clientResult = client_generator:executeClientGen(sanitizedSpec, clientPath, logLevel);
    if clientResult is error {
        oautils:logWarn(string `client regeneration failed: ${clientResult.message()} — continuing`, logLevel);
    }

    printOpenApiStepHeader(3, "Building and Validating Client", logLevel);
    oautils:CommandResult buildResult = oautils:executeBalBuild(clientPath, logLevel);
    if oautils:hasCompilationErrors(buildResult) {
        error? fixResult = fixer:executeCodeFixer(clientPath, logLevel);
        if fixResult is error {
            oautils:logWarn(string `initial recovery fix failed: ${fixResult.message()}`, logLevel);
        }

        oautils:CommandResult retryBuild = oautils:executeBalBuild(clientPath, logLevel);
        if oautils:hasCompilationErrors(retryBuild) {
            error? removeTests = file:remove(clientPath + "/tests", file:RECURSIVE);
            error? removeMock = file:remove(clientPath + "/modules/mock.server", file:RECURSIVE);
            if removeTests is error {
                oautils:logWarn(string `could not remove old tests: ${removeTests.message()}`, logLevel);
            }
            if removeMock is error {
                oautils:logWarn(string `could not remove old mock module: ${removeMock.message()}`, logLevel);
            }

            printOpenApiStepHeader(4, "Regenerating Tests for New API Version", logLevel);
            error? testResult = test_generator:executeOpenApiTestGen(outputDir, sanitizedSpec, logLevel);
            if testResult is error {
                return testResult;
            }
            retryBuild = oautils:executeBalBuild(clientPath, logLevel);
            if oautils:hasCompilationErrors(retryBuild) {
                error? finalFix = fixer:executeCodeFixer(clientPath, logLevel);
                if finalFix is error {
                    return finalFix;
                }
            }
        }
    } else {
        printOpenApiStepHeader(4, "Regenerating Tests", logLevel);
        error? testResult = test_generator:executeOpenApiTestGen(outputDir, sanitizedSpec, logLevel);
        if testResult is error {
            oautils:logWarn(string `test regeneration failed: ${testResult.message()}`, logLevel);
        }
    }

    printOpenApiStepHeader(5, "Regenerating Examples", logLevel);
    error? exampleResult = example_generator:executeExampleGen(outputDir, logLevel);
    if exampleResult is error {
        oautils:logWarn(string `example regeneration failed: ${exampleResult.message()}`, logLevel);
    }

    printOpenApiStepHeader(6, "Generating Documentation", logLevel);
    error? docResult = document_generator:executeDocGen("generate-all", outputDir, logLevel = logLevel);
    if docResult is error {
        oautils:logWarn(string `documentation generation failed: ${docResult.message()}`, logLevel);
    }

    printOpenApiPipelineCompletion(outputDir, logLevel);
}

function printOpenApiPipelineHeader(string openApiSpec, string outputDir, oautils:LogLevel logLevel, boolean regenerate) {
    if logLevel == "quiet" {
        return;
    }
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, regenerate ? "OpenAPI Connector Regeneration Pipeline" : "OpenAPI Connector Automation Pipeline");
    io:fprintln(io:stderr, string `  spec  : ${openApiSpec}`);
    io:fprintln(io:stderr, string `  output: ${outputDir}`);
}

function printOpenApiStepHeader(int stepNum, string title, oautils:LogLevel logLevel) {
    oautils:logStep(stepNum, 6, title, logLevel);
}

function printOpenApiPipelineCompletion(string outputDir, oautils:LogLevel logLevel) {
    oautils:logCompletion(outputDir, logLevel);
}

function printOpenApiUsage() {
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OpenAPI Workflow - OpenAPI Spec → Ballerina Connector");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE:");
    io:fprintln(io:stderr, "  bal tool-id openapi pipeline <spec> <output-dir> [options]");
    io:fprintln(io:stderr, "  bal tool-id openapi sanitize <spec> <output-dir> [options]");
    io:fprintln(io:stderr, "  bal tool-id openapi generate-client <spec> <output-dir> [options]");
    io:fprintln(io:stderr, "  bal tool-id openapi fix-code <connector-path> [options]");
    io:fprintln(io:stderr, "  bal tool-id openapi generate-tests <connector-path> <spec-path> [options]");
    io:fprintln(io:stderr, "  bal tool-id openapi generate-examples <connector-path> [options]");
    io:fprintln(io:stderr, "  bal tool-id openapi generate-docs <doc-command> <connector-path> [options]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "COMMANDS:");
    io:fprintln(io:stderr, "  pipeline          Run full OpenAPI pipeline end-to-end");
    io:fprintln(io:stderr, "  sanitize          Sanitize and enhance the OpenAPI specification");
    io:fprintln(io:stderr, "  generate-client   Generate Ballerina client from sanitized spec");
    io:fprintln(io:stderr, "  fix-code          Fix compilation errors in generated client");
    io:fprintln(io:stderr, "  generate-tests    Generate mock server + live integration tests");
    io:fprintln(io:stderr, "  generate-examples Generate code examples for the connector");
    io:fprintln(io:stderr, "  generate-docs     Generate documentation (specify doc-command)");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "DOC COMMANDS (for generate-docs):");
    io:fprintln(io:stderr, "  generate-all");
    io:fprintln(io:stderr, "  generate-ballerina");
    io:fprintln(io:stderr, "  generate-tests");
    io:fprintln(io:stderr, "  generate-examples");
    io:fprintln(io:stderr, "  generate-individual-examples");
    io:fprintln(io:stderr, "  generate-main");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OPTIONS:");
    io:fprintln(io:stderr, "  yes      Auto-confirm all prompts");
    io:fprintln(io:stderr, "  quiet    Reduce log output");
    io:fprintln(io:stderr, "  regenerate  Reapply recorded sanitations and recover tests/examples for an updated spec");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "EXAMPLES:");
    io:fprintln(io:stderr, "  bal tool-id openapi pipeline /home/user/spec.yaml /home/user/my-connector");
    io:fprintln(io:stderr, "  bal tool-id openapi pipeline /home/user/spec.yaml /home/user/my-connector yes regenerate");
    io:fprintln(io:stderr, "  bal tool-id openapi sanitize /home/user/spec.yaml /home/user/my-connector");
    io:fprintln(io:stderr, "  bal tool-id openapi generate-client /home/user/spec.yaml /home/user/my-connector");
    io:fprintln(io:stderr, "  bal tool-id openapi fix-code /home/user/my-connector/ballerina");
    io:fprintln(io:stderr, "  bal tool-id openapi generate-tests /home/user/my-connector /home/user/spec.yaml");
    io:fprintln(io:stderr, "  bal tool-id openapi generate-docs generate-all /home/user/my-connector");
    io:fprintln(io:stderr, "");
}

function printOpenApiPipelineUsage() {
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "Run the full OpenAPI connector automation pipeline");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE:");
    io:fprintln(io:stderr, "  bal tool-id openapi pipeline <spec> <output-dir> [options]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ARGUMENTS:");
    io:fprintln(io:stderr, "  <spec>        Path to the source OpenAPI specification");
    io:fprintln(io:stderr, "  <output-dir>  Directory for the generated connector workspace");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OPTIONS:");
    io:fprintln(io:stderr, "  yes, --yes, -y       Auto-confirm prompts");
    io:fprintln(io:stderr, "  quiet, --quiet, -q   Reduce log output");
    io:fprintln(io:stderr, "  regenerate           Reapply recorded sanitations and refresh generated assets");
    io:fprintln(io:stderr, "  remote-methods       Generate client APIs as remote methods");
    io:fprintln(io:stderr, "  resource-methods     Generate client APIs as resource methods");
    io:fprintln(io:stderr, "  license=<path>       License file path for generated source headers");
    io:fprintln(io:stderr, "  tags=<tag1,tag2>     Include only operations from the given OpenAPI tags");
    io:fprintln(io:stderr, "  operations=<op1,op2> Include only the given operation IDs");
    io:fprintln(io:stderr, "  client-method=<resource|remote>");
    io:fprintln(io:stderr, "");
}

function printOpenApiSanitizeUsage() {
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "Sanitize and enhance an OpenAPI specification");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE:");
    io:fprintln(io:stderr, "  bal tool-id openapi sanitize <spec> <output-dir> [options]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ARGUMENTS:");
    io:fprintln(io:stderr, "  <spec>        Path to the source OpenAPI specification");
    io:fprintln(io:stderr, "  <output-dir>  Directory for sanitized specification files and sanitation records");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OPTIONS:");
    io:fprintln(io:stderr, "  yes, --yes, -y       Auto-confirm prompts");
    io:fprintln(io:stderr, "  quiet, --quiet, -q   Reduce log output");
    io:fprintln(io:stderr, "");
}

function printOpenApiGenerateClientUsage() {
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "Generate a Ballerina client project from an OpenAPI specification");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE:");
    io:fprintln(io:stderr, "  bal tool-id openapi generate-client <spec> <output-dir> [options]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ARGUMENTS:");
    io:fprintln(io:stderr, "  <spec>        Path to the OpenAPI specification");
    io:fprintln(io:stderr, "  <output-dir>  Directory where the generated Ballerina client is written");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OPTIONS:");
    io:fprintln(io:stderr, "  yes, --yes, -y       Auto-confirm prompts");
    io:fprintln(io:stderr, "  quiet, --quiet, -q   Reduce log output");
    io:fprintln(io:stderr, "  remote-methods       Generate client APIs as remote methods");
    io:fprintln(io:stderr, "  resource-methods     Generate client APIs as resource methods");
    io:fprintln(io:stderr, "  license=<path>       License file path for generated source headers");
    io:fprintln(io:stderr, "  tags=<tag1,tag2>     Include only operations from the given OpenAPI tags");
    io:fprintln(io:stderr, "  operations=<op1,op2> Include only the given operation IDs");
    io:fprintln(io:stderr, "  client-method=<resource|remote>");
    io:fprintln(io:stderr, "");
}

function printOpenApiFixCodeUsage() {
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "Fix Ballerina compilation errors in a generated connector project");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE:");
    io:fprintln(io:stderr, "  bal tool-id openapi fix-code <connector-path> [options]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ARGUMENTS:");
    io:fprintln(io:stderr, "  <connector-path>  Path to the generated Ballerina connector project");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OPTIONS:");
    io:fprintln(io:stderr, "  yes, --yes, -y       Auto-confirm prompts");
    io:fprintln(io:stderr, "  quiet, --quiet, -q   Reduce log output");
    io:fprintln(io:stderr, "");
}

function printOpenApiGenerateTestsUsage() {
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "Generate OpenAPI connector tests and mock server module");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE:");
    io:fprintln(io:stderr, "  bal tool-id openapi generate-tests <connector-path> <spec-path> [options]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ARGUMENTS:");
    io:fprintln(io:stderr, "  <connector-path>  Path to the connector workspace");
    io:fprintln(io:stderr, "  <spec-path>       Path to the OpenAPI specification");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OPTIONS:");
    io:fprintln(io:stderr, "  yes, --yes, -y       Auto-confirm prompts");
    io:fprintln(io:stderr, "  quiet, --quiet, -q   Reduce log output");
    io:fprintln(io:stderr, "");
}

function printOpenApiGenerateExamplesUsage() {
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "Generate AI-assisted Ballerina examples for a connector");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE:");
    io:fprintln(io:stderr, "  bal tool-id openapi generate-examples <connector-path> [options]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ARGUMENTS:");
    io:fprintln(io:stderr, "  <connector-path>  Path to the connector workspace");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OPTIONS:");
    io:fprintln(io:stderr, "  yes, --yes, -y       Auto-confirm prompts");
    io:fprintln(io:stderr, "  quiet, --quiet, -q   Reduce log output");
    io:fprintln(io:stderr, "  regenerate           Try recovering existing examples before fresh generation");
    io:fprintln(io:stderr, "");
}

function printOpenApiGenerateDocsUsage() {
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "Generate README documentation for an OpenAPI-generated connector");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE:");
    io:fprintln(io:stderr, "  bal tool-id openapi generate-docs <doc-command> <connector-path> [options]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "DOC COMMANDS:");
    io:fprintln(io:stderr, "  generate-all");
    io:fprintln(io:stderr, "  generate-ballerina");
    io:fprintln(io:stderr, "  generate-tests");
    io:fprintln(io:stderr, "  generate-examples");
    io:fprintln(io:stderr, "  generate-individual-examples");
    io:fprintln(io:stderr, "  generate-main");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ARGUMENTS:");
    io:fprintln(io:stderr, "  <doc-command>     Documentation mode to run");
    io:fprintln(io:stderr, "  <connector-path>  Path to the connector workspace");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OPTIONS:");
    io:fprintln(io:stderr, "  yes, --yes, -y       Auto-confirm prompts");
    io:fprintln(io:stderr, "  quiet, --quiet, -q   Reduce log output");
    io:fprintln(io:stderr, "");
}

function printMainUsage() {
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "Connector Automator");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE:");
    foreach WorkflowCommand workflow in getWorkflowRegistry() {
        io:fprintln(io:stderr, string `  bal tool-id ${workflow.name} <command> [args...]      ${workflow.description}`);
    }
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "SDK COMMANDS:");
    io:fprintln(io:stderr, "  sdk analyze <sdk-ref> <output-dir>         Analyze Java SDK");
    io:fprintln(io:stderr, "  sdk pipeline <sdk-ref> <output-dir>        Run full SDK pipeline");
    io:fprintln(io:stderr, "  sdk generate <output-dir>                  Generate API spec + IR");
    io:fprintln(io:stderr, "  sdk connector <output-dir>                 Generate connector");
    io:fprintln(io:stderr, "  sdk fix-code <output-dir>                  Fix compilation errors");
    io:fprintln(io:stderr, "  sdk generate-tests <output-dir>            Generate live tests");
    io:fprintln(io:stderr, "  sdk generate-examples <output-dir>         Generate examples");
    io:fprintln(io:stderr, "  sdk generate-docs <output-dir>             Generate documentation");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OPENAPI COMMANDS:");
    io:fprintln(io:stderr, "  openapi pipeline <spec> <output-dir>       Run full OpenAPI pipeline");
    io:fprintln(io:stderr, "  openapi sanitize <spec> <output-dir>       Sanitize OpenAPI specification");
    io:fprintln(io:stderr, "  openapi generate-client <spec> <output>    Generate Ballerina client");
    io:fprintln(io:stderr, "  openapi fix-code <connector-path>          Fix compilation errors");
    io:fprintln(io:stderr, "  openapi generate-tests <path> <spec>       Generate mock + live tests");
    io:fprintln(io:stderr, "  openapi generate-examples <path>           Generate examples");
    io:fprintln(io:stderr, "  openapi generate-docs <cmd> <path>         Generate documentation");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "EXAMPLES:");
    io:fprintln(io:stderr, "  bal tool-id sdk analyze s3-2.4.0 /home/user/SDK-auto-generated-connectors");
    io:fprintln(io:stderr, "  bal tool-id sdk pipeline s3-2.4.0 /home/user/SDK-auto-generated-connectors");
    io:fprintln(io:stderr, "  bal tool-id sdk generate-tests /home/user/SDK-auto-generated-connectors/module-s3");
    io:fprintln(io:stderr, "  bal tool-id openapi generate-tests /home/user/my-connector /home/user/spec.yaml");
    io:fprintln(io:stderr, "");
}

function printAnalyzeUsage() {
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "Analyze a Java SDK reference and write metadata under the output root");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE:");
    io:fprintln(io:stderr, "  bal tool-id sdk analyze <sdk-ref> <output-dir> [options]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ARGUMENTS:");
    io:fprintln(io:stderr, "  <sdk-ref>     Dataset key or Maven coordinate for the Java SDK");
    io:fprintln(io:stderr, "  <output-dir>  Root directory for generated connector artifacts");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OUTPUT:");
    io:fprintln(io:stderr, "  <output-dir>/docs/spec/<dataset-key>-metadata.json");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OPTIONS:");
    io:fprintln(io:stderr, "  yes, --yes, -y       Auto-confirm prompts");
    io:fprintln(io:stderr, "  quiet, --quiet, -q   Reduce log output");
    io:fprintln(io:stderr, "  include-deprecated   Include deprecated SDK APIs");
    io:fprintln(io:stderr, "  include-internal     Include APIs normally filtered as internal");
    io:fprintln(io:stderr, "  include-non-public   Include non-public APIs where available");
    io:fprintln(io:stderr, "  include-packages=<packages>");
    io:fprintln(io:stderr, "  exclude-packages=<packages>");
    io:fprintln(io:stderr, "  max-depth=<n>");
    io:fprintln(io:stderr, "  methods-to-list=<n>");
    io:fprintln(io:stderr, "  sources=<path>");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "EXAMPLE:");
    io:fprintln(io:stderr, "  bal tool-id sdk analyze s3-2.4.0 /home/user/SDK-auto-generated-connectors quiet");
    io:fprintln(io:stderr, "  bal tool-id sdk analyze org.apache.kafka:kafka-clients:3.9.1 /home/user/SDK-auto-generated-connectors");
    io:fprintln(io:stderr, "");
}

function printGenerateUsage() {
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "Generate Ballerina API specification from fixed metadata output");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE:");
    io:fprintln(io:stderr, "  bal tool-id sdk generate <output-dir> [options]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "INPUT:");
    io:fprintln(io:stderr, "  <output-dir>/docs/spec/*-metadata.json");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OUTPUT:");
    io:fprintln(io:stderr, "  <output-dir>/docs/spec/<dataset-key>-ir.json");
    io:fprintln(io:stderr, "  <output-dir>/docs/spec/<dataset-key>_spec.bal");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OPTIONS:");
    io:fprintln(io:stderr, "  quiet, --quiet, -q   Reduce log output");
    io:fprintln(io:stderr, "  no-thinking          Disable LLM extended thinking");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "EXAMPLE:");
    io:fprintln(io:stderr, "  bal tool-id sdk generate /home/user/SDK-auto-generated-connectors");
    io:fprintln(io:stderr, "");
}

function printPipelineUsage() {
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "Run the full SDK connector generation pipeline");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "USAGE:");
    io:fprintln(io:stderr, "  bal tool-id sdk pipeline <sdk-ref> <output-dir> [options]");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "ARGUMENTS:");
    io:fprintln(io:stderr, "  <sdk-ref>     Dataset key or Maven coordinate for the Java SDK");
    io:fprintln(io:stderr, "  <output-dir>  Root directory for generated connector artifacts");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OUTPUTS:");
    io:fprintln(io:stderr, "  <output-dir>/docs/spec/<dataset-key>-metadata.json");
    io:fprintln(io:stderr, "  <output-dir>/docs/spec/<dataset-key>-ir.json");
    io:fprintln(io:stderr, "  <output-dir>/docs/spec/<dataset-key>_spec.bal");
    io:fprintln(io:stderr, "  <output-dir>/ballerina/... and <output-dir>/native/...");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "OPTIONS:");
    io:fprintln(io:stderr, "  yes, --yes, -y          Auto-confirm prompts");
    io:fprintln(io:stderr, "  quiet, --quiet, -q      Reduce log output");
    io:fprintln(io:stderr, "  --fix-code              Run full code fixer phase (default: enabled)");
    io:fprintln(io:stderr, "  --fix-report-only       Run fixer in diagnostics mode");
    io:fprintln(io:stderr, "  --skip-fix              Skip code fixing phase");
    io:fprintln(io:stderr, "  --skip-tests            Skip test generation phase");
    io:fprintln(io:stderr, "  --generate-examples     Run example generation phase");
    io:fprintln(io:stderr, "  --skip-examples         Skip example generation phase");
    io:fprintln(io:stderr, "  --generate-docs         Run documentation generation phase");
    io:fprintln(io:stderr, "  --skip-docs             Skip documentation generation phase");
    io:fprintln(io:stderr, "  --fix-iterations=<n>    Maximum fixer iterations (default: 3)");
    io:fprintln(io:stderr, "");
    io:fprintln(io:stderr, "EXAMPLE:");
    io:fprintln(io:stderr, "  bal tool-id sdk pipeline s3-2.4.0 /home/user/SDK-auto-generated-connectors --fix-code");
    io:fprintln(io:stderr, "");
}
