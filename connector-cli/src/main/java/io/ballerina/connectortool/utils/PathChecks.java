package io.ballerina.connectortool.utils;

import io.ballerina.connectortool.exceptions.CliException;

import java.nio.file.Files;
import java.nio.file.Path;

final class PathChecks {

    private PathChecks() {}

    static void requireExists(Path p, String option) {
        if (!Files.exists(p)) {
            throw new CliException(option, "no such file or directory", p.toString(), 1);
        }
    }

    static void requireDirectory(Path p, String option) {
        if (!Files.isDirectory(p)) {
            throw new CliException(option, "not a directory", p.toString(), 1);
        }
    }

    static void requireRegularFile(Path p, String option) {
        if (!Files.isRegularFile(p)) {
            throw new CliException(option, "not a file", p.toString(), 1);
        }
    }

    static void requireReadable(Path p, String option) {
        if (!Files.isReadable(p)) {
            throw new CliException(option, "permission denied", p.toString(), 1);
        }
    }

    static void requireWritable(Path p, String option) {
        if (!Files.isWritable(p)) {
            throw new CliException(option, "no write permission", p.toString(), 1);
        }
    }
}
