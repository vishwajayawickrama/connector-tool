package io.ballerina.connectortool;

import picocli.CommandLine;

public class BaseCmd {

    @CommandLine.Option(names = {"-h", "--help"}, hidden = true)
    public boolean helpFlag;
}
