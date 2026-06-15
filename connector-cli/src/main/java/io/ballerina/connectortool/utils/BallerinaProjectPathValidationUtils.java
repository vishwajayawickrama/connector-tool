package io.ballerina.connectortool.utils;

import io.ballerina.connectortool.exceptions.CliException;
import io.ballerina.projects.BuildOptions;
import io.ballerina.projects.Project;
import io.ballerina.projects.ProjectException;
import io.ballerina.projects.ProjectKind;
import io.ballerina.projects.directory.ProjectLoader;

import java.nio.file.Path;

public final class BallerinaProjectPathValidationUtils {

    private BallerinaProjectPathValidationUtils() {}

    public static Path resolve(String outputPath) {
        String raw = (outputPath == null || outputPath.isBlank())
                ? System.getProperty("user.dir")
                : outputPath;
        Path projectPath = Path.of(raw).toAbsolutePath().normalize();
        validateBallerinaProject(projectPath, "-o");
        return projectPath;
    }

    public static void validateBallerinaProject(Path projectPath, String option) {
        PathChecks.requireExists(projectPath, option);
        PathChecks.requireDirectory(projectPath, option);

        try {
            BuildOptions buildOptions = BuildOptions.builder().setOffline(true).build();
            Project project = ProjectLoader.load(projectPath, buildOptions).project();
            if (!project.kind().equals(ProjectKind.BUILD_PROJECT)) {
                throw new CliException(option, "not a Ballerina project", projectPath.toString(), 1);
            }
        } catch (ProjectException e) {
            throw new CliException(option, "not a Ballerina project", projectPath.toString(), 1);
        }
    }
}
