package io.ballerina.aigentool.utils;

import io.ballerina.runtime.api.creators.TypeCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.ArrayType;
import io.ballerina.runtime.api.types.PredefinedTypes;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.utils.StringUtils;

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
}
