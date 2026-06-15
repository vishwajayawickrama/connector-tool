# Pipeline Stage Exclusion — Architecture & Design

## Overview

The `-x` / `--exclude` flag lets callers skip one or more stages of the OpenAPI pipeline. It can be repeated to exclude multiple stages:

```
bal connector openapi -i spec.yaml -o ./out -x tests
bal connector openapi -o ./out -x client -x tests    # -i not required when client is excluded
```

---

## Pipeline Stages (user-facing)

| Flag value | What it does |
|---|---|
| `sanitize` | Flatten + AI-align the spec; produce `aligned_ballerina_openapi.json` |
| `client` | Generate Ballerina client from spec **and** build/validate it (build is merged into this step) |
| `tests` | Generate mock server + test file |
| `examples` | Generate usage example projects |
| `docs` | Generate README files for the connector, tests, and examples |

### Build is merged into `client`

`bal build` runs immediately after client generation as the validation half of the same step. It is not a user-facing stage. Excluding `client` skips both generation and build.

---

## Artifact Map

Each stage reads and writes specific files. This is the basis for all dependency and fallback decisions.

| Stage | Reads | Writes |
|---|---|---|
| `sanitize` | Raw input spec (any path, JSON or YAML) | `outputDir/docs/spec/aligned_ballerina_openapi.json`<br>`outputDir/docs/spec/sanitations.md` |
| `client` | `outputDir/docs/spec/aligned_ballerina_openapi.json` | `outputDir/client.bal`<br>`outputDir/types.bal`<br>`outputDir/Ballerina.toml`<br>`outputDir/target/` (build artefacts) |
| `tests` | `aligned_ballerina_openapi.json`<br>`outputDir/client.bal`, `types.bal` | `outputDir/tests/test.bal`<br>`outputDir/modules/mock.server/mock_server.bal`<br>`outputDir/modules/mock.server/types.bal` |
| `examples` | `outputDir/client.bal`, `Ballerina.toml` (also packs + pushes connector to local repo) | `examplesDir/<name>/main.bal`<br>`examplesDir/<name>/Ballerina.toml` |
| `docs` | `outputDir/client.bal`, `types.bal`<br>Optionally: `outputDir/tests/` and `examplesDir/` if they exist | `outputDir/README.md`<br>`outputDir/tests/README.md` *(only if tests not excluded)*<br>`examplesDir/README.md` *(only if examples not excluded)*<br>`examplesDir/<name>/README.md` per example |

---

## Dependency Graph

```
sanitize ──► client (+ build) ──► tests
                      │
                      ├──────────► examples
                      │
                      └──────────► docs
                                    ├── (tests README — only if tests not excluded)
                                    └── (examples README — only if examples not excluded)
```

`tests` has a dual dependency: it needs the aligned spec from `sanitize` **and** the client files from `client`.

---

## Sanitize + Client: Design Decision

### Decision: independently excludable stages with artifact-existence checks

`sanitize` and `client` are **separate, independently excludable** stages. There is no coupling rule. The protection against unsanitized specs comes from a hard preflight check — not from rejecting flag combinations.

**`-x sanitize` is allowed independently.** When it is excluded:
- The Java layer checks that `outputDir/docs/spec/aligned_ballerina_openapi.json` already exists on disk.
- If it does not exist → hard error before the Ballerina runtime starts.
- If it does exist → the pipeline uses it as-is; client re-generates from the already-aligned spec.
- There is **no fallback to the raw input spec**. The pipeline never generates a client from an unsanitized spec.

**`-x client` is allowed independently.** When it is excluded without `-x sanitize`:
- Sanitize still runs — it re-aligns the spec (and `-i` is still required for this).
- Client is skipped; the downstream stages reuse the existing `client.bal`.

**`-i` is only required when `sanitize` is running** (not excluded). When `sanitize` is excluded, `-i` is unused and not validated.

### Options considered

**Option A (chosen): separate, independently excludable stages**
- Maximum granularity: re-sanitize without regenerating client; or skip sanitize when the aligned spec is already good.
- Safety through artifact checks, not coupling rules.
- No `specForDownstream` fallback needed — aligned spec must exist or the run fails.

**Option B: merge sanitize and client into a single stage**
- Would prevent any re-sanitize-without-client workflow.
- Rejected: sanitization with AI batch processing is slow; forcing re-sanitize just to regenerate the client is wasteful on large specs.

**Option C: keep as separate stages but reject `-x sanitize` alone**
- Would prevent the combination where no aligned spec exists, but also prevents the valid use case of "skip sanitize, re-run client from the existing aligned spec."
- Rejected: the user can validly have an aligned spec on disk and want to skip re-sanitization.

---

## Exclusion Semantics: "skip and assume artifacts exist"

Excluding a stage means **its output artifacts are assumed to already be on disk** from a previous run. The pipeline skips the stage; downstream stages continue as if it had run. This matches the model used by Maven (`-DskipTests`), Gradle (`-x`), and Make (`-o`).

This is the right model for iterative development: run the full pipeline once, manually edit the generated client, then re-run with `-x sanitize -x client` to regenerate only tests and examples without overwriting your edits.

---

## Edge Cases

### Excluding `sanitize` alone

**Valid.** `-x sanitize` without `-x client` is accepted. The Java layer checks before the Ballerina runtime starts:

1. `outputDir/docs/spec/aligned_ballerina_openapi.json` must exist on disk.
2. If it does **not** exist → throw `CliException` (exit code 1):
   ```
   error: sanitize excluded but aligned spec not found at <path>
          run without -x sanitize to generate it first
   ```
3. If it **does** exist → client generates from it; `-i` is not required.

**There is no fallback to the raw input spec.** If the aligned spec is missing, it is always a hard error.

### Excluding `client`

`tests`, `examples`, and `docs` all need `client.bal`, `types.bal`, and `Ballerina.toml`. When `client` is excluded, the existence of `client.bal` is checked **in the Java layer, before the Ballerina runtime is started**:

1. Check that `outputDir/client.bal` exists.
2. If it does **not** exist → throw `CliException` (exit code 1) immediately:
   ```
   error: client stage excluded but no existing client found at <outputDir>/client.bal
          run without -x client to generate it first
   ```
3. If it **does** exist (from a previous run) → call `callBallerinaFunction` as normal.

**Why Java, not Ballerina:** The Ballerina runtime has a significant startup cost (JVM warmup, Ballerina stdlib loading, module initialisation). All other precondition checks in this codebase (`OpenApiPathValidationUtils`, `BallerinaProjectPathValidationUtils`, `ExamplesOutputPathValidationUtils`) are done in the Java layer for exactly this reason — fail before paying the startup cost. The `client.bal` existence check is a precondition of the same kind and follows the same pattern: validate at the CLI boundary, throw `CliException`, let the `catch` block in `execute()` handle formatting and exit.

### Excluding `tests`

- Safe. No downstream stage depends on test artefacts.
- The `docs` stage must **not** generate `tests/README.md` when `tests` is excluded. See [Docs partial generation](#docs-partial-generation) below.

### Excluding `examples`

- Safe. No downstream stage depends on example artefacts.
- The `docs` stage must **not** generate `examples/README.md` or per-example READMEs when `examples` is excluded. See [Docs partial generation](#docs-partial-generation) below.

### Excluding `docs`

- Safe. Terminal stage with no downstream dependents.

### Excluding `client` alone (without `-x sanitize`)

Sanitize still runs — it re-aligns the spec and writes `aligned_ballerina_openapi.json`. Because sanitize runs, **`-i` is still required**. The Java-layer preflight checks, in order:

1. `-i` is validated (sanitize needs it).
2. `client.bal` existence check — if `outputDir/client.bal` does not exist, throw `CliException`.

Downstream stages (`tests`, `examples`, `docs`) reuse the existing `client.bal`.

### Excluding both `sanitize` and `client`

Only `tests`, `examples`, and `docs` run. The Java-layer preflight checks, in order:

1. `aligned_ballerina_openapi.json` existence check — must exist for `tests` to use.
2. `client.bal` existence check — must exist for all downstream stages.
3. `-i` is **not validated** — no running stage reads the raw input spec.

The primary use case is "regenerate tests, examples, and docs against an already-built client without re-touching the spec or client."

### Excluding `tests` + `examples` + `docs`

Only `sanitize` and `client` run. Perfectly valid — "just regenerate the client."

### Excluding all five stages

Hard error before the pipeline starts:

```
error: all pipeline stages excluded — nothing to run
```

### Unknown stage name

Hard error before the pipeline starts:

```
error: unknown stage 'foobar'. Valid stages: sanitize, client, tests, examples, docs
```

---

## Docs Partial Generation

The `docs` stage generates a README for each part of the connector that was produced. When an upstream stage is excluded, the corresponding doc section must also be skipped — there is no point regenerating documentation for a stage whose output was not touched in this run.

| Stage excluded | Doc section skipped |
|---|---|
| `client` | `outputDir/README.md` (the main connector README) |
| `tests` | `outputDir/tests/README.md` |
| `examples` | `examplesDir/README.md` and all `examplesDir/<name>/README.md` |

These conditions are independent and additive — any combination of exclusions results in the corresponding doc sections being skipped.

Implementation: pass the `excluded` array down to `executeDocGen` and gate each sub-generation call:
```ballerina
if excluded.indexOf("client") is () {
    // generate outputDir/README.md
}
if excluded.indexOf("tests") is () {
    // generate outputDir/tests/README.md
}
if excluded.indexOf("examples") is () {
    // generate examplesDir/README.md and per-example READMEs
}
```

---

## Step Number Display

When stages are excluded, fixed step numbers (`[1/6]`, `[2/6]`, …) create gaps in the output (`[1/6]` then `[4/6]`). Instead:

- Compute the **active stage count** at pipeline start (total stages minus excluded).
- Number running steps sequentially within the active set.
- Log excluded stages as a single line before the pipeline starts:
  ```
  skipping stages: sanitize, tests
  [1/4] Generating Ballerina Client
  [2/4] Generating Examples
  [3/4] Generating Documentation
  ```

This matches the UX of GitHub Actions and Gradle's task output.

---

## Implementation Plan

### Java layer (`connector-cli`)

**`OpenApiAutomatorWorkflow.java`**
```java
@CommandLine.Option(
    names = {"-x", "--exclude"},
    description = "Exclude a pipeline stage. Repeatable. Valid: sanitize, client, tests, examples, docs.",
    paramLabel = "STAGE"
)
public List<String> excludedStages = new ArrayList<>();
```

In `execute()`, before calling `callBallerinaFunction`:
1. Validate each name against `Set.of("sanitize","client","tests","examples","docs")` — fail fast on unknown names.
2. If `excludedStages.size() == 5` — fail fast with "all stages excluded" error.
3. If `excludedStages.contains("sanitize") && !excludedStages.contains("client")` — fail fast: cannot exclude sanitize without also excluding client.
4. If `excludedStages.contains("client")` — check that `ballerinaProjectPath.resolve("client.bal")` exists; if not, throw `CliException` with exit code 1 and a clear remediation message.
5. Validate `-i` **only when `client` is not excluded** — `OpenApiPathValidationUtils.validate(inputPath)` is called conditionally; when `client` is excluded no running stage needs the raw spec so `-i` is optional and its absence is not an error.
6. Pass excluded stages as comma-separated string to `callBallerinaFunction` (new parameter).

All steps throw `CliException` and are caught by the existing `catch (CliException e)` block — no new error-handling plumbing needed. The Ballerina runtime is never started if any check fails.

**`BallerinaRuntimeUtils.callBallerinaFunction`**

Add `String excludedStages` parameter; pass as a `BString` arg to `runOpenApiGenerationWorkflow`.

### Ballerina layer (`openapi_workflow.bal`)

**`runOpenApiGenerationWorkflow`**
```ballerina
public function runOpenApiGenerationWorkflow(string openApiSpec, string outputDir,
        string logLevel, string examplesDir, string excludedStages) returns error? {
    utils:LogLevel level = ...;
    string[] excluded = excludedStages.length() == 0 ? [] : re`,`.split(excludedStages);
    return runOpenApiGenerationWorkflow(openApiSpec, outputDir, examplesDir, level, excluded);
}
```

**`runOpenApiGenerationWorkflow`**

Add `string[] excluded = []` parameter. At the top:

```ballerina
// Compute active stage list and sequential step numbers
// Note: client.bal existence is already validated in the Java layer before this runs.
string[] allStages = ["sanitize", "client", "tests", "examples", "docs"];
string[] activeStages = allStages.filter(s => excluded.indexOf(s) is ());
int total = activeStages.length();
int step = 0;

if excluded.length() > 0 {
    utils:logInfo(string `skipping stages: ${string:'join(", ", ...excluded)}`, logLevel);
}
```

Each stage block:
```ballerina
if excluded.indexOf("sanitize") is () {
    step += 1;
    utils:logStep(step, total, "Sanitizing OpenAPI Specification", logLevel);
    // ... run sanitize ...
} else {
    utils:logVerbose("skipping sanitize (excluded)", logLevel);
    // no fallback needed — sanitize alone is rejected in Java, so if we reach here
    // client is also excluded and aligned_ballerina_openapi.json is already on disk
}
```

The aligned spec path is always the fixed location — no fallback logic needed because `-x sanitize` alone is rejected in Java before this code runs:
```ballerina
string sanitizedSpec = string `${outputDir}/docs/spec/aligned_ballerina_openapi.json`;
```

Docs stage passes excluded set:
```ballerina
if excluded.indexOf("docs") is () {
    step += 1;
    utils:logStep(step, total, "Generating Documentation", logLevel);
    error? docResult = document_generator:executeDocGen("generate-all", outputDir, excluded, logLevel);
    ...
}
```

**`document_generator:executeDocGen`**

Add `string[] excluded = []` parameter. Gate each sub-generation:
```ballerina
if excluded.indexOf("client") is () {
    // generate outputDir/README.md
}
if excluded.indexOf("tests") is () {
    // generate outputDir/tests/README.md
}
if excluded.indexOf("examples") is () {
    // generate examplesDir/README.md and per-example READMEs
}
```

### No changes needed in modules

`sanitizor`, `client_generator`, `test_generator`, `example_generator` — all exclusion logic lives in the pipeline orchestrator (`openapi_workflow.bal`). Modules stay unaware of the skip concept.

---

## What is not in scope

- SDK workflow — the `-x` flag applies to the OpenAPI workflow only for now.
- Dependency cascade (auto-excluding downstream when upstream is excluded) — deliberately not implemented; "continue on error" handles it gracefully.
- `--only` / `--from` / `--to` range flags — can be added later as sugar over `-x`.
