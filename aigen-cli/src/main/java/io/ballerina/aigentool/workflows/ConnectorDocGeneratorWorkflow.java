package io.ballerina.aigentool.workflows;

import io.ballerina.aigentool.spi.AiGenWorkflow;
import io.ballerina.runtime.api.Module;
import io.ballerina.runtime.api.Runtime;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BError;

public final class ConnectorDocGeneratorWorkflow implements AiGenWorkflow {

    private final String ORG = "wso2";
    private final String MODULE = "connector_doc_generator";
    private final String VERSION = "0";
    private final String NAME = "doc-generator";

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
            runtime = Runtime.from(module);

            runtime.init();
            runtime.start();
            runtimeStarted = true;

            Object result = runtime.callFunction(module, "main", null, args);
            if (result instanceof BError error) {
                System.err.println("Error occurred while running connector doc generator: " + error.getErrorMessage());
            }
        } catch (Exception e) {
            System.err.println("Error occurred while running connector doc generator: " + e.getMessage());
        } finally {
            // Stop the runtime if it was started
            if (runtimeStarted && runtime != null) {
                runtime.stop();
            }
        }
    }

    @Override
    public void help() {
        System.out.println("Usage: aigen doc-generator [options]");
        System.out.println("Options:");
        System.out.println("  --spec <path>       Path to the OpenAPI specification file (YAML or JSON).");
        System.out.println("  --output <dir>     Directory where the generated connector will be saved.");
        System.out.println("  --package <name>   Ballerina package name for the generated connector.");
        System.out.println("  --help             Show this help message.");
    }
}
