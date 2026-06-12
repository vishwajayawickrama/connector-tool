import ballerina/io;

# Print a numbered step banner. Shown in normal and verbose modes.
public function logStep(int step, int total, string name, LogLevel level) {
    if level != "quiet" {
        io:fprintln(io:stderr, string `${"\n"}[${step}/${total}] ${name}`);
    }
}

# Print an informational message. Shown in normal and verbose modes.
public function logInfo(string msg, LogLevel level) {
    if level != "quiet" {
        io:fprintln(io:stderr, string `  ${msg}`);
    }
}

# Print a detail message. Shown in verbose mode only.
public function logVerbose(string msg, LogLevel level) {
    if level == "verbose" {
        io:fprintln(io:stderr, string `  ${msg}`);
    }
}

# Print a warning. Shown in normal and verbose modes.
public function logWarn(string msg, LogLevel level) {
    if level != "quiet" {
        io:fprintln(io:stderr, string `  warning: ${msg}`);
    }
}

# Print an error. Always shown regardless of log level.
public function logError(string msg) {
    io:fprintln(io:stderr, string `error: ${msg}`);
}

# Print a pipeline completion summary. Always shown, including quiet mode.
public function logCompletion(string outputDir, LogLevel level) {
    io:fprintln(io:stderr, string `${""}${"\n"}Connector generated at: ${outputDir}`);
}
