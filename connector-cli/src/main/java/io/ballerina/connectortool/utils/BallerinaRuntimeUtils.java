package io.ballerina.connectortool.utils;

import io.ballerina.runtime.api.creators.TypeCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.ArrayType;
import io.ballerina.runtime.api.types.PredefinedTypes;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BString;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.Module;
import io.ballerina.runtime.api.Runtime;

public class BallerinaRuntimeUtils {

    public static BArray addToFront(BArray original, String newValue) {
        ArrayType stringArrayType = TypeCreator.createArrayType(PredefinedTypes.TYPE_STRING);
        BArray newArray = ValueCreator.createArrayValue(stringArrayType);

        newArray.add(0, StringUtils.fromString(newValue));

        for (int i = 0; i < original.size(); i++) {
            newArray.add(i + 1, original.get(i));
        }

        return newArray;
    }

    public static void callBallerinaRunteimAPi(String org, String module, String version, BArray args) {
        callBallerinaRuntimeApiWithSingleArg(org, module, version, args);
    }

    public static void callBallerinaRuntimeApiWithSingleArg(String org, String module, String version, BArray args) {
        Runtime runtime = null;
        boolean runtimeStarted = false;
        try {
            Module balModule = new Module(org, module, version);
            runtime = Runtime.from(balModule);

            runtime.init();
            runtime.start();
            runtimeStarted = true;

            BString arg = args.size() > 0 ? args.getBString(0) : StringUtils.fromString("");
            Object result = runtime.callFunction(balModule, "main", null, arg);
            if (result instanceof BError error) {
                System.err.println("Error occurred while running " + module + ": " + error.getErrorMessage());
            }
        } catch (Exception e) {
            System.err.println("Error occurred while running " + module + ": " + e.getMessage());
        } finally {
            if (runtimeStarted && runtime != null) {
                runtime.stop();
            }
        }
    }

    public static void callBallerinaRuntimeApiWithMultipleArgs(String org, String module, String version, BArray args, int expectedCount) {
        Runtime runtime = null;
        boolean runtimeStarted = false;
        try {
            Module balModule = new Module(org, module, version);
            runtime = Runtime.from(balModule);

            runtime.init();
            runtime.start();
            runtimeStarted = true;

            Object[] functionArgs = new Object[expectedCount];
            for (int i = 0; i < expectedCount; i++) {
                functionArgs[i] = i < args.size() ? args.getBString(i) : StringUtils.fromString("");
            }

            Object result = runtime.callFunction(balModule, "main", null, functionArgs);
            if (result instanceof BError error) {
                System.err.println("Error occurred while running " + module + ": " + error.getErrorMessage());
            }
        } catch (Exception e) {
            System.err.println("Error occurred while running " + module + ": " + e.getMessage());
        } finally {
            if (runtimeStarted && runtime != null) {
                runtime.stop();
            }
        }
    }

    public static void callBallerinaRunteimAPiWithName(String org, String module, String version, String name, BArray args) {
        Runtime runtime = null;
        boolean runtimeStarted = false;
        try {
            Module balModule = new Module(org, module, version);
            BArray workflowArgs = BallerinaRuntimeUtils.addToFront(args, name);
            runtime = Runtime.from(balModule);

            runtime.init();
            runtime.start();
            runtimeStarted = true;

            Object result = runtime.callFunction(balModule, "main", null, workflowArgs);
            if (result instanceof BError error) {
                System.err.println("Error occurred while running connector automator: " + error.getErrorMessage());
            }
        } catch (Exception e) {
            System.err.println("Error occurred while running connector automator: " + e.getMessage());
        } finally {
            if (runtimeStarted && runtime != null) {
                runtime.stop();
            }
        }
    }

    public static void callBallerinaFunction(String org, String module, String version,
            String functionName, String inputPath, String outputPath, String logLevel,
            String examplesDir, String excludedStages, String specDir, String license,
            String tags, String operations, String clientMethod) {
        Runtime runtime = null;
        boolean runtimeStarted = false;
        try {
            Module balModule = new Module(org, module, version);
            runtime = Runtime.from(balModule);
            runtime.init();
            runtime.start();
            runtimeStarted = true;

            Object result = runtime.callFunction(balModule, functionName, null,
                    StringUtils.fromString(inputPath), StringUtils.fromString(outputPath),
                    StringUtils.fromString(logLevel), StringUtils.fromString(examplesDir),
                    StringUtils.fromString(excludedStages), StringUtils.fromString(specDir),
                    StringUtils.fromString(license), StringUtils.fromString(tags),
                    StringUtils.fromString(operations), StringUtils.fromString(clientMethod));
            if (result instanceof BError error) {
                throw new RuntimeException(error.getErrorMessage().toString());
            }
        } catch (RuntimeException e) {
            throw e;
        } catch (Exception e) {
            throw new RuntimeException(e.getMessage(), e);
        } finally {
            if (runtimeStarted && runtime != null) {
                runtime.stop();
            }
        }
    }
}
