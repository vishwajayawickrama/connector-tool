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

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Resolves and validates the examples output directory for the {@code bal connector openapi} workflow.
 */
public final class ExamplesOutputPathValidationUtils {

    private ExamplesOutputPathValidationUtils() {}

    /**
     * Resolves the examples output directory from the raw CLI value.
     *
     * <p>If {@code exampleDir} is {@code null}, defaults to {@code <cwd>/examples} and creates
     * the directory (including any missing parent directories) before returning.
     * If a path is supplied, it is returned as-is after normalisation — the Ballerina runtime
     * will create it with recursive semantics when examples are written.
     *
     * @param exampleDir raw CLI value for the {@code --example-dir} option, may be {@code null}
     * @return the resolved, normalized absolute path to the examples directory
     * @throws IOException if the default {@code <cwd>/examples} directory cannot be created
     */
    public static Path resolve(String exampleDir) throws IOException {
        if (exampleDir == null) {
            Path defaultPath = Path.of(System.getProperty("user.dir")).resolve("examples");
            Files.createDirectories(defaultPath);
            return defaultPath;
        }
        return Path.of(exampleDir).toAbsolutePath().normalize();
    }
}
