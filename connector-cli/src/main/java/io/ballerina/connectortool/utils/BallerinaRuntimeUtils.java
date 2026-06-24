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

import io.ballerina.runtime.api.Module;
import io.ballerina.runtime.api.Runtime;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BError;

/**
 * Utility methods for invoking Ballerina connector-automator workflow functions
 * from the JVM via the Ballerina runtime API.
 */
public class BallerinaRuntimeUtils {

    private static final String ORG = "wso2";
    private static final String MODULE = "connector_automator";
    private static final String VERSION = "0";

    /**
     * Invokes the {@code runSdkWorkflow} Ballerina function with the provided arguments.
     *
     * @param args string array of CLI arguments forwarded to the SDK workflow
     * @throws RuntimeException if the function returns a {@code BError} or an unexpected exception occurs
     */
    public static void runSdkWorkflow(BArray args) {
        Runtime runtime = null;
        try {
            Module balModule = new Module(ORG, MODULE, VERSION);
            runtime = Runtime.from(balModule);
            runtime.init();
            runtime.start();

            Object result = runtime.callFunction(balModule, "runSdkWorkflow", null, args);
            if (result instanceof BError error) {
                throw new RuntimeException(error.getErrorMessage().toString());
            }
        } catch (RuntimeException e) {
            throw e;
        } catch (Exception e) {
            throw new RuntimeException(e.getMessage(), e);
        } finally {
            if (runtime != null) {
                runtime.stop();
            }
        }
    }

    /**
     * Invokes the {@code runOpenApiGenerationWorkflow} Ballerina function with the OpenAPI pipeline arguments.
     *
     * @param inputPath      path to the OpenAPI specification file, or empty string when not required
     * @param outputPath     path to the Ballerina connector project
     * @param logLevel       one of {@code "quiet"}, {@code "normal"}, or {@code "verbose"}
     * @param examplesDir    output directory for generated examples
     * @param excludedStages comma-separated list of pipeline stages to skip
     * @param specDir        directory where aligned spec artefacts are stored
     * @param license        path to a license header file, or empty string to use the default
     * @param tags           comma-separated OpenAPI tags to filter during client generation
     * @param operations     comma-separated OpenAPI operation IDs to filter during client generation
     * @param clientMethod   {@code "remote"} to generate remote methods, or empty string for resource methods
     * @param interactiveArg {@code "interactive"} to pause between stages, or empty string for unattended mode
     * @throws RuntimeException if the function returns a {@code BError} or an unexpected exception occurs
     */
    public static void runOpenApiWorkflow(String inputPath, String outputPath, String logLevel,
            String examplesDir, String excludedStages, String specDir, String license,
            String tags, String operations, String clientMethod, String interactiveArg) {
        Runtime runtime = null;
        try {
            Module balModule = new Module(ORG, MODULE, VERSION);
            runtime = Runtime.from(balModule);
            runtime.init();
            runtime.start();

            Object result = runtime.callFunction(balModule, "runOpenApiGenerationWorkflow", null,
                    StringUtils.fromString(inputPath), StringUtils.fromString(outputPath),
                    StringUtils.fromString(logLevel), StringUtils.fromString(examplesDir),
                    StringUtils.fromString(excludedStages), StringUtils.fromString(specDir),
                    StringUtils.fromString(license), StringUtils.fromString(tags),
                    StringUtils.fromString(operations), StringUtils.fromString(clientMethod),
                    StringUtils.fromString(interactiveArg));
            if (result instanceof BError error) {
                throw new RuntimeException(error.getErrorMessage().toString());
            }
        } catch (RuntimeException e) {
            throw e;
        } catch (Exception e) {
            throw new RuntimeException(e.getMessage(), e);
        } finally {
            if (runtime != null) {
                runtime.stop();
            }
        }
    }
}
