# Ballerina Connector Tool

`bal connector` is a Ballerina CLI tool that automates the generation of Ballerina connectors from
OpenAPI specifications and Java SDKs. It runs AI-assisted pipelines — sanitizing contracts,
generating clients, repairing compilation errors, and producing tests, examples, and documentation —
so that a complete, ready-to-use connector project comes out the other end with a single command.
The tool uses Anthropic Claude for spec cleanup, code repair, example writing, and documentation.

## Prerequisites

- [Ballerina Swan Lake](https://ballerina.io/downloads/) `2201.13.0` or later
- OpenJDK 21
- An [Anthropic API key](https://console.anthropic.com/) exported as `ANTHROPIC_API_KEY`

```bash
export ANTHROPIC_API_KEY=<your-key>
```

## Installation

```bash
bal tool pull connector
```

## Commands

### `bal connector openapi`

Generates a Ballerina connector from an OpenAPI specification.

**Synopsis**

```
bal connector openapi -i <spec-file> [-o <output-dir>] [options...]
```

**Options**

| Option | Description | Required |
|--------|-------------|----------|
| `-i`, `--input` | Path to the OpenAPI specification file | Yes |
| `-o`, `--output` | Output directory for the connector workspace (default: current directory) | No |
| `-x`, `--exclude` | Exclude a pipeline stage. Repeatable. Values: `sanitize`, `client`, `tests`, `examples`, `docs` | No |
| `-t`, `--tags` | Include only operations with this OpenAPI tag. Repeatable. | No |
| `--operations` | Include only these operation IDs. Repeatable. | No |
| `--remote` | Generate client methods as `remote` instead of resource methods | No |
| `--license` | Path to a license header file for generated source files | No |
| `--example-dir` | Output directory for generated examples (default: `<output>/examples`) | No |
| `--spec-dir` | Directory for the aligned spec and `sanitations.md` (default: `<output>/docs/spec`) | No |
| `--interactive` | Pause after each pipeline stage for manual review | No |
| `-v`, `--verbose` | Show detailed diagnostic output | No |
| `-q`, `--quiet` | Suppress all output except errors | No |

**Pipeline stages**

The pipeline runs these stages in order. Any stage can be skipped with `-x <stage>`.

| Stage | What it does |
|-------|-------------|
| `sanitize` | Flatten, align, and AI-improve the OpenAPI spec; record sanitations |
| `client` | Generate Ballerina client, types, and utils; fix compilation errors |
| `tests` | Generate mock service and AI-assisted connector tests |
| `examples` | Generate AI-assisted usage examples |
| `docs` | Generate README documentation |

---

### `bal connector sdk`

Generates a Ballerina connector wrapping a Java SDK.

**Synopsis**

```
bal connector sdk <command> <sdk-ref> <output-dir> [options...]
bal connector sdk <command> <output-dir> [options...]
```

`<sdk-ref>` is a Maven coordinate (`group:artifact` or `group:artifact:version`) or a local
dataset key resolved from `test-jars/<key>.jar` + `test-jars/<key>-javadoc.jar`.

**Commands**

| Command | Description |
|---------|-------------|
| `pipeline` | Full workflow: SDK analysis → spec generation → connector codegen → fixes → tests/examples/docs |
| `analyze` | Analyze the Java SDK and write metadata under the output root |
| `generate` | Generate API spec and IR from analyzer metadata |
| `connector` | Generate Ballerina client, types, and native adapter |
| `fix-code` | Fix Java native adapter and Ballerina compilation errors |
| `fix-report-only` | Run code fixer diagnostics without applying fixes |
| `generate-tests` | Generate live integration tests |
| `generate-examples` | Generate AI-assisted usage examples |
| `generate-docs` | Generate README documentation |

**Options**

| Option | Description |
|--------|-------------|
| `--fix-iterations=<n>` | Maximum code fixer iterations (default: 3) |
| `--skip-fix` | Skip the code fixing phase |
| `--skip-tests` | Skip test generation |
| `--skip-examples` | Skip example generation |
| `--skip-docs` | Skip documentation generation |
| `--no-thinking` | Disable extended LLM reasoning during spec generation |
| `-y`, `--yes` | Auto-confirm all pipeline checkpoints |
| `-v`, `--verbose` | Show detailed diagnostic output |
| `-q`, `--quiet` | Suppress all output except errors |

## Examples

Generate a connector from an OpenAPI specification:

```bash
bal connector openapi -i ./openapi.yaml -o ./my-connector
```

Skip the sanitize stage when the spec is already aligned:

```bash
bal connector openapi -i ./openapi.yaml -x sanitize
```

Generate only the client and tests, skip examples and docs:

```bash
bal connector openapi -i ./openapi.yaml -x examples -x docs
```

Generate a connector from a Maven SDK:

```bash
bal connector sdk pipeline com.example:my-sdk:1.0.0 ./my-connector
```

## Useful Links

- Discuss code changes on [ballerina-dev@googlegroups.com](mailto:ballerina-dev@googlegroups.com)
- Chat live with the community on [Discord](https://discord.gg/ballerinalang)
- Post technical questions on [Stack Overflow](https://stackoverflow.com/questions/tagged/ballerina) with the `#ballerina` tag
