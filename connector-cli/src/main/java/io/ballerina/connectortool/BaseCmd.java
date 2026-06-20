package io.ballerina.connectortool;

import java.io.PrintStream;

import picocli.CommandLine;

public class BaseCmd {

    @CommandLine.Option(names = {"-h", "--help"}, hidden = true)
    public boolean helpFlag;

    public PrintStream outStream = System.out;
    public PrintStream errorStream = System.err;
}
