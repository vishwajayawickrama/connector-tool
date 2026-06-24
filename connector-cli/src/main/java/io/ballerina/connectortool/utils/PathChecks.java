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

package io.ballerina.connectortool.utils;

import io.ballerina.connectortool.exceptions.CliException;

import java.nio.file.Files;
import java.nio.file.Path;

final class PathChecks {

    private PathChecks() {}

    static void requireExists(Path p, String option) {
        if (!Files.exists(p)) {
            throw new CliException("no such file or directory", 1, option, p.toString());
        }
    }

    static void requireDirectory(Path p, String option) {
        if (!Files.isDirectory(p)) {
            throw new CliException("not a directory", 1, option, p.toString());
        }
    }

    static void requireRegularFile(Path p, String option) {
        if (!Files.isRegularFile(p)) {
            throw new CliException("not a file", 1, option, p.toString());
        }
    }

    static void requireReadable(Path p, String option) {
        if (!Files.isReadable(p)) {
            throw new CliException("permission denied", 1, option, p.toString());
        }
    }

    static void requireWritable(Path p, String option) {
        if (!Files.isWritable(p)) {
            throw new CliException("no write permission", 1, option, p.toString());
        }
    }
}
