// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/os;
import ballerina/lang.runtime;

# Checks whether the code-server binary is available on PATH.
# Runs `code-server --version`; a zero exit code means it is installed.
# + return - true if code-server is installed, false otherwise
public function checkCodeServerInstalled() returns boolean {
    os:Process|error proc = os:exec({
        value: "code-server",
        arguments: ["--version"]
    });
    if proc is error {
        return false;
    }
    int|error exitCode = proc.waitForExit();
    return exitCode is int && exitCode == 0;
}

# Installs code-server using the official installer script:
#   curl -fsSL https://code-server.dev/install.sh | sh
# The pipe is a shell construct, so this is run via `sh -c`.
# + return - an error if the installer script fails
public function installCodeServer() returns error? {
    os:Process|error proc = os:exec({
        value: "sh",
        arguments: ["-c", "curl -fsSL https://code-server.dev/install.sh | sh"]
    });
    if proc is error {
        return error("Failed to launch code-server installer: " + proc.message());
    }
    int|error exitCode = proc.waitForExit();
    if exitCode is error {
        return error("code-server installer script failed: " + exitCode.message());
    }
    if exitCode != 0 {
        return error("code-server installer script failed with exit code: " + exitCode.toString());
    }
}

# Checks whether the Claude Code CLI ('claude') is available on PATH.
# Runs `claude --version`; a zero exit code means it is installed.
# + return - true if Claude Code CLI is installed, false otherwise
public function checkClaudeCodeInstalled() returns boolean {
    os:Process|error proc = os:exec({
        value: "claude",
        arguments: ["--version"]
    });
    if proc is error {
        return false;
    }
    int|error exitCode = proc.waitForExit();
    return exitCode is int && exitCode == 0;
}

# Checks whether code-server is reachable on the given port using curl.
# + port - the port to check
# + return - true if code-server is running, false otherwise
public function checkCodeServerRunning(int port) returns boolean {
    os:Process|error proc = os:exec({
        value: "curl",
        arguments: ["-s", "-L", "-o", "/dev/null", "-w", "%{http_code}",
                    "--max-time", "3", "http://localhost:" + port.toString()]
    });
    if proc is error {
        return false;
    }
    int|error exitCode = proc.waitForExit();
    return exitCode is int && exitCode == 0;
}

# Checks whether a VS Code extension is installed in code-server.
# Pipes `code-server --list-extensions` through grep via `sh -c`.
# + extensionId - the extension identifier to look for (e.g. "wso2.wso2-integrator")
# + return - true if the extension is installed, false otherwise
public function checkExtensionInstalled(string extensionId) returns boolean {
    os:Process|error proc = os:exec({
        value: "sh",
        arguments: ["-c", "code-server --list-extensions | grep -q '" + extensionId + "'"]
    });
    if proc is error {
        return false;
    }
    int|error exitCode = proc.waitForExit();
    return exitCode is int && exitCode == 0;
}

# Ensures a VS Code extension is installed in code-server.
# First attempts to install from the Open VSX marketplace; if that fails,
# falls back to installing from a local .vsix file.
# + extensionId - the extension identifier (e.g. "wso2.wso2-integrator")
# + vsixFallbackPath - absolute path to the .vsix file to use as fallback
# + return - an error if both install attempts fail
public function ensureExtensionInstalled(string extensionId, string vsixFallbackPath) returns error? {
    // Attempt 1: marketplace install
    log("\t[INFO] Trying marketplace install for: " + extensionId);
    os:Process|error marketProc = os:exec({
        value: "code-server",
        arguments: ["--install-extension", extensionId]
    });
    if marketProc is os:Process {
        int|error marketExit = marketProc.waitForExit();
        if marketExit is int && marketExit == 0 {
            return;
        }
    }
    log("\t[WARN] Marketplace install failed — trying local VSIX: " + vsixFallbackPath);

    // Attempt 2: fallback to local .vsix
    os:Process|error vsixProc = os:exec({
        value: "code-server",
        arguments: ["--install-extension", vsixFallbackPath]
    });
    if vsixProc is error {
        return error("Failed to launch extension install from VSIX: " + vsixProc.message());
    }
    int|error vsixExit = vsixProc.waitForExit();
    if vsixExit is error {
        return error("Extension install from VSIX process error: " + vsixExit.message());
    }
    if vsixExit != 0 {
        return error("Extension install from VSIX failed with exit code: " + vsixExit.toString());
    }
}

# Starts code-server on the given port and waits until it is ready.
# + port - the port to bind code-server to
# + return - an error if code-server fails to start within the timeout
public function startCodeServer(int port) returns error? {
    os:Process|error proc = os:exec({
        value: "code-server",
        arguments: ["--auth", "none", "--bind-addr", "0.0.0.0:" + port.toString()]
    });
    if proc is error {
        return error("Failed to start code-server: " + proc.message());
    }
    // Wait up to 15 seconds for code-server to become ready
    int attempts = 0;
    while attempts < 15 {
        runtime:sleep(1);
        if checkCodeServerRunning(port) {
            return;
        }
        attempts += 1;
    }
    return error("Code-server did not become ready within 15 seconds on port " + port.toString());
}
