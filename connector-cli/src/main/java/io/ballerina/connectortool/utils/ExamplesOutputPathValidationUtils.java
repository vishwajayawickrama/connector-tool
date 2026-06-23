package io.ballerina.connectortool.utils;

import java.nio.file.Path;

public final class ExamplesOutputPathValidationUtils {

    private ExamplesOutputPathValidationUtils() {}

    public static Path resolve(String exampleDir) {
        if (exampleDir == null) {
            return Path.of(System.getProperty("user.dir")).resolve("examples");
        }
        Path path = Path.of(exampleDir).toAbsolutePath().normalize();
        PathChecks.requireExists(path, "--example-dir");
        PathChecks.requireDirectory(path, "--example-dir");
        PathChecks.requireWritable(path, "--example-dir");
        Path fileNamePart = path.getFileName();
        String lastName = fileNamePart != null ? fileNamePart.toString() : "";
        if (lastName.equals("example") || lastName.equals("examples")) {
            return path;
        }
        return path.resolve("examples");
    }
}
