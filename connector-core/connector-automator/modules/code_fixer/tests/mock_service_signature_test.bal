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

import ballerina/test;

const string ORIGINAL_SERVICE = string `service / on new http:Listener(9090) {
    resource function get files/[string id]() returns FileDetail|AnydataDefault {
        return {};
    }
}`;

@test:Config
function testAllowMockServiceBodyChange() {
    string fixedService = string `service / on new http:Listener(9090) {
    resource function get files/[string id]() returns FileDetail|AnydataDefault {
        return {id: "1"};
    }
}`;
    error? result = validateMockServiceResourceSignatures(ORIGINAL_SERVICE, fixedService);
    test:assertTrue(result is ());
}

@test:Config
function testAllowMockServiceSignatureWhitespaceChange() {
    string fixedService = string `service / on new http:Listener(9090) {
    resource function get files/[string id]() returns
        FileDetail | AnydataDefault {
        return {};
    }
}`;
    error? result = validateMockServiceResourceSignatures(ORIGINAL_SERVICE, fixedService);
    test:assertTrue(result is ());
}

@test:Config
function testRejectMockServiceReturnTypeChange() {
    string fixedService = string `service / on new http:Listener(9090) {
    resource function get files/[string id]() returns FileDetail|http:InternalServerError {
        return {};
    }
}`;
    error? result = validateMockServiceResourceSignatures(ORIGINAL_SERVICE, fixedService);
    test:assertTrue(result is error);
}

@test:Config
function testRejectRemovedMockServiceResource() {
    error? result = validateMockServiceResourceSignatures(ORIGINAL_SERVICE, "");
    test:assertTrue(result is error);
}

@test:Config
function testRejectMockServicePathChange() {
    string fixedService = string `service / on new http:Listener(9090) {
    resource function get folders/[string id]() returns FileDetail|AnydataDefault {
        return {};
    }
}`;
    error? result = validateMockServiceResourceSignatures(ORIGINAL_SERVICE, fixedService);
    test:assertTrue(result is error);
}

@test:Config
function testRejectMockServiceAnnotationChange() {
    string originalService = string `service / on new http:Listener(9090) {
    @http:ResourceConfig {
        methods: ["GET"]
    }
    resource function get files() returns FileDetail {
        return {};
    }
}`;
    string fixedService = string `service / on new http:Listener(9090) {
    @http:ResourceConfig {
        methods: ["POST"]
    }
    resource function get files() returns FileDetail {
        return {};
    }
}`;
    error? result = validateMockServiceResourceSignatures(originalService, fixedService);
    test:assertTrue(result is error);
}
