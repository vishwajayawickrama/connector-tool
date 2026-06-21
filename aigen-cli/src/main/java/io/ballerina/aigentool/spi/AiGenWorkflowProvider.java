package io.ballerina.aigentool.spi;

import java.util.ServiceLoader;

public class AiGenWorkflowProvider {

    public static AiGenWorkflow getWorkflow(String name) { 
        ServiceLoader<AiGenWorkflow> workflows = ServiceLoader.load(AiGenWorkflow.class);
        for (AiGenWorkflow workflow : workflows) {
            if (workflow.getName().equals(name)) {
                return workflow;
            }
        }
        throw new IllegalArgumentException("Workflow not found: " + name);
    }
}
