package io.ballerina.aigentool.workflows;

import io.ballerina.aigentool.spi.AiGenWorkflow;
import io.ballerina.runtime.api.Module;
import io.ballerina.runtime.api.Runtime;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BError;
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
        Runtime runtime = null;
        boolean runtimeStarted = false;
        try {
            Module module = new Module(ORG, MODULE, VERSION);
            BArray workflowArgs = Utils.addToFront(args, NAME);
            runtime = Runtime.from(module);

            runtime.init();
            runtime.start();
            runtimeStarted = true;

            Object result = runtime.callFunction(module, "main", null, workflowArgs);
            if (result instanceof BError error) {
                System.err.println("Error occurred while running connector automator: " + error.getErrorMessage());
            }
        } catch (Exception e) {
            System.err.println("Error occurred while running connector automator: " + e.getMessage());
        } finally {
            // Stop the runtime if it was started
            if (runtimeStarted && runtime != null) {
                runtime.stop();
            }
        }
    }

    @Override
    public void help() {
        System.out.println("Usage: aigen openapi [options]");
        System.out.println("Options:");
        System.out.println("  --spec <path>       Path to the OpenAPI specification file (YAML or JSON).");
        System.out.println("  --output <dir>     Directory where the generated connector will be saved.");
        System.out.println("  --package <name>   Ballerina package name for the generated connector.");
        System.out.println("  --help             Show this help message.");
    }
}
