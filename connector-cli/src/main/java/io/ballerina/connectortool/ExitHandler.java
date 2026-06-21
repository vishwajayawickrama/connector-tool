package io.ballerina.connectortool;

/**
 * Abstraction for process exit behaviour that allows tests to capture exit codes
 * without triggering a real JVM exit.
 *
 * <p>The production default is {@code code -> ProcessUtils.exit(code, true)}.
 * Tests inject an {@code ExitCodeCaptor} instance via the package-private constructor.</p>
 */
@FunctionalInterface
public interface ExitHandler {
    void exit(int code);
}
