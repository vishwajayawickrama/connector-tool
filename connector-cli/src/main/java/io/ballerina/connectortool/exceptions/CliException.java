package io.ballerina.connectortool.exceptions;

public class CliException extends RuntimeException {
    private final String option;
    private final String whatWentWrong;
    private final String subject;
    private final int exitCode;

    /**
     * Constructs a new CliException with all details.
     *
     * @param option         the command-line option associated with this error
     * @param whatWentWrong  a detailed explanation of the error
     * @param subject        the subject/value causing the error
     * @param exitCode       the process exit code
     */
    public CliException(String option, String whatWentWrong, String subject, int exitCode) {
        this.option = option;
        this.whatWentWrong = whatWentWrong;
        this.subject = subject;
        this.exitCode = exitCode;
    }

    /**
     * Constructs a new CliException with a message and exit code.
     *
     * @param whatWentWrong  a detailed explanation of the error
     * @param exitCode       the process exit code
     */
    public CliException(String whatWentWrong, int exitCode) {
        this.option = null;
        this.whatWentWrong = whatWentWrong;
        this.subject = null;
        this.exitCode = exitCode;
    }

    public String getFormattedMessage() {
        if (option != null && !option.isEmpty()) {
            return "bal: error: '" + option + "': " + whatWentWrong
                    + (subject != null && !subject.isEmpty() ? ": " + subject : "");
        } else {
            return "bal: error: " + whatWentWrong + (subject != null && !subject.isEmpty() ? ": " + subject : "");
        }
    }

    public int getExitCode() {
        return exitCode;
    }
}
