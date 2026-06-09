package io.ballerina.aigentool.workflows;

import io.ballerina.aigentool.spi.AiGenWorkflow;
import io.ballerina.aigentool.utils.Utils;
import io.ballerina.runtime.api.values.BArray;

public final class ExampleDocGeneratorWorkflow implements AiGenWorkflow {

    private final String ORG = "wso2";
    private final String MODULE = "example_doc_generator";
    private final String VERSION = "0";
    private final String NAME = "example-doc";

    @Override
    public String getName() {
        return NAME;
    }

    @Override
    public void runWorkflow(BArray args) {
        Utils.callBallerinaRunteimAPi(ORG, MODULE, VERSION, args);
    }

    @Override
    public void help() {
        System.out.println("Usage: aigen example-doc [options]");
        System.out.println("Options:");
        System.out.println("  --spec <path>       Path to the OpenAPI specification file (YAML or JSON).");
        System.out.println("  --output <dir>     Directory where the generated connector will be saved.");
        System.out.println("  --package <name>   Ballerina package name for the generated connector.");
        System.out.println("  --help             Show this help message.");
    }
}
