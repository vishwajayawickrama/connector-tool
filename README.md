# Ballerina Connector Generator

[![GitHub Last Commit](https://img.shields.io/github/last-commit/vishwajayawickrama/connector-generation-cli-tool.svg)](https://github.com/vishwajayawickrama/connector-generation-cli-tool/commits/main)
[![GitHub issues](https://img.shields.io/github/issues/vishwajayawickrama/connector-generation-cli-tool.svg?label=Open%20Issues)](https://github.com/vishwajayawickrama/connector-generation-cli-tool/issues)

`bal connector` is a Ballerina CLI tool that automates the generation and maintenance of Ballerina
connectors from OpenAPI specifications and Java SDKs. It runs AI-assisted, multi-stage pipelines —
sanitizing contracts, generating clients, repairing compilation errors, and producing tests, examples,
and documentation — so that a complete, ready-to-use connector project comes out the other end with a
single command.

```bash
bal connector openapi -i ./openapi.yaml
```

## What it does

The tool exposes two workflows behind a single entry point:

- **`bal connector openapi`** — takes an OpenAPI spec and runs: sanitize/align → generate client (build +
  auto-fix on error) → generate tests → generate examples → generate docs. Any stage can be skipped with
  `-x`/`--exclude`, and re-running the command against an existing output directory with an updated spec
  is how a connector is regenerated — there's no separate regeneration mode to learn.
- **`bal connector sdk`** — takes a Java SDK JAR (and Javadoc) and runs: analyze SDK → generate an API
  spec/IR → generate the Ballerina connector + native adaptor → fix code → generate examples → generate
  tests → generate docs.

Both workflows are AI-assisted (Anthropic Claude, via `ballerina/ai` and `ballerinax/ai.anthropic`) for
spec cleanup, code repair, example writing, and documentation. An `ANTHROPIC_API_KEY` is required.

Key capabilities:

- **Contract sanitization** — flattens and aligns OpenAPI specs, fills in missing `operationId`s and
  descriptions, and records every change to `sanitations.md` so it can be replayed automatically the next
  time the connector is regenerated from an updated spec.
- **Automatic code repair** — if the generated client fails to build, an AI-assisted fixer attempts to
  resolve the compilation errors before the pipeline gives up.
- **Selective pipeline stages** — `-x sanitize`, `-x client`, `-x tests`, `-x examples`, `-x docs` can be
  combined to skip any subset of the OpenAPI pipeline.
- **3-tier logging** — `-q`/`--quiet` for errors only, default for step-by-step progress, `-v`/`--verbose`
  for full subprocess and AI diagnostic output. All diagnostics go to stderr; stdout stays reserved for
  data.
- **SDK-to-connector generation** — parses a Java SDK's bytecode and Javadoc into a structured IR, then
  generates a typed Ballerina client backed by a native Java adaptor.

## Prerequisites

- [Ballerina Swan Lake](https://ballerina.io/downloads/) (`2201.13.1` or later)
- OpenJDK 21 ([Adopt OpenJDK](https://adoptopenjdk.net/) or any other distribution)
- Gradle (bundled wrapper is included — no separate install needed)
- An `ANTHROPIC_API_KEY` for the AI-assisted stages:
  ```bash
  export ANTHROPIC_API_KEY="<your-api-key>"
  ```

## Building From the Source

Build the three layers in order — the native SDK analyzer, the Ballerina automation package, and the
Java CLI:

```bash
# 1. Build the native SDK analyzer JAR
cd connector-core/connector-automator/modules/sdkanalyzer/native
./gradlew build
cd -

# 2. Pack the Ballerina automation package
cd connector-core/connector-automator
bal pack
cd -

# 3. Build the CLI JAR (shadow JAR bundles the Ballerina dependencies)
cd connector-cli
./gradlew shadowJar
cd -
```

This produces `connector-cli/build/libs/connector-tool-0.1.0.jar`, the artifact referenced by
`connector-tool/BalTool.toml`.

### Installing the tool locally

```bash
cd connector-tool
bal pack
bal push --repository=local
bal tool pull connector:0.1.0 --repository=local
```

Once installed, `bal connector` is available as a top-level Ballerina CLI command.

## Usage

```bash
# Generate a connector from an OpenAPI spec
bal connector openapi -i ./openapi.yaml -o ./my-connector

# Regenerate the same connector after the spec changes — same command, same directory
bal connector openapi -i ./openapi-v2.yaml -o ./my-connector

# Skip stages you don't need
bal connector openapi -i ./openapi.yaml -o ./my-connector -x examples -x docs

# Quiet or verbose output
bal connector openapi -i ./openapi.yaml -o ./my-connector -q
bal connector openapi -i ./openapi.yaml -o ./my-connector -v

# Generate a connector from a Java SDK
bal connector sdk pipeline <sdk-ref> ./my-sdk-connector
```

Run `bal connector openapi --help` or `bal connector sdk --help` for the full set of options.

## Repository Layout

```text
connector-generation-cli-tool/
├── connector-cli/          # Java layer — Ballerina tool JAR, CLI entry point
│   └── src/main/java/io/ballerina/connectortool/
│       ├── ConnectorCmd.java          # Root BLauncherCmd, "bal connector"
│       ├── spi/ConnectorWorkflow.java # SPI interface for registering subcommands
│       ├── utils/                     # Path validation, runtime invocation, process exit helpers
│       └── workflows/
│           ├── OpenApiAutomatorWorkflow.java  # "openapi" subcommand
│           └── SdkAutomatorWorkflow.java      # "sdk" subcommand
│
├── connector-core/
│   └── connector-automator/   # Ballerina package wso2/connector_automator
│       ├── main.bal             # SDK workflow CLI dispatcher
│       ├── openapi_workflow.bal # Public entry point: runOpenApiGenerationWorkflow
│       └── modules/
│           ├── utils/                       # Shared logging, process execution, path resolution
│           ├── sanitizor/                   # OpenAPI sanitization + sanitation tracking
│           ├── client_generator/            # OpenAPI → Ballerina client generation
│           ├── code_fixer/                  # AI-assisted compilation-error repair
│           ├── test_generator/              # Mock server + live test generation
│           ├── example_generator/           # AI-generated usage examples
│           ├── document_generator/          # README generation
│           ├── sdkanalyzer/                 # Java SDK → metadata extraction
│           ├── api_specification_generator/ # SDK metadata → IR + spec
│           ├── connector_generator/         # SDK spec → Ballerina client + native adaptor
│           └── client_regenerator/          # Version-aware client update utilities
│
└── connector-tool/          # BalTool descriptor — registers the "connector" tool id
```

See [`connector-core/connector-automator/README.md`](connector-core/connector-automator/README.md) for the
underlying automation package's direct commands.

## Output

A completed run produces a connector workspace containing:

- A typed Ballerina client (and native Java adaptor, for SDK-sourced connectors)
- Generated types and utilities
- Usage examples
- Tests and mock server code
- README documentation
- Sanitization records (`sanitations.md`) that drive future regeneration from an updated spec

## Contributing to Ballerina

As an open-source project, Ballerina welcomes contributions from the community.

For more information, go to the
[contribution guidelines](https://github.com/ballerina-platform/ballerina-lang/blob/master/CONTRIBUTING.md).

## Code of Conduct

All contributors are encouraged to read the [Ballerina Code of Conduct](https://ballerina.io/code-of-conduct).

## Useful Links

* Discuss code changes to Ballerina projects on [ballerina-dev@googlegroups.com](mailto:ballerina-dev@googlegroups.com).
* Chat live with the community via the [Discord server](https://discord.gg/ballerinalang).
* Post technical questions on Stack Overflow with the [#ballerina](https://stackoverflow.com/questions/tagged/ballerina) tag.
