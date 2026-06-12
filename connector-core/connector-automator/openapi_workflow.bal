import wso2/connector_automator.utils;

public function runOpenApiWorkflow(string openApiSpec, string outputDir, string logLevel) returns error? {
    utils:LogLevel level = logLevel == "quiet" ? "quiet" : logLevel == "verbose" ? "verbose" : "normal";
    return executeOpenApiPipeline(openApiSpec, outputDir, level);
}
