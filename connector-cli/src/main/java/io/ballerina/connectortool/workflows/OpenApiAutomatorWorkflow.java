package io.ballerina.connectortool.workflows;

import java.io.PrintStream;
import java.nio.file.Path;

import io.ballerina.connectortool.BaseCmd;
import io.ballerina.connectortool.spi.ConnectorWorkflow;
import io.ballerina.cli.BLauncherCmd;
import picocli.CommandLine;
import io.ballerina.connectortool.exceptions.CliException;
import io.ballerina.connectortool.utils.BallerinaProjectPathValidationUtils;
import io.ballerina.connectortool.utils.OpenApiPathValidationUtils;
import io.ballerina.connectortool.utils.Utils;

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

    @CommandLine.Mixin
    private BaseCmd baseCmd = new BaseCmd();

    @CommandLine.Option(names = {"-i", "--input"}, description = "input path to openapi specification file.")
    public String inputPath;

    @CommandLine.Option(names = {"-o", "--output"}, description = "output path for the generated connector.")
    public String outputPath;

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
            Path openApiSpecPath = OpenApiPathValidationUtils.validate(inputPath);
            Path ballerinaProjectPath = BallerinaProjectPathValidationUtils.validate(outputPath);

            Utils.callBallerinaFunction(ORG, MODULE, VERSION, "runOpenApiWorkflow",
                    openApiSpecPath.toString(), ballerinaProjectPath.toString());
        } catch (CliException e) {
            errorStream.println(e.getFormattedMessage());
            System.exit(e.getExitCode());
        } catch (Exception e) {
            errorStream.println("bal: fatal: unexpected error: " + e.getMessage());
            System.exit(1);
        }
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
