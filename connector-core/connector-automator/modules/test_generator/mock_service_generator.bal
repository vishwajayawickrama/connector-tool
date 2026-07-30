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
import ballerina/io;
import ballerina/lang.regexp;

type ServiceTypeDeclaration record {|
    string name;
    string sourceCode;
|};

function generateMockServerStub(string connectorPath, string specPath, string[]? selectedOperations) returns error? {
    string ballerinaDir = check utils:resolveBallerinaDir(connectorPath);
    string testsDir = ballerinaDir + "/tests";

    string absSpecPath = check file:getAbsolutePath(specPath);
    string absTestsDir = check file:getAbsolutePath(testsDir);

    check file:createDir(testsDir, file:RECURSIVE);

    // Generating mock server stub.
    string command;
    if selectedOperations is () {
        command = string `bal openapi -i ${absSpecPath} --mode service -o ${absTestsDir}`;
    } else {
        string operationsList = string:'join(",", ...selectedOperations);
        command = string `bal openapi -i ${absSpecPath} --mode service -o ${absTestsDir} --operations ${operationsList}`;
    }

    utils:CommandResult result = utils:executeCommand(command, ballerinaDir);
    if !result.success {
        return error("Failed to generate mock server stub using ballerina openAPI tool: " + result.stderr);
    }

    // Rename the generated service scaffold to mock_service.bal
    string serviceFileOld = testsDir + "/aligned_ballerina_openapi_service.bal";
    string serviceFileNew = testsDir + "/mock_service.bal";
    if check file:test(serviceFileOld, file:EXISTS) {
        check file:rename(serviceFileOld, serviceFileNew);
        utils:logVerbose("renamed service file to mock_service.bal");
    } else {
        return error(string `bal openapi --mode service succeeded but expected scaffold not found: ${serviceFileOld}`);
    }

    // Merge service-only response types into the connector types before removing the duplicate file.
    string serviceTypesPath = testsDir + "/types.bal";
    if check file:test(serviceTypesPath, file:EXISTS) {
        string connectorTypesPath = ballerinaDir + "/types.bal";
        int mergedTypeCount = check mergeMissingServiceTypes(connectorTypesPath, serviceTypesPath);
        if mergedTypeCount > 0 {
            utils:logVerbose(string `merged ${mergedTypeCount} service response type${mergedTypeCount == 1 ? "" : "s"} into types.bal`);
        } else {
            utils:logVerbose("all service response types already available");
        }
        check file:remove(serviceTypesPath);
        utils:logVerbose("removed generated tests/types.bal");
    }
}

function mergeMissingServiceTypes(string connectorTypesPath, string serviceTypesPath) returns int|error {
    string connectorTypes = check io:fileReadString(connectorTypesPath);
    string serviceTypes = check io:fileReadString(serviceTypesPath);

    ServiceTypeDeclaration[] connectorDeclarations = check extractServiceTypeDeclarations(connectorTypes);
    ServiceTypeDeclaration[] serviceDeclarations = check extractServiceTypeDeclarations(serviceTypes);
    map<boolean> connectorTypeNames = {};
    foreach ServiceTypeDeclaration declaration in connectorDeclarations {
        connectorTypeNames[declaration.name] = true;
    }

    ServiceTypeDeclaration[] missingDeclarations = serviceDeclarations.filter(
        function(ServiceTypeDeclaration declaration) returns boolean {
            return !connectorTypeNames.hasKey(declaration.name);
        }
    );
    if missingDeclarations.length() == 0 {
        return 0;
    }

    string[] connectorImports = extractTopLevelImports(connectorTypes);
    map<boolean> connectorImportPrefixes = {};
    foreach string importDeclaration in connectorImports {
        connectorImportPrefixes[getImportPrefix(importDeclaration)] = true;
    }
    string[] missingImports = extractTopLevelImports(serviceTypes).filter(
        function(string importDeclaration) returns boolean {
            string prefix = getImportPrefix(importDeclaration);
            return !connectorImportPrefixes.hasKey(prefix) &&
                missingDeclarations.some(
                    function(ServiceTypeDeclaration declaration) returns boolean {
                        return declaration.sourceCode.includes(prefix + ":");
                    }
                );
        }
    );

    string updatedTypes = addMissingImports(connectorTypes, missingImports);
    string[] declarationSources = missingDeclarations.'map(
        function(ServiceTypeDeclaration declaration) returns string {
            return declaration.sourceCode.trim();
        }
    );
    updatedTypes = trimTrailingWhitespace(updatedTypes) + "\n\n" +
        string:'join("\n\n", ...declarationSources) + "\n";
    check io:fileWriteString(connectorTypesPath, updatedTypes);
    return missingDeclarations.length();
}

function extractServiceTypeDeclarations(string content) returns ServiceTypeDeclaration[]|error {
    ServiceTypeDeclaration[] declarations = [];
    int searchStart = 0;
    string marker = "public type ";

    while searchStart < content.length() {
        int? declarationStart = content.indexOf(marker, searchStart);
        if declarationStart is () {
            break;
        }

        int nameStart = declarationStart + marker.length();
        while nameStart < content.length() && isWhitespaceCharacter(content.substring(nameStart, nameStart + 1)) {
            nameStart += 1;
        }
        int nameEnd = nameStart;
        while nameEnd < content.length() && isIdentifierCharacter(content.substring(nameEnd, nameEnd + 1)) {
            nameEnd += 1;
        }
        if nameEnd == nameStart {
            return error(string `Malformed generated type declaration at offset ${declarationStart}`);
        }

        string typeName = content.substring(nameStart, nameEnd);
        int declarationEnd = check findTypeDeclarationEnd(content, nameEnd, typeName);
        int sourceStart = findAttachedTypeMetadataStart(content, declarationStart);
        declarations.push({
            name: typeName,
            sourceCode: content.substring(sourceStart, declarationEnd)
        });
        searchStart = declarationEnd;
    }
    return declarations;
}

function findTypeDeclarationEnd(string content, int startIndex, string typeName) returns int|error {
    int braceDepth = 0;
    int bracketDepth = 0;
    int parenthesisDepth = 0;
    boolean inString = false;
    boolean escaped = false;
    int index = startIndex;

    while index < content.length() {
        string character = content.substring(index, index + 1);
        if inString {
            if escaped {
                escaped = false;
            } else if character == "\\" {
                escaped = true;
            } else if character == "\"" {
                inString = false;
            }
        } else {
            if character == "\"" {
                inString = true;
            } else if character == "{" {
                braceDepth += 1;
            } else if character == "}" {
                braceDepth -= 1;
            } else if character == "[" {
                bracketDepth += 1;
            } else if character == "]" {
                bracketDepth -= 1;
            } else if character == "(" {
                parenthesisDepth += 1;
            } else if character == ")" {
                parenthesisDepth -= 1;
            } else if character == ";" && braceDepth == 0 && bracketDepth == 0 && parenthesisDepth == 0 {
                return index + 1;
            }
            if braceDepth < 0 || bracketDepth < 0 || parenthesisDepth < 0 {
                return error(string `Malformed generated type declaration '${typeName}'`);
            }
        }
        index += 1;
    }
    return error(string `Unterminated generated type declaration '${typeName}'`);
}

function findAttachedTypeMetadataStart(string content, int declarationStart) returns int {
    int declarationLineStart = findLineStart(content, declarationStart);
    int sourceStart = declarationLineStart;
    int previousLineEnd = declarationLineStart;
    boolean foundMetadata = false;
    while previousLineEnd > 0 {
        if previousLineEnd < 2 {
            break;
        }
        int previousLineStart = findLineStart(content, previousLineEnd - 2);
        string previousLine = content.substring(previousLineStart, previousLineEnd).trim();
        if previousLine.length() == 0 || previousLine.endsWith(";") {
            break;
        }
        sourceStart = previousLineStart;
        if previousLine.startsWith("#") || previousLine.startsWith("@") {
            foundMetadata = true;
        }
        previousLineEnd = previousLineStart;
    }
    return foundMetadata ? sourceStart : declarationLineStart;
}

function findLineStart(string content, int index) returns int {
    int? newlineIndex = content.lastIndexOf("\n", index);
    return newlineIndex is int ? newlineIndex + 1 : 0;
}

function extractTopLevelImports(string content) returns string[] {
    string[] imports = [];
    foreach string line in regexp:split(re `\r?\n`, content) {
        string trimmed = line.trim();
        if trimmed.startsWith("import ") && trimmed.endsWith(";") && imports.indexOf(trimmed) is () {
            imports.push(trimmed);
        }
    }
    return imports;
}

function addMissingImports(string content, string[] missingImports) returns string {
    if missingImports.length() == 0 {
        return content;
    }

    int insertionPoint = 0;
    int searchStart = 0;
    while searchStart < content.length() {
        int? importStart = content.indexOf("import ", searchStart);
        if importStart is () {
            break;
        }
        int? importEnd = content.indexOf(";", importStart);
        if importEnd is () {
            break;
        }
        insertionPoint = importEnd + 1;
        searchStart = insertionPoint;
    }

    string importsText = string:'join("\n", ...missingImports);
    if insertionPoint > 0 {
        return content.substring(0, insertionPoint) + "\n" + importsText + content.substring(insertionPoint);
    }

    int? firstTypeStart = content.indexOf("public type ");
    insertionPoint = firstTypeStart is int ? findLineStart(content, firstTypeStart) : content.length();
    string separator = insertionPoint > 0 && !content.substring(0, insertionPoint).endsWith("\n") ? "\n" : "";
    return content.substring(0, insertionPoint) + separator + importsText + "\n\n" +
        content.substring(insertionPoint);
}

function getImportPrefix(string importDeclaration) returns string {
    string importPath = importDeclaration.substring("import ".length(),
        importDeclaration.length() - 1).trim();
    int? aliasIndex = importPath.lastIndexOf(" as ");
    if aliasIndex is int {
        return importPath.substring(aliasIndex + " as ".length()).trim();
    }
    int? slashIndex = importPath.lastIndexOf("/");
    string moduleName = slashIndex is int ? importPath.substring(slashIndex + 1) : importPath;
    int? dotIndex = moduleName.lastIndexOf(".");
    return dotIndex is int ? moduleName.substring(dotIndex + 1) : moduleName;
}

function isWhitespaceCharacter(string character) returns boolean {
    return character == " " || character == "\t" || character == "\r" || character == "\n";
}

function isIdentifierCharacter(string character) returns boolean {
    return character == "_" || character == "'" ||
        (character >= "A" && character <= "Z") ||
        (character >= "a" && character <= "z") ||
        (character >= "0" && character <= "9");
}

function trimTrailingWhitespace(string content) returns string {
    int endIndex = content.length();
    while endIndex > 0 && isWhitespaceCharacter(content.substring(endIndex - 1, endIndex)) {
        endIndex -= 1;
    }
    return content.substring(0, endIndex);
}
