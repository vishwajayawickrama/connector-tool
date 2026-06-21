package io.ballerina.aigentool;

import java.io.PrintStream;
import java.util.ArrayList;
import java.util.List;

import io.ballerina.aigentool.spi.AiGenWorkflow;
import io.ballerina.aigentool.spi.AiGenWorkflowProvider;
import io.ballerina.cli.BLauncherCmd;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BArray;
import picocli.CommandLine;

@CommandLine.Command(
        name = "aigen",
        description = "Centralized CLI tool to generate and maintain Ballerina connector assets with AI assistance."
)
public class AiGenCmd implements BLauncherCmd {

    private static final String COMMAND_NAME = "aigen";
    private PrintStream outStream;

    @CommandLine.Mixin
    private BaseCmd baseCmd = new BaseCmd();

    @CommandLine.Parameters(
        index = "0",
        arity = "0..1",
        description = "Subcommand to execute"
    )
    private String subCommand;

    @CommandLine.Parameters(
        index = "1..*", 
        arity = "0..*", 
        description = "arguments + flags and options")
    private final List<String> args = new ArrayList<>();

    public AiGenCmd() {
        outStream = System.out;
    }

    @Override
    public void execute() {
        // TODO: Are we going to handle subcommands --help functionality also in here?
        if (baseCmd.helpFlag || subCommand == null) {
            String helpCommand = subCommand == null ? getName() : getName() + "-" + subCommand;
            String commandUsageInfo = BLauncherCmd.getCommandUsageInfo(helpCommand, AiGenCmd.class.getClassLoader());
            outStream.println(commandUsageInfo);
            return;
        }
        
        BArray balArgs = StringUtils.fromStringArray(args.toArray(new String[0]));
        AiGenWorkflow workflow = AiGenWorkflowProvider.getWorkflow(subCommand);
        workflow.runWorkflow(balArgs);
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
    @SuppressWarnings("deprecation")
    public void printUsage(StringBuilder out) {
        out.append("bal aigen <sdk|openapi> <command> [args...]");
    }

    @Override
    public void setParentCmdParser(CommandLine parentCmdParser) {
    }
}
