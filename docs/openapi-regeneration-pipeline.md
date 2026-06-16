# OpenAPI Regeneration — Architecture Reference

This document covers how `runOpenApiGenerationWorkflow` (`openapi_workflow.bal`) handles regenerating an existing connector from an updated OpenAPI spec, and the `sanitations.md` mechanism that drives it. For module-by-module details (sanitizor, client_generator, etc.) see `CLAUDE.md` and `openapi-workflow-architecture.md`.

---

## Why regeneration needs no separate entry point

A fresh run (blank output directory) and a regeneration run (existing connector, updated spec) go through the exact same function — `runOpenApiGenerationWorkflow`. The behaviors that matter for regeneration are unconditional parts of that function and are no-ops on a fresh project:

1. **Sanitations replay** — `sanitations.md` captures every connector-specific transform from prior runs (server URL rewrites, prefix removals, type renames). If it exists at `${specDir}/sanitations.md`, it's applied to the incoming spec before sanitization so those decisions survive spec updates automatically. On a fresh project the file doesn't exist yet, so this step is skipped (non-fatal either way).
2. **Tests always rewritten** — `test_generator:executeOpenApiTestGen` overwrites all test/mock files whenever it runs, so a plain independent Stage 3 that always runs after the client build succeeds is sufficient to pick up API surface changes from an updated spec. No special recovery logic is needed.

There used to be a separate `runOpenApiRegenWorkflow` mirroring the legacy nested-layout `runOpenApiRegenerationPipeline` in `main.bal` (lines ~1805–1894). That duplication was removed — `runOpenApiGenerationWorkflow` is now a strict superset covering both cases. The legacy `main.bal` function still exists for the legacy nested-layout CLI path (`bal tool-id openapi …` via `executeOpenApiCommand`) and is unrelated to this one.

---

## Ballerina entry point

```ballerina
public function runOpenApiGenerationWorkflow(string openApiSpec, string outputDir, string logLevel,
        string examplesDir, string excludedStages, string specDir) returns error?
```

- Parses `logLevel` → `utils:LogLevel level`
- Parses `excludedStages` (comma-separated) → `string[]`
- Logs verbose preamble (spec, output, specDir, examplesDir paths)
- Logs skipped stages if any
- Runs the full pipeline inline (no private delegate)

`specDir` is the spec output directory (e.g. `${outputDir}/docs/spec`), **already resolved by the Java layer** before the call. The Ballerina side uses it as-is.

Uses **flat layout**: `clientPath = outputDir`. Do not use `${outputDir}/ballerina` — that is the legacy CLI path in `main.bal` (nested layout only).

---

## Java invocation

Java always calls the same function — there is no flag-based routing:

```java
BallerinaRuntimeUtils.callBallerinaFunction(ORG, MODULE, VERSION, "runOpenApiGenerationWorkflow",
        openApiSpecPath != null ? openApiSpecPath.toString() : "",
        ballerinaProjectPath.toString(), logLevel,
        resolvedExamplesDir.toString(), excludedArg, specDirPath.toString());
```

Same 6-arg call every time, same `RuntimeException`-on-`BError` error propagation contract. `OpenApiStageValidationUtils` preflight checks apply uniformly — there's no separate "regen" preflight path since there's no separate regen mode to validate into.

---

## Stage counter design

```ballerina
string[] allStages = ["sanitize", "client", "tests", "examples", "docs"];
int total = allStages.filter(s => excluded.indexOf(s) is ()).length();
```

`client` and `tests` are always two independent counted stages — `total` is fixed regardless of exclusions. Stage 3 (tests) runs once, unconditionally, immediately after Stage 2 (client) completes — it is not interleaved into Stage 2's build-recovery branches.

---

## Pipeline steps in detail

### Setup (before any stage)

```ballerina
string sanitizedSpec    = string `${specDir}/aligned_ballerina_openapi.json`;
string sanitationsPath  = string `${specDir}/sanitations.md`;
string clientPath       = outputDir;  // flat layout
```

### Pre-step — apply recorded sanitations, if any exist (scoped to sanitize exclusion)

Only runs when `sanitize` is **not** excluded. If `sanitize` is excluded the user is reusing an existing aligned spec; replaying sanitations against the raw spec is pointless since sanitization won't run.

```ballerina
if excluded.indexOf("sanitize") is () {
    error? applyResult = sanitizor:applySanitations(sanitationsPath, openApiSpec, level);
    // non-fatal — missing sanitations.md (fresh project) or AI failure → continue with plain sanitization
}
```

`applySanitations` modifies `openApiSpec` **in-place** before `executeSanitizor` reads it. AI initialization lives inside `applySanitations` itself now (`sanitations_handler.bal`): it calls `utils:initAIService(logLevel)` right after confirming `sanitations.md` exists, then checks `utils:isAIServiceInitialized()` to choose the AI path vs. the rule-based fallback. This avoids initializing AI at all when there's no `sanitations.md` to apply (e.g. a fresh project) or when `sanitize` is excluded. `executeSanitizor` independently calls `initLLMService` (which wraps `initAIService`) for its own AI-assisted steps — re-initializing is idempotent and cheap.

### Stage 1 — Sanitize (CRITICAL)

```ballerina
sanitizor:executeSanitizor(openApiSpec, specDir, level)   // CRITICAL: returns error → abort
sanitizor:generateSanitationsDoc(openApiSpec, sanitizedSpec, specDir, level)  // non-fatal: writes/refreshes sanitations.md
```

Note: `executeSanitizor` receives `specDir` as the output directory (not `outputDir`). Sanitized output lands at `specDir/aligned_ballerina_openapi.json`. `generateSanitationsDoc` also uses `specDir` as its output base — this is what creates `sanitations.md` on a fresh run, making the *next* run on this directory a regeneration.

### Stage 2 — Client + build recovery

```
client_generator:executeClientGen(sanitizedSpec, clientPath, level)   [non-fatal]

utils:executeBalBuild(clientPath, level)
│
├── [clean build] → Stage 2 done, proceed to Stage 3
│
└── [compilation errors]
    code_fixer:fixAllErrors(clientPath, level, true)   [non-fatal attempt]
    │
    utils:executeBalBuild(clientPath, level)   [retry]
    │
    ├── [clean after fix] → Stage 2 done, proceed to Stage 3
    │
    └── [still failing] → CRITICAL: log error, return error(...) — pipeline aborts
```

### Stage 3 — Tests

A single independent, non-fatal step that runs once, immediately after Stage 2 completes (or immediately, if `client` is excluded):

```ballerina
if excluded.indexOf("tests") is () {
    step += 1;
    utils:logStep(step, total, "Generating Tests", level);
    error? testResult = test_generator:executeOpenApiTestGen(outputDir, sanitizedSpec, level);
    // non-fatal: logs a warning and continues if it fails
}
```

`test_generator:executeOpenApiTestGen` overwrites all test/mock files on every run, so there's no need to special-case stale tests after a spec update — the same call handles fresh generation and regeneration alike.

`code_fixer:fixAllErrors(clientPath, level, true)` is used directly, not `fixer:executeCodeFixer`. The third arg `true` enables the iterative fix loop.

### Stage 4 — Examples (non-fatal)

```ballerina
example_generator:executeExampleGen(outputDir, examplesDir, level)
```

`examplesDir` is threaded from the Java `--example-dir` flag.

### Stage 5 — Docs (non-fatal)

```ballerina
document_generator:executeDocGen("generate-all", outputDir, excluded, level)
```

Passes `excluded` through so the doc generator can skip individual readme types if their corresponding stage was skipped.

---

## `sanitations.md` mechanics

### What it records

Every transformation applied to the raw spec during sanitization: server URL changes, path prefix removals, type renames, nullability changes, format changes, AI-generated operationId and description additions. Written to `${specDir}/sanitations.md`.

### How it is generated — `sanitizor:generateSanitationsDoc`

Called after `executeSanitizor`. Diffs the original spec against the aligned spec.

- If `sanitations.md` **already exists**: `mergeWithExistingSanitations` — appends new sections, renumbers, deduplicates.
- If **new**: `buildSanitationsContent` — AI-generated descriptions, falls back to auto-detection.

### How it is applied — `sanitizor:applySanitations`

Called in the pre-step on the incoming raw spec, before `executeSanitizor` rewrites it.

**Primary path (AI available):** Sends both `sanitations.md` content and the new spec JSON to Claude. If spec ≤ `SPEC_SINGLE_TURN_THRESHOLD` chars: single-turn rewrite. If larger: chunked multi-turn (same strategy as `client_regenerator/analyze_version_change.bal`). Result written back to `newSpecPath` in-place.

**Fallback (AI unavailable):** `parseSanitationsMarkdown` extracts typed `SanitationRules`; `applyRulesToSpec` applies them programmatically.

```ballerina
type SanitationRules record {|
    ServerUrlChange[]    serverUrlChanges;
    PathPrefixRule[]     pathPrefixRules;
    TypeChange[]         typeChanges;
    NullabilityChange[]  nullabilityChanges;
    FormatChange[]       formatChanges;
|};
```

`utils:isAIServiceInitialized()` selects between the two paths — `applySanitations` calls `utils:initAIService` itself immediately beforehand, so this check always reflects the freshest init attempt for this call.

---

## `client_regenerator` module

Standalone CI utilities. **Not called from within the pipeline.** Runs after `runOpenApiGenerationWorkflow` exits, once changed files are staged in a branch.

| File | Entry | Purpose |
|------|-------|---------|
| `analyze_version_change.bal` | `main(diffFilePath)` | AI classifies git diff as MAJOR/MINOR/PATCH; produces structured change lists |
| `sort_ballerina_client.bal` | `runSortBallerinaClient(args)` | Sorts resource methods by path + HTTP method for stable diffs |
| `sort_ballerina_type.bal` | `runSortBallerinaType(args)` | Sorts type definitions alphabetically |
| `update_changelog.bal` | `runUpdateChangelog(prDescription)` | Generates/merges `CHANGELOG.md` `[Unreleased]` section |

See `docs/client-regenerator-architecture.md` for full details.

---

## Invariants

- `applySanitations` modifies the incoming spec **in-place**. It runs before `executeSanitizor`. The original file is overwritten — if the caller needs the raw spec preserved, it must copy it before invoking `runOpenApiGenerationWorkflow`.
- `applySanitations` initializes AI itself (`utils:initAIService`) right after confirming `sanitations.md` exists — callers don't need to initialize AI beforehand for this step. The `isAIServiceInitialized()` check right after selects the AI path vs rule-based fallback.
- `clientPath = outputDir` (flat). Never use `${outputDir}/ballerina` — that is the `main.bal` legacy path (nested layout). The two must not be conflated.
- `specDir` is resolved by Java before the Ballerina call. Ballerina must use the `specDir` param directly for `sanitizedSpec` and `sanitationsPath` — never re-derive it from `outputDir` inside `runOpenApiGenerationWorkflow`.
