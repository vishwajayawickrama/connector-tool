/*
 * Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.connectortool;

import io.ballerina.cli.BLauncherCmd;
import io.ballerina.connectortool.spi.ConnectorWorkflow;
import picocli.CommandLine;

import java.io.PrintStream;
import java.util.ServiceLoader;

/**
 * Root {@code bal connector} command that discovers and registers workflow subcommands
 * ({@code openapi}, {@code sdk}) via the {@link ConnectorWorkflow} SPI.
 */
@CommandLine.Command(
        name = "connector",
        description = "Centralized CLI tool to generate and maintain Ballerina connector assets."
)
public class ConnectorCmd implements BLauncherCmd {

    private static final String COMMAND_NAME = "connector";
    private PrintStream outStream;
    private PrintStream errorStream;

    @CommandLine.Mixin
    private BaseCmd baseCmd = new BaseCmd();

    public ConnectorCmd() {
        outStream = baseCmd.outStream;
        errorStream = baseCmd.errorStream;
    }

    @Override
    public void execute() {
        String commandUsageInfo = BLauncherCmd.getCommandUsageInfo(getName(), ConnectorCmd.class.getClassLoader());
        outStream.println(commandUsageInfo);
    }

    @Override
    public String getName() {
        return COMMAND_NAME;
    }

    @Override
    public void printLongDesc(StringBuilder out) {
        out.append("Generate and maintain Ballerina connector assets from OpenAPI specifications or Java SDKs.");
    }

    @Override
    public void printUsage(StringBuilder out) {
        out.append("bal connector <sdk|openapi> <command> [args...]");
    }

    @Override
    public void setParentCmdParser(CommandLine parentCmdParser) {
        CommandLine connectorCmd = parentCmdParser.getSubcommands().get(COMMAND_NAME);
        if (connectorCmd != null) {
            ServiceLoader<ConnectorWorkflow> workflows = ServiceLoader.load(ConnectorWorkflow.class);
            for (ConnectorWorkflow workflow : workflows) {
                connectorCmd.addSubcommand(workflow.getName(), workflow);
            }
        }
    }
}
