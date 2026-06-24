// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import wso2/connector_automator.utils;

public function initExampleGenerator() returns error? {
    return utils:initAIService();
}

public function generateUseCaseAndFunctions(ConnectorDetails details, string[] usedFunctions) returns json|error {
    string prompt = getUsecasePrompt(details, usedFunctions);

    if !utils:isAIServiceInitialized() {
        return error("AI model not initialized. Please call initExampleGenerator() first.");
    }

    string result = check utils:callAI(prompt);

    return result.fromJsonString();
}

public function generateExampleCode(ConnectorDetails details, string useCase, string targetedContext) returns string|error {
    string prompt = getExampleCodegenerationPrompt(details, useCase, targetedContext);

    if !utils:isAIServiceInitialized() {
        return error("AI model not initialized. Please call initExampleGenerator() first.");
    }

    string result = check utils:callAI(prompt);

    return result;
}

public function generateExampleName(string useCase) returns string|error {
    string prompt = getExampleNamePrompt(useCase);

    if !utils:isAIServiceInitialized() {
        return error("AI model not initialized. Please call initExampleGenerator() first.");
    }

    string|error result = utils:callAI(prompt);
    if result is error {
        return error("Failed to generate example name", result);
    }

    return result == "" ? "example-1" : result;
}
