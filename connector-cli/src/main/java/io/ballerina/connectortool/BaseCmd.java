package io.ballerina.connectortool;

import picocli.CommandLine;

import java.io.PrintStream;

public class BaseCmd {

    @CommandLine.Option(names = {"-h", "--help"}, hidden = true)
    public boolean helpFlag;

    public PrintStream outStream = System.out;
    public PrintStream errorStream = System.err;
}
