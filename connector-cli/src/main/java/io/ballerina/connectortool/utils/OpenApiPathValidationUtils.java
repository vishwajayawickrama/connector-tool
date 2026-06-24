/*
 * Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.connectortool.utils;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;
import io.ballerina.connectortool.exceptions.CliException;

import java.io.IOException;
import java.nio.file.Path;
import java.util.Locale;

/**
 * Validates that a given path points to a readable, well-formed OpenAPI specification file.
 */
public final class OpenApiPathValidationUtils {

    private OpenApiPathValidationUtils() {}

    /**
     * Resolves and validates the input path as an OpenAPI specification file.
     *
     * @param inputPath raw CLI value for the {@code -i/--input} option, may be {@code null}
     * @return the resolved, normalized absolute path to the OpenAPI specification
     * @throws io.ballerina.connectortool.exceptions.CliException if the path is missing or invalid
     */
    public static Path resolve(String inputPath) {
        if (inputPath == null || inputPath.isBlank()) {
            throw new CliException("missing required option", 2, null, "'-i'");
        }
        Path specPath = Path.of(inputPath).toAbsolutePath().normalize();
        validateOpenApiSpec(specPath, "-i");
        return specPath;
    }

    private static void validateOpenApiSpec(Path specPath, String option) {
        PathChecks.requireExists(specPath, option);
        PathChecks.requireRegularFile(specPath, option);
        PathChecks.requireReadable(specPath, option);

        Path fileNamePart = specPath.getFileName();
        String fileName = fileNamePart != null ? fileNamePart.toString().toLowerCase(Locale.ROOT) : "";
        boolean jsonSpec = fileName.endsWith(".json");
        boolean yamlSpec = fileName.endsWith(".yaml") || fileName.endsWith(".yml");
        if (!jsonSpec && !yamlSpec) {
            throw new CliException("invalid OpenAPI specification", 1, option, specPath.toString());
        }

        try {
            ObjectMapper mapper = jsonSpec ? new ObjectMapper() : new ObjectMapper(new YAMLFactory());
            JsonNode root = mapper.readTree(specPath.toFile());
            if (root == null || !root.isObject()) {
                throw new CliException("invalid OpenAPI specification", 1, option, specPath.toString());
            }
            if (!hasNonBlankText(root, "openapi") && !hasNonBlankText(root, "swagger")) {
                throw new CliException("invalid OpenAPI specification", 1, option, specPath.toString());
            }
            JsonNode pathsNode = root.get("paths");
            if (pathsNode == null || !pathsNode.isObject()) {
                throw new CliException("invalid OpenAPI specification", 1, option, specPath.toString());
            }
        } catch (IOException e) {
            throw new CliException("invalid OpenAPI specification", 1, option, specPath.toString());
        }
    }

    private static boolean hasNonBlankText(JsonNode root, String fieldName) {
        JsonNode value = root.get(fieldName);
        return value != null && value.isTextual() && !value.asText().isBlank();
    }
}
