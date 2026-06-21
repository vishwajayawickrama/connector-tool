package io.ballerina.connectortool.utils;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;
import io.ballerina.connectortool.exceptions.CliException;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;

public class OpenApiPathValidationUtils {

    public static Path validate(String inputPath) {
        if (inputPath == null || inputPath.isBlank()) {
            throw new CliException(null, "missing required option", "'-i'", 2);
        }
        Path specPath = Path.of(inputPath);
        validateOpenApiSpec(specPath.toAbsolutePath().normalize(), "-i");
        return specPath;
    }

    public static void validateOpenApiSpec(Path specPath, String option) {
        if (!Files.exists(specPath)) {
            throw new CliException(option, "no such file", specPath.toString(), 1);
        }
        if (!Files.isRegularFile(specPath)) {
            throw new CliException(option, "not a file", specPath.toString(), 1);
        }
        if (!Files.isReadable(specPath)) {
            throw new CliException(option, "permission denied", specPath.toString(), 1);
        }

        String fileName = specPath.getFileName().toString().toLowerCase(Locale.ROOT);
        boolean jsonSpec = fileName.endsWith(".json");
        boolean yamlSpec = fileName.endsWith(".yaml") || fileName.endsWith(".yml");
        if (!jsonSpec && !yamlSpec) {
            throw new CliException(option, "invalid OpenAPI specification", specPath.toString(), 1);
        }

        try {
            ObjectMapper mapper = jsonSpec ? new ObjectMapper() : new ObjectMapper(new YAMLFactory());
            JsonNode root = mapper.readTree(specPath.toFile());
            if (root == null || !root.isObject()) {
                throw new CliException(option, "invalid OpenAPI specification", specPath.toString(), 1);
            }
            if (!hasNonBlankText(root, "openapi") && !hasNonBlankText(root, "swagger")) {
                throw new CliException(option, "invalid OpenAPI specification", specPath.toString(), 1);
            }
            JsonNode pathsNode = root.get("paths");
            if (pathsNode == null || !pathsNode.isObject()) {
                throw new CliException(option, "invalid OpenAPI specification", specPath.toString(), 1);
            }
        } catch (IOException e) {
            throw new CliException(option, "invalid OpenAPI specification", specPath.toString(), 1);
        }
    }

    private static boolean hasNonBlankText(JsonNode root, String fieldName) {
        JsonNode value = root.get(fieldName);
        return value != null && value.isTextual() && !value.asText().isBlank();
    }
}
