package io.ballerina.connectortool.workflows;

import java.io.PrintStream;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

import io.ballerina.connectortool.BaseCmd;
import io.ballerina.connectortool.spi.ConnectorWorkflow;
import io.ballerina.cli.BLauncherCmd;
import picocli.CommandLine;
import io.ballerina.connectortool.exceptions.CliException;
import io.ballerina.connectortool.utils.BallerinaProjectPathValidationUtils;
import io.ballerina.connectortool.utils.BallerinaRuntimeUtils;
import io.ballerina.connectortool.utils.ExamplesOutputPathValidationUtils;
import io.ballerina.connectortool.utils.OpenApiPathValidationUtils;
import io.ballerina.connectortool.utils.OpenApiStageValidationUtils;
import io.ballerina.connectortool.utils.ProcessUtils;
import io.ballerina.connectortool.utils.SpecDirResolutionUtils;

@CommandLine.Command(
    name = "openapi",
    description = "Automate Ballerina connector generation and maintenance from OpenAPI specifications.")
public final class OpenApiAutomatorWorkflow implements ConnectorWorkflow {

    private final String ORG = "wso2";
    private final String MODULE = "connector_automator";
    private final String VERSION = "0";
    private final String NAME = "openapi";
    private PrintStream outStream;
    private PrintStream errorStream;
    private boolean exitWhenFinish = true;

    @CommandLine.Mixin
    private BaseCmd baseCmd = new BaseCmd();

    @CommandLine.Option(names = {"-i", "--input"}, description = "input path to openapi specification file.")
    public String inputPath;

    @CommandLine.Option(names = {"-o", "--output"}, description = "Output path for the generated connector. Defaults to the current directory.")
    public String outputPath;

    @CommandLine.Option(names = {"-q", "--quiet"}, description = "Suppress all output except errors.")
    public boolean quietFlag;

    @CommandLine.Option(names = {"-v", "--verbose"}, description = "Show detailed diagnostic output including subprocess commands and batch details.")
    public boolean verboseFlag;

    @CommandLine.Option(names = {"--example-dir"}, description = "Output directory for generated examples. Defaults to <cwd>/examples.")
    public String exampleDir;

    @CommandLine.Option(names = {"--spec-dir"}, description = "Directory where aligned spec and sanitations.md are saved. Always stored inside a docs/spec subdirectory. Defaults to <cwd>/docs/spec.")
    public String specDir;

    @CommandLine.Option(names = {"-x", "--exclude"}, description = "Exclude a pipeline stage. Repeatable. Valid stages: sanitize, client, tests, examples, docs.")
    public List<String> excludedStages = new ArrayList<>();

    @CommandLine.Option(names = {"--license"}, description = "License file path to use when generating Ballerina client source headers.")
    public String licensePath;

    @CommandLine.Option(names = {"-t", "--tags"}, description = "OpenAPI tag to include during client generation. Repeatable.")
    public List<String> tags = new ArrayList<>();

    @CommandLine.Option(names = {"--operations"}, description = "OpenAPI operation ID to include during client generation. Repeatable.")
    public List<String> operations = new ArrayList<>();

    @CommandLine.Option(names = {"--remote"}, description = "Generate client APIs as remote methods instead of resource methods.")
    public boolean remoteFlag;

    @CommandLine.Option(names = {"--interactive"}, description = "Pause after each stage and prompt for confirmation before continuing.")
    public boolean interactiveFlag;

    public OpenApiAutomatorWorkflow() {
        outStream = System.out;
        errorStream = System.err;
    }

    @Override
    public String getName() {
        return NAME;
    }

    @Override
    public void execute() {
        if (baseCmd.helpFlag) {
            String commandUsageInfo = BLauncherCmd.getCommandUsageInfo("connector-" + NAME, OpenApiAutomatorWorkflow.class.getClassLoader());
            outStream.println(commandUsageInfo);
            return;
        }

        try {
            if (quietFlag && verboseFlag) {
                throw new CliException("options -q/--quiet and -v/--verbose are mutually exclusive", 2);
            }
            String logLevel = quietFlag ? "quiet" : verboseFlag ? "verbose" : "normal";

            Path ballerinaProjectPath = BallerinaProjectPathValidationUtils.resolve(outputPath);
            Path specDirPath = SpecDirResolutionUtils.resolve(specDir);
            OpenApiStageValidationUtils.validate(excludedStages, ballerinaProjectPath, specDirPath);

            Path openApiSpecPath = null;
            if (OpenApiStageValidationUtils.isSpecRequired(excludedStages)) {
                openApiSpecPath = OpenApiPathValidationUtils.resolve(inputPath);
            }

            Path resolvedExamplesDir = ExamplesOutputPathValidationUtils.resolve(exampleDir);

            String excludedArg = String.join(",", excludedStages);
            String licenseArg = licensePath != null ? Path.of(licensePath).toAbsolutePath().normalize().toString() : "";
            String tagsArg = String.join(",", tags);
            String operationsArg = String.join(",", operations);
            String clientMethodArg = remoteFlag ? "remote" : "";
            String interactiveArg = interactiveFlag ? "interactive" : "";

            BallerinaRuntimeUtils.callBallerinaFunction(ORG, MODULE, VERSION, "runOpenApiGenerationWorkflow",
                    openApiSpecPath != null ? openApiSpecPath.toString() : "",
                    ballerinaProjectPath.toString(), logLevel, resolvedExamplesDir.toString(), excludedArg,
                    specDirPath.toString(), licenseArg, tagsArg, operationsArg, clientMethodArg,
                    interactiveArg);

        } catch (CliException e) {
            errorStream.println(e.getFormattedMessage());
            ProcessUtils.exit(e.getExitCode(), exitWhenFinish);
            return;
        } catch (Exception e) {
            errorStream.println("bal: fatal: unexpected error: " + e.getMessage());
            ProcessUtils.exitError(exitWhenFinish);
            return;
        }
        ProcessUtils.exitSuccess(exitWhenFinish);
    }

    @Override
    public void printLongDesc(StringBuilder out) {
        out.append("Generate and maintain Ballerina connector assets from OpenAPI specifications.");
    }

    @Override
    public void printUsage(StringBuilder out) {
        out.append("bal connector openapi [args...]");
    }

    @Override
    public void setParentCmdParser(CommandLine parentCmdParser) {
    }
}
