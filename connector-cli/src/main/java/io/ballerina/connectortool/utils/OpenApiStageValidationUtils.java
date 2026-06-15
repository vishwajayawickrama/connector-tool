package io.ballerina.connectortool.utils;

import io.ballerina.connectortool.exceptions.CliException;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Set;

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
                throw new CliException("-x", "unknown stage '" + stage + "'",
                        "valid stages: sanitize, client, tests, examples, docs", 2);
            }
        }

        if (excludedStages.containsAll(VALID_STAGES)) {
            throw new CliException("all pipeline stages excluded — nothing to run", 2);
        }

        if (excludedStages.contains("sanitize")) {
            Path alignedSpec = specDirPath.resolve("aligned_ballerina_openapi.json");
            if (!Files.exists(alignedSpec)) {
                throw new CliException("-x", "sanitize excluded but aligned spec not found",
                        alignedSpec + " — run without -x sanitize to generate it first", 1);
            }
        }

        if (excludedStages.contains("client")) {
            Path clientBal = outputPath.resolve("client.bal");
            if (!Files.exists(clientBal)) {
                throw new CliException("-x", "client stage excluded but no existing client found",
                        clientBal + " — run without -x client to generate it first", 1);
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
