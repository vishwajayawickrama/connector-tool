# Connector Tool Package

This package owns the Ballerina tool metadata for `bal connector`.

Build the Java CLI artifact first, then install this tool package:

```bash
cd ../
./gradlew :connector-cli:build
cd connector-tool
bal pack
bal push --repository=local
bal tool pull connector:0.1.0 --repository=local
```
