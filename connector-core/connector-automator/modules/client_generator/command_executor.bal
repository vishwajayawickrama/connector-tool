import wso2/connector_automator.utils;

import ballerina/file;

public function executeBalClientGenerate(string inputPath, string outputPath, OpenAPIToolOptions? customOptions = ()) returns utils:CommandResult {
    OpenAPIToolOptions toolOptions = customOptions ?: options;

    string command = string `bal openapi -i ${inputPath} --mode client -o ${outputPath}`;

    string licensePath = toolOptions.license;
    if !licensePath.startsWith("/") {
        string workingDir = utils:getDirectoryPath(outputPath);
        licensePath = string `${workingDir}/${licensePath}`;
    }
    boolean|file:Error licenseExists = file:test(licensePath, file:EXISTS);
    if licenseExists is boolean && licenseExists {
        command += string ` --license ${licensePath}`;
    }

    if toolOptions.tags is string[] {
        string tagsList = string:'join(",", ...toolOptions.tags ?: []);
        command += string ` --tags ${tagsList}`;
    }

    if toolOptions.operations is string[] {
        string operationsList = string:'join(",", ...toolOptions.operations ?: []);
        command += string ` --operations ${operationsList}`;
    }

    command += string ` --client-methods ${toolOptions.clientMethod}`;

    utils:logVerbose(string `running: ${command}`);
    return utils:executeCommand(command, utils:getDirectoryPath(outputPath));
}
