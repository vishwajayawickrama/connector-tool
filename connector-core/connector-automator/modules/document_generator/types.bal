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

public type ConnectorMetadata record {
    string connectorName;
    string version;
    string[] examples;
    string clientBalContent;
    string typesBalContent;

};

public type ExampleData record {|
    string exampleName;
    string exampleDirName;
    string[] balFiles;
    string[] balFileContents;
    string mainBalContent;
|};
