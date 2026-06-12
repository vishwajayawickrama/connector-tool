# Code Fixer Module — Architecture & Internals

> **Package:** `wso2/connector_automator`
> **Location:** `connector-core/connector-automator/modules/code_fixer/`

---

## Overview

The `code_fixer` module is an iterative, AI-assisted compilation repair engine. It sits between code generation and packaging — after a Ballerina client or Java native adaptor is generated, the output almost never compiles cleanly on the first pass. `code_fixer` detects those failures, sends the broken code and error diagnostics to an LLM, applies the suggested patch, and re-compiles, looping until the project is clean or no further progress can be made.

It handles two distinct languages with separate pipelines:

| Pipeline | Entry Point | Build Tool | Language |
|----------|------------|------------|----------|
| Ballerina | `fixAllErrors()` | `bal build` | `.bal` source files |
| Java native adaptor | `fixJavaNativeAdaptorErrors()` | Gradle | `.java` source files |

---

## File Map

```
modules/code_fixer/
├── types.bal       — All record and type definitions
├── execute.bal     — Public entry point: executeCodeFixer(), user confirmation
├── prompts.bal     — LLM prompt builders for Ballerina and Java
└── code_fixer.bal  — All core logic (2 000+ lines)
```

---

## Type System

Defined in `types.bal`:

```
FixResult              — Return value from fixAllErrors / fixJavaNativeAdaptorErrors
  .success             bool — true if final build passes
  .errorsFixed         int  — total errors resolved
  .errorsRemaining     int  — errors still unresolved
  .ballerinaErrorsFixed / ballerinaErrorsRemaining
  .javaErrorsFixed     / javaErrorsRemaining
  .appliedFixes[]      string[] — description of each fix applied
  .remainingFixes[]    string[] — description of errors not fixed

CompilationError       — Single parsed error from compiler output
  .filePath            string  — relative or absolute path
  .line / .column      int     — position in file
  .message             string  — compiler error message
  .severity            string  — "ERROR" | "WARNING"
  .language            string  — "ballerina" | "java"  (default "ballerina")
  .sourceTool          string  — "bal" | "gradle"      (default "bal")
  .code?               string? — optional error code

FixRequest             — Input to a single-file fix operation
  .projectPath / .filePath / .code / .errors[] / .language

FixResponse            — LLM output for a single-file fix
  .success             bool
  .fixedCode           string  — full replacement file content
  .explanation         string

FixAttempt             — One iteration's attempt on a single file
  .iteration / .errorMessages[] / .appliedFix

BallerinaFixerError    — type alias for error (used in union return types)

JavaEditOperation      — Internal: parsed JSON patch from LLM
  .startLine / .endLine / .replacement[]  (1-based, inclusive)
```

---

## Who Calls This Module and When

### Caller 1 — `example_generator` (`modules/example_generator/analyzer.bal`)

Called in two contexts:

**`fixExampleCode(exampleDir, logLevel)`** — after generating a use-case example `.bal` file:
```
generateExample()
  └─ fixExampleCode(exampleDir, logLevel)
        └─ code_fixer:fixAllErrors(exampleDir, "quiet", autoYes: true)
```
The example generator always passes `"quiet"` and `autoYes=true` — it's a fully automated pipeline step with no user interaction.

**`prepareNativeInteropForPack(connectorPath, logLevel)`** — when packing a connector that has a Java native adaptor and the initial Gradle build fails:
```
packConnector()
  └─ gradleBuildFails?
        └─ prepareNativeInteropForPack(connectorPath, logLevel)
              ├─ code_fixer:fixJavaNativeAdaptorErrors(connectorPath, "quiet", autoYes: true)
              │     [attempt 1: fix from connectorPath]
              ├─ if still failing:
              │     code_fixer:fixJavaNativeAdaptorErrors(nativeDir, "quiet", autoYes: true)
              │     [attempt 2: fix from nativeDir directly]
              └─ code_fixer:fixAllErrors(ballerinaDir, "quiet", autoYes: true)
                    [fix Ballerina side after Java changes]
```

### Caller 2 — `test_generator` (`modules/test_generator/ai_generator.bal`)

Called after generating mock server tests:

**`fixTestFileErrors(ballerinaDir, logLevel)`** — repairs test files that fail `bal build`:
```
generateMockServerTests()
  └─ fixTestFileErrors(ballerinaDir, logLevel)
        └─ code_fixer:fixAllErrors(ballerinaDir, logLevel, autoYes: true)
```

**`sdkFixTestFileErrors(ballerinaDir, logLevel)`** — same but for SDK workflow:
```
generateSDKTests()
  └─ sdkFixTestFileErrors(ballerinaDir, logLevel)
        └─ code_fixer:fixAllErrors(ballerinaDir, logLevel, autoYes: true)
```

**`sdkFixBalTestCompilationErrors(ballerinaDir, diagnostics, logLevel)`** — targeted repair when `bal test` fails (not `bal build`). Instead of running a fresh build, it parses already-captured `bal test` output:
```
sdkFixBalTestCompilationErrors(ballerinaDir, diagnostics, logLevel)
  ├─ code_fixer:parseCompilationErrors(diagnostics)       → CompilationError[]
  ├─ code_fixer:groupErrorsByFile(errors)                 → map<CompilationError[]>
  ├─ for each file:
  │     code_fixer:fixFileWithLLM(ballerinaDir, filePath, errors, logLevel)
  └─     code_fixer:applyFix(ballerinaDir, filePath, fixedCode, logLevel)
```
This is the only caller that drives `fixFileWithLLM` and `applyFix` directly rather than going through a top-level entry point.

### Summary

| Caller | Function Called | When | logLevel |
|--------|----------------|------|----------|
| `example_generator` | `fixAllErrors` | After generating each example | `"quiet"` |
| `example_generator` | `fixJavaNativeAdaptorErrors` | Gradle build fails during pack | `"quiet"` |
| `example_generator` | `fixAllErrors` | After Java fixes, re-check Ballerina side | `"quiet"` |
| `test_generator` | `fixAllErrors` | After generating mock tests | caller's `logLevel` |
| `test_generator` | `parseCompilationErrors` + `fixFileWithLLM` + `applyFix` | After `bal test` fails | caller's `logLevel` |

---

## Ballerina Fix Pipeline — `fixAllErrors`

### Signature

```ballerina
public function fixAllErrors(
    string projectPath,
    utils:LogLevel logLevel = "quiet",
    boolean autoYes = false
) returns FixResult|BallerinaFixerError
```

### Flow

```
fixAllErrors(projectPath, logLevel, autoYes)
│
├── 1. Initialize AI service if not already up
│       utils:initAIService(logLevel)
│
├── 2. Pre-cleanup: remove any stale *_backup*.bak files
│       cleanupFixerBackups(projectPath, logLevel)
│       [graceful: warns on failure, continues]
│
└── 3. Iteration loop (max: maxIterations)
    │
    ├── A. Build
    │       executeBalBuild(projectPath)
    │         → runs: bal build
    │         → returns: {success, stdout, stderr}
    │
    ├── B. Parse errors from stderr
    │       parseCompilationErrors(stderr)
    │         → regex: ERROR [filePath:(line:col)] message
    │         → returns: CompilationError[]
    │
    ├── C. Filter eligible files
    │       isEligibleBallerinaSourcePath(filePath)
    │         → allows: client.bal, types.bal, main.bal, test.bal
    │         → rejects: target/, build/, backup files, everything else
    │
    ├── D. Check for interop CLASS_NOT_FOUND errors
    │       isInteropClassNotFoundError(err)
    │         → if all errors are Java interop issues:
    │            log warning, break loop (Java must be fixed first)
    │
    ├── E. Detect stagnation
    │       checkIfErrorsAreSame(currentErrors, previousErrors)
    │         → if errors unchanged from last iteration: break
    │
    ├── F. Group errors by file
    │       groupErrorsByFile(errors)
    │         → map<CompilationError[]>: filePath → errors
    │
    ├── G. Fix each file
    │       for each filePath → fileErrors in map:
    │         fixFileWithLLM(projectPath, filePath, fileErrors, logLevel, history)
    │           → FixResponse { fixedCode, explanation }
    │         applyFix(projectPath, filePath, fixedCode, logLevel)
    │           → creates backup, writes fix, removes backup on success
    │
    └── H. Final build check + post-cleanup
            executeBalBuild(projectPath)
            cleanupFixerBackups(projectPath, logLevel)
            return FixResult
```

### Stagnation & Loop Termination

The loop stops when any of these is true:
- Final `bal build` succeeds (`exitCode == 0`)
- `maxIterations` reached
- All remaining errors are interop CLASS_NOT_FOUND (Java build must be fixed first)
- Errors are identical to the previous iteration (`checkIfErrorsAreSame`)

`checkIfErrorsAreSame` sorts both error arrays by `filePath:line:column` and compares element-by-element.

---

## Java Fix Pipeline — `fixJavaNativeAdaptorErrors`

### Signature

```ballerina
public function fixJavaNativeAdaptorErrors(
    string projectPath,
    utils:LogLevel logLevel = "quiet",
    boolean autoYes = true,
    int iterationLimit = maxIterations
) returns FixResult|BallerinaFixerError
```

### Flow

```
fixJavaNativeAdaptorErrors(projectPath, logLevel, autoYes, iterationLimit)
│
├── 1. Initialize AI service
│
├── 2. Pre-cleanup: remove stale backups
│
└── 3. Iteration loop (max: iterationLimit)
    │
    ├── A. Gradle build
    │       runGradleBuild(projectPath)
    │         → detects gradlew location (current dir or parent)
    │         → resolves JAVA_HOME (JDK-21 or via javac symlink)
    │         → runs: ./gradlew clean build --console=plain --no-daemon
    │         → returns: {success, stdout, stderr}
    │
    ├── B. Parse Java errors from stderr
    │       parseJavaCompilationErrors(stderr, projectPath)
    │         → handles two formats:
    │            Format 1: "File.java:line: error: message"
    │            Format 2: ".java:line" pattern
    │         → normalizes paths relative to projectPath
    │         → skips backup artifact paths
    │         → returns: CompilationError[] (language="java")
    │
    ├── C. Detect stagnation
    │       checkIfErrorsAreSame(current, previous)
    │
    ├── D. Group errors by file + fix each file
    │       groupErrorsByFile(errors) → map
    │       for each file:
    │         fixFileWithLLM(..., logLevel, ...) → FixResponse
    │         applyFix(...) → bool|error
    │
    └── E. Final build + post-cleanup
            return FixResult
```

### Gradle Wrapper Resolution

`runGradleBuild` checks for `gradlew` in this order:
1. `{projectPath}/gradlew` — normal case
2. `{projectPath}/../gradlew` — SDK workflow: `native/` dir has no local wrapper, it lives at the connector root
3. `../../sdkanalyzer/native/gradlew` — fallback
4. `/usr/bin/gradle` or system `gradle`

JAVA_HOME is resolved:
1. Hard-coded: `/usr/lib/jvm/java-21-openjdk-amd64` (Linux CI)
2. Via symlink: `readlink -f $(command -v javac)` then walk up two directories

---

## Single-File Fix Engine — `fixFileWithLLM`

This is where the actual AI repair happens. It dispatches to different strategies depending on the error language.

### Signature

```ballerina
public function fixFileWithLLM(
    string projectPath,
    string filePath,
    CompilationError[] errors,
    utils:LogLevel logLevel = "quiet",
    FixAttempt[] previousAttempts = []
) returns FixResponse|error
```

### Ballerina Path

```
fixFileWithLLM (Ballerina)
│
├── Read full file content
├── Get type context (for test/mock files):
│     getTypeContextForFile() reads:
│       - types.bal (type definitions)
│       - modules/mock.server/*.bal (mock server types)
│       - client.bal (function signatures)
├── Build fix history context from previousAttempts
├── Build LLM prompt:
│     createFixPromptWithHistory(code, errors, filePath, typeContext, history)
│       → includes: error list, full file code, coding rules, test rules,
│                   reflection phase, fix history to avoid repeating failures
│       → instructs LLM: return ONLY raw .bal code, no markdown
├── Call LLM:
│     utils:callAI(prompt) → string
├── Normalize response:
│     normalizeCodeResponse() strips markdown fences
└── Return FixResponse { success: true, fixedCode, explanation }
```

### Java Path (Multi-Strategy)

The Java path tries strategies in sequence, stopping at the first success:

```
fixFileWithLLM (Java)
│
├── Strategy 0: Deterministic (no LLM needed)
│     applyDeterministicJavaCompileFixes(originalCode, errors)
│       → pattern: "unreported exception ... must be caught or declared"
│       → fix: add catch block or add throws to interface method
│     → validate with validateJavaFixCandidate()
│     → if passes: return immediately (fastest, most reliable)
│
└── Strategies 1–3: LLM attempts (up to 3 tries)
    │
    ├── Build Java-specific prompt:
    │     createJavaFixPrompt(code, errors, filePath, validationFailure, previousCandidate, attempt)
    │       → includes: error region snippet with >>> markers on error lines
    │       → includes: import section of the file
    │       → instructs LLM: return JSON array of edit operations, NOT full file
    │       → on retry (attempt > 1): includes validation failure reason + previous candidate
    │
    ├── Call LLM → JSON response
    │
    ├── Parse JSON edit operations:
    │     normalizeJsonResponse() strips markdown
    │     parseJavaEditOperations() validates + sorts bottom-to-top
    │       → each op: { startLine, endLine, replacement: string[] }
    │
    ├── Apply edits:
    │     applyJavaEditOperations(originalCode, sortedOps)
    │       → applies from bottom to top (line numbers stay valid)
    │
    ├── Validate result:
    │     validateJavaFixCandidate(original, candidate, filePath, errorCount)
    │       → checks: non-empty, package preserved, class name preserved,
    │                 method count not halved, ≥70% length preserved,
    │                 balanced braces, ends with }, changed lines ≤ max(24, errorCount×12)
    │
    ├── If validation fails → retry with failure feedback (next attempt)
    │
    ├── If all 3 attempts fail validation:
    │     Fallback A: applyLocalizedJavaMerge(original, lastCandidate, errors)
    │       → for each error line N: replace lines [N-4, N+4] from candidate into original
    │       → accepts any change that doesn't break the rest of the file
    │     Fallback B: applyStructuralSafeJavaMerge(original, lastCandidate, errors)
    │       → same window approach but validates each line replacement is "structurally safe"
    │         (no package/import/class/brace changes, parenthesis balance unchanged)
    │       → validates final braces are balanced before accepting
    │
    └── If all strategies fail → return error
```

### Java Prompt Design (Edit Operations vs Full File)

Unlike Ballerina (which asks for the full fixed file), the Java prompt asks for **JSON edit operations**:

```json
[
  { "startLine": 42, "endLine": 44, "replacement": ["    } catch (IOException e) {", "        throw new RuntimeException(e);", "    }"] },
  { "startLine": 15, "endLine": 15, "replacement": ["    Object call() throws Exception;"] }
]
```

Operations are applied **bottom-to-top** (sorted by descending `startLine`) so earlier line numbers remain valid as later edits are applied.

This design minimizes the risk of the LLM accidentally dropping large sections of a long Java file.

---

## Validation — `validateJavaFixCandidate`

Before accepting any LLM-generated Java fix (whether from direct edit ops or merge fallbacks), every candidate passes through:

| Check | Rule | Rejection Reason |
|-------|------|-----------------|
| Non-empty | length > 0 | LLM returned nothing |
| Package preserved | first `package ...;` line unchanged | LLM changed package declaration |
| Class name preserved | `class ClassName` unchanged | LLM renamed the class |
| Method count | candidate has ≥ 50% of original's method anchors | LLM dropped methods |
| Length ratio | candidate ≥ 70% of original length | LLM truncated the file |
| Balanced braces | `{` count == `}` count, never goes negative | Syntactically incomplete |
| Ends with `}` | last non-blank line is `}` | Truncated output |
| Line change limit | changed lines ≤ `max(24, errorCount × 12)` | LLM rewrote too much |

On failure the reason string is fed back into the next LLM prompt attempt.

---

## File Apply — `applyFix`

Every fix goes through a safe backup-restore cycle:

```
applyFix(projectPath, filePath, fixedCode, logLevel)
│
├── 1. Read original file content
├── 2. Compute backup path: file_backup.ext.bak
│        e.g. client.bal → client_backup.bal.bak
├── 3. Write original content to backup
├── 4. Write fixedCode to original path
├── 5a. On success: remove backup, return true
└── 5b. On any write error: restore from backup, return error
```

Backup files are named with `getBackupPath()`:
- `file.bal` → `file_backup.bal.bak`
- `File.java` → `File_backup.java.bak`
- `no_extension` → `no_extension_backup.bak`

Stale backups from previous failed runs are cleaned up at the start and end of every `fixAllErrors` / `fixJavaNativeAdaptorErrors` call via `cleanupFixerBackups` → `removeBackupFilesRecursive`.

---

## Error Parsing

### Ballerina — `parseCompilationErrors`

Parses `bal build` stderr. Pattern:

```
ERROR [path/to/file.bal:(14:5,14:25)] undefined symbol 'foo'
```

Regex extracts: `filePath`, `line`, `column`, `message`. Sets `language="ballerina"`, `sourceTool="bal"`.

### Java — `parseJavaCompilationErrors`

Handles two Gradle/javac output formats:

**Format 1** (standard javac):
```
/abs/path/File.java:42: error: cannot find symbol
```

**Format 2** (Gradle diagnostic):
```
src/main/java/Adaptor.java:15
```

Paths are normalized relative to `projectPath`. Backup artifact paths are skipped. Sets `language="java"`, `sourceTool="gradle"`.

---

## Shell Command Execution

### `executeShellCommand`

All subprocess invocations (both `bal build` and Gradle) go through one function:

```ballerina
function executeShellCommand(workingDir, shellCommand)
    returns record {int exitCode; string stdout; string stderr;}|error
```

Implementation:
1. Computes absolute paths for two temp log files: `workingDir/.code_fixer.stdout.log` and `workingDir/.code_fixer.stderr.log`
2. Runs: `bash -c "cd \"$0\" && {shellCommand} > \"$1\" 2> \"$2\"" workingDir .code_fixer.stdout.log .code_fixer.stderr.log`
3. Waits for exit via `process.waitForExit()`
4. Reads stdout/stderr from the temp files (silently falls back to `""` if a file is missing)
5. Deletes temp files via `cleanupCommandLogs`
6. Returns `{exitCode, stdout, stderr}`

Using redirect-to-file (rather than pipes) avoids pipe buffer limits on large compiler output.

### `executeBalBuild`

Thin wrapper around `executeShellCommand`:
```
executeBalBuild(projectPath)
  → executeShellCommand(projectPath, "bal build")
  → returns {success: exitCode==0, stdout, stderr}
```

### `runGradleBuild`

More complex — detects Gradle wrapper location, resolves JAVA_HOME, builds a compound shell script, then calls `executeShellCommand`.

---

## LLM Integration

All LLM calls go through `utils:callAI(prompt)` from the shared `utils` module. The `code_fixer` module never calls the AI SDK directly.

### Prompt Files

| File | Prompts Defined |
|------|----------------|
| `prompts.bal` | `createFixPrompt` (Ballerina full-file), `createFixPromptWithContext`, `createFixPromptWithHistory`, `createJavaFixPrompt` (Java JSON ops) |

Key prompt characteristics:
- **Ballerina prompt**: includes full file content + all errors + coding rules (no external HTTP calls, no `check` on `println`, return types must match, etc.) + test-specific rules + fix history
- **Java prompt**: includes only the error region (±N lines around each error line, with `>>>` markers) + imports section + instructions to return JSON edit ops + validation failure feedback on retry

### LLM Response Logging (Debug)

When `enableLLMResponseLogs = true` (compile-time constant), every LLM interaction is logged to:
```
{projectPath}/.code_fixer_llm_logs/{sanitized_filename}.attempt-N.{phase}.log
```
Where `phase` is one of: `raw-response`, `parse-failure`, `patched-result`, `validation-result`.

---

## Internal Call Graph (Top-Level View)

```
executeCodeFixer()          ← external entry point (execute.bal)
  └─ fixAllErrors()

fixAllErrors()              ← Ballerina repair loop
  ├─ cleanupFixerBackups()
  │   └─ removeBackupFilesRecursive()
  ├─ executeBalBuild()
  │   └─ executeShellCommand()
  ├─ parseCompilationErrors()
  ├─ isEligibleBallerinaSourcePath()
  ├─ isInteropClassNotFoundError()
  ├─ checkIfErrorsAreSame()
  ├─ groupErrorsByFile()
  ├─ fixFileWithLLM()
  │   ├─ [Ballerina path]
  │   │   ├─ getTypeContextForFile()
  │   │   ├─ buildFixHistoryContext()
  │   │   ├─ createFixPromptWithHistory()
  │   │   ├─ utils:callAI()
  │   │   └─ normalizeCodeResponse()
  │   └─ [Java path]
  │       ├─ applyDeterministicJavaCompileFixes()
  │       ├─ validateJavaFixCandidate()
  │       ├─ createJavaFixPrompt()
  │       ├─ utils:callAI()
  │       ├─ normalizeJsonResponse()
  │       ├─ parseJavaEditOperations()
  │       ├─ applyJavaEditOperations()
  │       ├─ applyLocalizedJavaMerge()       ← fallback A
  │       └─ applyStructuralSafeJavaMerge()  ← fallback B
  ├─ applyFix()
  └─ printFixingSummary()

fixJavaNativeAdaptorErrors()   ← Java repair loop
  ├─ cleanupFixerBackups()
  ├─ runGradleBuild()
  │   └─ executeShellCommand()
  ├─ parseJavaCompilationErrors()
  ├─ checkIfErrorsAreSame()
  ├─ groupErrorsByFile()
  ├─ fixFileWithLLM()           ← same as above, Java path
  └─ applyFix()
```

---

## Error Return Semantics

### `fixAllErrors` / `fixJavaNativeAdaptorErrors`

Return `FixResult|BallerinaFixerError`.

- `FixResult` with `success=true` — final build passed
- `FixResult` with `success=false` — loop exhausted, errors remain (`.remainingFixes[]` lists what's left)
- `BallerinaFixerError` — fatal: AI service init failed, build command itself errored, etc.

Callers distinguish with a type-pattern match:

```ballerina
FixResult|BallerinaFixerError result = check code_fixer:fixAllErrors(projectPath, logLevel, true);
if result is BallerinaFixerError {
    // fatal — propagate up
    return error("Code fixer failed", result);
}
// result is FixResult
if !result.success {
    utils:logWarn(string `${result.errorsRemaining} errors remain after fixing`, logLevel);
}
```

### `fixFileWithLLM`

Returns `FixResponse|error`.
- `FixResponse { success: true, fixedCode }` — at least one strategy succeeded
- `error` — all strategies (deterministic + 3 LLM attempts + 2 merge fallbacks) failed

### `applyFix`

Returns `boolean|error`.
- `true` — fix written successfully
- `error` — file write failed (original restored from backup)

---

## Configuration Constants (compile-time)

Defined at the top of `code_fixer.bal`:

| Constant | Value | Meaning |
|----------|-------|---------|
| `maxIterations` | (value in source) | Max fix/build cycles before giving up |
| `enableLLMResponseLogs` | `false` | Write raw LLM responses to disk for debugging |

---

## Eligible Source Files (Ballerina)

`isEligibleBallerinaSourcePath` enforces which `.bal` files can be auto-fixed:

**Allowed:**
- `client.bal` — the generated Ballerina client
- `types.bal` — type definitions
- `main.bal` — SDK workflow entry
- `test.bal` — generated tests

**Excluded:**
- Anything in `target/` or `build/` directories
- Files matching `isBackupArtifactPath` (contain `_backup.`, end with `.backup` or `.bak`)
- Any other `.bal` files (modules, utilities) — touched only by generation, not repair

---

## Interaction with the Broader Pipeline

```
OpenAPI Workflow (functions.bal)
  Step 1: sanitizor
  Step 2: client_generator ──→ generates client.bal
  Step 3: bal build check                              ← exits pipeline if fails
  Step 4: example_generator
            └─ generateExample()
                 └─ code_fixer:fixAllErrors()          ← fixes each example
  Step 5: test_generator
            └─ generateMockServerTests()
                 └─ code_fixer:fixAllErrors()          ← fixes test files
  Step 6: document_generator

SDK Workflow (main.bal)
  sdkanalyzer → api_specification_generator → connector_generator
            └─ connector_generator generates:
                 ├─ ballerina/ (client.bal, types.bal)
                 └─ native/    (Java adaptor source)
  example_generator
    └─ prepareNativeInteropForPack()
         ├─ code_fixer:fixJavaNativeAdaptorErrors()    ← fix Java native adaptor
         └─ code_fixer:fixAllErrors()                  ← re-check Ballerina side
  test_generator
    └─ sdkFixTestFileErrors()
         └─ code_fixer:fixAllErrors()                  ← fix SDK test files
```

The code fixer is **never** in the main pipeline step chain — it is always called as a repair sub-step from within `example_generator` and `test_generator`. It does not have its own step banner in the pipeline output.

---

## Key Invariants

1. **Always use `autoYes=true` from pipeline callers** — the fixer can prompt for user confirmation (used in interactive/manual invocations), but pipeline callers always pass `autoYes=true`.

2. **Backup before every write** — `applyFix` never overwrites without first saving a backup. Stale backups from crashes are cleaned at loop start.

3. **Stagnation detection** — if the same errors appear twice in a row, the loop breaks. Without this, a bad LLM fix could oscillate indefinitely.

4. **Java uses edit ops, not full file** — the LLM is never asked to reproduce an entire Java file. It returns a minimal patch (JSON array of line ranges) to reduce hallucination risk.

5. **Validation before apply (Java only)** — every Java candidate is validated against the original before being written. Ballerina candidates are applied and then re-built (the build itself is the validator).

6. **LogLevel flows through, not boolean** — since the logging refactor, `fixAllErrors` and `fixJavaNativeAdaptorErrors` accept `utils:LogLevel`. Internal helpers that still use boolean flags (`runGradleBuild`, `executeBalBuild`) derive them locally with `logLevel == "quiet"` / `logLevel == "verbose"`.
