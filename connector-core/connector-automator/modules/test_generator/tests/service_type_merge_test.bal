// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import ballerina/file;
import ballerina/io;
import ballerina/test;

@test:Config
function testMergeMissingServiceTypes() {
    string tempDir = checkpanic file:createTempDir(prefix = "service_type_merge_");
    string connectorTypesPath = checkpanic file:joinPath(tempDir, "connector_types.bal");
    string serviceTypesPath = checkpanic file:joinPath(tempDir, "service_types.bal");
    string connectorTypes = string `import ballerina/http;

public type Existing record {|
    string value;
|};
`;
    string serviceTypes = string `import ballerina/http;
import ballerina/time;
import ballerina/log;
import ballerina/test;

public type Existing record {|
    int value;
|};

# Default response generated for the service
public type AnydataDefault record {|
    *http:DefaultStatusCodeResponse;
    anydata body;
|};

@test:Mock {}
public type AcceptedResponse record {|
    record {|
        string id;
    |} body;
|};

public type ResponseAlias time:Utc|error;
`;
    checkpanic io:fileWriteString(connectorTypesPath, connectorTypes);
    checkpanic io:fileWriteString(serviceTypesPath, serviceTypes);

    int merged = checkpanic mergeMissingServiceTypes(connectorTypesPath, serviceTypesPath);
    string result = checkpanic io:fileReadString(connectorTypesPath);

    test:assertEquals(merged, 3);
    test:assertEquals(countOccurrences(result, "public type Existing "), 1);
    test:assertTrue(result.includes("import ballerina/time;"));
    test:assertFalse(result.includes("import ballerina/log;"));
    test:assertTrue(result.includes("import ballerina/test;"));
    test:assertTrue(result.includes("# Default response generated for the service"));
    test:assertTrue(result.includes("@test:Mock {}"));
    test:assertTrue(result.includes("public type AnydataDefault record"));
    test:assertTrue(result.includes("public type AcceptedResponse record"));
    test:assertTrue(result.includes("public type ResponseAlias time:Utc|error;"));

    checkpanic file:remove(tempDir, file:RECURSIVE);
}

@test:Config
function testRejectMalformedServiceType() {
    string malformed = "public type Broken record {| string value;";
    ServiceTypeDeclaration[]|error result = extractServiceTypeDeclarations(malformed);
    test:assertTrue(result is error);
}

function countOccurrences(string content, string value) returns int {
    int count = 0;
    int searchStart = 0;
    while searchStart < content.length() {
        int? matchIndex = content.indexOf(value, searchStart);
        if matchIndex is () {
            break;
        }
        count += 1;
        searchStart = matchIndex + value.length();
    }
    return count;
}
