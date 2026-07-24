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

import ballerina/file;
import ballerina/lang.regexp;

function shellQuote(string value) returns string {
    return "'" + regexp:replaceAll(re `'`, value, "'\"'\"'") + "'";
}

function isAbsolutePath(string path) returns boolean {
    if path.startsWith("/") || path.startsWith("\\") {
        return true;
    }
    return regexp:isFullMatch(re `^[A-Za-z]:[\\\\/].*`, path);
}

public function executeBalClientGenerate(string inputPath, string outputPath, OpenAPIToolOptions? customOptions = ()) returns utils:CommandResult {
    OpenAPIToolOptions toolOptions = customOptions ?: options;

    string command = string `bal openapi -i ${shellQuote(inputPath)} --mode client -o ${shellQuote(outputPath)}`;

    string licensePath = toolOptions.license;
    string licensePathForTest = licensePath;
    if !isAbsolutePath(licensePathForTest) {
        string workingDir = utils:getDirectoryPath(outputPath);
        licensePathForTest = string `${workingDir}/${licensePathForTest}`;
    }
    boolean|file:Error licenseExists = file:test(licensePathForTest, file:EXISTS);
    if licenseExists is boolean && licenseExists {
        command += string ` --license ${shellQuote(licensePath)}`;
    }

    if toolOptions.tags is string[] {
        string tagsList = string:'join(",", ...toolOptions.tags ?: []);
        command += string ` --tags ${shellQuote(tagsList)}`;
    }

    if toolOptions.operations is string[] {
        string operationsList = string:'join(",", ...toolOptions.operations ?: []);
        command += string ` --operations ${shellQuote(operationsList)}`;
    }

    command += string ` --client-methods ${shellQuote(toolOptions.clientMethod)}`;

    utils:logVerbose(string `running: ${command}`);
    return utils:executeCommand(command, utils:getDirectoryPath(outputPath));
}
