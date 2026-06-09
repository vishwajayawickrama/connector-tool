package io.ballerina.aigentool.utils;

import io.ballerina.runtime.api.creators.TypeCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.ArrayType;
import io.ballerina.runtime.api.types.PredefinedTypes;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.Module;
import io.ballerina.runtime.api.Runtime;

public class Utils {
    public static BArray addToFront(BArray original, String newValue) {
        ArrayType stringArrayType = TypeCreator.createArrayType(PredefinedTypes.TYPE_STRING);
        BArray newArray = ValueCreator.createArrayValue(stringArrayType);
    
        // Add new value at front
        newArray.add(0, StringUtils.fromString(newValue));
    
        // Shift existing values
        for (int i = 0; i < original.size(); i++) {
            newArray.add(i + 1, original.get(i));
        }
    
        return newArray;
    }

    public static void callBallerinaRunteimAPi(String org, String module, String version, BArray args) {   
        Runtime runtime = null;
        boolean runtimeStarted = false;
        try {
            Module balModule = new Module(org, module, version);
            runtime = Runtime.from(balModule);

            runtime.init();
            runtime.start();
            runtimeStarted = true;

            Object result = runtime.callFunction(balModule, "main", null, args);
            if (result instanceof BError error) {
                System.err.println("Error occurred while running connector doc generator: " + error.getErrorMessage());
            }
        } catch (Exception e) {
            System.err.println("Error occurred while running connector doc generator: " + e.getMessage());
        } finally {
            // Stop the runtime if it was started
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
            BArray workflowArgs = Utils.addToFront(args, name);
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
            // Stop the runtime if it was started
            if (runtimeStarted && runtime != null) {
                runtime.stop();
            }
        }
    }
}
