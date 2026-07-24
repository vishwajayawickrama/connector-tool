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

import ballerina/ai;
import ballerina/file;
import ballerina/io;
import ballerina/lang.regexp;
import ballerina/lang.'string as strings;
import wso2/connector_automator.utils;

public function generateAllDocumentation(string connectorPath) returns error? {
    check generateIndividualExampleReadmes(connectorPath);
    check generateExamplesReadme(connectorPath);
    check generateBallerinaReadme(connectorPath);
    check generateTestsReadme(connectorPath);
    check generateMainReadme(connectorPath);
    check generateKeywords(connectorPath);
}

public function generateBallerinaReadme(string connectorPath) returns error? {
    ConnectorMetadata metadata = check analyzeConnector(connectorPath);
    check retainDocumentedExamples(connectorPath, metadata);
    map<string> aiContent = check generateBallerinaContent(metadata, true);

    TemplateData data = createTemplateData(metadata);
    data = mergeAIContent(data, aiContent);

    string content = substituteVariables(ballerinaReadmeTemplate(), data);

    string ballerinaDir = check utils:resolveBallerinaDir(connectorPath);
    string outputPath = ballerinaDir + "/README.md";

    string? parentPath = check file:parentPath(outputPath);
    if parentPath is string {
        check ensureDirectoryExists(parentPath);
    }
    check writeOutput(content, outputPath);
    utils:logVerbose(string `written: ${outputPath}`);
}

public function generateTestsReadme(string connectorPath) returns error? {
    ConnectorMetadata metadata = check analyzeConnector(connectorPath);
    map<string> aiContent = check generateTestsContent(metadata);

    TemplateData data = createTemplateData(metadata);
    data = mergeAIContent(data, aiContent);

    string content = substituteVariables(testsReadmeTemplate(), data);

    string ballerinaDir = check utils:resolveBallerinaDir(connectorPath);
    string outputPath = ballerinaDir + "/tests/README.md";

    string? parentPath = check file:parentPath(outputPath);
    if parentPath is string {
        check ensureDirectoryExists(parentPath);
    }
    check writeOutput(content, outputPath);
    utils:logVerbose(string `written: ${outputPath}`);
}

public function generateIndividualExampleReadmes(string connectorPath) returns error? {
    ConnectorMetadata metadata = check analyzeConnector(connectorPath);

    string examplesPath = connectorPath + "/examples";

    if !check file:test(examplesPath, file:EXISTS) {
        utils:logVerbose("no examples directory found — skipping individual example documentation");
        return;
    }

    file:MetaData[] examples = check file:readDir(examplesPath);
    int exampleCount = 0;
    int successCount = 0;

    foreach file:MetaData example in examples {
        if example.dir {
            string exampleDirName = extractDirectoryName(example.absPath);
            if exampleDirName.startsWith(".") {
                continue;
            }
            string exampleDirPath = examplesPath + "/" + exampleDirName;
            boolean hasMain = check file:test(exampleDirPath + "/main.bal", file:EXISTS);
            boolean hasBallerinaToml = check file:test(exampleDirPath + "/Ballerina.toml", file:EXISTS);
            if !hasMain || !hasBallerinaToml {
                continue;
            }

            error? result = generateSingleExampleReadme(examplesPath, example.absPath, exampleDirName, metadata);
            if result is error {
                utils:logWarn(string `failed to generate documentation for ${exampleDirName}: ${result.message()}`);
            } else {
                successCount += 1;
                utils:logVerbose(string `written: ${exampleDirPath}/${exampleDirName}.md`);
            }
            exampleCount += 1;
        }
    }

    if exampleCount > 0 {
        utils:logVerbose(string `generated ${successCount}/${exampleCount} individual example documents`);
    }
}

function generateSingleExampleReadme(string examplesPath, string examplePath, string exampleDirName,
        ConnectorMetadata metadata) returns error? {
    // Read all .bal files in the example directory
    ExampleData exampleData = check analyzeExampleDirectory(examplePath, exampleDirName);

    // Generate AI content for this specific example
    map<string> aiContent = check generateIndividualExampleContent(exampleData, metadata);

    // Create template data
    TemplateData data = createTemplateData(metadata);
    data = mergeAIContent(data, aiContent);

    // Add example-specific data
    data.CONNECTOR_NAME = metadata.connectorName;

    string content = substituteVariables(exampleSpecificTemplate(), data);

    string outputPath = exampleDocumentPath(examplesPath, exampleDirName);

    check writeOutput(content, outputPath);
}

function exampleDocumentPath(string examplesPath, string exampleName) returns string {
    return examplesPath + "/" + exampleName + "/" + exampleName + ".md";
}

function generateIndividualExampleContent(ExampleData exampleData, ConnectorMetadata connectorMetadata) returns map<string>|error {
    map<string> content = {};
    string prompt = createIndividualExamplePrompt(exampleData, connectorMetadata);
    string result = check utils:callAI(prompt);

    content["individual_readme"] = result;
    return content;
}

public function generateExamplesReadme(string connectorPath) returns error? {
    ConnectorMetadata metadata = check analyzeConnector(connectorPath);
    check retainDocumentedExamples(connectorPath, metadata);
    map<string> aiContent = check generateExamplesContent(metadata);

    TemplateData data = createTemplateData(metadata);
    data = mergeAIContent(data, aiContent);

    string content = substituteVariables(examplesReadmeTemplate(), data);

    string outputPath = connectorPath + "/examples/README.md";

    string? parentPath = check file:parentPath(outputPath);
    if parentPath is string {
        check ensureDirectoryExists(parentPath);
    }
    check writeOutput(content, outputPath);
    utils:logVerbose(string `written: ${outputPath}`);
}

public function generateMainReadme(string connectorPath) returns error? {
    ConnectorMetadata metadata = check analyzeConnector(connectorPath);
    map<string> aiContent = check generateMainContent(metadata);

    TemplateData data = createTemplateData(metadata);
    data = mergeAIContent(data, aiContent);

    string content = substituteVariables(mainReadmeTemplate(), data);

    string outputPath = connectorPath + "/README.md";

    string? parentPath = check file:parentPath(outputPath);
    if parentPath is string {
        check ensureDirectoryExists(parentPath);
    }
    check writeOutput(content, outputPath);
    utils:logVerbose(string `written: ${outputPath}`);
}

function generateBallerinaContent(ConnectorMetadata metadata, boolean linkExampleDocuments = false)
        returns map<string>|error {
    map<string> content = {};

    string overviewPrompt = createBallerinaOverviewPrompt(metadata);
    string overviewResult = check utils:callAI(overviewPrompt);
    content["overview"] = overviewResult;

    string setupPrompt = createBallerinaSetupPrompt(metadata);
    string setupResult = check utils:callAI(setupPrompt);
    content["setup"] = setupResult;

    string quickstartPrompt = createBallerinaQuickstartPrompt(metadata);
    string quickstartResult = check utils:callAI(quickstartPrompt);
    content["quickstart"] = quickstartResult;

    string examplesPrompt = createBallerinaExamplesPrompt(metadata, linkExampleDocuments);
    string examplesResult = check utils:callAI(examplesPrompt);
    content["examples"] = examplesResult;

    return content;
}

function generateTestsContent(ConnectorMetadata metadata) returns map<string>|error {
    map<string> content = {};
    string testsPrompt = createTestReadmePrompt(metadata);
    string testsResult = check utils:callAI(testsPrompt);
    content["testing_approach"] = testsResult;

    return content;
}

function generateExamplesContent(ConnectorMetadata metadata) returns map<string>|error {
    map<string> content = {};
    string mainExamplesPrompt = createMainExampleReadmePrompt(metadata);
    string mainExamplesResult = check utils:callAI(mainExamplesPrompt);
    content["main_examples_readme"] = mainExamplesResult;

    return content;
}

function generateMainContent(ConnectorMetadata metadata) returns map<string>|error {
    map<string> content = {};

    content["header_and_badges"] = createHeaderAndBadges(metadata);
    content["useful_links"] = createUsefulLinksSection(metadata);

    string overviewPrompt = createBallerinaOverviewPrompt(metadata);
    string overviewResult = check utils:callAI(overviewPrompt);
    content["overview"] = overviewResult;

    string setupPrompt = createBallerinaSetupPrompt(metadata);
    string setupResult = check utils:callAI(setupPrompt);
    content["setup"] = setupResult;

    string quickstartPrompt = createBallerinaQuickstartPrompt(metadata);
    string quickstartResult = check utils:callAI(quickstartPrompt);
    content["quickstart"] = quickstartResult;

    string examplesPrompt = createBallerinaExamplesPrompt(metadata);
    string examplesResult = check utils:callAI(examplesPrompt);
    content["examples"] = examplesResult;

    return content;
}

function retainDocumentedExamples(string connectorPath, ConnectorMetadata metadata) returns error? {
    string[] documentedExamples = [];
    foreach string exampleName in metadata.examples {
        string documentPath = exampleDocumentPath(connectorPath + "/examples", exampleName);
        if check file:test(documentPath, file:EXISTS) {
            documentedExamples.push(exampleName);
        }
    }
    metadata.examples = documentedExamples;
}

// Template processing functions.
// Every placeholder is always replaced — even when its value is empty — so that
// no literal {{PLACEHOLDER}} token can leak into a published README.
function substituteVariables(string template, TemplateData data) returns string {
    string result = template;

    result = simpleReplace(result, "{{CONNECTOR_NAME}}", data.CONNECTOR_NAME ?: "");
    result = simpleReplace(result, "{{VERSION}}", data.VERSION ?: "");
    result = simpleReplace(result, "{{DESCRIPTION}}", data.DESCRIPTION ?: "");
    result = simpleReplace(result, "{{AI_GENERATED_OVERVIEW}}", data.AI_GENERATED_OVERVIEW ?: "");
    result = simpleReplace(result, "{{AI_GENERATED_SETUP}}", data.AI_GENERATED_SETUP ?: "");
    result = simpleReplace(result, "{{AI_GENERATED_QUICKSTART}}", data.AI_GENERATED_QUICKSTART ?: "");
    result = simpleReplace(result, "{{AI_GENERATED_EXAMPLES}}", data.AI_GENERATED_EXAMPLES ?: "");
    result = simpleReplace(result, "{{AI_GENERATED_USAGE}}", data.AI_GENERATED_USAGE ?: "");
    result = simpleReplace(result, "{{AI_GENERATED_TESTING_APPROACH}}", data.AI_GENERATED_TESTING_APPROACH ?: "");
    result = simpleReplace(result, "{{AI_GENERATED_EXAMPLE_DESCRIPTIONS}}", data.AI_GENERATED_EXAMPLE_DESCRIPTIONS ?: "");
    result = simpleReplace(result, "{{AI_GENERATED_GETTING_STARTED}}", data.AI_GENERATED_GETTING_STARTED ?: "");
    result = simpleReplace(result, "{{AI_GENERATED_HEADER_AND_BADGES}}", data.AI_GENERATED_HEADER_AND_BADGES ?: "");
    result = simpleReplace(result, "{{AI_GENERATED_USEFUL_LINKS}}", data.AI_GENERATED_USEFUL_LINKS ?: "");
    result = simpleReplace(result, "{{AI_GENERATED_INDIVIDUAL_README}}", data.AI_GENERATED_INDIVIDUAL_README ?: "");
    result = simpleReplace(result, "{{AI_GENERATED_MAIN_EXAMPLES_README}}", data.AI_GENERATED_MAIN_EXAMPLES_README ?: "");

    return result;
}

function createTemplateData(ConnectorMetadata metadata) returns TemplateData {
    return {
        CONNECTOR_NAME: metadata.connectorName,
        VERSION: metadata.version
    };
}

public function generateKeywords(string connectorPath) returns error? {

    ConnectorMetadata metadata = check analyzeConnector(connectorPath);
    string displayName = formatConnectorDisplayName(metadata.connectorName);
    if displayName.length() == 0 {
        return error("Ballerina.toml [package].name is required to generate the Name keyword");
    }

    ai:Prompt prompt = createKeywordGenerationPrompt(metadata);
    ai:ModelProvider model = check utils:getAIModel();
    ConnectorKeywords kw = check model->generate(prompt);

    string[] keywords = [displayName, kw.cost, kw.vendor, kw.area, "Type/Connector"];
    check writeKeywordsToToml(connectorPath, keywords);

    utils:logInfo(string `✓ keywords written: ${keywords.toString()}`);
}

function writeKeywordsToToml(string connectorPath, string[] keywords) returns error? {
    string tomlPath = connectorPath + "/Ballerina.toml";
    if !check file:test(tomlPath, file:EXISTS) {
        tomlPath = connectorPath + "/ballerina/Ballerina.toml";
    }
    if !check file:test(tomlPath, file:EXISTS) {
        utils:logWarn("writeKeywordsToToml: Ballerina.toml not found — skipping");
        return;
    }

    string content = check io:fileReadString(tomlPath);

    // Serialise the keywords array to TOML format
    string[] quoted = from string kw in keywords select string `"${kw}"`;
    string keywordsLine = string `keywords = [${strings:'join(", ", ...quoted)}]`;

    string[] lines = regexp:split(re `\n`, content);

    // Pass 1: replace an existing keywords key inside [package] only.
    boolean replaced = false;
    boolean inPackage = false;
    boolean skipping = false;
    string[] afterReplace = [];
    foreach string line in lines {
        string trimmed = strings:trim(line);
        if trimmed.startsWith("[") && !trimmed.startsWith("[[") {
            inPackage = trimmed == "[package]";
        }
        if skipping {
            if strings:includes(trimmed, "]") {
                skipping = false;
            }
            continue;
        }
        if inPackage && trimmed.startsWith("keywords") && strings:includes(trimmed, "=") {
            afterReplace.push(keywordsLine);
            replaced = true;
            int? eqIdx = trimmed.indexOf("=");
            if eqIdx is int {
                string valueHalf = strings:trim(trimmed.substring(eqIdx + 1));
                int? openBracket = valueHalf.indexOf("[");
                int? closeBracket = valueHalf.lastIndexOf("]");
                if openBracket is int && !(closeBracket is int && closeBracket > openBracket) {
                    skipping = true;
                }
            }
        } else {
            afterReplace.push(line);
        }
    }

    string updated;
    if replaced {
        updated = strings:'join("\n", ...afterReplace);
    } else {
        // Pass 2: insert once after the version line inside [package] only.
        // Platform dependency tables also contain version = lines; inserting after
        // each of those would produce duplicate keys and invalid TOML.
        boolean inPkg = false;
        boolean inserted = false;
        string[] newLines = [];
        foreach string line in lines {
            string trimmed = strings:trim(line);
            if trimmed.startsWith("[") {
                inPkg = trimmed == "[package]";
            }
            newLines.push(line);
            if inPkg && !inserted && trimmed.startsWith("version") {
                newLines.push(keywordsLine);
                inserted = true;
            }
        }
        updated = strings:'join("\n", ...newLines);
    }

    check io:fileWriteString(tomlPath, updated);
}

function mergeAIContent(TemplateData baseData, map<string> aiContent) returns TemplateData {
    TemplateData merged = baseData.clone();

    foreach var [key, value] in aiContent.entries() {
        match key {
            "overview" => {
                merged.AI_GENERATED_OVERVIEW = value;
            }
            "setup" => {
                merged.AI_GENERATED_SETUP = value;
            }
            "quickstart" => {
                merged.AI_GENERATED_QUICKSTART = value;
            }
            "examples" => {
                merged.AI_GENERATED_EXAMPLES = value;
            }
            "usage" => {
                merged.AI_GENERATED_USAGE = value;
            }
            "testing_approach" => {
                merged.AI_GENERATED_TESTING_APPROACH = value;
            }
            "test_scenarios" => {
                merged.AI_GENERATED_TEST_SCENARIOS = value;
            }
            "example_descriptions" => {
                merged.AI_GENERATED_EXAMPLE_DESCRIPTIONS = value;
            }
            "getting_started" => {
                merged.AI_GENERATED_GETTING_STARTED = value;
            }
            "header_and_badges" => {
                merged.AI_GENERATED_HEADER_AND_BADGES = value;
            }
            "useful_links" => {
                merged.AI_GENERATED_USEFUL_LINKS = value;
            }
            "individual_readme" => {
                merged.AI_GENERATED_INDIVIDUAL_README = value;
            }
            "main_examples_readme" => {
                merged.AI_GENERATED_MAIN_EXAMPLES_README = value;
            }
        }
    }

    return merged;
}
