import wso2/connector_automator.utils;

import ballerina/data.jsondata;
import ballerina/io;
import ballerina/lang.runtime;

configurable RetryConfig retryConfig = {};

public function generateDescriptionsBatchWithRetry(DescriptionRequest[] requests, string apiContext, utils:LogLevel logLevel = "normal", RetryConfig? config = ()) returns BatchDescriptionResponse[]|LLMServiceError {
    RetryConfig retryConf = config ?: retryConfig;

    int attempt = 0;
    while attempt <= retryConf.maxRetries {
        BatchDescriptionResponse[]|LLMServiceError result = generateDescriptionsBatch(requests, apiContext);

        if result is BatchDescriptionResponse[] {
            if attempt > 0 {
                utils:logVerbose(string `batch description generation succeeded after retry (attempt ${attempt})`, logLevel);
            }
            return result;
        } else {
            if attempt == retryConf.maxRetries {
                utils:logError(string `batch description generation failed after all retries (${retryConf.maxRetries}): ${result.message()}`);
                return result;
            }

            if !isRetryableError(result) {
                utils:logError(string `non-retryable error in batch description generation: ${result.message()}`);
                return result;
            }

            decimal delay = calculateBackoffDelay(attempt, retryConf);
            utils:logVerbose(string `batch description generation failed, retrying (attempt ${attempt + 1}/${retryConf.maxRetries}, delay ${delay}s)`, logLevel);
            runtime:sleep(delay);
            attempt += 1;
        }
    }

    return error LLMServiceError("Unexpected error in retry logic");
}

public function generateOperationIdsBatchWithRetry(OperationIdRequest[] requests, string apiContext, string[] existingOperationIds, utils:LogLevel logLevel = "normal", RetryConfig? config = ()) returns BatchOperationIdResponse[]|LLMServiceError {
    RetryConfig retryConf = config ?: retryConfig;

    int attempt = 0;
    while attempt <= retryConf.maxRetries {
        BatchOperationIdResponse[]|LLMServiceError result = generateOperationIdsBatch(requests, apiContext, existingOperationIds);

        if result is BatchOperationIdResponse[] {
            if attempt > 0 {
                utils:logVerbose(string `batch operationId generation succeeded after retry (attempt ${attempt})`, logLevel);
            }
            return result;
        } else {
            if attempt == retryConf.maxRetries {
                utils:logError(string `batch operationId generation failed after all retries (${retryConf.maxRetries}): ${result.message()}`);
                return result;
            }

            if !isRetryableError(result) {
                utils:logError(string `non-retryable error in batch operationId generation: ${result.message()}`);
                return result;
            }

            decimal delay = calculateBackoffDelay(attempt, retryConf);
            utils:logVerbose(string `batch operationId generation failed, retrying (attempt ${attempt + 1}/${retryConf.maxRetries}, delay ${delay}s)`, logLevel);
            runtime:sleep(delay);
            attempt += 1;
        }
    }

    return error LLMServiceError("Unexpected error in retry logic");
}

public function generateSchemaNamesBatchWithRetry(SchemaRenameRequest[] requests, string apiContext, string[] existingNames, utils:LogLevel logLevel = "normal", RetryConfig? config = ()) returns BatchRenameResponse[]|LLMServiceError {
    RetryConfig retryConf = config ?: retryConfig;

    int attempt = 0;
    while attempt <= retryConf.maxRetries {
        BatchRenameResponse[]|LLMServiceError result = generateSchemaNamesBatch(requests, apiContext, existingNames);

        if result is BatchRenameResponse[] {
            if attempt > 0 {
                utils:logVerbose(string `batch schema naming succeeded after retry (attempt ${attempt})`, logLevel);
            }
            return result;
        } else {
            if attempt == retryConf.maxRetries {
                utils:logError(string `batch schema naming failed after all retries (${retryConf.maxRetries}): ${result.message()}`);
                return result;
            }

            if !isRetryableError(result) {
                utils:logError(string `non-retryable error in batch schema naming: ${result.message()}`);
                return result;
            }

            decimal delay = calculateBackoffDelay(attempt, retryConf);
            utils:logVerbose(string `batch schema naming failed, retrying (attempt ${attempt + 1}/${retryConf.maxRetries}, delay ${delay}s)`, logLevel);
            runtime:sleep(delay);
            attempt += 1;
        }
    }

    return error LLMServiceError("Unexpected error in retry logic");
}

public function addMissingDescriptionsBatchWithRetry(string specFilePath, int batchSize = 20, utils:LogLevel logLevel = "normal", RetryConfig? config = ()) returns int|LLMServiceError {
    utils:logVerbose(string `processing spec for missing descriptions: ${specFilePath} (batch size ${batchSize})`, logLevel);

    json|error specResult = io:fileReadJson(specFilePath);
    if specResult is error {
        return error LLMServiceError("Failed to read OpenAPI spec file", specResult);
    }

    json specJson = specResult;
    int descriptionsAdded = 0;

    if specJson is map<json> {
        map<json> specMap = <map<json>>specJson;
        string apiContext = extractApiContext(specJson);

        DescriptionRequest[] allRequests = [];
        map<string> requestToLocationMap = {};

        json|error componentsResult = specMap.get("components");
        if componentsResult is map<json> {
            json|error schemasResult = componentsResult.get("schemas");
            if schemasResult is map<json> {
                map<json> schemas = <map<json>>schemasResult;

                foreach string schemaName in schemas.keys() {
                    json|error schemaResult = schemas.get(schemaName);
                    if schemaResult is map<json> {
                        map<json> schemaMap = <map<json>>schemaResult;
                        collectDescriptionRequests(schemaMap, schemaName, "", allRequests, requestToLocationMap, specJson);
                    }
                }
            }
        }

        collectParameterDescriptionRequests(specJson, allRequests, requestToLocationMap);
        collectOperationDescriptionRequests(specJson, allRequests, requestToLocationMap);

        int totalRequests = allRequests.length();
        utils:logVerbose(string `collected ${totalRequests} description requests`, logLevel);

        int startIdx = 0;
        while startIdx < totalRequests {
            int endIdx = startIdx + batchSize;
            if endIdx > totalRequests {
                endIdx = totalRequests;
            }

            DescriptionRequest[] batch = allRequests.slice(startIdx, endIdx);
            int batchNum = (startIdx / batchSize) + 1;
            utils:logVerbose(string `processing descriptions batch ${batchNum} (${batch.length()} items)`, logLevel);

            BatchDescriptionResponse[]|LLMServiceError batchResult = generateDescriptionsBatchWithRetry(batch, apiContext, logLevel, config);
            if batchResult is BatchDescriptionResponse[] {
                utils:logVerbose(string `batch ${batchNum} complete (${batchResult.length()} descriptions)`, logLevel);

                foreach BatchDescriptionResponse response in batchResult {
                    string? location = requestToLocationMap[response.id];
                    if location is string {
                        error? updateResult = ();

                        if location.startsWith("paths.") && location.includes("parameters[name=") {
                            json|error pathsResult = specMap.get("paths");
                            if pathsResult is map<json> {
                                updateResult = updateParameterDescriptionInSpec(<map<json>>pathsResult, location, response.description);
                            }
                        } else if location.startsWith("paths.") && location.includes(".responses.") && location.endsWith(".description") {
                            json|error pathsResult = specMap.get("paths");
                            if pathsResult is map<json> {
                                updateResult = updateResponseDescriptionInSpec(<map<json>>pathsResult, location, response.description);
                            }
                        } else if location.startsWith("paths.") && !location.includes(".properties.") && !location.includes(".responses.") {
                            json|error pathsResult = specMap.get("paths");
                            if pathsResult is map<json> {
                                updateResult = updateOperationDescriptionInSpec(<map<json>>pathsResult, location, response.description);
                            }
                        } else {
                            json|error componentsResult2 = specMap.get("components");
                            if componentsResult2 is map<json> {
                                json|error schemasResult2 = componentsResult2.get("schemas");
                                if schemasResult2 is map<json> {
                                    updateResult = updateDescriptionInSpec(<map<json>>schemasResult2, location, response.description);
                                }
                            }
                        }

                        if updateResult is () {
                            descriptionsAdded += 1;
                            utils:logVerbose(string `applied description for ${response.id} at ${location}`, logLevel);
                        } else {
                            utils:logError(string `failed to apply description for ${response.id}: ${updateResult.message()}`);
                        }
                    }
                }
            } else {
                utils:logError(string `descriptions batch ${batchNum} failed after all retries: ${batchResult.message()}`);
            }
            startIdx += batchSize;
        }
    }

    string|error prettifiedResult = jsondata:prettify(specJson);
    if prettifiedResult is error {
        return error LLMServiceError("Failed to prettify JSON", prettifiedResult);
    }

    error? writeResult = io:fileWriteString(specFilePath, prettifiedResult);
    if writeResult is error {
        return error LLMServiceError("Failed to write updated OpenAPI spec", writeResult);
    }

    return descriptionsAdded;
}

public function renameInlineResponseSchemasBatchWithRetry(string specFilePath, int batchSize = 10, utils:LogLevel logLevel = "normal", RetryConfig? config = ()) returns int|LLMServiceError {
    utils:logVerbose(string `processing spec to rename InlineResponse schemas: ${specFilePath}`, logLevel);

    json|error specResult = io:fileReadJson(specFilePath);
    if specResult is error {
        return error LLMServiceError("Failed to read OpenAPI spec file", specResult);
    }

    json specJson = specResult;

    if !(specJson is map<json>) {
        return error LLMServiceError("Invalid OpenAPI spec format");
    }

    map<json> specMap = <map<json>>specJson;

    json|error componentsResult = specMap.get("components");
    if !(componentsResult is map<json>) {
        return error LLMServiceError("No components section found in OpenAPI spec");
    }

    map<json> components = <map<json>>componentsResult;
    json|error schemasResult = components.get("schemas");
    if !(schemasResult is map<json>) {
        return error LLMServiceError("No schemas section found in components");
    }

    map<json> schemas = <map<json>>schemasResult;

    string[] allExistingNames = [];
    foreach string schemaName in schemas.keys() {
        if (!schemaName.startsWith("InlineResponse")) {
            allExistingNames.push(schemaName);
        }
    }

    SchemaRenameRequest[] renameRequests = [];
    string apiContext = extractApiContext(specMap);

    foreach string schemaName in schemas.keys() {
        if (schemaName.startsWith("InlineResponse") || schemaName.endsWith("AllOf2") || schemaName.endsWith("OneOf2")) {
            json|error schemaResult = schemas.get(schemaName);
            if (schemaResult is map<json>) {
                string schemaDefinition = (<map<json>>schemaResult).toJsonString();
                string usageContext = extractSchemaUsageContext(schemaName, specMap);

                renameRequests.push({
                    originalName: schemaName,
                    schemaDefinition: schemaDefinition,
                    usageContext: usageContext
                });
            }
        }
    }

    if renameRequests.length() == 0 {
        utils:logVerbose("no InlineResponse schemas found to rename", logLevel);
        return 0;
    }

    map<string> nameMapping = {};
    int renamedCount = 0;
    int totalRequests = renameRequests.length();
    utils:logVerbose(string `collected ${totalRequests} schema rename requests`, logLevel);

    int startIdx = 0;
    while startIdx < totalRequests {
        int endIdx = startIdx + batchSize;
        if endIdx > totalRequests {
            endIdx = totalRequests;
        }

        SchemaRenameRequest[] batch = renameRequests.slice(startIdx, endIdx);
        int batchNum = (startIdx / batchSize) + 1;
        utils:logVerbose(string `processing schema rename batch ${batchNum} (${batch.length()} schemas)`, logLevel);

        BatchRenameResponse[]|LLMServiceError batchResult = generateSchemaNamesBatchWithRetry(batch, apiContext, allExistingNames, logLevel, config);
        if batchResult is BatchRenameResponse[] {
            utils:logVerbose(string `schema rename batch ${batchNum} complete (${batchResult.length()} schemas)`, logLevel);

            foreach BatchRenameResponse response in batchResult {
                string newName = response.newName;

                if (isValidSchemaName(newName)) {
                    if (!isNameTaken(newName, allExistingNames, nameMapping)) {
                        allExistingNames.push(newName);
                        nameMapping[response.originalName] = newName;
                        utils:logVerbose(string `renamed schema '${response.originalName}' → '${newName}'`, logLevel);
                        renamedCount += 1;
                    } else {
                        utils:logWarn(string `duplicate schema name generated for '${response.originalName}': '${newName}', using fallback`, logLevel);
                        string fallbackName = newName + "Alt";
                        int counter = 1;
                        while (isNameTaken(fallbackName, allExistingNames, nameMapping)) {
                            fallbackName = newName + "Alt" + counter.toString();
                            counter += 1;
                        }
                        allExistingNames.push(fallbackName);
                        nameMapping[response.originalName] = fallbackName;
                        renamedCount += 1;
                    }
                } else {
                    utils:logWarn(string `invalid schema name generated for '${response.originalName}': '${newName}', using fallback`, logLevel);
                    string fallbackBaseName = "Schema" + response.originalName.substring(14);
                    string fallbackName = fallbackBaseName;
                    int counter = 1;
                    while (isNameTaken(fallbackName, allExistingNames, nameMapping)) {
                        fallbackName = fallbackBaseName + counter.toString();
                        counter += 1;
                    }
                    allExistingNames.push(fallbackName);
                    nameMapping[response.originalName] = fallbackName;
                    renamedCount += 1;
                }
            }
        } else {
            utils:logError(string `schema rename batch ${batchNum} failed after all retries: ${batchResult.message()}`);
        }

        startIdx += batchSize;
    }

    if (nameMapping.length() > 0) {
        map<json> newSchemas = {};
        foreach string oldName in schemas.keys() {
            json|error schemaValue = schemas.get(oldName);
            if (schemaValue is json) {
                if (nameMapping.hasKey(oldName)) {
                    string? newNameResult = nameMapping[oldName];
                    if (newNameResult is string) {
                        newSchemas[newNameResult] = schemaValue;
                    }
                } else {
                    newSchemas[oldName] = schemaValue;
                }
            }
        }

        components["schemas"] = newSchemas;
        specMap["components"] = components;

        json updatedSpecResult = updateSchemaReferences(specMap, nameMapping, logLevel);

        string|error prettifiedResult = jsondata:prettify(updatedSpecResult);
        if prettifiedResult is error {
            return error LLMServiceError("Failed to prettify JSON", prettifiedResult);
        }

        error? writeResult = io:fileWriteString(specFilePath, prettifiedResult);
        if writeResult is error {
            return error LLMServiceError("Failed to write updated OpenAPI spec", writeResult);
        }
    }

    return renamedCount;
}

public function addMissingOperationIdsBatchWithRetry(string specFilePath, int batchSize = 15, utils:LogLevel logLevel = "normal", RetryConfig? config = ()) returns int|LLMServiceError {
    utils:logVerbose(string `processing spec for missing operationIds: ${specFilePath}`, logLevel);

    json|error specResult = io:fileReadJson(specFilePath);
    if specResult is error {
        return error LLMServiceError("Failed to read OpenAPI spec file", specResult);
    }

    json specJson = specResult;

    if !(specJson is map<json>) {
        return error LLMServiceError("Invalid OpenAPI spec format");
    }

    map<json> specMap = <map<json>>specJson;

    json|error pathsResult = specMap.get("paths");
    if !(pathsResult is map<json>) {
        return error LLMServiceError("No paths section found in OpenAPI spec");
    }

    map<json> paths = <map<json>>pathsResult;

    string[] existingOperationIds = [];
    collectExistingOperationIds(paths, existingOperationIds);

    OperationIdRequest[] missingOperationIds = [];
    map<string> requestToLocationMap = {};

    string apiContext = extractApiContext(specMap);
    collectMissingOperationIdRequests(paths, missingOperationIds, requestToLocationMap, apiContext);

    int totalRequests = missingOperationIds.length();
    if totalRequests == 0 {
        utils:logVerbose("no missing operationIds found", logLevel);
        return 0;
    }

    utils:logVerbose(string `collected ${totalRequests} missing operationId requests`, logLevel);

    int operationIdsAdded = 0;

    int startIdx = 0;
    while startIdx < totalRequests {
        int endIdx = startIdx + batchSize;
        if endIdx > totalRequests {
            endIdx = totalRequests;
        }

        OperationIdRequest[] batch = missingOperationIds.slice(startIdx, endIdx);
        int batchNum = (startIdx / batchSize) + 1;
        utils:logVerbose(string `processing operationId batch ${batchNum} (${batch.length()} operations)`, logLevel);

        BatchOperationIdResponse[]|LLMServiceError batchResult = generateOperationIdsBatchWithRetry(batch, apiContext, existingOperationIds, logLevel, config);
        if batchResult is BatchOperationIdResponse[] {
            utils:logVerbose(string `operationId batch ${batchNum} complete (${batchResult.length()} operations)`, logLevel);

            foreach BatchOperationIdResponse response in batchResult {
                string? location = requestToLocationMap[response.id];
                if location is string {
                    error? updateResult = updateOperationIdInSpec(paths, location, response.operationId);
                    if updateResult is () {
                        existingOperationIds.push(response.operationId);
                        operationIdsAdded += 1;
                        utils:logVerbose(string `applied operationId '${response.operationId}' at ${location}`, logLevel);
                    } else {
                        utils:logError(string `failed to apply operationId for ${response.id}: ${updateResult.message()}`);
                    }
                }
            }
        } else {
            utils:logError(string `operationId batch ${batchNum} failed after all retries: ${batchResult.message()}`);
        }
        startIdx += batchSize;
    }

    string|error prettifiedResult = jsondata:prettify(specJson);
    if prettifiedResult is error {
        return error LLMServiceError("Failed to prettify JSON", prettifiedResult);
    }

    error? writeResult = io:fileWriteString(specFilePath, prettifiedResult);
    if writeResult is error {
        return error LLMServiceError("Failed to write updated OpenAPI spec", writeResult);
    }

    return operationIdsAdded;
}
