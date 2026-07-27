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

const int DISPLAY_NAME_MAX_LENGTH = 37;

public function generateDescriptionsBatch(DescriptionRequest[] requests, string apiContext) returns BatchDescriptionResponse[]|error {
    if !utils:isAIServiceInitialized() {
        return error("LLM service not initialized");
    }

    if requests.length() == 0 {
        return [];
    }

    // Build batch prompt with enhanced categorization
    string requestsSection = "";
    foreach int i in 0 ..< requests.length() {
        DescriptionRequest req = requests[i];
        string requestType = getDescriptionRequestType(req.schemaPath);

        requestsSection += string `
${i + 1}. ID: ${req.id}
   Type: ${requestType}
   Name: ${req.name}
   Path: ${req.schemaPath}
   Context: ${req.context}
`;
    }

    string prompt = string `You are an API documentation expert. Generate concise, professional descriptions for the following API elements.

API CONTEXT:
${apiContext}

REQUESTS TO PROCESS:
${requestsSection}

INSTRUCTIONS:
1. For FIELD descriptions: Describe what the field represents (under 80 characters)
2. For PARAMETER descriptions: Explain the parameter's purpose (under 100 characters)
3. For REQUEST BODY descriptions: Describe the submitted payload and its purpose (under 100 characters)
4. For SECURITY SCHEME descriptions: Describe the credential and where/how it is supplied (under 100 characters)
5. For OPERATION descriptions: Describe what the operation returns (under 120 characters, suitable for return parameter docs)
6. For OPERATION SUMMARY: Produce a short imperative-verb action phrase suitable as a one-line doc comment. Rules (all mandatory, no exceptions):
   a) HARD LIMIT: ${DISPLAY_NAME_MAX_LENGTH} characters total — count every character including spaces before you respond.
   b) The phrase MUST be complete: it must end at a natural sentence or clause boundary — never mid-word and never mid-sentence. If your draft exceeds ${DISPLAY_NAME_MAX_LENGTH} characters, shorten the idea (drop qualifiers, use a shorter synonym, simplify the verb object) until the entire phrase fits within ${DISPLAY_NAME_MAX_LENGTH} characters as a finished thought.
   c) Use an imperative verb phrase, e.g. "Retrieve a contact by ID" or "List all active deals". Do not restate the operationId verbatim.
   d) If the context provides an existing summary marked as "too long", condense that exact summary to fit the limit while preserving its meaning — do not invent unrelated wording.
7. Use professional API documentation language
8. Consider the API context and element context
9. Return responses in the exact JSON format shown below
10. Do not include fenced code blocks in the response
11. Keep descriptions concise but informative

REQUIRED RESPONSE FORMAT (JSON):
{
  "descriptions": [
    {
      "id": "request_id_1",
      "description": "Generated description text"
    },
    {
      "id": "request_id_2", 
      "description": "Generated description text"
    }
  ]
}`;

    string|error response = utils:callAI(prompt);
    if response is error {
        return error("Failed to generate batch descriptions", response);
    }

    // Parse JSON response
    json|error jsonResult = response.fromJsonString();
    if jsonResult is error {
        return error("Failed to parse batch response JSON", jsonResult);
    }

    if jsonResult is map<json> && jsonResult.hasKey("descriptions") {
        json descriptionsJson = jsonResult.get("descriptions");
        if descriptionsJson is json[] {
            BatchDescriptionResponse[] results = [];
            foreach json desc in descriptionsJson {
                if desc is map<json> {
                    string? id = desc.get("id") is string ? <string>desc.get("id") : ();
                    string? description = desc.get("description") is string ? <string>desc.get("description") : ();
                    if id is string && description is string {
                        string cleanedDesc = description.trim();
                        if cleanedDesc.endsWith(".") {
                            cleanedDesc = cleanedDesc.substring(0, cleanedDesc.length() - 1).trim();
                        }
                        results.push({id: id, description: cleanedDesc});
                    }
                }
            }
            return results;
        }
    }
    return error("Invalid batch response format");
}

function getDescriptionRequestType(string schemaPath) returns string {
    if schemaPath.startsWith("paths.") && schemaPath.includes("parameters[name=") {
        return "parameter";
    }
    if schemaPath.startsWith("paths.") && schemaPath.endsWith(".requestBody") {
        return "requestBody";
    }
    if schemaPath.startsWith("components.securitySchemes.") {
        return "securityScheme";
    }
    if schemaPath.startsWith("paths.") && schemaPath.endsWith(".summary") {
        return "operationSummary";
    }
    if schemaPath.startsWith("paths.") && !schemaPath.includes(".properties.") {
        return "operation";
    }
    return "field";
}

// Process multiple operationId requests in a single LLM call
public function generateOperationIdsBatch(OperationIdRequest[] requests, string apiContext, string[] existingOperationIds) returns BatchOperationIdResponse[]|error {
    if !utils:isAIServiceInitialized() {
        return error("LLM service not initialized");
    }

    if requests.length() == 0 {
        return [];
    }

    string requestsSection = "";
    foreach int i in 0 ..< requests.length() {
        OperationIdRequest req = requests[i];
        string tags = req.tags is string[] ? string:'join(", ", ...<string[]>req.tags) : "N/A";
        string currentId = req.currentOperationId ?: "N/A (not yet assigned)";
        requestsSection += string `
${i + 1}. ID: ${req.id}
   Path: ${req.path}
   Method: ${req.method.toUpperAscii()}
   Current operationId: ${currentId}
   Summary: ${req.summary ?: "N/A"}
   Description: ${req.description ?: "N/A"}
   Tags: ${tags}
`;
    }

    string existingIdsStr = string:'join(", ", ...existingOperationIds);

    string prompt = string `You are an expert in REST API design. Generate or improve operationIds for these API operations, producing concise, intent-revealing camelCase names.

API CONTEXT:
${apiContext}

EXISTING OPERATION IDS (must not conflict):
${existingIdsStr}

OPERATIONS TO NAME OR IMPROVE:
${requestsSection}

REQUIREMENTS:
- Use camelCase (e.g., getUserProfile, createPlaylist, updateUserSettings)
- Be descriptive and follow REST conventions (get*, create*, update*, delete*, list*)
- If "Current operationId" is verbose or path-encoded (e.g., postFilesV3FilesUpload), replace it with a concise intent-revealing name (e.g., uploadFile)
- If "Current operationId" is already concise and intent-revealing, keep it unchanged
- Ensure operationIds are unique and don't conflict with existing ones
- Consider HTTP method, path, and operation purpose
- Keep names concise but clear (prefer verbs + nouns)
- HARD LIMIT: ${DISPLAY_NAME_MAX_LENGTH} characters for the camelCase operationId — it is rendered as a spaced display label in low-code environments (e.g. getUserProfile → "Get User Profile"), so brevity matters. If you cannot fit within the limit, drop qualifiers or simplify the verb-object rather than truncating mid-word.
- Do not include fenced code blocks in the response

REQUIRED RESPONSE FORMAT (JSON):
{
  "operationIds": [
    {
      "id": "request_id_1",
      "operationId": "getUserProfile"
    },
    {
      "id": "request_id_2",
      "operationId": "createPlaylist"
    }
  ]
}`;

    string|error response = utils:callAI(prompt);
    if response is error {
        return error("Failed to generate batch operationIds", response);
    }

    json|error jsonResult = response.fromJsonString();
    if jsonResult is error {
        return error("Failed to parse batch operationId response JSON", jsonResult);
    }

    if jsonResult is map<json> && jsonResult.hasKey("operationIds") {
        json operationIdsJson = jsonResult.get("operationIds");
        if operationIdsJson is json[] {
            BatchOperationIdResponse[] results = [];
            foreach json opId in operationIdsJson {
                if opId is map<json> {
                    string? id = opId.get("id") is string ? <string>opId.get("id") : ();
                    string? operationId = opId.get("operationId") is string ? <string>opId.get("operationId") : ();
                    if id is string && operationId is string {
                        results.push({id: id, operationId: operationId.trim()});
                    }
                }
            }
            return results;
        }
    }
    return error("Invalid batch operationId response format");
}

public function generateSchemaNamesBatch(SchemaRenameRequest[] requests, string apiContext, string[] existingNames) returns BatchRenameResponse[]|error {
    if !utils:isAIServiceInitialized() {
        return error("LLM service not initialized");
    }

    if requests.length() == 0 {
        return [];
    }

    string requestsSection = "";
    foreach int i in 0 ..< requests.length() {
        SchemaRenameRequest req = requests[i];
        requestsSection += string `
${i + 1}. Original: ${req.originalName}
   Definition: ${req.schemaDefinition}
   Usage: ${req.usageContext}
`;
    }

    string existingNamesStr = string:'join(", ", ...existingNames);

    string prompt = string `You are an expert in naming OpenAPI schemas. Review each schema name and return a meaningful, unique PascalCase name.

API CONTEXT:
${apiContext}

EXISTING SCHEMA NAMES (avoid conflicts):
${existingNamesStr}

SCHEMAS TO RENAME:
${requestsSection}

REQUIREMENTS:
- Use PascalCase (e.g., UserProfile, AttachmentResponse)
- Be descriptive but concise (2-3 words max)
- Ensure names are unique and don't conflict with existing names
- Consider schema role (Request, Response, List, Details, etc.)
- If the original name is already clear and meaningful, return it unchanged
- Return exactly one result for every input schema and preserve each originalName exactly
- Do not include fenced code blocks in the response. 

REQUIRED RESPONSE FORMAT (JSON):
{
  "renames": [
    {
      "originalName": "InlineResponse200",
      "newName": "UserListResponse"
    },
    {
      "originalName": "InlineResponse201",
      "newName": "CreateUserResponse"
    }
  ]
}`;

    string|error response = utils:callAI(prompt);
    if response is error {
        return error("Failed to generate batch schema names", response);
    }

    string|error jsonContent = utils:extractJsonFromLLMResponse(response);
    if jsonContent is error {
        return error("Failed to extract batch schema-name response JSON: " +
            truncateAiResponseForError(response), jsonContent);
    }

    json|error jsonResult = jsonContent.fromJsonString();
    if jsonResult is error {
        return error("Failed to parse batch schema-name response JSON: " +
            truncateAiResponseForError(response), jsonResult);
    }

    if jsonResult is map<json> && jsonResult.hasKey("renames") {
        json renamesJson = jsonResult.get("renames");
        if renamesJson is json[] {
            BatchRenameResponse[] results = [];
            foreach json rename in renamesJson {
                if rename is map<json> {
                    string? originalName = rename.get("originalName") is string ? <string>rename.get("originalName") : ();
                    string? newName = rename.get("newName") is string ? <string>rename.get("newName") : ();
                    if originalName is string && newName is string {
                        results.push({originalName: originalName, newName: newName.trim()});
                    }
                }
            }
            return results;
        }
    }
    return error("Invalid batch rename response format");
}

function truncateAiResponseForError(string response) returns string {
    string normalized = response.trim();
    int previewLimit = 500;
    if normalized.length() > previewLimit {
        normalized = normalized.substring(0, previewLimit) + "...";
    }
    return string `response preview: ${normalized}`;
}
