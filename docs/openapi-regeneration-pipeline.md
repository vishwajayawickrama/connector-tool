# OpenAPI Regeneration Pipeline — Architecture Reference

This document covers the design of `executeOpenApiRegen` in `openapi_workflow.bal`, how it differs from `runOpenApiGenerationWorkflow`, and the `sanitations.md` mechanism that drives regeneration. For module-by-module details (sanitizor, client_generator, etc.) see `CLAUDE.md` and `openapi-workflow-architecture.md`.

---

## Why a separate regen pipeline

The fresh pipeline (`runOpenApiGenerationWorkflow`) assumes a blank output directory and generates everything from scratch. Regeneration has three additional requirements:

1. **Pre-sanitization replay** — recorded sanitations from a previous run must be applied to the new spec version before sanitizing, so connector-specific decisions survive API updates.
2. **Aggressive build recovery** — old tests and mock stubs frequently reference types that no longer exist in the new spec; the pipeline must detect this and delete/regenerate them instead of failing.
3. **Unconditional test regeneration** — even when the build passes cleanly, the API surface may have changed; tests are always regenerated on a regen run.

---

## Ballerina entry points

### `runOpenApiRegenWorkflow` (public — called by Java)

```ballerina
public function runOpenApiRegenWorkflow(string openApiSpec, string outputDir, string logLevel, string examplesDir, string excludedStages) returns error?
```

Same signature as `runOpenApiGenerationWorkflow`. Parses `logLevel` → `utils:LogLevel` and `excludedStages` (comma-separated string) → `string[]`, then delegates to `executeOpenApiRegen`.

### `executeOpenApiRegen` (private — the actual pipeline)

```ballerina
function executeOpenApiRegen(string openApiSpec, string outputDir, string examplesDir, utils:LogLevel logLevel = "normal", string[] excluded = []) returns error?
```

Uses **flat layout** (`outputDir` is the client path / `Ballerina.toml` root), identical to `runOpenApiGenerationWorkflow`. Do not use `${outputDir}/ballerina` — that is the legacy CLI path in `main.bal` which is nested layout only.

---

## Java invocation

`OpenApiAutomatorWorkflow` gains a `-r` / `--regen` flag. When set, it calls `runOpenApiRegenWorkflow` instead of `runOpenApiGenerationWorkflow`:

```java
String functionName = regenFlag ? "runOpenApiRegenWorkflow" : "runOpenApiGenerationWorkflow";
BallerinaRuntimeUtils.callBallerinaFunction(
    ORG, MODULE, VERSION, functionName,
    openApiSpecPath != null ? openApiSpecPath.toString() : "",
    ballerinaProjectPath.toString(), logLevel, resolvedExamplesDir, excludedArg
);
```

Same 5-arg call, same error-propagation contract (`RuntimeException` on `BError`).

---

## Pipeline steps

```
Pre-step  sanitizor:applySanitations           non-fatal
Stage 1   sanitizor:executeSanitizor            CRITICAL
          sanitizor:generateSanitationsDoc      non-fatal (refreshes sanitations.md)
Stage 2   client_generator:executeClientGen     non-fatal
          utils:executeBalBuild
          ├── [errors] code_fixer:fixAllErrors  non-fatal attempt
          │   utils:executeBalBuild             (retry)
          │   ├── [errors] file:remove tests/ + mock.server/
          │   │   test_generator:executeOpenApiTestGen   CRITICAL
          │   │   utils:executeBalBuild
          │   │   └── [errors] code_fixer:fixAllErrors  CRITICAL
          │   └── [clean] → continue
          └── [clean] test_generator:executeOpenApiTestGen  non-fatal
Stage 3   example_generator:executeExampleGen   non-fatal
Stage 4   document_generator:executeDocGen      non-fatal
```

**Stage numbering** follows `runOpenApiGenerationWorkflow` (`total` is computed from non-excluded stages). The `-x` exclude flags carry over: `sanitize`, `client`, `tests`, `examples`, `docs` are all skippable. Tests sit inside Stage 2 (client+build) here, not as a separate top-level stage, because their fate depends on the build outcome.

### Pre-step — apply recorded sanitations

```ballerina
string sanitationsPath = string `${outputDir}/docs/spec/sanitations.md`;
error? applyResult = sanitizor:applySanitations(sanitationsPath, openApiSpec, logLevel);
```

Run before Stage 1. Non-fatal: if `sanitations.md` doesn't exist or AI fails, the pipeline continues with raw sanitization.

### Stage 2 — build recovery tiers

| Build outcome | Action |
|---|---|
| Clean | Regenerate tests (non-fatal) |
| Errors, fixed by `code_fixer` | Regenerate tests (non-fatal) |
| Errors, `code_fixer` cannot fix | Delete `tests/` + `modules/mock.server/`, regenerate tests (CRITICAL), rebuild, final `code_fixer` attempt (CRITICAL) |

The CRITICAL designations on the forced-regen branch mean the pipeline returns an error and aborts if those steps fail.

---

## `sanitations.md` mechanics

### What it records

Every transformation applied to the raw spec during sanitization: server URL changes, path prefix removals, type renames, nullability changes, format changes, AI-generated operationId and description additions. Written to `${outputDir}/docs/spec/sanitations.md`.

### How it is generated — `sanitizor:generateSanitationsDoc`

Called after `executeSanitizor` in both fresh and regen pipelines. Diffs the original spec against the aligned spec and writes human-readable, machine-parseable markdown sections.

- If `sanitations.md` **already exists**: calls `mergeWithExistingSanitations` — appends new sections, renumbers, deduplicates.
- If **new**: calls `buildSanitationsContent` — AI-generated descriptions, falls back to auto-detection.

### How it is applied — `sanitizor:applySanitations`

Called in the pre-step, before `executeSanitizor`, on the incoming new spec.

**Primary path (AI available):** Sends both `sanitations.md` content and the new spec JSON to Claude. If spec ≤ `SPEC_SINGLE_TURN_THRESHOLD` chars: single-turn rewrite. If larger: chunked multi-turn (same strategy as `client_regenerator/analyze_version_change.bal`). Result is written back to `newSpecPath` in-place.

**Fallback (AI unavailable):** `parseSanitationsMarkdown` extracts typed `SanitationRules` and `applyRulesToSpec` applies them programmatically.

```ballerina
type SanitationRules record {|
    ServerUrlChange[]    serverUrlChanges;
    PathPrefixRule[]     pathPrefixRules;
    TypeChange[]         typeChanges;
    NullabilityChange[]  nullabilityChanges;
    FormatChange[]       formatChanges;
|};
```

The `utils:isAIServiceInitialized()` check selects between the two paths — AI must have been initialized before calling `applySanitations` for the primary path to activate.

---

## `client_regenerator` module

Standalone utilities called outside the pipeline (typically via `bal run` in CI after a regen PR is created). Not invoked from `executeOpenApiRegen` directly.

| File | Entry | Purpose |
|------|-------|---------|
| `analyze_version_change.bal` | `main(diffFilePath)` | AI classifies git diff as breaking/non-breaking; generates PR description sections |
| `sort_ballerina_client.bal` | `runSortBallerinaClient(args)` | Sorts resource methods by HTTP method + path for stable diffs across regenerations |
| `sort_ballerina_type.bal` | (internal) | Sorts type definitions alphabetically |
| `update_changelog.bal` | `runUpdateChangelog(prDescription)` | Parses PR description, generates/merges `Changelog.md` unreleased section |

`analyze_version_change.bal` uses the same chunked multi-turn pattern as `applySanitations` for large diffs.

---

## Differences from `runOpenApiGenerationWorkflow`

| Aspect | `runOpenApiGenerationWorkflow` (fresh) | `executeOpenApiRegen` |
|--------|-----------------------------------|-----------------------|
| Pre-step | none | `applySanitations` |
| Build recovery | auto-fix → CRITICAL fail | auto-fix → delete tests+mock → force-regen tests → CRITICAL fail |
| Test generation | independent stage, non-fatal | interleaved with build, conditionally CRITICAL |
| `examplesDir` | threaded from Java `-E` flag | same |
| Layout | flat (`outputDir`) | flat (`outputDir`) — same |
| Invoked by | `runOpenApiGenerationWorkflow` | `runOpenApiRegenWorkflow` |
| Java flag | (default) | `-r` / `--regen` |

---

## Invariants specific to regen

- `applySanitations` modifies the spec **in-place** before `executeSanitizor` reads it. The original spec file is overwritten; ensure the incoming path is a writable copy if the original must be preserved.
- `file:remove(clientPath + "/tests", file:RECURSIVE)` and `file:remove(clientPath + "/modules/mock.server", file:RECURSIVE)` are destructive. They only execute after two failed build attempts, not speculatively.
- `clientPath` in `executeOpenApiRegen` is `outputDir` (flat layout). The `main.bal::runOpenApiRegenerationPipeline` uses `${outputDir}/ballerina` (nested layout, CLI-only legacy path) — do not copy that pattern into `openapi_workflow.bal`.
