# AI Connector Generation Tool

This repository contains the proof-of-concept implementation for
[ballerina-platform/ballerina-library#8791](https://github.com/ballerina-platform/ballerina-library/issues/8791),
which proposes a centralized CLI tool for automated Ballerina connector
generation.

## Problem

Ballerina already has several workflows that let users create connectors, SDKs,
and listeners from different kinds of specifications and contracts. These
workflows are not simple wrappers around commands such as `bal openapi` or
`bal asyncapi`. They are higher-level generation pipelines that combine
deterministic tooling and LLM-assisted steps to sanitize contracts, analyze SDKs,
generate clients, create tests and examples, repair generated code, and produce
comprehensive documentation.

Although these workflows work end to end, using them currently requires a
tedious amount of setup before the actual generation can begin. Users often need
to clone the relevant repositories, move into the correct application
directories, resolve dependencies, configure environment variables, and then run
workflow-specific commands. This is time consuming, and for users who are not
already familiar with the Ballerina connector ecosystem, it creates a knowledge
barrier before they can even try the workflows.

The problem will grow as more generation workflows are introduced for new
specification and contract types. A connector-generation entry point must be
able to incorporate current and future workflows without making the CLI tightly
coupled to any single workflow implementation.

There is also an AI-provider coupling problem. The current workflows require an
`ANTHROPIC_API_KEY` for LLM-assisted stages, which effectively locks users into
one provider. That dependency can discourage adoption, and in some environments
it can prevent users from using the tool at all.

## Goal

The goal is to provide one Ballerina CLI tool that unifies these generation
workflows behind a single connector-focused interface:

```bash
bal connector <contract-type> <contract-path> <connector-out>
```

The command should accept a source contract or SDK specification and unroll it
into a complete Ballerina connector project. The generated connector should
include the client implementation, examples, tests, documentation, and the
metadata needed to regenerate or maintain the connector later.

The tool should bundle the core generation source and required dependencies so
users do not need to manually clone repositories, navigate into workflow
directories, or perform repeated environment setup before running a connector
generation pipeline.

## Proposed Solution

Introduce a centralized Ballerina CLI command that acts as the stable entry
point for all connector-generation workflows. The CLI should route each
`contract-type` to the correct workflow implementation, run the required stages,
and write a complete connector project to `connector-out`.

The solution should be extensible in three ways:

1. **Workflow extensibility**: New workflows for future contract or
   specification types should be easy to register without redesigning the CLI.
2. **Implementation flexibility**: The CLI should depend on workflow contracts,
   not concrete implementations, so workflow internals can be replaced or
   improved independently.
3. **Stage modularity**: Pipeline stages such as client generation, test
   generation, example generation, documentation generation, code repair, and
   regeneration should be individually reusable and configurable.

The tool should also avoid hard-coding a single LLM provider. AI-assisted stages
should use a provider abstraction so the implementation can support Anthropic
today while allowing other providers or enterprise-hosted models later.

## Repository Layout

```text
.
├── build.gradle
├── settings.gradle
├── gradle/
├── config/
├── docs/
├── connector-tool/
│   ├── BalTool.toml
│   ├── Ballerina.toml
│   └── tool_connector.bal
├── connector-cli/
│   ├── build.gradle
│   └── src/main/java/io/ballerina/connectortool/ConnectorCmd.java
├── connector-core/
│   └── connector-automator/
│       ├── Ballerina.toml
│       ├── main.bal
│       ├── modules/
│       ├── resources/scripts/
│       └── README.md
```

| Path | Purpose |
|------|---------|
| `connector-tool/` | Ballerina tool package. Registers the tool id as `connector` and points to the Java CLI artifact |
| `connector-cli/` | Java-based Ballerina CLI tool entry point |
| `connector-core/connector-automator/` | Ballerina connector automation package for OpenAPI and Java SDK workflows |
| `connector-core/connector-automator/modules/sanitizor` | OpenAPI sanitization and sanitation tracking |
| `connector-core/connector-automator/modules/sdkanalyzer` | Java SDK metadata extraction and analysis |
| `connector-core/connector-automator/modules/api_specification_generator` | SDK metadata to API spec and IR generation |
| `connector-core/connector-automator/modules/connector_generator` | SDK-backed Ballerina connector generation |
| `connector-core/connector-automator/modules/client_generator` | OpenAPI-based Ballerina client generation |
| `connector-core/connector-automator/modules/example_generator` | AI-assisted example generation |
| `connector-core/connector-automator/modules/test_generator` | OpenAPI mock/live tests and SDK live tests |
| `connector-core/connector-automator/modules/document_generator` | Connector documentation generation |
| `connector-core/connector-automator/modules/code_fixer` | AI-assisted compilation-error repair |
| `connector-core/connector-automator/modules/client_regenerator` | Regeneration support for existing connectors |

See [connector-core/connector-automator/README.md](connector-core/connector-automator/README.md) for the
current direct package commands exposed by the automation pipeline.

## Current Status

This repository currently contains three primary layers:

1. A Ballerina tool package under `connector-tool/`.
2. A Java CLI command implementation under `connector-cli/`.
3. The combined OpenAPI and SDK connector automation workflow under `connector-core/connector-automator/`.

The Java CLI discovers workflow module mappings through `ServiceLoader` providers
implementing `io.ballerina.connectortool.spi.ConnectorWorkflow`. The built-in
workflows register the current `sdk`, `openapi`, `doc-generator`, and
`example-doc` workflow names and route them to the Ballerina
`wso2/connector_automator` module.

Inside `connector_automator`, the top-level workflow commands are registered in
a Ballerina workflow registry before dispatching to the SDK or OpenAPI command
handlers. Future workflows can add Java SPI providers for new Ballerina modules
and, where they share `connector_automator`, add Ballerina registry entries
without changing the Java command launcher.

## Prerequisites

- Ballerina Swan Lake
- Java and Gradle
- An LLM provider API key for AI-assisted generation and repair flows

The current implementation uses Anthropic-backed AI calls. Set the API key
before running AI-powered automations:

```bash
export ANTHROPIC_API_KEY="<your-api-key>"
```

## Build

Build the Ballerina workflow jar consumed by the Java CLI:

```bash
cd connector-core/connector-automator/modules/sdkanalyzer/native
./gradlew build
cd ../../..
bal build
```

Build the Java CLI tool artifact from the repository root:

```bash
./gradlew :connector-cli:build
```

The CLI build creates the tool dependency referenced by
`connector-tool/BalTool.toml`:

```text
connector-cli/build/libs/connector-tool-0.1.0.jar
```

## Install the Local Tool

From the Ballerina tool package, install the tool locally:

```bash
cd connector-tool
bal pack
bal push --repository=local
bal tool pull connector:0.1.0 --repository=local
```

After installation, the intended top-level command is:

```bash
bal connector <sdk|openapi> <command> [args...]
```

The Java command entry point delegates to the Ballerina `connector_automator`
package, which exposes both OpenAPI and SDK workflows.

## Run the Existing Automation Pipeline

The top-level tool and direct Ballerina package commands use the same workflow
shape:

```bash
bal connector openapi pipeline <openapi-spec> <output-dir> yes quiet
bal connector sdk pipeline <dataset-key> <output-dir> yes quiet
```

For example:

```bash
 bal connector openapi pipeline ./openapi.yaml ./generated-connector yes quiet
 bal connector sdk pipeline s3-2.31.66 ./generated-sdk-connector yes quiet
```

The OpenAPI pipeline performs the main spec-driven connector workflow:

1. Sanitize and align the source specification.
2. Generate the Ballerina client.
3. Build and repair generated code where possible.
4. Generate examples.
5. Generate tests and mock services.
6. Generate connector documentation.

These stages are expected to become modular CLI-accessible units as the
centralized tool evolves. For example, users should eventually be able to run a
full pipeline or invoke selected stages such as client generation, example
generation, test generation, documentation generation, or regeneration.

The SDK pipeline analyzes a Java SDK JAR or dataset key, generates SDK metadata,
creates an API spec and IR, generates a Ballerina connector plus native Java
adaptor, then runs the same repair, examples, tests, and documentation stages.

## Expected Output

A completed run should produce a connector workspace containing:

- Ballerina client source
- Generated types and utilities
- Usage examples
- Tests and mock server code
- README documentation
- Sanitization records for future regeneration

## Issue Alignment

This solution is designed around the requirements in
[ballerina-platform/ballerina-library#8791](https://github.com/ballerina-platform/ballerina-library/issues/8791):

- Provide one centralized connector-focused CLI entry point.
- Avoid forcing users to clone and navigate multiple source repositories.
- Bundle the required generation workflow behind the tool.
- Support source inputs such as standard contracts and SDK specifications.
- Provide an extensible workflow model for new contract and specification types.
- Keep workflow implementations replaceable behind stable CLI contracts.
- Expose modular workflow stages for clients, tests, examples, docs, and repair.
- Avoid tight coupling to a single LLM provider.
- Produce maintainable Ballerina connectors with supporting assets.
