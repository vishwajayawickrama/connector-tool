package io.ballerina.connectortool;

import io.ballerina.connectortool.exceptions.CliException;
import io.ballerina.connectortool.utils.OpenApiStageValidationUtils;
import org.testng.Assert;
import org.testng.annotations.AfterClass;
import org.testng.annotations.BeforeClass;
import org.testng.annotations.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

public class OpenApiStageValidationUtilsTest {

    private Path tmpDir;
    private Path outputPath;
    private Path specDirPath;

    @BeforeClass
    public void setup() throws IOException {
        tmpDir = Files.createTempDirectory("connector-stage-test-" + System.nanoTime());
        outputPath = Files.createDirectory(tmpDir.resolve("output"));
        specDirPath = Files.createDirectories(tmpDir.resolve("docs").resolve("spec"));
    }

    @AfterClass
    public void cleanup() throws IOException {
        Files.walk(tmpDir)
                .sorted(Comparator.reverseOrder())
                .forEach(p -> {
                    try { Files.delete(p); } catch (IOException ignored) {}
                });
    }

    // ── unknown stage ──────────────────────────────────────────────────────────

    @Test(description = "unknown stage name throws CliException exit 2")
    public void testUnknownStageThrowsExit2() {
        CliException ex = expectCliException(() ->
                OpenApiStageValidationUtils.validate(List.of("bogus"), outputPath, specDirPath));
        Assert.assertEquals(ex.getExitCode(), 2);
        Assert.assertTrue(ex.getFormattedMessage().contains("unknown stage"),
                "Message should mention 'unknown stage': " + ex.getFormattedMessage());
    }

    @Test(description = "unknown stage name error message includes the bad stage")
    public void testUnknownStageMessageIncludesBadStageName() {
        CliException ex = expectCliException(() ->
                OpenApiStageValidationUtils.validate(List.of("compile"), outputPath, specDirPath));
        Assert.assertTrue(ex.getFormattedMessage().contains("compile"),
                "Message should include the bad stage name: " + ex.getFormattedMessage());
    }

    // ── all stages excluded ────────────────────────────────────────────────────

    @Test(description = "excluding all 5 stages throws CliException exit 2")
    public void testAllStagesExcludedThrowsExit2() {
        List<String> all = Arrays.asList("sanitize", "client", "tests", "examples", "docs");
        CliException ex = expectCliException(() ->
                OpenApiStageValidationUtils.validate(all, outputPath, specDirPath));
        Assert.assertEquals(ex.getExitCode(), 2);
    }

    // ── sanitize excluded ─────────────────────────────────────────────────────

    @Test(description = "sanitize excluded with no aligned spec throws CliException exit 1")
    public void testSanitizeExcludedNoAlignedSpecThrowsExit1() {
        CliException ex = expectCliException(() ->
                OpenApiStageValidationUtils.validate(List.of("sanitize"), outputPath, specDirPath));
        Assert.assertEquals(ex.getExitCode(), 1);
        Assert.assertTrue(ex.getFormattedMessage().contains("aligned spec"),
                "Message should mention 'aligned spec': " + ex.getFormattedMessage());
    }

    @Test(description = "sanitize excluded with aligned spec present succeeds")
    public void testSanitizeExcludedWithAlignedSpecSucceeds() throws IOException {
        Path alignedSpec = specDirPath.resolve("aligned_ballerina_openapi.json");
        Files.createFile(alignedSpec);
        try {
            // should not throw
            OpenApiStageValidationUtils.validate(List.of("sanitize"), outputPath, specDirPath);
        } finally {
            Files.deleteIfExists(alignedSpec);
        }
    }

    // ── client excluded ───────────────────────────────────────────────────────

    @Test(description = "client excluded with no client.bal throws CliException exit 1")
    public void testClientExcludedNoClientBalThrowsExit1() {
        CliException ex = expectCliException(() ->
                OpenApiStageValidationUtils.validate(List.of("client"), outputPath, specDirPath));
        Assert.assertEquals(ex.getExitCode(), 1);
        Assert.assertTrue(ex.getFormattedMessage().contains("client"),
                "Message should mention 'client': " + ex.getFormattedMessage());
    }

    @Test(description = "client excluded with client.bal present succeeds")
    public void testClientExcludedWithClientBalSucceeds() throws IOException {
        Path clientBal = outputPath.resolve("client.bal");
        Files.createFile(clientBal);
        try {
            OpenApiStageValidationUtils.validate(List.of("client"), outputPath, specDirPath);
        } finally {
            Files.deleteIfExists(clientBal);
        }
    }

    // ── no exclusions ─────────────────────────────────────────────────────────

    @Test(description = "empty exclusion list succeeds (no pre-flight checks needed)")
    public void testEmptyExclusionListSucceeds() {
        // should not throw
        OpenApiStageValidationUtils.validate(Collections.emptyList(), outputPath, specDirPath);
    }

    @Test(description = "excluding only 'tests' and 'examples' succeeds")
    public void testPartialExclusionSucceeds() {
        // should not throw — sanitize and client are still active, and spec/client.bal not checked
        OpenApiStageValidationUtils.validate(List.of("tests", "examples"), outputPath, specDirPath);
    }

    // ── isSpecRequired ────────────────────────────────────────────────────────

    @Test(description = "isSpecRequired returns true when sanitize is not excluded")
    public void testIsSpecRequiredWhenSanitizeActive() {
        Assert.assertTrue(OpenApiStageValidationUtils.isSpecRequired(Collections.emptyList()));
        Assert.assertTrue(OpenApiStageValidationUtils.isSpecRequired(List.of("tests")));
        Assert.assertTrue(OpenApiStageValidationUtils.isSpecRequired(List.of("client", "docs")));
    }

    @Test(description = "isSpecRequired returns false when sanitize is excluded")
    public void testIsSpecRequiredWhenSanitizeExcluded() {
        Assert.assertFalse(OpenApiStageValidationUtils.isSpecRequired(List.of("sanitize")));
        Assert.assertFalse(OpenApiStageValidationUtils.isSpecRequired(
                List.of("sanitize", "tests")));
    }

    // ── helper ────────────────────────────────────────────────────────────────

    private static CliException expectCliException(Runnable action) {
        try {
            action.run();
            Assert.fail("Expected CliException but no exception was thrown");
            return null;
        } catch (CliException ex) {
            return ex;
        }
    }
}
