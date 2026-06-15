package io.ballerina.connectortool.utils;

import java.nio.file.Path;

public final class SpecDirResolutionUtils {

    private SpecDirResolutionUtils() {}
    
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
