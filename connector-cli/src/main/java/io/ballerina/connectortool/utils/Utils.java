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

/**
 * General-purpose utility methods shared across {@code connector-cli} workflows.
 */
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
