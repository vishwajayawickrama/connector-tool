import wso2/connector_automator.utils;

public function initLLMService(utils:LogLevel logLevel = "normal") returns LLMServiceError? {
    error? result = utils:initAIService(logLevel);
    if result is error {
        return error LLMServiceError("Failed to initialize LLM service", result);
    }
}
