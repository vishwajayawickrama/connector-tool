import ballerina/io;

// Active log level — set once at workflow entry via initLogLevel().
// Defaults to "normal" until explicitly initialized.
LogLevel _activeLogLevel = "normal";

# Initialize the log level for the current workflow run.
# Must be called at the entry point of every workflow before any logging or AI calls.
public function initLogLevel(LogLevel level) {
    _activeLogLevel = level;
}

# Return the currently active log level.
# Use this when you need to branch on level outside a log function (e.g. boolean quietMode conversion).
public function getLogLevel() returns LogLevel {
    return _activeLogLevel;
}

# Print a numbered step banner. Shown in normal and verbose modes.
public function logStep(int step, int total, string name) {
    if _activeLogLevel != "quiet" {
        io:fprintln(io:stderr, string `${"\n"}[${step}/${total}] ${name}`);
    }
}

# Print an informational message. Shown in normal and verbose modes.
public function logInfo(string msg) {
    if _activeLogLevel != "quiet" {
        io:fprintln(io:stderr, string `  ${msg}`);
    }
}

# Print a detail message. Shown in verbose mode only.
public function logVerbose(string msg) {
    if _activeLogLevel == "verbose" {
        io:fprintln(io:stderr, string `  ${msg}`);
    }
}

# Print a warning. Shown in normal and verbose modes.
public function logWarn(string msg) {
    if _activeLogLevel != "quiet" {
        io:fprintln(io:stderr, string `  warning: ${msg}`);
    }
}

# Print an error. Always shown regardless of log level.
public function logError(string msg) {
    io:fprintln(io:stderr, string `error: ${msg}`);
}

# Print a pipeline completion summary. Always shown.
public function logCompletion(string outputDir) {
    io:fprintln(io:stderr, string `${""}${"\n"}Connector generated at: ${outputDir}`);
}
