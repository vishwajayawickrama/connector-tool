package io.ballerina.connectortool.utils;

import io.ballerina.connectortool.exceptions.CliException;

public final class Utils {

    private static final String API_KEY_ENV_VAR = "ANTHROPIC_API_KEY";

    private Utils() {}

    /**
     * Throws a {@link CliException} with exit code 1 if {@code ANTHROPIC_API_KEY}
     * is not set or is blank.
     */
    public static void validateApiKey() throws CliException {
        String apiKey = System.getenv(API_KEY_ENV_VAR);
        if (apiKey == null || apiKey.isBlank()) {
            throw new CliException("ANTHROPIC_API_KEY environment variable is not set", 1);
        }
    }
}
