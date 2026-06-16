# CLAUDE.md — Connector Generation CLI Tool

This file is the authoritative architecture reference for this repository. Read it at the start of every session. If you make a change that deviates from, extends, or invalidates any section below, **update this file in the same session before committing**. Do not let it drift.

---

## What this tool does

`bal connector` is a Ballerina CLI tool that automates Ballerina connector generation and maintenance from two source types:

- **OpenAPI workflow** (`bal connector openapi …`) — takes an OpenAPI spec, runs a 5-step pipeline: sanitize → generate client (+ build/validate) → generate tests → generate examples → generate docs; individual stages can be skipped with `-x`
- **SDK workflow** (`bal connector sdk …`) — takes a Java SDK JAR, runs: analyze SDK → generate API spec/IR → generate connector → fix code → generate examples → generate tests → generate docs

Both workflows are AI-assisted (Anthropic Claude via `ballerina/ai` + `ballerinax/ai.anthropic`). `ANTHROPIC_API_KEY` must be set.

---

## Repository layout

```
connector-generation-cli-tool/
├── connector-cli/          # Java layer — Ballerina tool JAR, CLI entry point
│   └── src/main/java/io/ballerina/connectortool/
│       ├── ConnectorCmd.java              # Root BLauncherCmd, "bal connector"
│       ├── BaseCmd.java                   # Shared --help mixin
│       ├── spi/ConnectorWorkflow.java     # SPI interface (extends BLauncherCmd)
│       ├── exceptions/CliException.java   # Typed CLI error with exit code
│       ├── utils/
│       │   ├── BallerinaRuntimeUtils.java  # All Ballerina runtime invocation
│       │   ├── ProcessUtils.java           # JVM process exit helpers
│       │   ├── BallerinaProjectPathValidationUtils.java
│       │   ├── OpenApiPathValidationUtils.java
│       │   └── Utils.java                  # EMPTY — kept for binary compatibility only
│       └── workflows/
│           ├── OpenApiAutomatorWorkflow.java  # "openapi" subcommand
│           └── SdkAutomatorWorkflow.java      # "sdk" subcommand
│
├── connector-core/
│   └── connector-automator/   # Ballerina package wso2/connector_automator
│       ├── Ballerina.toml
│       ├── main.bal             # SDK workflow CLI dispatcher + all SDK subcommands
│       ├── openapi_workflow.bal # Public entry point: runOpenApiGenerationWorkflow
│       └── modules/
│           ├── utils/           # Shared: executeCommand, resolveBallerinaDir, types, LogLevel, log_utils
│           ├── sanitizor/       # Step 1 OpenAPI: sanitize + align spec
│           ├── client_generator/# Step 2 OpenAPI: bal openapi client generation
│           ├── code_fixer/      # Step 3/optional: fix Ballerina compilation errors
│           ├── example_generator/ # Step 5: AI-generated code examples
│           ├── test_generator/  # Step 4: mock server + live test generation
│           ├── document_generator/ # Step 6: AI-generated README files
│           ├── sdkanalyzer/     # SDK workflow: Java SDK → metadata JSON
│           ├── api_specification_generator/ # SDK: metadata → IR + spec
│           ├── connector_generator/ # SDK: spec → Ballerina client + native adapter
│           └── client_regenerator/  # SDK: version-aware client update
│
├── connector-tool/          # BalTool descriptor (BalTool.toml, Ballerina.toml)
│   └── BalTool.toml         # tool.id = "connector"; points to connector-cli JAR
│
└── docs/
    └── openapi-workflow-architecture.md  # Detailed design doc (append, never rewrite)
```

---

## Invocation model: Java → Ballerina

The CLI tool is a standard Ballerina tool (`BalTool.toml`). When a user runs `bal connector`, the Ballerina launcher loads the tool JAR and calls `ConnectorCmd`. `ConnectorCmd.setParentCmdParser` uses `ServiceLoader<ConnectorWorkflow>` to register subcommands (`openapi`, `sdk`) into the picocli tree.

### OpenAPI path — named function invocation

`OpenApiAutomatorWorkflow.execute()` calls:

```java
BallerinaRuntimeUtils.callBallerinaFunction(
    "wso2", "connector_automator", "0",
    "runOpenApiGenerationWorkflow",
    openApiSpecPath != null ? openApiSpecPath.toString() : "",
    ballerinaProjectPath.toString(), logLevel, resolvedExamplesDir.toString(),
    excludedArg, specDirPath.toString()
);
```

`callBallerinaFunction` creates a fresh `Runtime`, calls the named function with **six** `BString` args (spec path, output dir, log level, examples dir, excluded stages, spec dir), and **throws `RuntimeException`** on `BError` or any exception. The caller catches it and exits with `ProcessUtils.exitError(exitWhenFinish)`.

`openApiSpecPath` is `null` when `sanitize` is excluded — in that case an empty string is passed and the Ballerina side ignores it.

`runOpenApiGenerationWorkflow` handles both fresh generation and regeneration of an existing connector — see "Regeneration is automatic" below. There is no separate regen flag or function; Java always calls the same function name.

The `logLevel` string (`"quiet"`, `"normal"`, or `"verbose"`) is derived from the `-q`/`-v` flags on `OpenApiAutomatorWorkflow`. If both flags are set, a `CliException(exitCode=2)` is thrown before Ballerina is invoked.

### SDK path — main + name prefix

`SdkAutomatorWorkflow.execute()` calls:

```java
BallerinaRuntimeUtils.callBallerinaRunteimAPiWithName(
    "wso2", "connector_automator", "0",
    "sdk", balArgs
);
```

This prepends the workflow name to the args array and calls `main(...)` on the Ballerina package. Errors are printed to stderr but not thrown — the SDK path does **not** propagate errors to Java.

### `callBallerinaFunction` vs legacy methods

| Method | Throws on error? | Used by |
|--------|-----------------|---------|
| `callBallerinaFunction` | Yes — throws `RuntimeException` | OpenAPI workflow |
| `callBallerinaRunteimAPiWithName` | No — prints to stderr | SDK workflow |
| `callBallerinaRuntimeApiWithSingleArg` | No | Legacy |
| `callBallerinaRuntimeApiWithMultipleArgs` | No | Legacy |

When adding new workflows that need proper exit-code propagation, follow the `callBallerinaFunction` pattern.

---

## 3-tier logging — `LogLevel`

All diagnostic output goes to **stderr**. Stdout is reserved for data (generated files are the data, not text).

### LogLevel type

Defined in `modules/utils/types.bal`:
```ballerina
public type LogLevel "quiet"|"normal"|"verbose";
```

### Central logging utilities (`modules/utils/log_utils.bal`)

```ballerina
logStep(step, total, name, level)   // normal+verbose: "[N/6] Step name"
logInfo(msg, level)                 // normal+verbose: "  msg"
logVerbose(msg, level)              // verbose only:   "  [verbose] msg"
logWarn(msg, level)                 // normal+verbose: "  warning: msg"
logError(msg)                       // always:         "error: msg"
logCompletion(outputDir, level)     // normal+verbose: "Connector generated at: …"
```

### Mode behaviour

| Flag | Level | What's shown |
|------|-------|--------------|
| (none) | `"normal"` | step headers + key outcomes + warnings |
| `-q` / `--quiet` | `"quiet"` | errors only (nothing on success) |
| `-v` / `--verbose` | `"verbose"` | everything: subprocess commands, batch details, AI internals |

`-q` and `-v` are mutually exclusive — Java layer throws `CliException(exitCode=2)` if both are given.

### Thread-through pattern

`LogLevel` flows from Java → `runOpenApiGenerationWorkflow` (takes `(spec, outputDir, logLevel, examplesDir, excludedStages, specDir)`) → every step function. All public step functions have the signature:
```ballerina
public function executeXxx(..., utils:LogLevel logLevel = "normal") returns error?
```

### Converting boolean quietMode at SDK boundaries

SDK modules (`sdkanalyzer`, `api_specification_generator`, `connector_generator`, `code_fixer`) still use `boolean quietMode` internally. Convert at the call boundary:
```ballerina
utils:initAIService(config.quietMode ? "quiet" : "normal");
code_fixer:fixAllErrors(dir, quietMode = logLevel == "quiet", ...);
```

---

## JVM exit after Ballerina runtime

The embedded Ballerina runtime leaves non-daemon threads alive after `runtime.stop()`. The JVM will hang unless forced to exit.

**Pattern:**
```java
private boolean exitWhenFinish = true;  // set false in tests

// on success:
ProcessUtils.exitSuccess(exitWhenFinish);  // exit(0) if flag set
// on error:
ProcessUtils.exitError(exitWhenFinish);    // exit(1) if flag set
ProcessUtils.exit(code, exitWhenFinish);   // arbitrary code
```

`return` after every `ProcessUtils.exit*` call — execution continues if `exitWhenFinish` is false.

`OpenApiAutomatorWorkflow` implements this. `SdkAutomatorWorkflow` does **not** yet (it relies on the legacy runtime path).

---

## Error handling in `OpenApiAutomatorWorkflow.execute()`

```java
try {
    Path openApiSpecPath = OpenApiPathValidationUtils.validate(inputPath);
    Path ballerinaProjectPath = BallerinaProjectPathValidationUtils.validate(outputPath);
    BallerinaRuntimeUtils.callBallerinaFunction(...);
} catch (CliException e) {
    errorStream.println(e.getFormattedMessage());
    ProcessUtils.exit(e.getExitCode(), exitWhenFinish);
    return;
} catch (Exception e) {
    errorStream.println("bal: fatal: unexpected error: " + e.getMessage());
    ProcessUtils.exitError(exitWhenFinish);
    return;
}
ProcessUtils.exitSuccess(exitWhenFinish);
```

`CliException` carries an exit code and a formatted message. Exit codes: `1` = path/validation error, `2` = missing required option.

---

## Flat vs nested Ballerina project layout

Two workspace structures are supported:

| Layout | `Ballerina.toml` location | When used |
|--------|--------------------------|-----------|
| **Nested (SDK)** | `connectorPath/ballerina/Ballerina.toml` | SDK workflow output |
| **Flat (OpenAPI)** | `connectorPath/Ballerina.toml` | OpenAPI workflow output |

All code that navigates into the Ballerina project **must** call:

```ballerina
string ballerinaDir = check utils:resolveBallerinaDir(connectorPath);
```

`resolveBallerinaDir` in `modules/utils/command_executor.bal` checks for the nested path first; returns `connectorPath` itself if flat. Never hardcode `/ballerina` suffix.

---

## Subprocess CWD isolation — always use absolute paths

`executeCommand(cmd, workDir, ...)` runs subprocesses with `cd "<workDir>" && <cmd>`. Any relative path inside `cmd` resolves relative to `workDir`, not the caller's CWD.

**Rule:** Before interpolating a path into a command string that runs in a different working directory, convert it to absolute:

```ballerina
string absSpecPath = check file:getAbsolutePath(specPath);
string absMockServerDir = check file:getAbsolutePath(mockServerDir);
string command = string `bal openapi -i ${absSpecPath} -o ${absMockServerDir}`;
```

---

## Template embedding — document_generator

`.md` template files are **not** bundled into the compiled JAR by `bal pack`. Runtime `io:fileReadString` with a relative path will fail when the tool is invoked from any directory other than the package source root.

**All templates are embedded as compile-time constants** in:
```
modules/document_generator/templates.bal
```

```ballerina
final map<string> & readonly DOCUMENT_TEMPLATES = {
    "ballerina_readme_template.md": "...",
    "example_specific_template.md": "...",
    ...
};
```

`processTemplate(templateName, data)` in `ai_generator.bal` does a map lookup — no filesystem access. If you add a new template, add it to `DOCUMENT_TEMPLATES`; do not introduce `io:fileReadString` for templates.

---

## Ballerina module visibility

All `.bal` files in the same module directory share a single namespace — no imports needed. Example: `templates.bal` and `ai_generator.bal` in `modules/document_generator/` both see `DOCUMENT_TEMPLATES` directly.

Cross-module imports use the aliased form:
```ballerina
import wso2/connector_automator.utils as oautils;
import wso2/connector_automator.document_generator as document_generator;
```

---

## OpenAPI pipeline steps (openapi_workflow.bal)

```
Stage 1  sanitizor:executeSanitizor           — flatten + AI-align spec
Stage 2  client_generator:executeClientGen    — bal openapi → Ballerina client
         code_fixer:fixAllErrors (embedded)   — auto-fix compilation errors (no extra step)
Stage 3  test_generator:executeOpenApiTestGen — mock server + live tests
Stage 4  example_generator:executeExampleGen  — AI-generated .bal examples
Stage 5  document_generator:executeDocGen     — README files
```

`client` and `tests` are both counted as independent stages (`total` is computed from the fixed list `["sanitize", "client", "tests", "examples", "docs"]` filtered by `-x` exclusions), each with its own `logStep` header. Stage 2 (client) runs generate → build → auto-fix-on-error → rebuild, failing CRITICALLY if errors persist. Stage 3 (tests) runs once, independently, immediately after Stage 2 completes — it does not branch on the build outcome. Step numbers are recomputed sequentially within whichever stages are active after exclusions.

Client is generated into `outputDir/` (flat layout). Sanitized spec goes to `outputDir/docs/spec/aligned_ballerina_openapi.json`.

### Regeneration is automatic

`runOpenApiGenerationWorkflow` is the single entry point for both fresh generation and regenerating an existing connector from an updated spec — there is no separate flag or function:

- **Sanitations replay**: if `${specDir}/sanitations.md` exists (it's written by `generateSanitationsDoc` after every successful sanitize), it's replayed onto the incoming spec via `sanitizor:applySanitations` before sanitization runs (non-fatal — a missing file or AI failure just falls through to plain sanitization). On a fresh project this file doesn't exist yet, so the pre-step is a no-op.
- **Test generation**: runs as a plain independent Stage 3 once Stage 2 (client generation + build) completes successfully — `test_generator:executeOpenApiTestGen` always overwrites all test/mock files, so no special handling of stale tests is needed on a spec update.

Re-running `bal connector openapi -i <updated-spec> -o <existing-connector-dir>` is the regeneration workflow.

### `-x`/`--exclude` flag

Any of the 5 stages can be independently excluded:

```
bal connector openapi -i spec.yaml -o ./out -x tests -x examples
bal connector openapi -o ./out -x sanitize    # reuses aligned_ballerina_openapi.json on disk
```

Java-layer preflight checks (before Ballerina runtime starts):
- Unknown stage name → exit 2
- All 5 stages excluded → exit 2
- `sanitize` excluded but `aligned_ballerina_openapi.json` missing → exit 1
- `client` excluded but `client.bal` missing → exit 1
- `-i` is only validated when `sanitize` is NOT excluded

`docs` skips sections whose source stage was excluded: `client` excluded → skip main README; `tests` excluded → skip tests README; `examples` excluded → skip examples READMEs.

### Alternative entry: Java path vs `executeOpenApiCommand`

Java calls `runOpenApiGenerationWorkflow` in `openapi_workflow.bal` via `callBallerinaFunction` (6 args) for every invocation — there is no flag-based function routing.

`executeOpenApiCommand` in `main.bal` — called when running the tool directly as `bal tool-id openapi …`; includes all subcommands (sanitize, generate-client, generate-tests, etc.) and its own legacy pipeline implementation (nested layout), including the separate legacy `runOpenApiRegenerationPipeline` for that nested-layout CLI path. That legacy function is unrelated to the unified `runOpenApiGenerationWorkflow` described above.

---

## SDK workspace directory layout

```
<outputRoot>/
  docs/spec/
    <dataset-key>-metadata.json
    <dataset-key>-ir.json
    <dataset-key>_spec.bal
    aligned_ballerina_openapi.json
  ballerina/           ← Ballerina.toml here (nested layout)
    client.bal
    types.bal
    tests/
    modules/mock.server/
  native/
    build.gradle
    src/...
  examples/
    <example-name>/
      main.bal
      README.md
  README.md
```

OpenAPI workspace is flat — `Ballerina.toml` is at `<outputRoot>/Ballerina.toml`.

---

## Example count step function

`example_generator/analyzer.bal` → `numberOfExamples(apiCount)` determines how many use-case examples to generate based on the count of `remote function` declarations in `client.bal`:

| `apiCount` | examples generated |
|-----------|-------------------|
| < 15 | 1 |
| 16–30 | 2 |
| 31–60 | 3 |
| > 60 | 4 (ceiling) |

---

## `Utils.java` is intentionally empty

`Utils.java` contains only a package declaration. All logic was moved to:
- `BallerinaRuntimeUtils.java` — Ballerina runtime lifecycle and function invocation
- `ProcessUtils.java` — JVM process exit

Do not add new code to `Utils.java`. It exists only to avoid breaking any external callers that may import the class.

---

## Build

### Full build

```bash
# 1. Build native SDK analyzer JAR
cd connector-core/connector-automator/modules/sdkanalyzer/native
./gradlew build

# 2. Pack the Ballerina automator
cd connector-core/connector-automator
bal pack

# 3. Build the CLI JAR (shadow JAR bundles everything)
cd connector-cli
./gradlew shadowJar
# output: connector-cli/build/libs/connector-tool-0.1.0.jar

# 4. Run the tool
bal connector openapi -i <spec> -o <outputDir>
```

### Gradle properties

`ballerinaHome` is auto-resolved via `bal home`. Override with `-Pballerina.home=…` or `BALLERINA_HOME` env var.

The shadow JAR includes `connector_automator`, `connector_doc_generator`, and `example_doc_generator` Ballerina JARs as runtime dependencies (picked up from `connector-core/*/target/bin/`).

---

## Key invariants — do not break these

1. **Never hardcode `/ballerina` suffix** — always call `resolveBallerinaDir(connectorPath)`.
2. **Always absolutize paths before subprocess interpolation** — `file:getAbsolutePath(path)` before using in `executeCommand` strings.
3. **Templates must be compile-time constants** — no `io:fileReadString` for document templates.
4. **`callBallerinaFunction` must throw on error** — do not catch `RuntimeException` and swallow it; the Java caller needs the signal to exit with non-zero code.
5. **`Utils.java` stays empty** — do not add code there.
6. **Every `ProcessUtils.exit*` call must be followed by `return`** — guards against fall-through when `exitWhenFinish = false`.
7. **All diagnostic output goes to stderr** — use `utils:log*` functions or `io:fprintln(io:stderr, ...)`, never bare `io:println` for diagnostic/progress messages.
8. **Thread `LogLevel` through, don't convert to boolean** — pass `logLevel` directly to callee functions; only convert to `boolean quietMode` at SDK module boundaries where the API is `boolean`-based.

---

## Keeping this file current

When you make any of the following changes, update the relevant section of this file in the same session:

- Adding a new workflow subcommand
- Changing how Java invokes Ballerina (new method in `BallerinaRuntimeUtils`)
- Adding a new Ballerina module to `connector-automator`
- Changing the output directory layout (SDK or OpenAPI)
- Adding or removing a pipeline step
- Adding a new pattern for path resolution, error handling, or process exit
- Moving logic between Java utility classes

If you notice a section is stale (e.g., a function was renamed), correct it before proceeding with the task.
