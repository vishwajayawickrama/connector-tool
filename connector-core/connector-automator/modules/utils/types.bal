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

# result of executing a `bal` command
public type CommandResult record {|
    # The command that was executed
    string command;
    # Whether the command executed successfully
    boolean success;
    # Exit code returned by the command
    int exitCode;
    # Standard output from the command
    string stdout;
    # Standard error output from the command
    string stderr;
    # Parsed compilation errors from the output
    CmdCompilationError[] compilationErrors;
    # Execution time 
    decimal executionTime;
|};

# Compilation error from a `bal build` output

public type CmdCompilationError record {|
    # name of the file where error occured
    string fileName;
    # Line number of the error
    int line;
    # Column number of the error
    int column;
    # Error message description
    string message;
    # Type of error (ERROR, WARNING)
    string errorType;
    # file path
    string filePath?;
|};

public type CommandExecutorError distinct error;

# Logging verbosity level for the connector generation pipeline.
# quiet  — errors only (stderr)
# normal — step banners + key outcomes + warnings (stderr)
# verbose — full diagnostics including subprocess output (stderr)
public type LogLevel "quiet"|"normal"|"verbose";
