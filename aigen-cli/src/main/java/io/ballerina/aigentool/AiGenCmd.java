package io.ballerina.aigentool;

import java.io.PrintStream;

import io.ballerina.aigentool.spi.AiGenWorkflow;
import io.ballerina.cli.BLauncherCmd;
import picocli.CommandLine;

import java.util.ServiceLoader;

@CommandLine.Command(
        name = "aigen",
        description = "Centralized CLI tool to generate and maintain Ballerina connector assets with AI assistance."
)
public class AiGenCmd implements BLauncherCmd {

    private static final String COMMAND_NAME = "aigen";
    private PrintStream outStream;

    @CommandLine.Mixin
    private BaseCmd baseCmd = new BaseCmd();

    public AiGenCmd() {
        outStream = System.out;
    }

    @Override
    public void execute() {
        String commandUsageInfo = BLauncherCmd.getCommandUsageInfo(getName(), AiGenCmd.class.getClassLoader());
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
        out.append("bal aigen <sdk|openapi> <command> [args...]");
    }

    @Override
    public void setParentCmdParser(CommandLine parentCmdParser) {
        CommandLine aigenCmd = parentCmdParser.getSubcommands().get(COMMAND_NAME);
        if (aigenCmd != null) {
            ServiceLoader<AiGenWorkflow> workflows = ServiceLoader.load(AiGenWorkflow.class);
            for (AiGenWorkflow workflow : workflows) {
                aigenCmd.addSubcommand(workflow.getName(), workflow);
            }
        }
    }
}
