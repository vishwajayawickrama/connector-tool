package io.ballerina.connectortool.cmd;

import io.ballerina.connectortool.workflows.OpenApiAutomatorWorkflow;
import org.testng.Assert;
import org.testng.SkipException;
import org.testng.annotations.AfterClass;
import org.testng.annotations.BeforeClass;
import org.testng.annotations.Test;
import picocli.CommandLine;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.PrintStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;

/**
 * In-process command-level tests for {@link OpenApiAutomatorWorkflow}.
 *
 * <p>All tests cover <em>pre-flight</em> error paths — failures that cause {@code execute()} to
 * exit before it reaches the Ballerina runtime invocation. Because {@code Utils.validateApiKey()}
 * is the very first check, these tests require {@code ANTHROPIC_API_KEY} to be set; otherwise they
 * are skipped gracefully.</p>
 *
 * <p>The in-process pattern is taken from asyncapi-tools:
 * {@code new CommandLine(cmd).parseArgs(args); cmd.execute();}
 * with an injected {@link ExitCodeCaptor} absorbing exit codes.</p>
 */
public class OpenApiAutomatorWorkflowTest {

    private Path tmpDir;
    private Path balProjectDir;   // minimal Ballerina project for tests that need step 3+
    private ByteArrayOutputStream outCapture;
    private ByteArrayOutputStream errCapture;
    private PrintStream outStream;
    private PrintStream errStream;

    @BeforeClass
    public void setup() throws IOException {
        tmpDir = Files.createTempDirectory("connector-cmd-test-" + System.nanoTime());
        outCapture = new ByteArrayOutputStream();
        errCapture = new ByteArrayOutputStream();
        outStream = new PrintStream(outCapture);
        errStream = new PrintStream(errCapture);

        // Minimal Ballerina project to pass BallerinaProjectPathValidationUtils.
        // ProjectLoader requires: Ballerina.toml with [package] + distribution, plus at least
        // one .bal source file. The distribution must match the installed Ballerina version.
        balProjectDir = Files.createDirectory(tmpDir.resolve("bal-project"));
        Files.writeString(balProjectDir.resolve("Ballerina.toml"),
                "[package]\n"
                + "org = \"testorg\"\n"
                + "name = \"testpkg\"\n"
                + "version = \"0.1.0\"\n"
                + "distribution = \"2201.13.4\"\n");
        Files.writeString(balProjectDir.resolve("stub.bal"), "// stub\n");
    }

    @BeforeClass(dependsOnMethods = "setup")
    public void requireApiKey() {
        String key = System.getenv("ANTHROPIC_API_KEY");
        if (key == null || key.isBlank()) {
            throw new SkipException(
                    "ANTHROPIC_API_KEY is not set — skipping command-level tests. "
                    + "Set the env var to run this test class.");
        }
    }

    @AfterClass
    public void cleanup() throws IOException {
        Files.walk(tmpDir)
                .sorted(Comparator.reverseOrder())
                .forEach(p -> {
                    try { Files.delete(p); } catch (IOException ignored) {}
                });
        outStream.close();
        errStream.close();
    }

    // ── -q / -v mutual exclusion (step 2 in execute()) ───────────────────────

    @Test(description = "-q and -v together → exit code 2 (flags are mutually exclusive)")
    public void testQuietAndVerboseAreMutuallyExclusive() {
        ExitCodeCaptor captor = new ExitCodeCaptor();
        OpenApiAutomatorWorkflow cmd = new OpenApiAutomatorWorkflow(outStream, errStream, captor);
        new CommandLine(cmd).parseArgs("-q", "-v", "-o", tmpDir.toString());
        cmd.execute();

        Assert.assertTrue(captor.wasExitCalled(), "exit() should have been called");
        Assert.assertEquals(captor.getExitCode(), 2,
                "mutually exclusive flags should exit with code 2");
        assertErrContains("mutually exclusive");
    }

    // ── output path validation (step 3) ──────────────────────────────────────

    @Test(description = "non-existent output path → exit code 1")
    public void testNonExistentOutputPathExitsWithCode1() {
        ExitCodeCaptor captor = new ExitCodeCaptor();
        OpenApiAutomatorWorkflow cmd = new OpenApiAutomatorWorkflow(outStream, errStream, captor);
        new CommandLine(cmd).parseArgs("-o", tmpDir.resolve("does-not-exist").toString());
        cmd.execute();

        Assert.assertTrue(captor.wasExitCalled());
        Assert.assertEquals(captor.getExitCode(), 1);
        assertErrContains("bal: error:");
    }

    @Test(description = "output path is a file (not a directory) → exit code 1")
    public void testOutputPathIsFileExitsWithCode1() throws IOException {
        Path file = Files.createFile(tmpDir.resolve("not-a-dir.txt"));
        ExitCodeCaptor captor = new ExitCodeCaptor();
        OpenApiAutomatorWorkflow cmd = new OpenApiAutomatorWorkflow(outStream, errStream, captor);
        new CommandLine(cmd).parseArgs("-o", file.toString());
        cmd.execute();

        Assert.assertTrue(captor.wasExitCalled());
        Assert.assertEquals(captor.getExitCode(), 1);
    }

    // ── stage validation (step 5) ─────────────────────────────────────────────
    // These tests require balProjectDir to pass step 3.

    @Test(description = "unknown -x stage name → exit code 2")
    public void testUnknownExcludeStageExitsWithCode2() {
        ExitCodeCaptor captor = new ExitCodeCaptor();
        OpenApiAutomatorWorkflow cmd = new OpenApiAutomatorWorkflow(outStream, errStream, captor);
        new CommandLine(cmd).parseArgs("-o", balProjectDir.toString(), "-x", "bogus");
        cmd.execute();

        Assert.assertTrue(captor.wasExitCalled());
        Assert.assertEquals(captor.getExitCode(), 2,
                "unknown stage should produce exit code 2");
        assertErrContains("unknown stage");
    }

    @Test(description = "all 5 stages excluded → exit code 2")
    public void testAllStagesExcludedExitsWithCode2() {
        ExitCodeCaptor captor = new ExitCodeCaptor();
        OpenApiAutomatorWorkflow cmd = new OpenApiAutomatorWorkflow(outStream, errStream, captor);
        new CommandLine(cmd).parseArgs(
                "-o", balProjectDir.toString(),
                "-x", "sanitize", "-x", "client", "-x", "tests", "-x", "examples", "-x", "docs");
        cmd.execute();

        Assert.assertTrue(captor.wasExitCalled());
        Assert.assertEquals(captor.getExitCode(), 2);
    }

    @Test(description = "sanitize excluded but aligned spec absent → exit code 1")
    public void testSanitizeExcludedNoAlignedSpecExitsWithCode1() {
        // The balProjectDir has no docs/spec/aligned_ballerina_openapi.json
        ExitCodeCaptor captor = new ExitCodeCaptor();
        OpenApiAutomatorWorkflow cmd = new OpenApiAutomatorWorkflow(outStream, errStream, captor);
        new CommandLine(cmd).parseArgs(
                "-o", balProjectDir.toString(),
                "-x", "sanitize");
        cmd.execute();

        Assert.assertTrue(captor.wasExitCalled());
        Assert.assertEquals(captor.getExitCode(), 1);
        assertErrContains("aligned spec");
    }

    @Test(description = "client excluded but client.bal absent → exit code 1")
    public void testClientExcludedNoClientBalExitsWithCode1() {
        // balProjectDir has no client.bal
        ExitCodeCaptor captor = new ExitCodeCaptor();
        OpenApiAutomatorWorkflow cmd = new OpenApiAutomatorWorkflow(outStream, errStream, captor);
        new CommandLine(cmd).parseArgs(
                "-o", balProjectDir.toString(),
                "-x", "client");
        cmd.execute();

        Assert.assertTrue(captor.wasExitCalled());
        Assert.assertEquals(captor.getExitCode(), 1);
        assertErrContains("client");
    }

    // ── help flag ─────────────────────────────────────────────────────────────

    @Test(description = "--help flag prints usage and does NOT invoke exit handler")
    public void testHelpFlagPrintsUsageWithoutExit() {
        ExitCodeCaptor captor = new ExitCodeCaptor();
        OpenApiAutomatorWorkflow cmd = new OpenApiAutomatorWorkflow(outStream, errStream, captor);
        new CommandLine(cmd).parseArgs("--help");
        cmd.execute();

        Assert.assertFalse(captor.wasExitCalled(),
                "help flag should not trigger the exit handler");
    }

    // ── helper ───────────────────────────────────────────────────────────────

    /** Flushes and asserts that stderr contains the given substring. */
    private void assertErrContains(String substring) {
        errStream.flush();
        String captured = errCapture.toString();
        Assert.assertTrue(captured.contains(substring),
                "Expected stderr to contain '" + substring + "' but got: " + captured);
        // reset for the next test
        errCapture.reset();
        outCapture.reset();
    }
}
