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

package io.ballerina.connectortool.exceptions;

public class CliException extends RuntimeException {
    private final String option;
    private final String description;
    private final String detail;
    private final int exitCode;

    /**
     * Constructs a new CliException with all details.
     *
     * <p>Produces a message of the form:
     * <pre>bal: error: '&lt;option&gt;': &lt;description&gt;: &lt;detail&gt;</pre>
     *
     * @param description    human-readable explanation of what went wrong
     *                       (e.g. {@code "no such file or directory"})
     * @param exitCode       process exit code to use when the exception is caught at the top level
     * @param option         the CLI flag that triggered the error (e.g. {@code "-i"}),
     *                       or {@code null} when the error is not tied to a specific option
     * @param detail         the concrete path, value, or hint that qualifies the description
     *                       (e.g. the offending file path or a list of valid values);
     *                       omitted from the message when {@code null} or blank
     */
    public CliException(String description, int exitCode, String option, String detail) {
        this.option = option;
        this.description = description;
        this.detail = detail;
        this.exitCode = exitCode;
    }

    /**
     * Constructs a new CliException with a description and exit code.
     *
     * <p>Produces a message of the form:
     * <pre>bal: error: &lt;description&gt;</pre>
     *
     * @param description    human-readable explanation of what went wrong
     *                       (e.g. {@code "no such file or directory"})
     * @param exitCode       process exit code to use when the exception is caught at the top level
     */
    public CliException(String description, int exitCode) {
        this.option = null;
        this.description = description;
        this.detail = null;
        this.exitCode = exitCode;
    }

    public String getFormattedMessage() {
        if (option != null && !option.isEmpty()) {
            return "bal: error: '" + option + "': " + description
                    + (detail != null && !detail.isEmpty() ? ": " + detail : "");
        } else {
            return "bal: error: " + description + (detail != null && !detail.isEmpty() ? ": " + detail : "");
        }
    }

    public int getExitCode() {
        return exitCode;
    }
}
