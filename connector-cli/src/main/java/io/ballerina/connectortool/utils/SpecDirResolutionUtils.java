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

import java.nio.file.Path;

/**
 * Resolves the {@code docs/spec} directory used to store aligned specs and sanitation artefacts.
 */
public final class SpecDirResolutionUtils {

    private SpecDirResolutionUtils() {}

    /**
     * Resolves the spec directory from the raw CLI value.
     *
     * <p>If {@code rawSpecDir} is {@code null}, defaults to {@code <cwd>/docs/spec}.
     * If the supplied path already ends with {@code docs/spec} it is returned as-is;
     * otherwise {@code docs/spec} is appended.
     *
     * @param rawSpecDir raw CLI value for the {@code --spec-dir} option, may be {@code null}
     * @return the resolved, normalized absolute path to the spec directory
     */
    public static Path resolve(String rawSpecDir) {
        Path base = rawSpecDir != null
                ? Path.of(rawSpecDir).toAbsolutePath().normalize()
                : Path.of(System.getProperty("user.dir"));

        if (base.endsWith(Path.of("docs/spec"))) {
            return base;
        }
        return base.resolve("docs/spec");
    }
}
