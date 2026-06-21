package io.ballerina.connectortool;

import io.ballerina.connectortool.exceptions.CliException;
import org.testng.Assert;
import org.testng.annotations.Test;

public class CliExceptionTest {

    // ── 2-arg constructor ──────────────────────────────────────────────────────

    @Test(description = "2-arg constructor: formatted message has no option prefix")
    public void testTwoArgFormattedMessage() {
        CliException ex = new CliException("something went wrong", 1);
        Assert.assertEquals(ex.getFormattedMessage(), "bal: error: something went wrong");
    }

    @Test(description = "2-arg constructor: exit code is stored correctly")
    public void testTwoArgExitCode() {
        CliException ex = new CliException("bad input", 2);
        Assert.assertEquals(ex.getExitCode(), 2);
    }

    @Test(description = "2-arg constructor: instance is a RuntimeException")
    public void testTwoArgIsRuntimeException() {
        CliException ex = new CliException("error", 1);
        Assert.assertTrue(ex instanceof RuntimeException,
                "CliException should extend RuntimeException");
    }

    // ── 4-arg constructor ──────────────────────────────────────────────────────

    @Test(description = "4-arg constructor: formatted message includes option and subject")
    public void testFourArgFormattedMessageWithSubject() {
        CliException ex = new CliException("-i", "file not found", "spec.json", 1);
        Assert.assertEquals(ex.getFormattedMessage(),
                "bal: error: '-i': file not found: spec.json");
    }

    @Test(description = "4-arg constructor: exit code is stored correctly")
    public void testFourArgExitCode() {
        CliException ex = new CliException("-x", "unknown stage", "bogus", 2);
        Assert.assertEquals(ex.getExitCode(), 2);
    }

    @Test(description = "4-arg constructor: null subject is omitted from message")
    public void testFourArgNullSubjectOmitted() {
        CliException ex = new CliException("-o", "not a directory", null, 1);
        Assert.assertEquals(ex.getFormattedMessage(), "bal: error: '-o': not a directory");
    }

    @Test(description = "4-arg constructor: empty subject is omitted from message")
    public void testFourArgEmptySubjectOmitted() {
        CliException ex = new CliException("-o", "not a directory", "", 1);
        Assert.assertEquals(ex.getFormattedMessage(), "bal: error: '-o': not a directory");
    }

    @Test(description = "4-arg constructor: empty option falls back to no-prefix format")
    public void testFourArgEmptyOptionNoPrefix() {
        CliException ex = new CliException("", "all stages excluded", null, 2);
        Assert.assertEquals(ex.getFormattedMessage(), "bal: error: all stages excluded");
    }

    // ── exit codes ────────────────────────────────────────────────────────────

    @Test(description = "exit code 1 is stored as 1")
    public void testExitCode1() {
        Assert.assertEquals(new CliException("err", 1).getExitCode(), 1);
    }

    @Test(description = "exit code 2 is stored as 2")
    public void testExitCode2() {
        Assert.assertEquals(new CliException("err", 2).getExitCode(), 2);
    }
}
