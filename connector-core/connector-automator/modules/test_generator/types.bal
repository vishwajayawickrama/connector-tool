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

// Unified connector analysis record for both OpenAPI and SDK workflows.
public type ConnectorAnalysis record {
    string packageName;
    string mockServerContent = "";
    string initMethodSignature;
    string referencedTypeDefinitions;
    string connectionConfigDefinition = "";
    string enumDefinitions = "";
    "resource"|"remote" methodType = "resource";
    string remoteMethodSignatures = "";
    string clientContent = "";
    string typesContent = "";
};
