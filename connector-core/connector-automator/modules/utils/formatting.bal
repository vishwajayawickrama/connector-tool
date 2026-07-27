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

import ballerina/file;
import ballerina/io;
import ballerina/lang.regexp;

public function repeat() {
    io:fprintln(io:stderr, createSeparator("=", 80));
}

public function createSeparator(string char, int count) returns string {
    string sep = "";
    int i = 0;
    while i < count {
        sep += char;
        i += 1;
    }
    return sep;
}

# Returns an invocation-relative path for user-facing output.
# Operational paths must continue to use the original value.
#
# + path - Absolute or relative filesystem path
# + return - Invocation-relative path when it is within the current directory; otherwise, the original path
public function getDisplayPath(string path) returns string {
    if path.length() == 0 {
        return path;
    }

    string invocationDir = file:getCurrentDir();
    if invocationDir.length() == 0 {
        return path;
    }

    string normalizedPath = regexp:replaceAll(re `\\`, path, "/");
    string normalizedInvocationDir = regexp:replaceAll(re `\\`, invocationDir, "/");
    boolean isAbsolute = normalizedPath.startsWith("/") ||
        regexp:isFullMatch(re `^[A-Za-z]:/.*`, normalizedPath);
    if !isAbsolute {
        return path;
    }

    while normalizedInvocationDir.length() > 1 && normalizedInvocationDir.endsWith("/") &&
        !regexp:isFullMatch(re `^[A-Za-z]:/$`, normalizedInvocationDir) {
        normalizedInvocationDir = normalizedInvocationDir.substring(0, normalizedInvocationDir.length() - 1);
    }

    if normalizedPath == normalizedInvocationDir {
        return ".";
    }
    if normalizedInvocationDir == "/" ||
        regexp:isFullMatch(re `^[A-Za-z]:/$`, normalizedInvocationDir) {
        return path;
    }

    string invocationPrefix = normalizedInvocationDir + "/";
    if normalizedPath.startsWith(invocationPrefix) {
        return normalizedPath.substring(invocationPrefix.length());
    }
    return path;
}
