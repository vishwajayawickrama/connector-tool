package io.ballerina.connectortool.utils;

import io.ballerina.connectortool.exceptions.CliException;
import io.ballerina.projects.BuildOptions;
import io.ballerina.projects.Project;
import io.ballerina.projects.ProjectException;
import io.ballerina.projects.ProjectKind;
import io.ballerina.projects.directory.ProjectLoader;

import java.nio.file.Files;
import java.nio.file.Path;

public class BallerinaProjectPathValidationUtils {

    public static Path validate(String outputPath) {
        if (outputPath == null || outputPath.isBlank()) {
            throw new CliException(null, "missing required option", "'-o'", 2);
        }
        Path projectPath = Path.of(outputPath);
        validateBallerinaProject(projectPath.toAbsolutePath().normalize(), "-o");
        return projectPath;
    }

    public static void validateBallerinaProject(Path projectPath, String option) {
        if (!Files.exists(projectPath)) {
            throw new CliException(option, "no such directory", projectPath.toString(), 1);
        }
        if (!Files.isDirectory(projectPath)) {
            throw new CliException(option, "not a directory", projectPath.toString(), 1);
        }
        if (!Files.isRegularFile(projectPath.resolve("Ballerina.toml"))) {
            throw new CliException(option, "not a Ballerina project", projectPath.toString(), 1);
        }

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
