package io.ballerina.aigentool;

import picocli.CommandLine;

public class BaseCmd {

    @CommandLine.Option(names = {"-h", "--help"}, hidden = true)
    public boolean helpFlag;

    @CommandLine.Option(names = {"--license"}, description = "Location of the file which contains the license header")
    public String licenseFilePath;
}
