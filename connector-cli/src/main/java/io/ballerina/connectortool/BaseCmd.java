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

import picocli.CommandLine;

import java.io.PrintStream;

/**
 * Common CLI options shared across all {@code bal connector} subcommands.
 */
public class BaseCmd {

    @CommandLine.Option(names = {"-h", "--help"}, hidden = true)
    public boolean helpFlag;

    public PrintStream outStream = System.out;
    public PrintStream errorStream = System.err;
}
