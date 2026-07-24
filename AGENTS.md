# Repository Agent Guide

## Project overview

This repository builds `bal connector`, a Ballerina CLI tool for generating and
maintaining connectors from OpenAPI specifications and Java SDKs. The project is
a mixed Java 21, Gradle, and Ballerina codebase.

The main areas are:

- `connector-cli/`: Java CLI entry points, argument validation, help text, and
  the bridge into the Ballerina runtime.
- `connector-core/`: Gradle orchestration for the Ballerina automator package.
- `connector-core/connector-automator/`: Ballerina workflow implementations for
  OpenAPI and Java SDK connector generation.
- `connector-core/connector-automator/modules/sdkanalyzer/native/`: Java 21
  native SDK analyzer built with its own Gradle wrapper.
- `connector-tool/`: Ballerina tool package and manifests that assemble the CLI
  artifact for installation.
- `build-config/`: shared Checkstyle rules and generated TOML templates.
- `examples/`: sample inputs and reference material; do not treat generated
  output here as production source without checking its purpose.

## Prerequisites and environment

- Use JDK 21. The configured Java and Ballerina versions are authoritative in
  `gradle.properties`; currently Ballerina is `2201.13.4`.
- Use the checked-in Gradle wrappers instead of a system Gradle installation.
- `ANTHROPIC_API_KEY` is required to run the AI-assisted connector workflows,
  but not for ordinary compilation or static checks.
- Never print, commit, or write API keys or other credentials into repository
  files. Local `.env` files and `Config.toml` are intentionally ignored.

## Build and validation

Run commands from the repository root unless a different directory is stated.
After completing each logical repository change set, run the following command
before handing the work back:

```bash
./gradlew build
```

This final build is mandatory. Focused checks may be used while iterating, but
they do not replace it. If the build fails, fix the failure and rerun it. If an
environmental limitation prevents the build from running, report that explicitly
instead of claiming the change is complete and validated.

Use the narrowest useful check while iterating:

```bash
# Java CLI checks, including Checkstyle and SpotBugs
./gradlew :connector-cli:check --console=plain --no-daemon

# Ballerina automator and its native SDK analyzer
./gradlew :connector-core:build --console=plain --no-daemon

# Native SDK analyzer only
cd connector-core/connector-automator/modules/sdkanalyzer/native
./gradlew build --no-daemon -PballerinaLangVersion=2201.13.4

# Ballerina automator only, after the native analyzer JAR exists
cd connector-core/connector-automator
bal build

# CLI shadow JAR and installable Ballerina tool package
./gradlew :connector-cli:shadowJar :connector-tool:build \
  --console=plain --no-daemon
```

When changing Ballerina sources, run `bal format` only on the files or package
you touched. When adding behavior, add focused tests where practical and run the
smallest relevant test task before the full build. If a check cannot run because
of unavailable credentials, network access, or tooling, report that explicitly.

Do not run end-to-end connector generation merely as a build check. It calls an
external AI service, can incur cost, and writes generated projects. Run it only
when the task explicitly requires workflow-level validation and a suitable API
key and input fixture are available.

## Implementation conventions

- Preserve the Apache 2.0 copyright header used by existing Java, Ballerina,
  Gradle, and configuration files.
- Follow the style of neighboring code. Keep Java compatible with release 21
  and allow Checkstyle and SpotBugs to drive static-analysis fixes.
- Use Ballerina documentation comments for public functions and types. Keep
  error handling explicit and preserve the existing structured logging and
  exit-code behavior.
- Keep responsibilities separated: Java owns CLI parsing and runtime bridging;
  Ballerina owns the generation workflows; the native analyzer owns Java SDK
  inspection.
- Java invokes public Ballerina workflow entry points through
  `BallerinaRuntimeUtils`. Treat those function names, parameters, and return
  shapes as cross-language interfaces and update both sides together.
- When CLI flags, validation, or output changes, update the matching files in
  `connector-cli/src/main/resources/cli-help/` and relevant README examples.
- Keep OpenAPI and SDK workflow behavior consistent where they share stages,
  utilities, output conventions, or error reporting.
- When changing `bal connector openapi` behavior, also update the corresponding
  behavior in `ballerina-platform/ballerina-library` under
  `agent-skills/skills/generating-connectors` to minimize deviations between the
  connector tool and the coding-agent skill.
- Prefer existing utilities and modules over duplicating process execution,
  path validation, logging, formatting, or AI-client logic.

## Generated and release-managed files

- Do not commit build output under `build/`, `target/`, `.gradle/`, or
  `generated/`.
- Treat `Dependencies.toml`, packaged JARs, and generated tool manifests as
  tool-managed artifacts. Regenerate them through the appropriate Ballerina or
  Gradle task and review any tracked diff instead of editing lock data by hand.
- Do not run publishing, release, version-bump, `bal push`, or Git commit/tag
  tasks unless the user explicitly requests that operation.
- Release workflows expect repository credentials and may create branches,
  commits, tags, releases, or published packages; they are not validation tasks.

## Working-tree discipline

- Inspect `git status` before editing. Existing modifications belong to the user;
  preserve them and do not reformat, revert, or overwrite unrelated work.
- Keep changes scoped to the request and avoid broad mechanical rewrites.
- Do not amend commits, force-push, delete files, or use destructive Git commands
  unless explicitly authorized.
- Summarize changed files and validation performed when handing work back.
