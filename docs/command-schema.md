# Command Schema

This document describes the centralized `bal tool-id` command surface for the four workflow families:

- `openapi`
- `sdk`
- `connector-doc`
- `example-doc`

## Base Invocation

```bash
bal tool-id <command> <sub-command> [arguments...] [options...] [flags...]
```

## Global Flags

| Flag | Type | Description |
|---|---:|---|
| `help`, `--help`, `-h` | boolean | Show help information. |

## Environment

| Variable | Required for | Description |
|---|---|---|
| `ANTHROPIC_API_KEY` | `sdk`, `openapi sanitize`, `openapi generate-tests`, `openapi generate-examples`, `openapi generate-docs`, `openapi pipeline`, `connector-doc`, `example-doc` | Required for AI-powered analysis, generation, documentation, and repair stages. |

## `openapi`

Generate and maintain Ballerina connectors from OpenAPI specifications.

### OpenAPI Shared Flags

These flags are available for all `openapi` subcommands.

| Flag | Type | Description |
|---|---:|---|
| `yes`, `--yes`, `-y` | boolean | Auto-confirm prompts where confirmation is required. |
| `quiet`, `--quiet`, `-q` | boolean | Reduce log output. |

### `openapi pipeline`

Run the full OpenAPI connector workflow: sanitize the source specification, generate the Ballerina client, build and validate the client, generate examples, generate tests, and produce documentation.

```bash
bal tool-id openapi pipeline <openapi_spec> <output_dir> [options...] [flags...]
```

| Argument | Required | Description |
|---|---:|---|
| `openapi_spec` | yes | Path to the source OpenAPI specification file. |
| `output_dir` | yes | Output directory for the generated connector workspace. |

| Option | Type | Format / Values | Description |
|---|---:|---|---|
| `license` | string | `license=<path>` | License file path to use when generating Ballerina client source headers. |
| `tags` | string array | `tags=tag1,tag2` | Comma-separated OpenAPI tags to include during client generation. |
| `operations` | string array | `operations=op1,op2` | Comma-separated OpenAPI operation IDs to include during client generation. |
| `client-method` | string | `client-method=resource\|remote` | Client method style to use during Ballerina client generation. |

| Flag | Type | Description |
|---|---:|---|
| `regenerate` | boolean | Reapply recorded sanitations and recover or refresh generated assets for an updated specification. |
| `remote-methods` | boolean | Generate client APIs as remote methods. |
| `resource-methods` | boolean | Generate client APIs as resource methods. |

### `openapi sanitize`

Flatten and align an OpenAPI specification, apply AI-assisted operation ID, schema-name, and description improvements, and record sanitations for future regeneration.

```bash
bal tool-id openapi sanitize <input_spec> <output_dir> [flags...]
```

| Argument | Required | Description |
|---|---:|---|
| `input_spec` | yes | Path to the source OpenAPI specification file. |
| `output_dir` | yes | Directory where sanitized specification files and sanitation records are written. |

### `openapi generate-client`

Generate a Ballerina client project from an OpenAPI specification.

```bash
bal tool-id openapi generate-client <openapi_spec> <output_directory> [options...] [flags...]
```

| Argument | Required | Description |
|---|---:|---|
| `openapi_spec` | yes | Path to the OpenAPI specification file used for client generation. |
| `output_directory` | yes | Directory where the generated Ballerina client project is written. |

| Option | Type | Format / Values | Description |
|---|---:|---|---|
| `license` | string | `license=<path>` | License file path to use for generated source headers. |
| `tags` | string array | `tags=tag1,tag2` | Comma-separated OpenAPI tags to include. |
| `operations` | string array | `operations=op1,op2` | Comma-separated operation IDs to include. |
| `client-method` | string | `client-method=resource\|remote` | Client method style to generate. |

| Flag | Type | Description |
|---|---:|---|
| `remote-methods` | boolean | Generate client APIs as remote methods. |
| `resource-methods` | boolean | Generate client APIs as resource methods. |

### `openapi fix-code`

Fix Ballerina compilation errors in an OpenAPI-generated connector project using AI-assisted code repair.

```bash
bal tool-id openapi fix-code <connector_path> [flags...]
```

| Argument | Required | Description |
|---|---:|---|
| `connector_path` | yes | Path to the generated Ballerina connector project to analyze and repair. |

### `openapi generate-tests`

Generate OpenAPI connector tests, including a mock server module and test suite derived from the connector and source specification.

```bash
bal tool-id openapi generate-tests <connector_path> <spec_path> [flags...]
```

| Argument | Required | Description |
|---|---:|---|
| `connector_path` | yes | Path to the connector workspace. |
| `spec_path` | yes | Path to the OpenAPI specification used to derive mock responses and test coverage. |

### `openapi generate-examples`

Generate AI-assisted Ballerina examples for an OpenAPI-generated connector.

```bash
bal tool-id openapi generate-examples <connector_path> [flags...]
```

| Argument | Required | Description |
|---|---:|---|
| `connector_path` | yes | Path to the connector workspace. |

| Flag | Type | Description |
|---|---:|---|
| `regenerate` | boolean | Try recovering or updating existing examples before falling back to fresh example generation. |

### `openapi generate-docs`

Generate README documentation for an OpenAPI-generated connector.

```bash
bal tool-id openapi generate-docs <doc_command> <connector_path> [flags...]
```

| Argument | Required | Values | Description |
|---|---:|---|---|
| `doc_command` | yes | `generate-all`, `generate-ballerina`, `generate-tests`, `generate-examples`, `generate-individual-examples`, `generate-main` | Documentation generation mode. |
| `connector_path` | yes | path | Path to the connector workspace. |

## `sdk`

Generate and maintain Ballerina connectors from Java SDKs.

### SDK Shared Flags

These flags are available for all `sdk` subcommands.

| Flag | Type | Description |
|---|---:|---|
| `quiet`, `--quiet`, `-q` | boolean | Reduce log output. |

### `sdk analyze`

Analyze a Java SDK from a dataset key or Maven coordinate and write SDK metadata under the output root.

```bash
bal tool-id sdk analyze <sdk_ref> <output_dir> [options...] [flags...]
```

| Argument | Required | Description |
|---|---:|---|
| `sdk_ref` | yes | Dataset key or Maven coordinate such as `group:artifact:version`. |
| `output_dir` | yes | Root directory for generated SDK analysis artifacts. |

| Option | Type | Format | Description |
|---|---:|---|---|
| `sources` | string | `sources=<path>` or `--sources <path>` | Path to a sources JAR or extracted source directory. |
| `include-packages` | string array | `include-packages=pkg1,pkg2` | Restrict analysis to specific Java packages. |
| `exclude-packages` | string array | `exclude-packages=pkg1,pkg2` | Exclude specific Java packages from analysis. |
| `max-depth` | integer | `max-depth=<n>` | Maximum dependency traversal depth. |
| `methods-to-list` | integer | `methods-to-list=<n>` | Maximum number of SDK methods to list for analysis. |

| Flag | Type | Description |
|---|---:|---|
| `yes`, `--yes`, `-y` | boolean | Auto-confirm prompts for this command where confirmation is required. |
| `include-deprecated`, `--include-deprecated` | boolean | Include deprecated SDK methods. |
| `include-internal`, `--include-internal` | boolean | Include SDK classes or methods that would otherwise be treated as internal. |
| `include-non-public`, `--include-non-public` | boolean | Include non-public SDK classes or methods. |

### `sdk pipeline`

Run the full Java SDK connector workflow: analyze the SDK, generate API specification and IR, generate connector code, then optionally run code fixing, tests, examples, and documentation.

```bash
bal tool-id sdk pipeline <dataset_key> <output_dir> [options...] [flags...]
```

| Argument | Required | Description |
|---|---:|---|
| `dataset_key` | yes | Dataset key used to resolve the SDK JAR and Javadoc JAR. |
| `output_dir` | yes | Root directory for generated connector artifacts. |

| Option | Type | Format | Description |
|---|---:|---|---|
| `fix-iterations` | integer | `--fix-iterations=<n>` | Maximum fixer iterations. Default is `3`. |

| Flag | Type | Description |
|---|---:|---|
| `yes`, `--yes`, `-y` | boolean | Auto-confirm prompts for this command where confirmation is required. |
| `--fix-code` | boolean | Run the full code fixing phase. Enabled by default. |
| `--fix-report-only` | boolean | Run code fixer diagnostics without applying all fixes. |
| `--skip-fix` | boolean | Skip the code fixing phase. |
| `--skip-tests` | boolean | Skip SDK live test generation. |
| `--generate-examples` | boolean | Run example generation. Enabled by default. |
| `--skip-examples` | boolean | Skip example generation. |
| `--generate-docs` | boolean | Run documentation generation. Enabled by default. |
| `--skip-docs` | boolean | Skip documentation generation. |

### `sdk generate`

Generate the API specification and intermediate representation from SDK analyzer metadata.

```bash
bal tool-id sdk generate <output_dir> [flags...]
```

| Argument | Required | Description |
|---|---:|---|
| `output_dir` | yes | Root directory containing SDK analyzer metadata. |

| Flag | Type | Description |
|---|---:|---|
| `no-thinking`, `--no-thinking` | boolean | Disable extended LLM reasoning mode during specification generation. |

### `sdk connector`

Generate Ballerina connector artifacts from SDK metadata, IR, and API specification.

```bash
bal tool-id sdk connector <output_dir> [flags...]
```

| Argument | Required | Description |
|---|---:|---|
| `output_dir` | yes | Root directory containing SDK metadata, IR, and API specification artifacts. |

### `sdk fix-code`

Fix Java native adapter and Ballerina compilation errors in an SDK-generated connector.

```bash
bal tool-id sdk fix-code <output_dir> [options...] [flags...]
```

| Argument | Required | Description |
|---|---:|---|
| `output_dir` | yes | Root directory containing generated SDK connector artifacts. |

| Option | Type | Format | Description |
|---|---:|---|---|
| `fix-iterations` | integer | `--fix-iterations=<n>` | Maximum fixer iterations. Default is `3`. |

### `sdk fix-report-only`

Run code fixer diagnostics for an SDK-generated connector without applying all fixes.

```bash
bal tool-id sdk fix-report-only <output_dir> [options...] [flags...]
```

| Argument | Required | Description |
|---|---:|---|
| `output_dir` | yes | Root directory containing generated SDK connector artifacts. |

| Option | Type | Format | Description |
|---|---:|---|---|
| `fix-iterations` | integer | `--fix-iterations=<n>` | Maximum fixer iterations to use while collecting diagnostics. Default is `3`. |

### `sdk generate-tests`

Generate live integration tests for an SDK-generated connector.

```bash
bal tool-id sdk generate-tests <output_dir> [flags...]
```

| Argument | Required | Description |
|---|---:|---|
| `output_dir` | yes | Root directory containing generated SDK connector artifacts. |

| Flag | Type | Description |
|---|---:|---|
| `yes`, `--yes`, `-y` | boolean | Auto-confirm prompts for this command where confirmation is required. |

### `sdk generate-examples`

Generate AI-assisted Ballerina examples for an SDK-generated connector.

```bash
bal tool-id sdk generate-examples <output_dir> [flags...]
```

| Argument | Required | Description |
|---|---:|---|
| `output_dir` | yes | Root directory containing generated SDK connector artifacts. |

| Flag | Type | Description |
|---|---:|---|
| `yes`, `--yes`, `-y` | boolean | Auto-confirm prompts for this command where confirmation is required. |

### `sdk generate-docs`

Generate all README documentation for an SDK-generated connector.

```bash
bal tool-id sdk generate-docs <output_dir> [flags...]
```

| Argument | Required | Description |
|---|---:|---|
| `output_dir` | yes | Root directory containing a single SDK-generated connector workspace. |

| Flag | Type | Description |
|---|---:|---|
| `yes`, `--yes`, `-y` | boolean | Auto-confirm prompts for this command where confirmation is required. |

## `connector-doc`

Generate connector catalog documentation: overview, setup guide, action reference, and trigger reference.

### `connector-doc generate`

Generate or refresh catalog documentation for a connector source repository.

```bash
bal tool-id connector-doc generate [options...] [flags...]
```

| Option | Type | Format | Description |
|---|---:|---|---|
| `connector-name` | string | `connector-name=<display-name>` | Connector display name, for example `HubSpot`. |
| `module-slug` | string | `module-slug=<slug>` | Connector module or documentation folder slug, for example `hubspot`. |
| `package-name` | string | `package-name=<org/package>` | Ballerina package name, for example `ballerinax/hubspot`. |
| `github-repo` | string | `github-repo=<repo>` | Source repository name for the connector. |
| `category` | string | `category=<slug>` | Connector catalog category slug. |
| `connector-version` | string | `connector-version=<version>` | Connector version to document. If omitted, the latest available version is used. |
| `docs-repo-root` | string | `docs-repo-root=<path>` | Path to the documentation repository root. |

| Flag | Type | Description |
|---|---:|---|
| `dry-run` | boolean | Preview the generation inputs and planned output without writing documentation files. |
| `force` | boolean | Overwrite existing generated doc files. |

### `connector-doc dry-run`

Shortcut for `connector-doc generate dry-run`.

```bash
bal tool-id connector-doc dry-run [options...]
```

### `connector-doc update`

Update existing catalog documentation for a connector.

```bash
bal tool-id connector-doc update [options...] [flags...]
```

| Flag | Type | Description |
|---|---:|---|
| `force` | boolean | Overwrite existing doc files instead of preserving them. |

## `example-doc`

Generate visual WSO2 Integrator example documentation with screenshots.

### `example-doc connector`

Generate a visual example guide for a connector.

```bash
bal tool-id example-doc connector <connector_name> [additional_instructions]
```

| Argument | Required | Description |
|---|---:|---|
| `connector_name` | yes | Connector package or module name to document, for example `mysql` or `zoom.meetings`. |
| `additional_instructions` | no | Extra guidance for the generated example, such as authentication, operations, or setup preferences. |

### `example-doc trigger`

Generate a visual example guide for a trigger.

```bash
bal tool-id example-doc trigger <trigger_name> [additional_instructions]
```

| Argument | Required | Description |
|---|---:|---|
| `trigger_name` | yes | Trigger package or module name to document, for example `trigger.github`. |
| `additional_instructions` | no | Extra guidance for the generated trigger guide. |

### `example-doc batch`

Generate multiple connector and trigger example guides from a batch queue.

```bash
bal tool-id example-doc batch [options...]
```

| Option | Type | Format | Default | Description |
|---|---:|---|---|---|
| `config` | string | `config=<path>` | `batch_items.json` | Path to the batch queue JSON file. |
| `timeout` | integer | `timeout=<seconds>` | `7200` | Per-item timeout in seconds. |

Batch config shape:

```json
{
  "items": [
    {
      "type": "connector",
      "name": "mysql",
      "instructions": "Optional guidance"
    },
    {
      "type": "trigger",
      "name": "trigger.github",
      "instructions": "Optional guidance"
    }
  ]
}
```

| Batch field | Required | Values | Description |
|---|---:|---|---|
| `type` | yes | `connector`, `trigger` | Type of example documentation to generate. |
| `name` | yes | string | Connector or trigger name. |
| `instructions` | no | string | Additional per-item guidance. |
