package io.ballerina.aigentool.workflows;

import java.util.ArrayList;
import java.util.List;

import io.ballerina.aigentool.BaseCmd;
import io.ballerina.aigentool.spi.AiGenWorkflow;
import io.ballerina.cli.BLauncherCmd;
import io.ballerina.runtime.api.values.BArray;
import picocli.CommandLine;
import io.ballerina.aigentool.utils.Utils;
import io.ballerina.runtime.api.utils.StringUtils;

@CommandLine.Command(
    name = "example-doc", 
    description = "Generate and maintain Ballerina connector example documentation.")
public final class ExampleDocGeneratorWorkflow implements AiGenWorkflow {

    private final String ORG = "wso2";
    private final String MODULE = "example_doc_generator";
    private final String VERSION = "0";
    private final String NAME = "example-doc";

    @CommandLine.Mixin
    private BaseCmd baseCmd = new BaseCmd();

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
            String commandUsageInfo = BLauncherCmd.getCommandUsageInfo("aigen-" + NAME, ExampleDocGeneratorWorkflow.class.getClassLoader());
            System.out.println(commandUsageInfo);
            return;
        }
        BArray balArgs = StringUtils.fromStringArray(args.toArray(new String[0]));
        Utils.callBallerinaRuntimeApiWithMultipleArgs(ORG, MODULE, VERSION, balArgs, 4);
    }

    @Override
    public void printLongDesc(StringBuilder out) {
        out.append("Generate and maintain Ballerina connector example documentation.");
    }

    @Override
    public void printUsage(StringBuilder out) {
        out.append("bal aigen example-doc [args...]");
    }

    @Override
    public void setParentCmdParser(CommandLine parentCmdParser) {
    }
}
