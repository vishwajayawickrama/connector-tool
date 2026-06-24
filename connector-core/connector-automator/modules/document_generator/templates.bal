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

final map<string> & readonly DOCUMENT_TEMPLATES = {
    "ballerina_readme_template.md":
        "# {{CONNECTOR_NAME}} Connector\n\n" +
        "## Overview\n{{AI_GENERATED_OVERVIEW}}\n\n" +
        "## Setup guide\n{{AI_GENERATED_SETUP}}\n\n" +
        "## Quickstart\n{{AI_GENERATED_QUICKSTART}}\n\n" +
        "## Examples\n{{AI_GENERATED_EXAMPLES}}\n",

    "example_specific_template.md":
        "{{AI_GENERATED_INDIVIDUAL_README}}\n",

    "examples_readme_template.md":
        "{{AI_GENERATED_MAIN_EXAMPLES_README}}\n",

    "main_readme_template.md":
        "# {{CONNECTOR_NAME}}\n\n" +
        "{{AI_GENERATED_HEADER_AND_BADGES}}\n\n" +
        "## Overview\n{{AI_GENERATED_OVERVIEW}}\n\n" +
        "## Setup guide\n{{AI_GENERATED_SETUP}}\n\n" +
        "## Quickstart\n{{AI_GENERATED_QUICKSTART}}\n\n" +
        "## Examples\n{{AI_GENERATED_EXAMPLES}}\n\n" +
        "## Useful Links\n{{AI_GENERATED_USEFUL_LINKS}}\n",

    "tests_readme_template.md":
        "{{AI_GENERATED_TESTING_APPROACH}}\n"
};
