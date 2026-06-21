package io.ballerina.connectortool;

import io.ballerina.connectortool.exceptions.CliException;
import io.ballerina.connectortool.utils.OpenApiPathValidationUtils;
import org.testng.Assert;
import org.testng.annotations.AfterClass;
import org.testng.annotations.BeforeClass;
import org.testng.annotations.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Comparator;

public class OpenApiPathValidationUtilsTest {

    private Path tmpDir;

    /** Absolute path to the test fixture specs bundled under src/test/resources/specs/ */
    private static final Path SPEC_RESOURCES =
            Paths.get("src/test/resources/specs").toAbsolutePath();

    @BeforeClass
    public void setup() throws IOException {
        tmpDir = Files.createTempDirectory("connector-openapi-path-test-" + System.nanoTime());
    }

    @AfterClass
    public void cleanup() throws IOException {
        Files.walk(tmpDir)
                .sorted(Comparator.reverseOrder())
                .forEach(p -> {
                    try { Files.delete(p); } catch (IOException ignored) {}
                });
    }

    // ── null / blank ───────────────────────────────────────────────────────────

    @Test(description = "null path throws CliException exit 2 (missing required option)")
    public void testNullPathThrowsExit2() {
        CliException ex = expectCliException(() -> OpenApiPathValidationUtils.resolve(null));
        Assert.assertEquals(ex.getExitCode(), 2);
        Assert.assertTrue(ex.getFormattedMessage().contains("missing required option"));
    }

    @Test(description = "blank path throws CliException exit 2 (missing required option)")
    public void testBlankPathThrowsExit2() {
        CliException ex = expectCliException(() -> OpenApiPathValidationUtils.resolve("   "));
        Assert.assertEquals(ex.getExitCode(), 2);
    }

    // ── path existence / type ─────────────────────────────────────────────────

    @Test(description = "non-existent file path throws CliException exit 1")
    public void testNonExistentFileThrowsExit1() {
        CliException ex = expectCliException(() ->
                OpenApiPathValidationUtils.resolve(tmpDir.resolve("no-such-file.json").toString()));
        Assert.assertEquals(ex.getExitCode(), 1);
    }

    @Test(description = "directory instead of file throws CliException exit 1")
    public void testDirectoryNotFileThrowsExit1() {
        CliException ex = expectCliException(() ->
                OpenApiPathValidationUtils.resolve(tmpDir.toString()));
        Assert.assertEquals(ex.getExitCode(), 1);
    }

    // ── extension ─────────────────────────────────────────────────────────────

    @Test(description = "wrong file extension (.txt) throws CliException exit 1")
    public void testWrongExtensionThrowsExit1() throws IOException {
        Path txtFile = copyFixture("not-openapi.txt", "not-openapi.txt");
        CliException ex = expectCliException(() ->
                OpenApiPathValidationUtils.resolve(txtFile.toString()));
        Assert.assertEquals(ex.getExitCode(), 1);
    }

    // ── valid specs ───────────────────────────────────────────────────────────

    @Test(description = "valid JSON OpenAPI spec returns resolved path")
    public void testValidJsonSpecReturnsPath() throws IOException {
        Path spec = copyFixture("valid-openapi.json", "valid.json");
        Path result = OpenApiPathValidationUtils.resolve(spec.toString());
        Assert.assertNotNull(result);
        Assert.assertEquals(result, spec.toAbsolutePath().normalize());
    }

    @Test(description = "valid YAML OpenAPI spec returns resolved path")
    public void testValidYamlSpecReturnsPath() throws IOException {
        Path spec = copyFixture("valid-openapi.yaml", "valid.yaml");
        Path result = OpenApiPathValidationUtils.resolve(spec.toString());
        Assert.assertNotNull(result);
        Assert.assertEquals(result, spec.toAbsolutePath().normalize());
    }

    @Test(description = ".yml extension is accepted alongside .yaml")
    public void testYmlExtensionAccepted() throws IOException {
        Path spec = copyFixture("valid-openapi.yaml", "valid.yml");
        Path result = OpenApiPathValidationUtils.resolve(spec.toString());
        Assert.assertNotNull(result);
    }

    // ── content validation ────────────────────────────────────────────────────

    @Test(description = "JSON missing 'paths' object throws CliException exit 1")
    public void testMissingPathsObjectThrowsExit1() throws IOException {
        Path spec = copyFixture("missing-paths.json", "missing-paths.json");
        CliException ex = expectCliException(() ->
                OpenApiPathValidationUtils.resolve(spec.toString()));
        Assert.assertEquals(ex.getExitCode(), 1);
    }

    @Test(description = "JSON missing 'openapi'/'swagger' key throws CliException exit 1")
    public void testMissingOpenApiKeyThrowsExit1() throws IOException {
        Path spec = copyFixture("missing-openapi-key.json", "missing-key.json");
        CliException ex = expectCliException(() ->
                OpenApiPathValidationUtils.resolve(spec.toString()));
        Assert.assertEquals(ex.getExitCode(), 1);
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    /** Copies a fixture from src/test/resources/specs/ into the temp dir under a given name. */
    private Path copyFixture(String fixture, String destName) throws IOException {
        Path dest = tmpDir.resolve(destName);
        Files.copy(SPEC_RESOURCES.resolve(fixture), dest);
        return dest;
    }

    /** Runs {@code action}, asserts it throws {@link CliException}, and returns the exception. */
    private static CliException expectCliException(Runnable action) {
        try {
            action.run();
            Assert.fail("Expected CliException but no exception was thrown");
            return null; // unreachable
        } catch (CliException ex) {
            return ex;
        }
    }
}
