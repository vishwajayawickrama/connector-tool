import ballerina/io;

// Active log level — set once at workflow entry via initLogLevel().
// Defaults to "normal" until explicitly initialized.
LogLevel _activeLogLevel = "normal";

# Initialize the log level for the current workflow run.
# Must be called at the entry point of every workflow before any logging or AI calls.
# + level - The log level to activate: "quiet", "normal", or "verbose"
public function initLogLevel(LogLevel level) {
    _activeLogLevel = level;
}

# Return the currently active log level.
# Use this when you need to branch on level outside a log function (e.g. boolean quietMode conversion).
# + return - The currently active LogLevel
public function getLogLevel() returns LogLevel {
    return _activeLogLevel;
}

# Print a numbered step banner. Shown in normal and verbose modes.
# + step - Current step number
# + total - Total number of steps in the workflow
# + name - Display name of this step
public function logStep(int step, int total, string name) {
    if _activeLogLevel != "quiet" {
        io:fprintln(io:stderr, string `${"\n"}[${step}/${total}] ${name}`);
    }
}

# Print an informational message. Shown in normal and verbose modes.
# + msg - Message to print
public function logInfo(string msg) {
    if _activeLogLevel != "quiet" {
        io:fprintln(io:stderr, string `  ${msg}`);
    }
}

# Print a detail message. Shown in verbose mode only.
# + msg - Message to print
public function logVerbose(string msg) {
    if _activeLogLevel == "verbose" {
        io:fprintln(io:stderr, string `  ${msg}`);
    }
}

# Print a warning. Shown in normal and verbose modes.
# + msg - Warning message to print
public function logWarn(string msg) {
    if _activeLogLevel != "quiet" {
        io:fprintln(io:stderr, string `  warning: ${msg}`);
    }
}

# Print an error. Always shown regardless of log level.
# + msg - Error message to print
public function logError(string msg) {
    io:fprintln(io:stderr, string `error: ${msg}`);
}

# Print a pipeline completion summary. Always shown.
# + outputDir - Path to the directory where output was written
public function logCompletion(string outputDir) {
    io:fprintln(io:stderr, string `${""}${"\n"}Connector generated at: ${outputDir}`);
}
