package io.ballerina.aigentool.spi;

import io.ballerina.runtime.api.values.BArray;

public interface AiGenWorkflow {

    public String getName();

    public void runWorkflow(BArray args);

    public void help();
}
