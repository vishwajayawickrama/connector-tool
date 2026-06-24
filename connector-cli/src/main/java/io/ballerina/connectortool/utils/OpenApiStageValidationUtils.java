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

import io.ballerina.connectortool.exceptions.CliException;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.List;

/**
 * Validates pipeline stage exclusions for the {@code bal connector openapi} workflow.
 */
public final class OpenApiStageValidationUtils {

    private OpenApiStageValidationUtils() {}

    /** The set of pipeline stages that may be excluded via {@code -x/--exclude}. */
    public enum ValidStages {
        SANITIZE,
        CLIENT,
        TESTS,
        EXAMPLES,
        DOCS
    }

    /**
     * Validates all stage-related concerns and returns the comma-separated lowercase stage names
     * to forward to Ballerina. Validation order:
     * 1. Unknown stage names → exit 2
     * 2. All stages excluded → exit 2
     * 3. sanitize excluded but aligned spec missing in specDirPath → exit 1
     * 4. client excluded but client.bal missing in outputPath → exit 1
     *
     * @param excludedStages raw stage names from {@code -x/--exclude} CLI options
     * @param outputPath     resolved Ballerina project directory
     * @param specDirPath    resolved spec directory ({@code docs/spec})
     * @return comma-separated lowercase stage names to pass to the Ballerina runtime
     * @throws CliException if any validation check fails
     */
    public static String resolve(List<String> excludedStages, Path outputPath, Path specDirPath) {
        for (String stage : excludedStages) {
            try {
                ValidStages.valueOf(stage.toUpperCase());
            } catch (IllegalArgumentException e) {
                throw new CliException("unknown stage '" + stage + "'", 2,
                        "-x", "valid stages: sanitize, client, tests, examples, docs");
            }
        }

        if (Arrays.stream(ValidStages.values())
                .allMatch(s -> excludedStages.contains(s.name().toLowerCase()))) {
            throw new CliException("all pipeline stages excluded — nothing to run", 2);
        }

        if (excludedStages.contains("sanitize")) {
            Path alignedSpec = specDirPath.resolve("aligned_ballerina_openapi.json");
            if (!Files.exists(alignedSpec)) {
                throw new CliException("sanitize excluded but aligned spec not found", 1,
                        "-x", alignedSpec + " — run without -x sanitize to generate it first");
            }
        }

        if (excludedStages.contains("client")) {
            Path clientBal = outputPath.resolve("client.bal");
            if (!Files.exists(clientBal)) {
                throw new CliException("client stage excluded but no existing client found", 1,
                        "-x", clientBal + " — run without -x client to generate it first");
            }
        }

        return String.join(",", excludedStages);
    }

    /**
     * Returns {@code true} when the raw input spec ({@code -i}) is required,
     * i.e. when the {@code sanitize} stage is not excluded.
     *
     * @param excludedStages raw stage names from {@code -x/--exclude} CLI options
     * @return {@code true} if {@code -i} must be provided
     */
    public static boolean isSpecRequired(List<String> excludedStages) {
        return !excludedStages.contains("sanitize");
    }
}
