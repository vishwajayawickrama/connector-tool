package io.ballerina.connectortool.utils;

import io.ballerina.connectortool.exceptions.CliException;

import java.nio.file.Files;
import java.nio.file.Path;

public class ExamplesOutputPathValidationUtils {

    public static void validate(String exampleDir) {
        Path path = Path.of(exampleDir).toAbsolutePath().normalize();
        if (!Files.exists(path)) {
            throw new CliException("-E", "no such directory", path.toString(), 1);
        }
        if (!Files.isDirectory(path)) {
            throw new CliException("-E", "not a directory", path.toString(), 1);
        }
        if (!Files.isWritable(path)) {
            throw new CliException("-E", "no write permission", path.toString(), 1);
        }
    }

    public static String resolveExamplesDir(String exampleDir, String outputPath) {
        if (exampleDir == null) {
            return outputPath + "/examples";
        }
        String lastName = Path.of(exampleDir).getFileName().toString();
        if (lastName.equals("example") || lastName.equals("examples")) {
            return exampleDir;
        }
        return exampleDir + "/examples";
    }
}
