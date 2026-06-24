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
import java.util.List;
import java.util.Set;

/**
 * Validates pipeline stage exclusions for the {@code bal connector openapi} workflow.
 */
public final class OpenApiStageValidationUtils {

    private OpenApiStageValidationUtils() {}

    private static final Set<String> VALID_STAGES = Set.of("sanitize", "client", "tests", "examples", "docs");

    /**
     * Validates all stage-related concerns in order:
     * 1. Unknown stage names → exit 2
     * 2. All stages excluded → exit 2
     * 3. sanitize excluded but aligned spec missing in specDirPath → exit 1
     * 4. client excluded but client.bal missing in outputPath → exit 1
     */
    public static void validate(List<String> excludedStages, Path outputPath, Path specDirPath) {
        for (String stage : excludedStages) {
            if (!VALID_STAGES.contains(stage)) {
                throw new CliException("unknown stage '" + stage + "'", 2,
                        "-x", "valid stages: sanitize, client, tests, examples, docs");
            }
        }

        if (excludedStages.containsAll(VALID_STAGES)) {
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
    }

    /**
     * Returns true when the raw input spec (-i) is required, i.e. when sanitize is not excluded.
     */
    public static boolean isSpecRequired(List<String> excludedStages) {
        return !excludedStages.contains("sanitize");
    }
}
