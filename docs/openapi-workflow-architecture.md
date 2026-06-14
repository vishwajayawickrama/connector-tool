# OpenAPI Workflow Architecture

This document covers the architectural decisions and implementation details for the OpenAPI connector generation workflow, including the Java-to-Ballerina invocation model, the pipeline structure, and the flat-project layout introduced for OpenAPI-driven generation.

---

## Overview

The connector generation tool has two distinct generation paths:

| Path | Entry | Ballerina project location |
|---|---|---|
| **SDK workflow** | `bal tool-id sdk pipeline …` | `outputDir/ballerina/` (nested) |
| **OpenAPI workflow** | `bal connector openapi -i spec -o dir` | `outputDir/` (flat — the output dir IS the project) |

The OpenAPI workflow is invoked via the Java PicoCLI layer, which validates inputs and then calls into the Ballerina runtime directly — bypassing the Ballerina CLI dispatch entirely.

---

## Two-Layer Invocation Model

```
User CLI
  └─▶ bal connector openapi -i <spec> -o <project-dir>
        │
        ▼
  OpenApiAutomatorWorkflow.java      (PicoCLI / BLauncherCmd SPI)
        │  validate inputs
        │  Utils.callBallerinaFunction(...)
        │
        ▼
  Ballerina Runtime API              (io.ballerina.runtime.api.Runtime)
        │  runtime.callFunction(balModule, "runOpenApiWorkflow", null, specBStr, outBStr)
        │
        ▼
  openapi_workflow.bal
        │  runOpenApiWorkflow(openApiSpec, outputDir)
        │
        ▼
  functions.bal
        └─▶ executeOpenApiPipeline(openApiSpec, outputDir)
```

### Why bypass `main.bal`?

The existing Ballerina CLI path (`bal tool-id openapi pipeline …`) invokes `main.bal`'s `runOpenApiPipeline(string[] args)`, which parses CLI string arguments. Calling that from Java would require re-serializing structured data back into a string array and passing it through `main`, adding unnecessary coupling.

By exposing a named public function (`runOpenApiWorkflow`) and calling it via `runtime.callFunction`, the Java layer passes strongly-typed string values directly — no CLI parsing on the Ballerina side.

---

## Java Layer

### `OpenApiAutomatorWorkflow.java`

Implements `ConnectorWorkflow` (SPI) and `BLauncherCmd`. Registered under the command name `openapi`.

**Responsibilities:**
1. Parse CLI options (`-i` / `--input`, `-o` / `--output`) via PicoCLI annotations.
2. Validate the OpenAPI spec path (`OpenApiPathValidationUtils.validate`).
3. Validate the output directory as an existing Ballerina BUILD_PROJECT (`BallerinaProjectPathValidationUtils.validate`).
4. Invoke the Ballerina pipeline function via `Utils.callBallerinaFunction`.

```java
// constants
private final String ORG = "wso2";
private final String MODULE = "connector_automator";
private final String VERSION = "0";

// in execute()
Path openApiSpecPath = OpenApiPathValidationUtils.validate(inputPath);
Path ballerinaProjectPath = BallerinaProjectPathValidationUtils.validate(outputPath);

Utils.callBallerinaFunction(ORG, MODULE, VERSION, "runOpenApiWorkflow",
        openApiSpecPath.toString(), ballerinaProjectPath.toString());
```

### Input validation

| Validator | What it checks |
|---|---|
| `OpenApiPathValidationUtils` | File exists, is JSON or YAML, contains `openapi`/`swagger` field and a `paths` object |
| `BallerinaProjectPathValidationUtils` | Directory exists, contains `Ballerina.toml`, loads successfully as a `BUILD_PROJECT` via `ProjectLoader` |

The output path validation is intentionally strict — the directory must already be a valid Ballerina project. There is no auto-creation. This means users prepare the project once (`bal new`) and point the tool at it.

### `Utils.callBallerinaFunction`

A general-purpose helper in `connector-cli/.../utils/Utils.java` for invoking a named Ballerina function with two string arguments.

```java
public static void callBallerinaFunction(String org, String module, String version,
        String functionName, String inputPath, String outputPath) {
    Runtime runtime = null;
    boolean runtimeStarted = false;
    try {
        Module balModule = new Module(org, module, version);
        runtime = Runtime.from(balModule);
        runtime.init();
        runtime.start();
        runtimeStarted = true;

        Object result = runtime.callFunction(balModule, functionName, null,
                StringUtils.fromString(inputPath), StringUtils.fromString(outputPath));
        if (result instanceof BError error) {
            System.err.println("Error occurred while running connector automator: " + error.getErrorMessage());
        }
    } catch (Exception e) {
        System.err.println("Error occurred while running connector automator: " + e.getMessage());
    } finally {
        if (runtimeStarted && runtime != null) {
            runtime.stop();
        }
    }
}
```

The method is non-variadic: `inputPath` and `outputPath` are explicit parameters rather than a `String...` array. This is intentional — the signature is clear about what the function requires, and adding more parameters in the future means extending the signature explicitly rather than relying on positional convention.

The existing `callWorkflow` method (which calls `main`) is preserved unchanged for the SDK workflow.

---

## Ballerina Layer

### `openapi_workflow.bal`

The single public entry point callable from Java. Lives in the `connector-automator` module root (same module as `main.bal`, `functions.bal`).

```ballerina
public function runOpenApiWorkflow(string openApiSpec, string outputDir) returns error? {
    return executeOpenApiPipeline(openApiSpec, outputDir);
}
```

`public` visibility is required for `runtime.callFunction` to resolve it. The thin wrapper keeps the entry point stable even if the pipeline implementation in `functions.bal` evolves.

### `functions.bal`

Contains `executeOpenApiPipeline` — the self-contained 6-step OpenAPI pipeline with explicit `(string openApiSpec, string outputDir)` parameters. No CLI arg parsing occurs here.

Because all `.bal` files in the `connector-automator/` root belong to the same Ballerina module, `functions.bal` can call printing helpers defined in `main.bal` (`printOpenApiPipelineHeader`, `printOpenApiStepHeader`, `printOpenApiPipelineCompletion`) without any import.

**The function name `executeOpenApiPipeline` is distinct from `runOpenApiPipeline` in `main.bal`** — both exist in the same module, so they cannot share a name. The `execute*` prefix follows the naming convention used across submodule entry points in this codebase.

#### Pipeline steps

```
Step 1 — Sanitize        sanitizor:executeSanitizor(openApiSpec, outputDir)
                         sanitizor:generateSanitationsDoc(...)
                         → writes outputDir/docs/spec/aligned_ballerina_openapi.json

Step 2 — Generate client client_generator:executeClientGen(sanitizedSpec, outputDir)
                         → writes client.bal, types.bal directly to outputDir/

Step 3 — Build/validate  oautils:executeBalBuild(outputDir, false)
                         → fails pipeline on compilation errors

Step 4 — Examples        example_generator:executeExampleGen(outputDir)

Step 5 — Tests           test_generator:executeTestGen("openapi", outputDir, sanitizedSpec)

Step 6 — Documentation   document_generator:executeDocGen("generate-all", outputDir)
```

Steps 4–6 are non-fatal: a failure prints a warning and continues so that partial output is still written.

---

## Flat vs Nested Project Layout

### The problem

The SDK workflow creates connectors as:
```
outputDir/
  ballerina/          ← actual Ballerina project
    Ballerina.toml
    client.bal
    types.bal
    ...
```

The modules (`example_generator`, `test_generator`, `document_generator`) were all written to append `/ballerina` to the `connectorPath` argument when looking for `client.bal`, `types.bal`, `Ballerina.toml`, etc.

For the OpenAPI workflow, the Java CLI validates that `outputDir` itself is a Ballerina project. Writing generated files into `outputDir/ballerina/` would create a nested project inside a project — incorrect and inconsistent.

### The solution: `resolveBallerinaDir`

A single helper in `modules/utils/command_executor.bal` detects the layout at runtime:

```ballerina
public function resolveBallerinaDir(string connectorPath) returns string|error {
    if check file:test(connectorPath + "/ballerina/Ballerina.toml", file:EXISTS) {
        return connectorPath + "/ballerina";   // SDK: nested
    }
    return connectorPath;                       // OpenAPI: flat
}
```

All modules that previously hardcoded `connectorPath + "/ballerina"` now call this helper. The SDK pipeline continues to work unchanged because its workspace always has `connectorPath/ballerina/Ballerina.toml`, so the helper always returns the nested path.

### Files modified to use `resolveBallerinaDir`

| File | What changed |
|---|---|
| `modules/example_generator/analyzer.bal` | `analyzeConnector`: added `ballerinaDir` resolution; `clientBalPath`, `typesBalPath`, `ballerinaTomlPath` now use `ballerinaDir` |
| `modules/test_generator/connector_analyzer.bal` | `analyzeConnectorForTests`: 4 path references replaced; `analyzeConnectorForSdkTests`: 3 path references replaced |
| `modules/test_generator/mock_service_generator.bal` | `setupMockServerModule` and `generateMockServer`: `ballerinaDir` resolved at top of each function |
| `modules/test_generator/ai_generator.bal` | `generateTestFile`: `testFilePath` now uses `ballerinaDir + "/tests/test.bal"` |
| `modules/document_generator/ai_generator.bal` | `generateBallerinaReadme` and `generateTestsReadme`: replaced manual directory-existence fallback with helper |

### Paths that do NOT use `resolveBallerinaDir`

These are workspace-relative paths that sit alongside (not inside) the Ballerina project in both layouts:

- `connectorPath + "/examples"` — examples directory
- `connectorPath + "/README.md"` — main README
- `connectorPath + "/docs/spec/..."` — sanitized spec artifacts

---

## Resulting directory structure (OpenAPI path)

After a successful `bal connector openapi -i spec.yaml -o /path/to/project` run:

```
/path/to/project/               ← pre-existing Ballerina BUILD_PROJECT
  Ballerina.toml                ← pre-existing
  client.bal                    ← step 2: client_generator
  types.bal                     ← step 2: client_generator
  docs/
    spec/
      aligned_ballerina_openapi.json   ← step 1: sanitizor
      flattened_openapi.json           ← step 1: sanitizor
      sanitations.md                   ← step 1: sanitizor
  tests/
    test.bal                    ← step 5: test_generator
    README.md                   ← step 6: document_generator
  modules/
    mock.server/                ← step 5: test_generator
  examples/                     ← step 4: example_generator
    README.md                   ← step 6: document_generator
  README.md                     ← step 6: document_generator
```

---

## Backward compatibility

The changes preserve backward compatibility at every level:

- **SDK CLI path** (`bal tool-id sdk pipeline …`) — calls `main.bal`'s dispatch; unmodified.
- **OpenAPI CLI path** (`bal tool-id openapi pipeline …`) — calls `main.bal`'s `runOpenApiPipeline(string[] args)`; unmodified.
- **`resolveBallerinaDir` for SDK** — SDK workspaces always have `connectorPath/ballerina/Ballerina.toml`; the helper always returns the nested path. All module behavior is identical to before.
- **`main.bal`** — not touched. Printing helpers, `runOpenApiPipeline`, and `runOpenApiRegenerationPipeline` remain exactly as they were.

---

## Module-level visibility rule

All `.bal` files in `connector-core/connector-automator/` (the module root) belong to the same Ballerina module (`wso2/connector_automator`). Functions defined in one file are visible across all files in the same directory without any import statement.

This is why:
- `functions.bal` can call `printOpenApiPipelineHeader` etc. from `main.bal` without importing.
- `openapi_workflow.bal` can call `executeOpenApiPipeline` from `functions.bal` without importing.
- `openapi_workflow.bal` cannot duplicate any public function name already used in `main.bal` — they share the same module namespace.

---

## Key design decisions

**Why not create new module-level functions per workflow (e.g. `executeExampleGenOpenApi`)?**
This was evaluated and rejected as redundant. The `resolveBallerinaDir` helper achieves layout-awareness in a single place without duplicating any public function or adding new entry points to each module.

**Why is output path validation strict (must be an existing project)?**
Weak validation was rejected in favor of strict validation. The Java `BallerinaProjectPathValidationUtils` requires a fully-loadable `BUILD_PROJECT`. This prevents silent errors where the pipeline runs against an invalid directory and produces malformed output.

**Why is `callBallerinaFunction` not variadic?**
The signature `(String org, String module, String version, String functionName, String inputPath, String outputPath)` makes the required arguments explicit. A variadic `String... args` would require callers to remember argument order by convention rather than by signature, and would lose compile-time clarity.

---

## Bug Fixes Applied During Pipeline Testing

Three bugs were found after initial integration and fixed before the pipeline was considered stable.

### 1. `packAndPushConnector` used hardcoded `/ballerina` suffix

**File:** `modules/example_generator/analyzer.bal` — `packAndPushConnector`

**Symptom:** "Ballerina directory not found at: ./test-openapi/ballerina" during example generation.

**Cause:** `packAndPushConnector` was not updated during the initial `resolveBallerinaDir` refactor. It still hardcoded `connectorPath + "/ballerina"` instead of calling the helper.

**Fix:**
```ballerina
// Before
string ballerinaDir = connectorPath + "/ballerina";
if !check file:test(ballerinaDir, file:EXISTS) {
    return error("Ballerina directory not found at: " + ballerinaDir);
}

// After
string ballerinaDir = check oautils:resolveBallerinaDir(connectorPath);
```

### 2. Subprocess path double-prefix in mock server generation

**File:** `modules/test_generator/mock_service_generator.bal` — `generateMockServer`

**Symptom:** "OpenAPI contract doesn't exist at /test-openapi/test-openapi/..." — the connector path appeared twice.

**Cause:** `executeCommand` runs the `bal openapi` subprocess with `workingDirectory = ballerinaDir`. When `specPath` and `mockServerDir` were CWD-relative strings (e.g. `./test-openapi/...`), the subprocess resolved them relative to `ballerinaDir` — producing `ballerinaDir/test-openapi/...` which doubled the prefix.

**Fix:** Convert both paths to absolute before building the command string:
```ballerina
string absSpecPath = check file:getAbsolutePath(specPath);
string absMockServerDir = check file:getAbsolutePath(mockServerDir);
// use absSpecPath and absMockServerDir in command string
```

This applies to both the single-operation and filtered-operation command variants.

### 3. Hardcoded `/ballerina/modules/mock.server/` paths in test executor

**File:** `modules/test_generator/execute.bal` — `executeOpenApiTestGen`

**Symptom:** Mock server `.bal` files not found at expected paths after mock server generation.

**Cause:** `executeOpenApiTestGen` had two hardcoded paths (`connectorPath + "/ballerina/modules/mock.server/mock_server.bal"` etc.) that were never updated to use `resolveBallerinaDir`.

**Fix:**
```ballerina
string ballerinaDir = check utils:resolveBallerinaDir(connectorPath);
string mockServerPath = ballerinaDir + "/modules/mock.server/mock_server.bal";
string typesPath = ballerinaDir + "/modules/mock.server/types.bal";
```

---

## JVM Exit After Pipeline Completion

### Problem

After `runtime.stop()` returns, the embedded Ballerina runtime leaves non-daemon JVM threads alive. The process hangs indefinitely even after a successful pipeline run.

### Solution: `exitWhenFinish` + `ProcessUtils`

`OpenApiAutomatorWorkflow` uses the Ballerina CLI convention of an `exitWhenFinish` instance field (defaults to `true`) that guards explicit `Runtime.getRuntime().exit()` calls. The helpers are in a dedicated `ProcessUtils` class:

```java
// ProcessUtils.java
public class ProcessUtils {
    public static void exitSuccess(boolean exit) { exit(0, exit); }
    public static void exitError(boolean exit)   { exit(1, exit); }
    public static void exit(int code, boolean exit) {
        if (exit) { Runtime.getRuntime().exit(code); }
    }
}
```

```java
// OpenApiAutomatorWorkflow.execute()
try {
    Path openApiSpecPath = OpenApiPathValidationUtils.validate(inputPath);
    Path ballerinaProjectPath = BallerinaProjectPathValidationUtils.validate(outputPath);
    BallerinaRuntimeUtils.callBallerinaFunction(ORG, MODULE, VERSION, "runOpenApiWorkflow",
            openApiSpecPath.toString(), ballerinaProjectPath.toString());
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

The `return` after each error path is required — `Runtime.getRuntime().exit()` terminates the JVM immediately, but the compiler does not know that, so `return` prevents fall-through in tests or contexts where `exitWhenFinish = false`.

The `exitWhenFinish` field makes the command embeddable in tests (set to `false`) without changing the normal CLI behavior.

---

## Java Utility Class Refactoring

The original monolithic `Utils.java` was split into two focused classes:

| Class | Responsibility |
|---|---|
| `BallerinaRuntimeUtils` | Ballerina runtime lifecycle — `callBallerinaFunction`, `callBallerinaRunteimAPiWithName`, `addToFront`, etc. |
| `ProcessUtils` | JVM process lifecycle — `exitSuccess`, `exitError`, `exit` |

`Utils.java` now contains only the package declaration. It is kept to avoid build breakage from any lingering references but holds no logic.

### Error propagation in `callBallerinaFunction`

The original implementation swallowed errors — both `BError` results and Java exceptions were printed to stderr and then silently returned. This meant `OpenApiAutomatorWorkflow` could not tell whether the pipeline succeeded or failed.

The fixed version throws:

```java
if (result instanceof BError error) {
    throw new RuntimeException(error.getErrorMessage().toString());
}
// ...
} catch (RuntimeException e) {
    throw e;                            // don't double-wrap
} catch (Exception e) {
    throw new RuntimeException(e.getMessage(), e);
}
```

`OpenApiAutomatorWorkflow` catches `Exception` and calls `ProcessUtils.exitError` on failure, producing a non-zero exit code.

---

## Template Embedding

### Problem

`document_generator/ai_generator.bal` read template files at runtime via:
```ballerina
const string TEMPLATES_PATH = "./modules/document_generator/templates";
// ...
string template = check io:fileReadString(TEMPLATES_PATH + "/" + templateName);
```

`io:fileReadString` resolves paths relative to the process working directory. When `bal connector openapi` is run from any directory other than `connector-core/connector-automator/`, the path `./modules/document_generator/templates` does not exist and documentation generation fails with "Template not found".

Additionally, `.md` files are not compiled by `bal build` or `bal pack` — they are not included in the output JAR. There is no `resources/` support in the Ballerina JAR layout that would allow bundling arbitrary files.

### Solution: Ballerina string constants in `templates.bal`

The five templates are embedded directly as a `final map<string> & readonly` constant in a new source file within the `document_generator` module:

```
modules/document_generator/
  ai_generator.bal      ← uses DOCUMENT_TEMPLATES
  templates.bal         ← defines DOCUMENT_TEMPLATES  (NEW)
  execute.bal
  types.bal
```

Because both files are in the same module directory (`modules/document_generator/`), they share the same Ballerina module namespace — `DOCUMENT_TEMPLATES` in `templates.bal` is directly visible in `ai_generator.bal` without any import.

`processTemplate` becomes a simple map lookup with no filesystem access:

```ballerina
// Before (filesystem read — fails outside source directory)
function processTemplate(string templateName, TemplateData data) returns string|error {
    string templatePath = TEMPLATES_PATH + "/" + templateName;
    if !check file:test(templatePath, file:EXISTS) {
        return error("Template not found: " + templatePath);
    }
    string template = check io:fileReadString(templatePath);
    return substituteVariables(template, data);
}

// After (map lookup — compiled into JAR bytecode, no path resolution)
function processTemplate(string templateName, TemplateData data) returns string|error {
    string? template = DOCUMENT_TEMPLATES[templateName];
    if template is () {
        return error("Template not found: " + templateName);
    }
    return substituteVariables(template, data);
}
```

The map keys are the original filenames (`"ballerina_readme_template.md"`, etc.) so all existing callers of `processTemplate` are unchanged.

The `templates/` directory on disk is kept as a developer reference but is no longer read at runtime.

### Why not `resources/` or Java classpath loading?

| Approach | Bundled in JAR? | Requires Java interop? | Path resolution needed? |
|---|---|---|---|
| String constants in `.bal` (chosen) | Yes — compiled into bytecode | No | No — map key lookup |
| Ballerina `resources/` directory | Not currently (JAR is empty of non-`.class` content) | Yes — `io:fileReadString` is FS-only | Yes — classpath path |
| Java interop via native adapter | Yes, if added to native JAR | Yes — new native module required | Yes — classpath path |

Embedding as constants is the only approach with zero moving parts at runtime.

---

## Optional `-o` / `--output` — defaults to CWD

The `-o`/`--output` option was previously required. It is now optional.

When `-o` is omitted, `BallerinaProjectPathValidationUtils.validate(null)` resolves the output path to `System.getProperty("user.dir")` — the JVM's working directory at startup, which equals the shell CWD where `bal connector openapi` was invoked.

```java
public static Path validate(String outputPath) {
    String resolvedPath = (outputPath == null || outputPath.isBlank())
            ? System.getProperty("user.dir")
            : outputPath;
    Path projectPath = Path.of(resolvedPath);
    validateBallerinaProject(projectPath.toAbsolutePath().normalize(), "-o");
    return projectPath;
}
```

This matches the convention used by `bal build`, `bal new`, and `npm init`, all of which default to "the directory you're currently in." The downstream validation is unchanged — the resolved path must still exist, be a directory, contain `Ballerina.toml`, and load successfully as a `BUILD_PROJECT`.

**Practical result:** A user can `cd` into an existing Ballerina project and run `bal connector openapi -i spec.yaml` without specifying `-o`.

---

## Removal of `autoYes` / Interactive Gate Pattern from OpenAPI Modules

### The original pattern

Several OpenAPI modules had a `getUserConfirmation(message, autoYes)` helper that prompted the user "Proceed?" before each step. To let the automated Java-invoked pipeline skip these prompts, every call site passed `autoYes=true`.

The hidden bug: because `getUserConfirmation(msg, autoYes=true)` always returned `true`, the `if !getUserConfirmation(...) { return; }` abort branch **could never execute**. When a critical step failed — for example, YAML→JSON conversion in the sanitizor — the pipeline logged a warning and continued to the next step, which then failed on the missing output file, which logged another warning, and so on through all six steps. The user saw six warnings but no non-zero exit code and no clear root cause.

### The fix

`autoYes` and `getUserConfirmation` were removed from every OpenAPI module. The pipeline runs unconditionally — no prompts, no gates. Critical failures propagate as `error?`; non-critical failures emit a warning and continue.

| Module | What was removed |
|--------|-----------------|
| `modules/sanitizor/execute.bal` | `boolean autoYes` param, `getUserConfirmation` helper, all gate blocks; YAML→JSON failure now hard-aborts |
| `modules/example_generator/execute.bal` | `boolean autoYes` param, `getUserConfirmation` helper, "Proceed with example generation?" gate |
| `modules/client_generator/types.bal` | `boolean autoYes` field from `ClientGeneratorConfig` record |
| `modules/client_generator/execute.bal` | `getUserConfirmation` gate before Ballerina client generation |
| `modules/document_generator/execute.bal` | `boolean autoYes` from six private functions, `getUserConfirmation` helper, all "Proceed?" gates |
| `modules/test_generator/execute.bal` | `getUserConfirmation` helper function |
| `main.bal` | `parseOpenApiAutoYes` helper, all `autoYes` local vars from OpenAPI call sites, `"yes"` exclusion from `parseOpenApiPositionalArgs` |

**What was NOT changed:** `code_fixer`'s `autoYes` is a "apply fixes automatically" feature flag (not an interactive gate) — it was left intact. The OpenAPI pipeline calls `code_fixer:fixAllErrors(clientPath, logLevel, true)` with `autoYes=true`, which is intentional and correct.

---

## Consolidation of `functions.bal` into `openapi_workflow.bal`

`functions.bal` contained exactly one function: `executeOpenApiPipeline`. `openapi_workflow.bal` contained exactly one function: `runOpenApiWorkflow`, which delegated immediately to `executeOpenApiPipeline`.

Both files lived in the same Ballerina module root (`connector-core/connector-automator/`), so the split was cosmetic. They were merged into `openapi_workflow.bal` and `functions.bal` was deleted.

**After the merge**, `openapi_workflow.bal` contains:
1. All imports (the seven cross-module imports from `functions.bal` merged with the `utils` import already in `openapi_workflow.bal`)
2. `runOpenApiWorkflow(openApiSpec, outputDir, logLevel)` — the `public` entry point called by Java
3. `executeOpenApiPipeline(openApiSpec, outputDir, logLevel)` — the private 6-step pipeline body

The Java invocation path is unchanged: `BallerinaRuntimeUtils.callBallerinaFunction(...)` still resolves `runOpenApiWorkflow` by name at runtime from the `wso2/connector_automator` module.

The invocation diagram in "Two-Layer Invocation Model" section above is now simplified:

```
openapi_workflow.bal
  runOpenApiWorkflow(spec, outputDir, logLevel)        [public — Java entry point]
    └─▶ executeOpenApiPipeline(spec, outputDir, logLevel)  [private — 6-step pipeline]
```

The intermediate hop through the now-deleted `functions.bal` is gone.

---

## YAML→JSON Conversion — Backtick Fix

### Why the conversion exists

`sanitizor:executeSanitizor` produces `aligned_ballerina_openapi.json`, which all downstream steps (steps 2–6) read exclusively. When the input spec is YAML, `bal openapi flatten` and `bal openapi align` always emit YAML. `convertAlignedYamlToJson` bridges the gap using Ballerina's built-in `yaml:readString` to parse the aligned YAML file and write the JSON output.

### Why Ballerina's YAML parser fails on real-world specs

Ballerina uses a YAML 1.1 parser. YAML 1.1 reserves the backtick character (U+0060) as a future indicator — it cannot appear in a plain scalar value. OpenAPI spec descriptions commonly contain Markdown code spans (`` `name` ``, `` `limit` ``, `` `format` ``). These cause `yaml:readString` to hard-fail on the first line containing a backtick.

Before this fix, the failure was swallowed by the `autoYes=true` gate (see § above), causing all six pipeline steps to fail silently with no clear root cause. After removing `autoYes`, the failure became a hard abort, making the root cause visible and fixable.

### Why single-quote is not a safe replacement

The first candidate replacement was single-quote (U+0027). Single-quote is a YAML flow scalar indicator. When it appears at the start of a word in a plain-scalar continuation line — exactly the pattern produced by `` `name` used when creating the resource `` → `'name' used when creating the resource` — the parser interprets it as a new flow-scalar token and fails with `Expected a key for the block mapping.`

Double-quote (U+0022) fails for the same reason. Asterisk (U+002A) fails because it is a YAML alias indicator.

### Sandbox testing

Six candidate replacements were tested against the actual 33,784-line aligned YAML file (Twilio Conversations API) using a standalone Ballerina program before committing:

| Replacement | Code point | Result |
|------------|-----------|--------|
| raw (backtick intact) | U+0060 (96) | FAIL |
| single-quote | U+0027 (39) | FAIL — YAML flow scalar token |
| asterisk | U+002A (42) | FAIL — YAML alias indicator |
| double-quote | U+0022 (34) | FAIL — YAML flow scalar token |
| space | U+0020 (32) | PASS |
| underscore | U+005F (95) | PASS |
| removal | — | PASS |

### The fix

Code-point mapping replaces each backtick (U+0060, decimal 96) with underscore (U+005F, decimal 95):

```ballerina
if jsonData is yaml:Error {
    // Ballerina YAML 1.1 rejects backtick (U+0060) in plain scalars — reserved indicator.
    // Single-quote/double-quote/asterisk are also unsafe (YAML token characters).
    // Underscore is safe and preserves code-span readability: `name` → _name_.
    int[] sanitizedCodePoints = from int cp in yamlContent.toCodePointInts()
        select (cp == 96 ? 95 : cp);
    string|error sanitizedContent = string:fromCodePointInts(sanitizedCodePoints);
    if sanitizedContent is string {
        json|yaml:Error retryData = yaml:readString(sanitizedContent);
        if retryData is json {
            // write JSON and return
        }
    }
    // falls through to yq fallback, then python3 fallback, then hard error
}
```

`regex:replaceAll` was considered but rejected: the `\x60` hex escape in Ballerina's regex engine has ambiguous behaviour and was unreliable in testing. The `toCodePointInts()` / `fromCodePointInts()` round-trip is character-precise and unambiguous.

Underscore was chosen over space and removal because `` `name` `` → `_name_` preserves the code-span intent in a way that is still legible for downstream AI processing.

### Fallback chain

If the code-point remapping still fails (other problematic characters in a spec not seen during testing), the function falls through to:
1. `yq -o=json '.' <file>` — system `yq` tool
2. `python3 -c 'import yaml,json; ...'` — Python YAML parser
3. Hard `error?` propagated up to `executeOpenApiPipeline`, which aborts the pipeline at step 1

The fallback chain predates this fix; the new primary path (Ballerina parser with backtick substitution) runs before the fallbacks.
