package io.ballerina.connectortool.openapi;

import io.ballerina.connectortool.ConnectorIntegrationTest;
import io.ballerina.connectortool.TestUtil;
import io.ballerina.connectortool.TestUtil.ProcessResult;
import org.testng.Assert;
import org.testng.annotations.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;

/**
 * Integration tests for {@code bal connector openapi} error / pre-flight paths.
 *
 * <p>Most tests inject a fake {@code ANTHROPIC_API_KEY} so the API-key check passes and we reach
 * the actual validation being tested. The missing-key test uses
 * {@link TestUtil#executeConnectorWithoutApiKey} to guarantee the key is fully absent in the
 * subprocess — not just overridden with an empty string, which still propagates the parent env
 * value on macOS. None of these tests ever invoke the Ballerina runtime — they all exit before
 * step 8 (the Ballerina function call).</p>
 *
 * <p>Tests are fast (≪ 1 s each) and have no dependency on a real Anthropic API key.
 */
public class OpenApiCLINegativeTests extends ConnectorIntegrationTest {

    /** A fake API key that passes {@code Utils.validateApiKey()} so other checks can be reached. */
    private static final Map<String, String> FAKE_API_KEY =
            Map.of("ANTHROPIC_API_KEY", "test-key-for-integration-tests");

    // ── API key validation (step 1) ───────────────────────────────────────────

    @Test(description = "Missing ANTHROPIC_API_KEY → exit 1 and error on stderr")
    public void testMissingApiKeyExitsWithCode1() throws IOException, InterruptedException {
        // Use executeConnectorWithoutApiKey so the key is fully absent in the subprocess
        // environment — setting it to "" via putAll still inherits the parent-env value on
        // macOS and results in the wrong exit code (2 instead of 1).
        ProcessResult result = TestUtil.executeConnectorWithoutApiKey(tmpDir,
                List.of("openapi", "-o", balProjectDir.toString()));

        Assert.assertEquals(result.exitCode(), 1,
                "Missing API key should exit with code 1");
        TestUtil.assertContains(result.stderr(), "ANTHROPIC_API_KEY",
                "stderr should mention ANTHROPIC_API_KEY");
    }

    // ── -q / -v mutual exclusion (step 2) ────────────────────────────────────

    @Test(description = "-q and -v together → exit 2, stderr contains 'mutually exclusive'")
    public void testQuietAndVerboseAreMutuallyExclusive() throws IOException, InterruptedException {
        ProcessResult result = TestUtil.executeConnector(tmpDir,
                List.of("openapi", "-q", "-v", "-o", balProjectDir.toString()),
                FAKE_API_KEY);

        Assert.assertEquals(result.exitCode(), 2,
                "-q and -v should exit with code 2");
        TestUtil.assertContains(result.stderr(), "mutually exclusive",
                "stderr should say 'mutually exclusive'");
    }

    // ── output path validation (step 3) ──────────────────────────────────────

    @Test(description = "Non-existent output path → exit 1")
    public void testNonExistentOutputPathExitsWithCode1() throws IOException, InterruptedException {
        ProcessResult result = TestUtil.executeConnector(tmpDir,
                List.of("openapi", "-o", tmpDir.resolve("no-such-dir").toString()),
                FAKE_API_KEY);

        Assert.assertEquals(result.exitCode(), 1,
                "Non-existent output path should exit with code 1");
        TestUtil.assertContains(result.stderr(), "bal: error:",
                "stderr should contain formatted error");
    }

    @Test(description = "Output path is a file (not a directory) → exit 1")
    public void testOutputPathIsFileExitsWithCode1() throws IOException, InterruptedException {
        Path notADir = Files.createFile(tmpDir.resolve("not-a-dir.txt"));

        ProcessResult result = TestUtil.executeConnector(tmpDir,
                List.of("openapi", "-o", notADir.toString()),
                FAKE_API_KEY);

        Assert.assertEquals(result.exitCode(), 1);
    }

    // ── stage validation (step 5) ─────────────────────────────────────────────

    @Test(description = "Unknown -x stage name → exit 2, stderr contains 'unknown stage'")
    public void testUnknownStageExitsWithCode2() throws IOException, InterruptedException {
        ProcessResult result = TestUtil.executeConnector(tmpDir,
                List.of("openapi", "-o", balProjectDir.toString(), "-x", "bogus"),
                FAKE_API_KEY);

        Assert.assertEquals(result.exitCode(), 2,
                "Unknown stage should exit with code 2");
        TestUtil.assertContains(result.stderr(), "unknown stage",
                "stderr should mention 'unknown stage'");
    }

    @Test(description = "All 5 stages excluded → exit 2")
    public void testAllStagesExcludedExitsWithCode2() throws IOException, InterruptedException {
        ProcessResult result = TestUtil.executeConnector(tmpDir,
                List.of("openapi",
                        "-o", balProjectDir.toString(),
                        "-x", "sanitize",
                        "-x", "client",
                        "-x", "tests",
                        "-x", "examples",
                        "-x", "docs"),
                FAKE_API_KEY);

        Assert.assertEquals(result.exitCode(), 2,
                "All stages excluded should exit with code 2");
    }

    @Test(description = "sanitize excluded but aligned spec absent → exit 1")
    public void testSanitizeExcludedNoAlignedSpecExitsWithCode1()
            throws IOException, InterruptedException {

        // Create a fresh output dir with NO aligned spec
        Path freshOutDir = Files.createDirectory(tmpDir.resolve("fresh-output"));
        Files.writeString(freshOutDir.resolve("Ballerina.toml"),
                "[package]\norg = \"testorg\"\nname = \"freshpkg\"\nversion = \"0.1.0\"\n"
                + "distribution = \"2201.13.4\"\n");
        Files.writeString(freshOutDir.resolve("stub.bal"), "// stub\n");

        ProcessResult result = TestUtil.executeConnector(tmpDir,
                List.of("openapi",
                        "-o", freshOutDir.toString(),
                        "-x", "sanitize"),
                FAKE_API_KEY);

        Assert.assertEquals(result.exitCode(), 1,
                "sanitize excluded with missing aligned spec should exit with code 1");
        TestUtil.assertContains(result.stderr(), "aligned spec",
                "stderr should mention 'aligned spec'");
    }

    @Test(description = "client excluded but client.bal absent → exit 1")
    public void testClientExcludedNoClientBalExitsWithCode1()
            throws IOException, InterruptedException {

        // The base-class specDir lives at balProjectDir/docs/spec.  Without --spec-dir, the tool
        // resolves the spec directory relative to the subprocess CWD (tmpDir/docs/spec), which is
        // a different path — making the sanitize pre-flight fire instead of the client check.
        // Passing --spec-dir points to the path where aligned_ballerina_openapi.json actually is,
        // so the -x sanitize pre-flight passes and the -x client pre-flight can be reached.
        ProcessResult result = TestUtil.executeConnector(tmpDir,
                List.of("openapi",
                        "-o", balProjectDir.toString(),
                        "--spec-dir", specDir.toString(),
                        "-x", "sanitize",   // aligned spec found at specDir → passes
                        "-x", "client"),    // client.bal missing → exit 1
                FAKE_API_KEY);

        Assert.assertEquals(result.exitCode(), 1,
                "client excluded with missing client.bal should exit with code 1");
        TestUtil.assertContains(result.stderr(), "client",
                "stderr should mention 'client'");
    }

    // ── spec file validation (step 6, when sanitize is excluded) ─────────────
    //   Sanitize excluded → spec file is NOT validated (spec path is optional).
    //   The test below verifies that an invalid spec file provided with -i is caught
    //   when sanitize IS active (i.e., spec is required and validated).

    @Test(description = "Invalid spec file (txt extension) → exit 1")
    public void testInvalidSpecFileExitsWithCode1() throws IOException, InterruptedException {
        Path badSpec = Files.createFile(tmpDir.resolve("bad-spec.txt"));
        Files.writeString(badSpec, "not an openapi spec");

        ProcessResult result = TestUtil.executeConnector(tmpDir,
                List.of("openapi",
                        "-i", badSpec.toString(),
                        "-o", balProjectDir.toString()),
                FAKE_API_KEY);

        Assert.assertEquals(result.exitCode(), 1,
                "Spec with .txt extension should exit with code 1");
    }
}
