# Build and Compilation Flow

This document details the step-by-step instructions to compile, build, and push/install the connector generation tool locally.

## Flow Steps

### 1. Compile the Java Native Adapter (sdkanalyzer)
Navigate to the native Java directory of `sdkanalyzer` and build the native adapter:
```bash
cd connector-core/connector-automator/modules/sdkanalyzer/native
./gradlew build
cd ../../../..
```

### 2. Build the Ballerina Automator Package
Build the Ballerina package (`wso2/connector_automator`) that provides the core generation capabilities:
```bash
cd connector-core/connector-automator
bal build
cd ../..
```

### 3. Build the CLI Wrapper Tool
Build the Java CLI launcher tool:
```bash
./gradlew :connector-cli:build
```
This produces the JAR artifact:
`connector-cli/build/libs/connector-tool-0.1.0.jar`

### 4. Package and Install the CLI Tool Locally
Build the Ballerina tool package and push it to the local repository, then pull it to install:
```bash
cd connector-tool
bal pack
bal push --repository=local
bal tool pull connector:0.1.0 --repository=local
cd ..
```

---
*Note: Make sure that the required prerequisites (Ballerina Swan Lake, Java, and Gradle) are set up.*
