package io.ballerina.connectortool.utils;

public class ProcessUtils {

    public static void exitSuccess(boolean exit) {
        exit(0, exit);
    }

    public static void exitError(boolean exit) {
        exit(1, exit);
    }

    public static void exit(int code, boolean exit) {
        if (exit) {
            Runtime.getRuntime().exit(code);
        }
    }
}
