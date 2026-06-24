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

public type LLMServiceError distinct error; // custom error type for LLM related failures

// Batch processing types
public type DescriptionRequest record {
    string id;
    string name;
    string context;
    string schemaPath; // e.g., "User.properties.email" or "User"
};

public type SchemaRenameRequest record {
    string originalName;
    string schemaDefinition;
    string usageContext;
};

public type BatchDescriptionResponse record {
    string id;
    string description;
};

public type DescriptionEnhancementResult record {
    int descriptionsAdded;
    int summariesAdded;
};

public type BatchRenameResponse record {
    string originalName;
    string newName;
};

public type OperationIdRequest record {
    string id;
    string path;
    string method;
    string summary?;
    string description?;
    string[] tags?;
};

public type BatchOperationIdResponse record {
    string id;
    string operationId;
};

public type RetryConfig record {
    int maxRetries = 3;
    decimal initialDelaySeconds = 1.0;
    decimal maxDelaySeconds = 60.0;
    decimal backoffMultiplier = 2.0;
    boolean jitter = true;
};
