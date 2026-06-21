package io.ballerina.connectortool.cmd;

import io.ballerina.connectortool.ExitHandler;

/**
 * Test double for {@link ExitHandler} that captures the exit code instead of
 * triggering a real JVM exit. Mirrors the same pattern used in asyncapi-tools.
 */
public class ExitCodeCaptor implements ExitHandler {

    private int exitCode = -1;
    private boolean exitCalled = false;

    @Override
    public void exit(int code) {
        this.exitCode = code;
        this.exitCalled = true;
    }

    /**
     * Returns the captured exit code.
     *
     * @throws IllegalStateException if {@link #exit} was never called
     */
    public int getExitCode() {
        if (!exitCalled) {
            throw new IllegalStateException("exit() was not called");
        }
        return exitCode;
    }

    /** Returns {@code true} if {@link #exit} was called at least once. */
    public boolean wasExitCalled() {
        return exitCalled;
    }
}
