package io.ballerina.aigentool.workflows;

import io.ballerina.aigentool.spi.AiGenWorkflow;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.aigentool.utils.Utils;

public final class SdkAutomatorWorkflow implements AiGenWorkflow {

    private final String ORG = "wso2";
    private final String MODULE = "connector_automator";
    private final String VERSION = "0";
    private final String NAME = "sdk";

    @Override
    public String getName() {
        return NAME;
    }

    @Override
    public void runWorkflow(BArray args) {
        Utils.callBallerinaRunteimAPiWithName(ORG, MODULE, VERSION, NAME, args);
    }

    @Override
    public void help() {
        System.out.println("Usage: aigen sdk [options]");
        System.out.println("Options:");
        System.out.println("  --spec <path>       Path to the SDK specification file (YAML or JSON).");
        System.out.println("  --output <dir>     Directory where the generated connector will be saved.");
        System.out.println("  --package <name>   Ballerina package name for the generated connector.");
        System.out.println("  --help             Show this help message.");
    }
}
