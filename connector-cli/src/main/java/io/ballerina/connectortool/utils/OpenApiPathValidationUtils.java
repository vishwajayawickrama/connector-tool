package io.ballerina.connectortool.utils;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;
import io.ballerina.connectortool.exceptions.CliException;

import java.io.IOException;
import java.nio.file.Path;
import java.util.Locale;

public final class OpenApiPathValidationUtils {

    private OpenApiPathValidationUtils() {}

    public static Path resolve(String inputPath) {
        if (inputPath == null || inputPath.isBlank()) {
            throw new CliException(null, "missing required option", "'-i'", 2);
        }
        Path specPath = Path.of(inputPath).toAbsolutePath().normalize();
        validateOpenApiSpec(specPath, "-i");
        return specPath;
    }

    public static void validateOpenApiSpec(Path specPath, String option) {
        PathChecks.requireExists(specPath, option);
        PathChecks.requireRegularFile(specPath, option);
        PathChecks.requireReadable(specPath, option);

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
