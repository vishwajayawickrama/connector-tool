package io.ballerina.connectortool.openapi;

import io.ballerina.connectortool.ConnectorIntegrationTest;
import io.ballerina.connectortool.TestUtil;
import io.ballerina.connectortool.TestUtil.ProcessResult;
import org.testng.Assert;
import org.testng.SkipException;
import org.testng.annotations.BeforeClass;
import org.testng.annotations.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.util.List;
import java.util.Map;

/**
 * Integration tests for {@code bal connector openapi} happy-path client generation.
 *
 * <p>These tests invoke {@code bal openapi} (via the Ballerina pipeline) to generate a real
 * Ballerina client. They skip when {@code ANTHROPIC_API_KEY} is not set — the API key check
 * happens before any pipeline stage, so even client-only runs require it to be present.
 *
 * <p>All AI-heavy stages (sanitize, tests, examples, docs) are excluded via {@code -x} so
 * no real Anthropic calls are made. The input is a pre-sanitized aligned spec fixture.</p>
 */
public class OpenApiClientGenerationTests extends ConnectorIntegrationTest {

    // ── Guards ────────────────────────────────────────────────────────────────

    @BeforeClass(dependsOnMethods = "setup", alwaysRun = true)
    public void requireApiKey() {
        String key = System.getenv("ANTHROPIC_API_KEY");
        if (key == null || key.isBlank()) {
            throw new SkipException(
                    "ANTHROPIC_API_KEY is not set — skipping client generation tests. "
                    + "Set the environment variable to any non-blank value to run them.");
        }
    }

    // ── Tests ─────────────────────────────────────────────────────────────────

    /**
     * Runs the pipeline with only the client stage active (sanitize + tests + examples + docs
     * all excluded). The aligned spec fixture is pre-placed in {@link #specDir} by the base
     * class. Verifies that {@code client.bal} is generated in the output directory.
     *
     * <p>This test invokes {@code bal openapi} under the hood (no Claude API calls).
     */
    @Test(description = "Client-only pipeline generates client.bal from pre-aligned spec")
    public void testClientOnlyGeneratesClientBal() throws IOException, InterruptedException {
        ProcessResult result = TestUtil.executeConnector(tmpDir,
                List.of("openapi",
                        "--spec-dir", specDir.toString(),
                        "-o", balProjectDir.toString(),
                        "-x", "sanitize",
                        "-x", "tests",
                        "-x", "examples",
                        "-x", "docs"),
                Map.of()); // use env-inherited ANTHROPIC_API_KEY (already set — requireApiKey guards)

        Assert.assertEquals(result.exitCode(), 0,
                "Client-only pipeline should exit 0. stderr: " + result.stderr());

        Assert.assertTrue(Files.exists(balProjectDir.resolve("client.bal")),
                "client.bal should be generated in the output directory");
    }

    /**
     * Verifies that {@code types.bal} is also generated alongside {@code client.bal}.
     * Runs only when the previous client generation test has already created the files
     * (depends on {@link #testClientOnlyGeneratesClientBal}).
     */
    @Test(description = "Client generation also produces types.bal",
          dependsOnMethods = "testClientOnlyGeneratesClientBal")
    public void testClientGenerationProducesTypesBal() {
        Assert.assertTrue(Files.exists(balProjectDir.resolve("types.bal")),
                "types.bal should be generated alongside client.bal");
    }

    /**
     * Verifies that the generated {@code client.bal} contains a Ballerina client class
     * declaration — a minimal structural assertion that does not depend on exact content.
     */
    @Test(description = "Generated client.bal contains a client declaration",
          dependsOnMethods = "testClientOnlyGeneratesClientBal")
    public void testGeneratedClientBalContainsClientDeclaration() throws IOException {
        String content = Files.readString(balProjectDir.resolve("client.bal"));
        Assert.assertTrue(content.contains("client class"),
                "client.bal should contain a 'client class' declaration");
    }
}
