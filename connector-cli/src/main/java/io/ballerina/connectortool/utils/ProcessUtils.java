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

/**
 * Helpers for terminating the JVM process with a standard exit code.
 *
 * <p>The {@code exit} parameter on each method allows callers (e.g. tests) to
 * suppress the actual {@link Runtime#exit} call while still exercising the logic.
 */
public class ProcessUtils {

    /**
     * Exits the process with code {@code 0} when {@code exit} is {@code true}.
     *
     * @param exit whether to actually call {@link Runtime#exit}
     */
    public static void exitSuccess(boolean exit) {
        exit(0, exit);
    }

    /**
     * Exits the process with code {@code 1} when {@code exit} is {@code true}.
     *
     * @param exit whether to actually call {@link Runtime#exit}
     */
    public static void exitError(boolean exit) {
        exit(1, exit);
    }

    /**
     * Exits the process with the given {@code code} when {@code exit} is {@code true}.
     *
     * @param code the exit code to pass to {@link Runtime#exit}
     * @param exit whether to actually call {@link Runtime#exit}
     */
    public static void exit(int code, boolean exit) {
        if (exit) {
            Runtime.getRuntime().exit(code);
        }
    }
}
