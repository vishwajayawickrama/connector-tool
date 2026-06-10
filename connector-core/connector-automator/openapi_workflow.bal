public function runOpenApiWorkflow(string openApiSpec, string outputDir) returns error? {
    return executeOpenApiPipeline(openApiSpec, outputDir);
}
