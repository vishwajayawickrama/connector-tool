package io.ballerina.connectortool;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.PrintStream;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * Subprocess helper utilities for connector integration tests.
 *
 * <p>All public methods invoke the installed {@code bal connector} command via
 * {@link ProcessBuilder}. Tests that need the connector tool to be installed check
 * {@link #isConnectorToolAvailable()} in a {@code @BeforeClass} and skip gracefully via
 * {@code SkipException} when it is absent.</p>
 *
 * <p>Stream draining is done concurrently (separate threads) to avoid the deadlock that occurs
 * when the subprocess fills its OS pipe buffer before {@code waitFor()} returns.</p>
 */
public final class TestUtil {

    static final PrintStream OUT = System.out;

    private TestUtil() {}

    // ── Result type ────────────────────────────────────────────────────────────

    /** Immutable result of a subprocess invocation. */
    public record ProcessResult(int exitCode, String stdout, String stderr) {}

    // ── Subprocess invocation ─────────────────────────────────────────────────

    /**
     * Runs {@code bal connector <args>} in {@code workDir} and returns the result.
     *
     * <p>{@code extraEnv} entries are merged into the subprocess environment on top of the
     * current process environment. Pass an empty map to inherit the parent environment as-is.</p>
     */
    public static ProcessResult executeConnector(
            Path workDir, List<String> args, Map<String, String> extraEnv)
            throws IOException, InterruptedException {

        List<String> command = buildCommand(args);
        OUT.println("Executing: " + String.join(" ", command));

        ProcessBuilder pb = new ProcessBuilder(command);
        pb.directory(workDir.toFile());
        pb.environment().putAll(extraEnv);

        return run(pb);
    }

    /**
     * Convenience overload that inherits the current process environment with no extras.
     */
    public static ProcessResult executeConnector(Path workDir, List<String> args)
            throws IOException, InterruptedException {
        return executeConnector(workDir, args, Map.of());
    }

    /**
     * Runs {@code bal connector <args>} with {@code ANTHROPIC_API_KEY} fully removed from the
     * subprocess environment — it is not just set to an empty string, it is absent entirely.
     *
     * <p>Use this to test the "missing API key" error path reliably even when the current shell
     * already has {@code ANTHROPIC_API_KEY} set; {@code putAll(Map.of("...", ""))} would only
     * override with an empty string, which ProcessBuilder inherits on top of the parent env.</p>
     */
    public static ProcessResult executeConnectorWithoutApiKey(Path workDir, List<String> args)
            throws IOException, InterruptedException {

        List<String> command = buildCommand(args);
        OUT.println("Executing (no API key): " + String.join(" ", command));

        ProcessBuilder pb = new ProcessBuilder(command);
        pb.directory(workDir.toFile());
        pb.environment().remove("ANTHROPIC_API_KEY");

        return run(pb);
    }

    /**
     * Returns {@code true} when the {@code bal connector} command is available on PATH.
     * Runs {@code bal connector --help} and checks that it exits normally.
     */
    public static boolean isConnectorToolAvailable() {
        try {
            ProcessResult result = executeConnector(
                    Path.of(System.getProperty("user.dir")),
                    List.of("--help"),
                    Map.of());
            // --help exits 0 regardless of whether there are subcommands
            return result.exitCode() == 0;
        } catch (Exception e) {
            OUT.println("bal connector not available: " + e.getMessage());
            return false;
        }
    }

    // ── Assertion helpers ─────────────────────────────────────────────────────

    /**
     * Asserts that the given {@code content} string contains {@code expectedSubstring},
     * after normalising consecutive whitespace to a single space.
     */
    public static void assertContains(String content, String expectedSubstring,
                                      String failMessage) {
        String normalised = content.trim().replaceAll("\\s+", " ");
        String normExpected = expectedSubstring.trim().replaceAll("\\s+", " ");
        if (!normalised.contains(normExpected)) {
            throw new AssertionError(failMessage
                    + "\nExpected to contain: " + expectedSubstring
                    + "\nActual content:      " + content);
        }
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    /** Returns {@code "bal.bat"} on Windows, {@code "bal"} everywhere else. */
    static String getBalExecutable() {
        return System.getProperty("os.name", "").startsWith("Windows") ? "bal.bat" : "bal";
    }

    /** Builds the full command list: {@code [bal, connector, <args...>]}. */
    private static List<String> buildCommand(List<String> args) {
        List<String> command = new ArrayList<>();
        command.add(getBalExecutable());
        command.add("connector");
        command.addAll(args);
        return command;
    }

    /**
     * Starts the process described by {@code pb}, drains stdout/stderr concurrently, waits for
     * exit, and returns a {@link ProcessResult}.
     */
    private static ProcessResult run(ProcessBuilder pb) throws IOException, InterruptedException {
        Process process = pb.start();

        // Drain stdout and stderr concurrently — prevents deadlock when output is large.
        StringBuilder stdoutSb = new StringBuilder();
        StringBuilder stderrSb = new StringBuilder();
        Thread outThread = drainStream(process.getInputStream(), stdoutSb);
        Thread errThread = drainStream(process.getErrorStream(), stderrSb);

        int exitCode = process.waitFor();
        outThread.join();
        errThread.join();

        OUT.println("Exit code: " + exitCode);
        if (!stderrSb.isEmpty()) {
            OUT.println("stderr: " + stderrSb);
        }

        return new ProcessResult(exitCode, stdoutSb.toString(), stderrSb.toString());
    }

    /** Drains {@code stream} into {@code sb} on a background thread; returns the thread. */
    private static Thread drainStream(InputStream stream, StringBuilder sb) {
        Thread t = new Thread(() -> {
            try (BufferedReader br = new BufferedReader(new InputStreamReader(stream))) {
                sb.append(br.lines().collect(Collectors.joining("\n")));
            } catch (IOException ignored) {}
        });
        t.setDaemon(true);
        t.start();
        return t;
    }
}
