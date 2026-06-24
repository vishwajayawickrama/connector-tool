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
import io.ballerina.projects.BuildOptions;
import io.ballerina.projects.Project;
import io.ballerina.projects.ProjectException;
import io.ballerina.projects.ProjectKind;
import io.ballerina.projects.directory.ProjectLoader;

import java.nio.file.Path;

/**
 * Validates that a given path points to a valid Ballerina build project.
 */
public final class BallerinaProjectPathValidationUtils {

    private BallerinaProjectPathValidationUtils() {}

    /**
     * Resolves and validates the output path as a Ballerina build project.
     *
     * <p>Falls back to the current working directory when {@code outputPath} is {@code null} or blank.
     *
     * @param outputPath raw CLI value for the {@code -o/--output} option, may be {@code null}
     * @return the resolved, normalized absolute path to the Ballerina project
     * @throws io.ballerina.connectortool.exceptions.CliException if the path is not a valid Ballerina project
     */
    public static Path resolve(String outputPath) {
        String raw = (outputPath == null || outputPath.isBlank())
                ? System.getProperty("user.dir")
                : outputPath;
        Path projectPath = Path.of(raw).toAbsolutePath().normalize();
        validateBallerinaProject(projectPath, "-o");
        return projectPath;
    }

    private static void validateBallerinaProject(Path projectPath, String option) {
        PathChecks.requireExists(projectPath, option);
        PathChecks.requireDirectory(projectPath, option);

        try {
            BuildOptions buildOptions = BuildOptions.builder().setOffline(true).build();
            Project project = ProjectLoader.load(projectPath, buildOptions).project();
            if (!project.kind().equals(ProjectKind.BUILD_PROJECT)) {
                throw new CliException("not a Ballerina project", 1, option, projectPath.toString());
            }
        } catch (ProjectException e) {
            throw new CliException("not a Ballerina project", 1, option, projectPath.toString());
        }
    }
}
