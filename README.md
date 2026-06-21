# Ballerina Connector Tool

[![GitHub Last Commit](https://img.shields.io/github/last-commit/vishwajayawickrama/connector-generation-cli-tool.svg)](https://github.com/vishwajayawickrama/connector-generation-cli-tool/commits/main)
[![GitHub issues](https://img.shields.io/github/issues/vishwajayawickrama/connector-generation-cli-tool.svg?label=Open%20Issues)](https://github.com/vishwajayawickrama/connector-generation-cli-tool/issues)

`bal connector` is a Ballerina CLI tool that automates the generation and maintenance of Ballerina
connectors from OpenAPI specifications and Java SDKs. It exposes two AI-assisted workflows: `bal connector openapi`
sanitizes an OpenAPI contract and runs a full pipeline — generating the client, fixing compilation errors,
and producing tests, examples, and documentation — while `bal connector sdk` takes a Java SDK JAR and produces
a typed Ballerina client backed by a native Java adaptor through the same end-to-end pipeline. Both workflows
use Anthropic Claude (via `ballerinax/ai.anthropic`) and require an `ANTHROPIC_API_KEY` to run.

```bash
bal connector openapi -i ./openapi.yaml
```

## Building from the Source

### Setting Up the Prerequisites

1. OpenJDK 21 ([Adopt OpenJDK](https://adoptopenjdk.net/) or any other OpenJDK distribution)

   >**Info:** You can also use [Oracle JDK](https://www.oracle.com/java/technologies/javase-downloads.html).
   Set the `JAVA_HOME` environment variable to the pathname of the directory into which you installed JDK.

2. [Ballerina Swan Lake](https://ballerina.io/downloads/) `2201.13.1` or later

3. Set your Anthropic API key:

   ```bash
   export ANTHROPIC_API_KEY=<your-api-key>
   ```

### Building the Source

The tool is built in three layers. Execute the following commands in order from the repository root.

1. Build the native SDK analyzer JAR:

        cd connector-core/connector-automator/modules/sdkanalyzer/native
        ./gradlew build
        cd -

2. Pack the Ballerina automation package:

        cd connector-core/connector-automator
        bal pack
        cd -

3. Build the CLI shadow JAR:

        cd connector-cli
        ./gradlew shadowJar
        cd -

This produces `connector-cli/build/libs/connector-tool-0.1.0.jar`, the artifact referenced by
`connector-tool/BalTool.toml`.

### Installing Locally

After building, install the tool into your local Ballerina distribution:

        cd connector-tool
        bal pack
        bal push --repository=local
        bal tool pull connector:0.1.0 --repository=local

Once installed, `bal connector` is available as a top-level Ballerina CLI command.

## Contributing to Ballerina

As an open-source project, Ballerina welcomes contributions from the community.

For more information, go to the [contribution guidelines](https://github.com/ballerina-platform/ballerina-lang/blob/master/CONTRIBUTING.md).

## Code of Conduct

All contributors are encouraged to read the [Ballerina Code of Conduct](https://ballerina.io/code-of-conduct).

## Useful Links

* Discuss code changes to Ballerina projects on [ballerina-dev@googlegroups.com](mailto:ballerina-dev@googlegroups.com).
* Chat live with the community via the [Discord server](https://discord.gg/ballerinalang).
* Post technical questions on Stack Overflow with the [#ballerina](https://stackoverflow.com/questions/tagged/ballerina) tag.
