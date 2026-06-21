import wso2/connector_automator.utils;

public function initLLMService() returns LLMServiceError? {
    error? result = utils:initAIService();
    if result is error {
        return error LLMServiceError("Failed to initialize LLM service", result);
    }
}
