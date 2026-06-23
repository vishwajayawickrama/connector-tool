package io.ballerina.connectortool.workflows;

import io.ballerina.cli.BLauncherCmd;
import io.ballerina.connectortool.BaseCmd;
import io.ballerina.connectortool.exceptions.CliException;
import io.ballerina.connectortool.spi.ConnectorWorkflow;
import io.ballerina.connectortool.utils.BallerinaRuntimeUtils;
import io.ballerina.connectortool.utils.ProcessUtils;
import io.ballerina.connectortool.utils.Utils;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BArray;
import picocli.CommandLine;

import java.io.PrintStream;
import java.util.ArrayList;
import java.util.List;

@CommandLine.Command(
    name = "sdk",
    description = "Automate Ballerina connector generation and maintenance from Java SDKs.")
public final class SdkAutomatorWorkflow implements ConnectorWorkflow {

    private static final String ORG = "wso2";
    private static final String MODULE = "connector_automator";
    private static final String VERSION = "0";
    private static final String NAME = "sdk";
    private PrintStream outStream;
    private PrintStream errorStream;
    private boolean exitWhenFinish = true;

    @CommandLine.Mixin
    private BaseCmd baseCmd = new BaseCmd();

    public SdkAutomatorWorkflow() {
        outStream = baseCmd.outStream;
        errorStream = baseCmd.errorStream;
    }

    @CommandLine.Parameters(
        arity = "0..*",
        description = "arguments + flags and options")
    private final List<String> args = new ArrayList<>();

    @Override
    public String getName() {
        return NAME;
    }

    @Override
    public void execute() {
        if (baseCmd.helpFlag) {
            String commandUsageInfo = BLauncherCmd.getCommandUsageInfo(
                    "connector-" + NAME, SdkAutomatorWorkflow.class.getClassLoader());
            outStream.println(commandUsageInfo);
            return;
        }
        try {
            Utils.validateApiKey();
            BArray balArgs = StringUtils.fromStringArray(args.toArray(new String[0]));
            BallerinaRuntimeUtils.callBallerinaFunctionWithBArray(ORG, MODULE, VERSION, "runSdkWorkflow", balArgs);
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
        out.append("Generate and maintain Ballerina connector assets from OpenAPI specifications or Java SDKs.");
    }

    @Override
    public void printUsage(StringBuilder out) {
        out.append("bal connector <sdk|openapi> <command> [args...]");
    }

    @Override
    public void setParentCmdParser(CommandLine parentCmdParser) {
    }
}
