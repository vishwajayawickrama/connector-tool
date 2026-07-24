// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
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
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/file;
import ballerina/io;
import ballerina/lang.regexp;
import ballerina/os;

import wso2/connector_automator.utils;

public type SourceFileSnapshot readonly & record {|
    boolean exists;
    string content;
|};

public type ClientSourceBaseline readonly & record {|
    SourceFileSnapshot clientSnapshot;
    SourceFileSnapshot typesSnapshot;
    boolean hasMeaningfulClient;
|};

type NativeDiffResult record {|
    int exitCode;
    string stdout;
    string stderr;
|};

function readSourceSnapshot(string sourcePath) returns SourceFileSnapshot|error {
    boolean|file:Error exists = file:test(sourcePath, file:EXISTS);
    if exists is file:Error {
        return error(string `could not inspect ${sourcePath}: ${exists.message()}`);
    }
    if !exists {
        return {exists: false, content: ""};
    }

    string|io:Error content = io:fileReadString(sourcePath);
    if content is io:Error {
        return error(string `could not read ${sourcePath}: ${content.message()}`);
    }
    return {exists: true, content};
}

// A missing, empty, or comment-only client is not a usable version-analysis baseline.
function hasMeaningfulBallerinaSource(string content) returns boolean {
    int offset = 0;
    while offset < content.length() {
        string remaining = content.substring(offset);
        string current = remaining.substring(0, 1);
        if current.trim().length() == 0 {
            offset += 1;
        } else if remaining.startsWith("//") || remaining.startsWith("#") {
            int? lineEnd = remaining.indexOf("\n");
            if lineEnd is () {
                return false;
            }
            offset += lineEnd + 1;
        } else if remaining.startsWith("/*") {
            int? commentEnd = remaining.indexOf("*/");
            if commentEnd is () {
                return false;
            }
            offset += commentEnd + 2;
        } else {
            return true;
        }
    }
    return false;
}

public function captureClientSourceBaseline(string connectorPath) returns ClientSourceBaseline|error {
    string ballerinaDir = check utils:resolveBallerinaDir(connectorPath);
    SourceFileSnapshot clientSnapshot = check readSourceSnapshot(ballerinaDir + "/client.bal");
    SourceFileSnapshot typesSnapshot = check readSourceSnapshot(ballerinaDir + "/types.bal");
    return {
        clientSnapshot,
        typesSnapshot,
        hasMeaningfulClient: clientSnapshot.exists && hasMeaningfulBallerinaSource(clientSnapshot.content)
    };
}

function normalizeLineEndings(string content) returns string {
    return regexp:replaceAll(re `\r\n?`, content, "\n");
}

function executeNativeDiff(string oldPath, string newPath) returns NativeDiffResult|error {
    boolean windows = os:getEnv("OS").toLowerAscii() == "windows_nt";
    os:Command command = windows
        ? {value: "fc.exe", arguments: ["/L", "/N", oldPath, newPath]}
        : {value: "diff", arguments: ["-u", oldPath, newPath]};

    os:Process process = check os:exec(command);
    byte[] stdoutBytes = check process.output();
    byte[] stderrBytes = check process.output(io:stderr);
    int exitCode = check process.waitForExit();
    return {
        exitCode,
        stdout: check string:fromBytes(stdoutBytes),
        stderr: check string:fromBytes(stderrBytes)
    };
}

function compareSource(string fileName, string oldContent, string newContent) returns string|error {
    string normalizedOld = normalizeLineEndings(oldContent);
    string normalizedNew = normalizeLineEndings(newContent);
    if normalizedOld == normalizedNew {
        return "";
    }

    string tempDir = check file:createTempDir(prefix = "connector_automator_diff_");
    string oldPath = tempDir + "/old_" + fileName;
    string newPath = tempDir + "/new_" + fileName;

    error? writeOld = io:fileWriteString(oldPath, normalizedOld);
    if writeOld is error {
        do { check file:remove(tempDir, file:RECURSIVE); } on fail { }
        return error(string `could not create ${fileName} baseline: ${writeOld.message()}`);
    }
    error? writeNew = io:fileWriteString(newPath, normalizedNew);
    if writeNew is error {
        do { check file:remove(tempDir, file:RECURSIVE); } on fail { }
        return error(string `could not create generated ${fileName} snapshot: ${writeNew.message()}`);
    }

    NativeDiffResult|error diffResult = executeNativeDiff(oldPath, newPath);
    do { check file:remove(tempDir, file:RECURSIVE); } on fail error cleanupError {
        utils:logVerbose(string `could not remove version-analysis files: ${cleanupError.message()}`);
    }
    if diffResult is error {
        return error(string `could not compare ${fileName}: ${diffResult.message()}`);
    }
    if diffResult.exitCode == 0 {
        return "";
    }
    if diffResult.exitCode != 1 {
        string diagnostics = diffResult.stderr.trim();
        return error(string `could not compare ${fileName} (exit ${diffResult.exitCode})${diagnostics.length() > 0 ? ": " + diagnostics : ""}`);
    }
    if diffResult.stdout.trim().length() == 0 {
        return error(string `comparison reported changes for ${fileName} without producing output`);
    }
    return string `Changes in ${fileName}:\n${diffResult.stdout.trim()}`;
}

function readCurrentSource(string sourcePath) returns string|error {
    SourceFileSnapshot snapshot = check readSourceSnapshot(sourcePath);
    return snapshot.content;
}

function readPackageVersion(string ballerinaDir) returns string? {
    string|io:Error content = io:fileReadString(ballerinaDir + "/Ballerina.toml");
    if content is io:Error {
        return ();
    }
    boolean inPackage = false;
    foreach string line in regexp:split(re `\n`, content) {
        string trimmed = line.trim();
        if trimmed.startsWith("[") {
            inPackage = trimmed == "[package]";
        } else if inPackage && trimmed.startsWith("version") {
            string[] parts = regexp:split(re `=`, trimmed);
            if parts.length() >= 2 {
                return regexp:replaceAll(re `^\s*"|"\s*$`, parts[1].trim(), "");
            }
        }
    }
    return ();
}

function recommendedVersion(string currentVersion, string changeType) returns string? {
    string[] parts = regexp:split(re `\.`, currentVersion);
    if parts.length() != 3 {
        return ();
    }
    int|error major = int:fromString(parts[0]);
    int|error minor = int:fromString(parts[1]);
    int|error patch = int:fromString(parts[2]);
    if major is error || minor is error || patch is error {
        return ();
    }
    match changeType {
        "MAJOR" => { return string `${major + 1}.0.0`; }
        "MINOR" => { return string `${major}.${minor + 1}.0`; }
        "PATCH" => { return string `${major}.${minor}.${patch + 1}`; }
        _ => { return (); }
    }
}

public function executeVersionSummary(string connectorPath, ClientSourceBaseline baseline) returns error? {
    if !baseline.hasMeaningfulClient {
        utils:logVerbose("version analysis skipped: no meaningful previous client.bal");
        return;
    }

    string ballerinaDir = check utils:resolveBallerinaDir(connectorPath);
    string clientDiff = check compareSource(
        "client.bal", baseline.clientSnapshot.content, check readCurrentSource(ballerinaDir + "/client.bal"));
    string typesDiff = check compareSource(
        "types.bal", baseline.typesSnapshot.content, check readCurrentSource(ballerinaDir + "/types.bal"));

    string[] sourceDiffs = [];
    if clientDiff.length() > 0 {
        sourceDiffs.push(clientDiff);
    }
    if typesDiff.length() > 0 {
        sourceDiffs.push(typesDiff);
    }
    string sourceDiff = string:'join("\n\n", ...sourceDiffs).trim();
    if sourceDiff.length() == 0 {
        printNoVersionChangeAnalysis();
        return;
    }

    AnalysisResult analysis = check analyzeVersionChange(sourceDiff);
    string recommended = "";
    string? currentVersion = readPackageVersion(ballerinaDir);
    if currentVersion is string {
        recommended = recommendedVersion(currentVersion, analysis.changeType) ?: "";
    }
    printVersionChangeAnalysis(analysis, recommended);
}
