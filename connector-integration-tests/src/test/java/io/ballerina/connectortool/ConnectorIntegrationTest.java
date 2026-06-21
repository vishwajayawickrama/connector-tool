package io.ballerina.connectortool;

import org.testng.SkipException;
import org.testng.annotations.AfterClass;
import org.testng.annotations.BeforeClass;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Comparator;

/**
 * Abstract base class for connector integration tests.
 *
 * <p>Provides:
 * <ul>
 *   <li>A per-class temporary directory ({@link #tmpDir}) cleaned up in {@code @AfterClass}</li>
 *   <li>A minimal Ballerina project directory ({@link #balProjectDir}) with {@code Ballerina.toml}
 *       and a stub {@code .bal} file — used as the {@code -o} output path for tests that need to
 *       reach past the output-path validation step</li>
 *   <li>A spec directory ({@link #specDir}) pre-populated with the aligned spec fixture, so tests
 *       can use {@code -x sanitize} without failing the "aligned spec missing" pre-flight check</li>
 *   <li>A {@code @BeforeClass} guard that skips the entire test class when {@code bal connector}
 *       is not installed</li>
 * </ul>
 */
public abstract class ConnectorIntegrationTest {

    /** Absolute path to test fixture resources bundled under src/test/resources/. */
    protected static final Path RESOURCE_DIR =
            Paths.get("src/test/resources").toAbsolutePath();

    /** Per-test-class scratch directory deleted after the class finishes. */
    protected Path tmpDir;

    /** Minimal Ballerina project (Ballerina.toml + stub.bal) inside {@link #tmpDir}. */
    protected Path balProjectDir;

    /**
     * Spec directory inside {@link #tmpDir} pre-populated with an aligned OpenAPI spec
     * ({@code aligned_ballerina_openapi.json}). Corresponds to {@code <outputDir>/docs/spec}
     * — the default location when no {@code --spec-dir} flag is passed.
     */
    protected Path specDir;

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    @BeforeClass(alwaysRun = true)
    public void checkToolAvailable() {
        if (!TestUtil.isConnectorToolAvailable()) {
            throw new SkipException(
                    "bal connector is not installed. "
                    + "Install with: bal tool install --local ./connector-tool/ "
                    + "and rebuild the shadow JAR first.");
        }
    }

    @BeforeClass(dependsOnMethods = "checkToolAvailable", alwaysRun = true)
    public void setup() throws IOException {
        tmpDir = Files.createTempDirectory("connector-it-" + System.nanoTime());

        // Minimal Ballerina project — passes BallerinaProjectPathValidationUtils.
        // Needs Ballerina.toml with [package] block + distribution + at least one .bal file.
        balProjectDir = Files.createDirectory(tmpDir.resolve("output"));
        Files.writeString(balProjectDir.resolve("Ballerina.toml"),
                "[package]\n"
                + "org = \"testorg\"\n"
                + "name = \"testpkg\"\n"
                + "version = \"0.1.0\"\n"
                + "distribution = \"2201.13.4\"\n");
        Files.writeString(balProjectDir.resolve("stub.bal"), "// stub\n");

        // Spec dir with a pre-sanitized spec so -x sanitize tests don't fail the pre-flight check.
        specDir = Files.createDirectories(balProjectDir.resolve("docs").resolve("spec"));
        Files.copy(RESOURCE_DIR.resolve("specs").resolve("aligned_ballerina_openapi.json"),
                specDir.resolve("aligned_ballerina_openapi.json"));
    }

    @AfterClass(alwaysRun = true)
    public void cleanup() throws IOException {
        if (tmpDir != null && Files.exists(tmpDir)) {
            Files.walk(tmpDir)
                    .sorted(Comparator.reverseOrder())
                    .forEach(p -> {
                        try { Files.delete(p); } catch (IOException ignored) {}
                    });
        }
    }
}
