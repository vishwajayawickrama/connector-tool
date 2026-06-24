// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

# OpenAPI tool configuration options
public type OpenAPIToolOptions record {|
    # License file path to add copyright/license header to generated files
    string license = "docs/license.txt";
    # Tags to filter operations that need to be generated
    string[] tags?;
    # List of specific operations to generate
    string[] operations?;
    # Client method type - resource methods or remote methods
    "resource"|"remote" clientMethod = "resource";
|};

# Default OpenAPI tool options - can be overridden via configuration
configurable OpenAPIToolOptions options = {};

public type ClientGeneratorConfig record {|
    boolean quietMode = false;
    OpenAPIToolOptions? toolOptions = ();
|};
