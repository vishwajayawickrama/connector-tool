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
