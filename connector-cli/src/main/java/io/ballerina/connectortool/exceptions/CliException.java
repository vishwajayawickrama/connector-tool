package io.ballerina.connectortool.exceptions;

public class CliException extends RuntimeException {
    private final String option;
    private final String whatWentWrong;
    private final String subject;
    private final int exitCode;

    public CliException(String option, String whatWentWrong, String subject, int exitCode) {
        this.option = option;
        this.whatWentWrong = whatWentWrong;
        this.subject = subject;
        this.exitCode = exitCode;
    }

    public String getFormattedMessage() {
        if (option != null && !option.isEmpty()) {
            return "bal: error: '" + option + "': " + whatWentWrong + ": " + subject;
        } else {
            return "bal: error: " + whatWentWrong + ": " + subject;
        }
    }

    public int getExitCode() {
        return exitCode;
    }
}
