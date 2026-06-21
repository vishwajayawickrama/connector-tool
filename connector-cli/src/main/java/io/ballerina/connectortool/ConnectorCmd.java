package io.ballerina.connectortool;

import java.io.PrintStream;

import io.ballerina.connectortool.spi.ConnectorWorkflow;
import io.ballerina.cli.BLauncherCmd;
import picocli.CommandLine;

import java.util.ServiceLoader;

@CommandLine.Command(
        name = "connector",
        description = "Centralized CLI tool to generate and maintain Ballerina connector assets."
)
public class ConnectorCmd implements BLauncherCmd {

    private static final String COMMAND_NAME = "connector";
    private PrintStream outStream;
    private PrintStream errorStream;

    @CommandLine.Mixin
    private BaseCmd baseCmd = new BaseCmd();

    public ConnectorCmd() {
        outStream = baseCmd.outStream;
        errorStream = baseCmd.errorStream;
    }

    @Override
    public void execute() {
        String commandUsageInfo = BLauncherCmd.getCommandUsageInfo(getName(), ConnectorCmd.class.getClassLoader());
        outStream.println(commandUsageInfo);
    }

    @Override
    public String getName() {
        return COMMAND_NAME;
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
        CommandLine connectorCmd = parentCmdParser.getSubcommands().get(COMMAND_NAME);
        if (connectorCmd != null) {
            ServiceLoader<ConnectorWorkflow> workflows = ServiceLoader.load(ConnectorWorkflow.class);
            for (ConnectorWorkflow workflow : workflows) {
                connectorCmd.addSubcommand(workflow.getName(), workflow);
            }
        }
    }
}
