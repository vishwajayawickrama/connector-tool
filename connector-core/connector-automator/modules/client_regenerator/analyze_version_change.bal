// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/ai;
import ballerina/io;
import ballerina/lang.value;
import ballerina/os;
import ballerina/lang.regexp;
import ballerinax/ai.anthropic;

import wso2/connector_automator.utils;

const string ANTHROPIC_API_KEY_ENV = "ANTHROPIC_API_KEY";

const int MAX_RETRIES = 4;
const decimal RETRY_INITIAL_DELAY = 10.0d; // seconds
const float BACK_OFF_FACTOR = 2.0;
const decimal MAX_WAIT_INTERVAL = 80.0d; // 10 → 20 → 40 → 80

// Diffs larger than this threshold are sent in multiple turns to stay within
// the OS argument-length limit and the model's single-message context budget.
const int CHUNK_SIZE = 50000;
// Maximum chunks sent in a multi-turn conversation. Beyond this the accumulated
// context overflows the model's window and causes mid-session API errors.
// 10 chunks = 500 KB — enough to capture all API-surface changes in practice.
const int MAX_CHUNKS = 10;

/// Structured semantic-version analysis returned for generated source changes.
///
/// `changeType` is `MAJOR`, `MINOR`, or `PATCH`; `confidence` is `HIGH`,
/// `MEDIUM`, or `LOW`. The arrays contain concrete classified changes and
/// `summary` contains a concise explanation.
public type AnalysisResult record {|
    string changeType;
    string[] breakingChanges;
    string[] newFeatures;
    string[] bugFixes;
    string summary;
    string confidence;
|};

const string VERSION_RULES = string `RULES FOR VERSION CLASSIFICATION:
- MAJOR: Breaking changes (removed/renamed methods, removed/renamed types, changed method signatures, changed field types, removed fields)
- MINOR: Backward-compatible additions (new methods, new types, new optional fields, new fields with default values)
- PATCH: Documentation changes, internal refactoring, bug fixes with no API surface changes`;

const string JSON_SCHEMA = string `{
  "changeType": "MAJOR|MINOR|PATCH",
  "breakingChanges": ["list specific breaking changes"],
  "newFeatures": ["list new features/additions"],
  "bugFixes": ["list bug fixes or improvements"],
  "summary": "concise summary of changes",
  "confidence": "HIGH|MEDIUM|LOW (your confidence in the classification based on the clarity of the diff)"
}`;

function buildModel() returns ai:ModelProvider|error {
    string apiKey = os:getEnv(ANTHROPIC_API_KEY_ENV);
    if apiKey == "" {
        return error(string `${ANTHROPIC_API_KEY_ENV} environment variable is not set`);
    }
    return check new anthropic:ModelProvider(
        apiKey,
        anthropic:CLAUDE_SONNET_4_6,
        maxTokens = 4096,
        retryConfig = {
            count: MAX_RETRIES,
            interval: RETRY_INITIAL_DELAY,
            backOffFactor: BACK_OFF_FACTOR,
            maxWaitInterval: MAX_WAIT_INTERVAL
        }
    );
}

function parseAnalysisResponse(string raw) returns AnalysisResult|error {
    string cleaned = regexp:replaceAll(re `\u{60}\u{60}\u{60}json|\u{60}\u{60}\u{60}`, raw.trim(), "");
    return check value:fromJsonStringWithType(cleaned.trim());
}

function analyzeInSingleTurn(ai:ModelProvider model, string sourceDiff) returns AnalysisResult|error {
    string prompt = string `You are analyzing generated source changes for a Ballerina connector to determine the semantic version change needed. The input contains filename-labelled sections produced by either Unix diff or Windows fc.

SOURCE CHANGES:
${sourceDiff}

${VERSION_RULES}

Analyze the diff and respond with ONLY a JSON object (no markdown, no explanation):
${JSON_SCHEMA}`;

    ai:ChatMessage[] messages = [{role: "user", content: prompt}];
    ai:ChatAssistantMessage response = check model->chat(messages);

    string? content = response.content;
    if content is () {
        return error("Empty response from Anthropic API");
    }
    return parseAnalysisResponse(content);
}

function analyzeInChunks(ai:ModelProvider model, string sourceDiff) returns AnalysisResult|error {
    int totalChunks = (sourceDiff.length() + CHUNK_SIZE - 1) / CHUNK_SIZE;
    int chunksToSend = totalChunks > MAX_CHUNKS ? MAX_CHUNKS : totalChunks;
    boolean truncated = totalChunks > MAX_CHUNKS;

    if truncated {
        utils:logWarn(string `diff has ${totalChunks} chunks — capping at ${MAX_CHUNKS} to stay within model context limit (${MAX_CHUNKS * CHUNK_SIZE / 1000}KB of ${sourceDiff.length() / 1000}KB analysed)`);
    } else {
        utils:logInfo(string `diff too large for single turn — splitting into ${chunksToSend} chunks`);
    }

    ai:ChatMessage[] messages = [];

    string truncationNote = truncated
        ? string ` NOTE: the source changes are very large; you will receive only the first ${chunksToSend} of ${totalChunks} parts (~${MAX_CHUNKS * CHUNK_SIZE / 1000}KB of ~${sourceDiff.length() / 1000}KB). Focus on API-surface changes visible in the portion you receive.`
        : "";

    string intro = string `I will send you large generated source changes for a Ballerina connector in ${chunksToSend} parts because of their size.${truncationNote} The input may use Unix diff or Windows fc format. Please wait until you have received all parts before analysing. After each part simply acknowledge with "Received part X/${chunksToSend}." and nothing else.`;
    messages.push({role: "user", content: intro});

    ai:ChatAssistantMessage introAck = check model->chat(messages);
    messages.push({role: "assistant", content: introAck.content ?: ""});

    // Send only up to MAX_CHUNKS chunks
    foreach int i in 0 ..< chunksToSend {
        int startIdx = i * CHUNK_SIZE;
        int endIdx = startIdx + CHUNK_SIZE;
        int safeEnd = endIdx < sourceDiff.length() ? endIdx : sourceDiff.length();
        string chunk = sourceDiff.substring(startIdx, safeEnd);

        utils:logVerbose(string `sending chunk ${i + 1}/${chunksToSend} (${chunk.length()} chars)`);

        messages.push({role: "user", content: string `Part ${i + 1}/${chunksToSend}:\n\n${chunk}`});
        ai:ChatAssistantMessage chunkAck = check model->chat(messages);
        messages.push({role: "assistant", content: chunkAck.content ?: ""});
    }

    string truncationWarning = truncated
        ? string `\n\nIMPORTANT: You only received the first ~${MAX_CHUNKS * CHUNK_SIZE / 1000}KB of ~${sourceDiff.length() / 1000}KB of source changes. Base your classification on what you saw; set confidence to LOW if you cannot be certain.`
        : "";

    string analysisRequest = string `You have received all ${chunksToSend} parts of the generated source changes.${truncationWarning}

${VERSION_RULES}

Analyze the complete diff and respond with ONLY a JSON object (no markdown, no explanation):
${JSON_SCHEMA}`;

    messages.push({role: "user", content: analysisRequest});
    ai:ChatAssistantMessage response = check model->chat(messages);

    string? content = response.content;
    if content is () {
        return error("Empty response from Anthropic API after chunked delivery");
    }
    return parseAnalysisResponse(content);
}

/// Analyzes a client/types source diff and classifies the required version bump.
///
/// Empty input, missing AI configuration, failed model calls, and invalid model
/// responses are returned as errors.
///
/// + sourceDiff - Filename-labelled source diff to classify
/// + return - Structured change classification or an analysis error
public function analyzeVersionChange(string sourceDiff) returns AnalysisResult|error {
    if sourceDiff.trim().length() == 0 {
        return error("Source diff is empty");
    }
    ai:ModelProvider model = check buildModel();

    if sourceDiff.length() <= CHUNK_SIZE {
        return analyzeInSingleTurn(model, sourceDiff);
    }
    return analyzeInChunks(model, sourceDiff);
}

function formatVersionChangeAnalysis(AnalysisResult analysis, string recommendedVersion = "") returns string {
    string recommendedVersionLine = recommendedVersion.length() > 0 ? string `Recommended Version: ${recommendedVersion}
` : "";
    string report = string `Version change analysis

Version Bump: ${analysis.changeType}
${recommendedVersionLine}Confidence:   ${analysis.confidence}

Summary:
${analysis.summary}`;

    return report;
}

function formatNoVersionChangeAnalysis() returns string {
    return string `Version Bump: NONE
No client/types changes; no version bump required`;
}

/// Prints a human-readable version analysis to the configured summary output.
///
/// + analysis - Analysis result to report
/// + recommendedVersion - Optional version calculated from the package version
public function printVersionChangeAnalysis(AnalysisResult analysis, string recommendedVersion = "") {
    utils:printOutput(formatVersionChangeAnalysis(analysis, recommendedVersion));
}

function printNoVersionChangeAnalysis() {
    utils:printOutput(formatNoVersionChangeAnalysis());
}

/// Reads a diff file, analyzes it, prints the result, and writes analysis_result.json.
///
/// The file path avoids passing large diffs as shell arguments. File-read,
/// analysis, and output-write failures are returned to the caller.
///
/// + diffFilePath - Path to the source diff file
/// + return - An error when reading, analyzing, or writing the result fails
public function main(string diffFilePath) returns error? {
    utils:logInfo(string `reading diff from file: ${diffFilePath}`);
    string sourceDiffContent = check io:fileReadString(diffFilePath);

    utils:logInfo("analyzing source diff...");
    utils:logVerbose(string `diff size: ${sourceDiffContent.length()} chars`);

    if sourceDiffContent.length() == 0 {
        return error("Source diff file is empty");
    }

    AnalysisResult analysis = check analyzeVersionChange(sourceDiffContent);
    printVersionChangeAnalysis(analysis);

    json resultJson = check analysis.cloneWithType(json);
    check io:fileWriteJson("analysis_result.json", resultJson);
    utils:logInfo("saved to: analysis_result.json");
}
