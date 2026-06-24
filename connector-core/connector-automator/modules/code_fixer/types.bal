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

// Simple types for the fixer module
public type FixResult record {|
    boolean success;
    int errorsFixed;
    int errorsRemaining;
    int ballerinaErrorsFixed = 0;
    int javaErrorsFixed = 0;
    int ballerinaErrorsRemaining = 0;
    int javaErrorsRemaining = 0;
    string[] appliedFixes;
    string[] remainingFixes;
|};

public type CompilationError record {|
    string filePath;
    int line;
    int column;
    string message;
    string severity;
    string language = "ballerina";
    string sourceTool = "bal";
    string code?;
|};

public type FixRequest record {|
    string projectPath;
    string filePath;
    string code;
    CompilationError[] errors;
    string language = "ballerina";
|};

public type FixResponse record {|
    boolean success;
    string fixedCode;
    string explanation;
|};

// Track fix attempts for a specific file to prevent oscillation
public type FixAttempt record {|
    int iteration;
    string[] errorMessages;        // Errors that were present
    string appliedFix;             // Brief description of what was attempted
|};

// History of fix attempts per file
public type FileFixHistory record {|
    string filePath;
    FixAttempt[] attempts;
|};

public type BallerinaFixerError error;

type JavaEditOperation record {|
    int startLine;
    int endLine;
    string[] replacement;
|};
