package io.ballerina.connectortool;

import io.ballerina.connectortool.utils.SpecDirResolutionUtils;
import org.testng.Assert;
import org.testng.annotations.Test;

import java.nio.file.Path;

public class SpecDirResolutionUtilsTest {

    @Test(description = "null rawSpecDir resolves to <cwd>/docs/spec")
    public void testNullResolvesToCwdDocsSpec() {
        Path result = SpecDirResolutionUtils.resolve(null);
        Path expected = Path.of(System.getProperty("user.dir")).resolve("docs/spec");
        Assert.assertEquals(result, expected.toAbsolutePath().normalize());
    }

    @Test(description = "blank rawSpecDir resolves to <cwd>/docs/spec")
    public void testBlankResolvesToCwdDocsSpec() {
        // A blank string becomes Path.of("") which normalises to cwd
        Path result = SpecDirResolutionUtils.resolve("   ".strip());
        // strip gives "" so Path.of("") is "." i.e. cwd
        // The method does: Path.of(rawSpecDir) when rawSpecDir != null
        // " " strip → "" → Path.of("") → cwd
        Path expected = Path.of("").toAbsolutePath().normalize().resolve("docs/spec");
        Assert.assertEquals(result, expected);
    }

    @Test(description = "path already ending in docs/spec is returned as-is")
    public void testAlreadyEndsWithDocsSpecIsUnchanged() {
        Path input = Path.of("/some/project/docs/spec");
        Path result = SpecDirResolutionUtils.resolve(input.toString());
        Assert.assertEquals(result, input.toAbsolutePath().normalize());
    }

    @Test(description = "plain directory gets docs/spec appended")
    public void testPlainDirAppendsDocsSpec() {
        Path result = SpecDirResolutionUtils.resolve("/some/project");
        Assert.assertEquals(result,
                Path.of("/some/project/docs/spec").toAbsolutePath().normalize());
    }

    @Test(description = "directory ending in 'docs' alone gets the full docs/spec suffix appended")
    public void testDocsOnlyAppendsFullDocsSpec() {
        // The util short-circuits only when the path already ends with "docs/spec".
        // A path ending in "docs" alone still has "docs/spec" appended, yielding …/docs/docs/spec.
        Path result = SpecDirResolutionUtils.resolve("/some/project/docs");
        Assert.assertEquals(result,
                Path.of("/some/project/docs/docs/spec").toAbsolutePath().normalize());
    }

    @Test(description = "custom spec dir returns docs/spec under that dir")
    public void testCustomSpecDirAppendsDocsSpec() {
        Path result = SpecDirResolutionUtils.resolve("/custom/location");
        Assert.assertTrue(result.toString().endsWith("docs" + java.io.File.separator + "spec"),
                "Expected path to end with docs/spec but got: " + result);
    }
}
