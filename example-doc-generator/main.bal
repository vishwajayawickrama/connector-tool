// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/file;
import ballerina/io;
import ballerina/os;
import ballerina/time;

import wso2/example_doc_generator.agent_client;
import wso2/example_doc_generator.ai_client;
import wso2/example_doc_generator.prompts;
import wso2/example_doc_generator.utils;


# Entry point for the full automation pipeline.
#
# Phase 1  (Steps 1–2):  Pre-flight validation — API key and Claude Code CLI.
# Phase 2  (Steps 3–6):  Infrastructure     — code-server, extension check, and Python agent server.
# Phase 3  (Steps 7–10): Prompt generation  — build, call Claude, format, save.
# Phase 4  (Steps 11–12): Agent execution   — run agent, enforce doc structure.
# Phase 5  (Steps 13–16): Post-processing   — inject Devant button, append examples link, crop screenshots, write run log.
#
# + return - an error if any step fails
public function main() returns error? {
    utils:log("=== WSO2 Integrator Documentation Pipeline ===");
    utils:log("");

    time:Utc startTime = time:utcNow();
    utils:log("[INFO] Start time: " + time:utcToString(startTime));
    utils:log("[INFO] Connector: " + connectorName);
    utils:log("");

    // Track LLM usage across all direct API calls (agent cost is tracked separately)
    ai_client:LlmUsage promptGenUsage    = {inputTokens: 0, outputTokens: 0, costUsd: 0.0d};
    ai_client:LlmUsage docEnfUsage       = {inputTokens: 0, outputTokens: 0, costUsd: 0.0d};

    // ── Phase 1: Pre-flight validation ─────────────────────────────────────

    // Step 1: Validate Anthropic API key with a small ping before doing anything else
    utils:log("[STEP 1] Validating Anthropic API key...");
    check ai_client:validateApiKey(llmApiKey);
    utils:log("");

    // Step 2: Check Claude Code CLI is installed (required for agent execution)
    utils:log("[STEP 2] Checking if Claude Code CLI is installed...");
    boolean claudeInstalled = utils:checkClaudeCodeInstalled();
    if !claudeInstalled {
        return error("Claude Code CLI ('claude') is not installed or not on PATH. " +
                     "Install it from https://claude.ai/code and re-run the pipeline.");
    }
    utils:log("\t[INFO] Claude Code CLI is installed.");
    utils:log("");

    // ── Phase 2: Infrastructure ─────────────────────────────────────────────

    // Step 3: Check if code-server binary is installed; install via official script if not
    utils:log("[STEP 3] Checking if code-server is installed...");
    boolean codeServerBinaryInstalled = utils:checkCodeServerInstalled();
    if !codeServerBinaryInstalled {
        utils:log("\t[INFO] code-server not found. Installing via official script (curl -fsSL https://code-server.dev/install.sh | sh)...");
        check utils:installCodeServer();
        utils:log("\t[INFO] code-server installed successfully.");
    } else {
        utils:log("\t[INFO] code-server is already installed.");
    }
    utils:log("");

    // Step 4: Verify code-server is running on the configured port, start if needed
    utils:log("[STEP 4] Verifying code-server on port " + codeServerPort.toString() + "...");
    boolean codeServerRunning = utils:checkCodeServerRunning(codeServerPort);
    if !codeServerRunning {
        utils:log("\t[INFO] Code-server not running. Starting code-server...");
        check utils:startCodeServer(codeServerPort);
        utils:log("\t[INFO] Code-server started successfully.");
    } else {
        utils:log("\t[INFO] Code-server is already running.");
    }
    string codeServerUrl = "http://localhost:" + codeServerPort.toString();
    utils:log("\t[INFO] Code-server URL: " + codeServerUrl);
    utils:log("");

    // Step 5: Ensure the WSO2 Integrator extension is installed in code-server
    utils:log("[STEP 5] Checking WSO2 Integrator extension (wso2.wso2-integrator)...");
    boolean extInstalled = utils:checkExtensionInstalled("wso2.wso2-integrator");
    if !extInstalled {
        utils:log("\t[INFO] Extension not found. Installing...");
        string|error cwdForExt = file:getCurrentDir();
        string projectRootForExt = cwdForExt is string ? cwdForExt : os:getEnv("PWD");
        string vsixPath = projectRootForExt + "/extensions/wso2.wso2-integrator-0.2.1.vsix";
        check utils:ensureExtensionInstalled("wso2.wso2-integrator", vsixPath);
        utils:log("\t[INFO] Extension installed successfully.");
    } else {
        utils:log("\t[INFO] WSO2 Integrator extension is already installed.");
    }
    utils:log("");

    // Step 6: Check if the Python agent server is running; start it if not
    utils:log("[STEP 6] Checking Python agent server on port " + agentServerPort.toString() + "...");
    boolean agentRunning = utils:checkAgentServerRunning(agentServerPort);
    if !agentRunning {
        utils:log("\t[INFO] Agent server not running. Starting via `uv run agent_server.py`...");
        check utils:startAgentServer(agentServerPort);
        utils:log("\t[INFO] Agent server started.");
    } else {
        utils:log("\t[INFO] Agent server is already running.");
    }
    string agentUrl = "http://localhost:" + agentServerPort.toString();
    utils:log("\t[INFO] Agent server URL: " + agentUrl);
    utils:log("");

    // ── Phase 3: Prompt generation ──────────────────────────────────────────

    // Derive connector slug from connector name — no LLM call needed
    string connectorSlug = connectorName.trim().toLowerAscii();
    connectorSlug = re `\s+`.replaceAll(connectorSlug, "-");
    connectorSlug = re `[^a-z0-9\-]`.replaceAll(connectorSlug, "");
    string goalSlug = connectorSlug + "-connector-example";
    utils:log("[INFO] Connector slug: " + goalSlug);

    // Write connector name to artifacts/run-log/ for downstream steps
    string runLogDir = "./artifacts/run-log";
    file:Error? cnDirErr = file:createDir(runLogDir, file:RECURSIVE);
    if cnDirErr is () {
        io:Error? cnWriteErr = io:fileWriteString(runLogDir + "/connector-name.txt", connectorName.trim());
        if cnWriteErr is io:Error {
            utils:log("\t[WARN] Could not write connector-name.txt: " + cnWriteErr.message());
        } else {
            utils:log("\t[INFO] Connector name saved to " + runLogDir + "/connector-name.txt");
        }
    }
    utils:log("");

    // Step 7: Build system and user prompts
    utils:log("[STEP 7] Building system and user prompts...");
    string|error cwdResult = file:getCurrentDir();
    string projectRoot = cwdResult is string ? cwdResult : os:getEnv("PWD");
    string systemPrompt = prompts:buildSystemPrompt(projectRoot);
    string userMessage = prompts:buildUserMessage(connectorName, codeServerUrl, projectRoot);

    // Step 8: Call Anthropic API to generate the execution prompt
    utils:log("[STEP 8] Calling Anthropic API to generate execution prompt...");
    ai_client:LlmResult promptResult = check ai_client:callClaude(systemPrompt, userMessage, llmApiKey);
    string executionPrompt = promptResult.text;
    promptGenUsage = promptResult.usage;

    // Step 9: Add header to the generated prompt
    utils:log("[STEP 9] Formatting execution prompt...");
    string header = string `# Execution Prompt

<!-- ============================================================
     XML-TAGGED MARKDOWN EXECUTION PROMPT
     Generated by: WSO2 Integrator Documentation Pipeline
     Agent: Playwright MCP (Browser Automation)
     Target: Code-Server — WSO2 Integrator (Low-Code)
     Connector: ${connectorName}
     ============================================================ -->

`;
    string fullPrompt = header + executionPrompt;

    // Step 10: Save to file — returns the path used for the agent in Step 11
    utils:log("[STEP 10] Saving execution prompt to " + utils:OUTPUT_DIR + "...");
    string promptPath = check utils:saveExecutionPrompt(fullPrompt, goalSlug);
    utils:log("\t[INFO] Saved to: " + promptPath);
    utils:log("");

    // ── Phase 4: Agent execution ─────────────────────────────────────────────

    // Step 11: Submit the execution prompt to the agent server and stream logs
    utils:log("[STEP 11] Running Claude agent...");
    agent_client:AgentCost? agentCost = check agent_client:runClaudeAgent(promptPath, agentUrl);
    utils:log("");

    // ── Phase 5: Post-processing ──────────────────────────────────────────────

    // Step 12: Enforce documentation structure via a dedicated Claude API call.
    // The agent writes the doc with all browser-automation context in its window;
    // rules stated early in the system prompt get buried. This call has the rules
    // fresh in context with no other noise, so they are reliably applied.
    utils:log("[STEP 13] Enforcing documentation structure...");
    string workflowDocsDir = "./artifacts/workflow-docs";
    string enforcedDocPath = "";
    file:MetaData[]|file:Error dirEntries = file:readDir(workflowDocsDir);
    if dirEntries is file:MetaData[] {
        string docPath = "";
        foreach file:MetaData entry in dirEntries {
            if entry.absPath.endsWith(".md") {
                docPath = entry.absPath;
                break;
            }
        }
        if docPath == "" {
            utils:log("\t[INFO] No .md file found in " + workflowDocsDir + " — skipping enforcement.");
        } else {
            utils:log("\t[INFO] Found workflow doc: " + docPath);
            string|io:Error rawDoc = io:fileReadString(docPath);
            if rawDoc is string {
                string enforcementSystemPrompt = prompts:buildDocEnforcementSystemPrompt();
                ai_client:LlmResult|error enfResult = ai_client:callClaude(enforcementSystemPrompt, rawDoc, llmApiKey);
                if enfResult is ai_client:LlmResult {
                    io:Error? writeErr = io:fileWriteString(docPath, enfResult.text);
                    if writeErr is io:Error {
                        utils:log("\t[WARN] Could not write enforced doc: " + writeErr.message());
                    } else {
                        enforcedDocPath = docPath;
                        docEnfUsage = enfResult.usage;
                        utils:log("\t[INFO] Documentation structure enforced successfully.");
                    }
                } else {
                    utils:log("\t[WARN] Doc enforcement LLM call failed: " + enfResult.message());
                }
            } else {
                utils:log("\t[WARN] Could not read doc file: " + rawDoc.message());
            }
        }
    } else {
        utils:log("\t[INFO] Workflow docs directory not found — skipping enforcement.");
    }
    utils:log("");

    // Step 13: Inject "Deploy to Devant" button into the workflow doc
    utils:log("[STEP 13] Injecting Deploy to Devant button into workflow doc...");
    if enforcedDocPath != "" {
        utils:injectDevantButton(enforcedDocPath);
    } else {
        utils:log("\t[INFO] No enforced doc path available — skipping Devant button injection.");
    }
    utils:log("");

    // Step 14: Append Ballerina Central examples link to the workflow doc (if examples exist)
    utils:log("[STEP 14] Checking Ballerina Central for connector examples link...");
    if enforcedDocPath != "" {
        utils:appendExamplesSection(enforcedDocPath);
    } else {
        utils:log("\t[INFO] No enforced doc path available — skipping examples link.");
    }
    utils:log("");

    // Step 15: Crop UI chrome from screenshots produced by the agent
    utils:log("[STEP 15] Cropping screenshots...");
    os:Process|error cropProc = os:exec({
        value: "python/.venv/bin/python",
        arguments: ["python/crop_screenshots.py"]
    });
    if cropProc is error {
        utils:log("\t[WARN] Could not launch crop_screenshots.py: " + cropProc.message());
        utils:log("\t[WARN] Run `make crop-screenshots` manually to crop screenshots.");
    } else {
        int exitCode = check cropProc.waitForExit();
        if exitCode == 0 {
            utils:log("\t[INFO] Screenshots cropped successfully.");
        } else {
            utils:log("\t[WARN] crop_screenshots.py exited with code " + exitCode.toString() + ".");
            utils:log("\t[WARN] Run `make crop-screenshots` manually to crop screenshots.");
        }
    }
    utils:log("");

    // ── Phase 5 (cont.): Finalise ─────────────────────────────────────────────

    time:Utc endTime = time:utcNow();
    decimal durationSecs = time:utcDiffSeconds(endTime, startTime);

    // Aggregate direct API call costs
    int totalInputTokens  = promptGenUsage.inputTokens  + docEnfUsage.inputTokens;
    int totalOutputTokens = promptGenUsage.outputTokens + docEnfUsage.outputTokens;
    decimal totalCostUsd  = promptGenUsage.costUsd      + docEnfUsage.costUsd;

    // Add agent SDK cost to combined total
    decimal agentCostUsd = 0.0d;
    if agentCost is agent_client:AgentCost {
        decimal? ac = agentCost.totalCostUsd;
        if ac is decimal {
            agentCostUsd = ac;
        }
    }
    decimal totalCombinedCostUsd = totalCostUsd + agentCostUsd;

    // Step 16: Write run log to artifacts/run-log/
    utils:log("[STEP 16] Writing run log...");
    utils:writeRunLog({
        connectorName:       connectorName,
        connectorSlug:       goalSlug,
        startTime:           startTime,
        endTime:             endTime,
        durationSecs:        durationSecs,
        promptGenUsage:      promptGenUsage,
        docEnfUsage:         docEnfUsage,
        agentCost:           agentCost,
        totalDirectCostUsd:  totalCostUsd,
        totalCombinedCostUsd: totalCombinedCostUsd,
        promptPath:          promptPath,
        workflowDocPath:     enforcedDocPath == "" ? "(not written)" : enforcedDocPath
    });
    utils:log("");

    // Print pipeline stats
    utils:log("--- Pipeline Stats ---");
    utils:log(string `Start time:      ${time:utcToString(startTime)}`);
    utils:log(string `End time:        ${time:utcToString(endTime)}`);
    utils:log(string `Duration:        ${durationSecs}s`);
    utils:log(string `Prompt length:   ${fullPrompt.length()} chars`);
    utils:log("--- LLM Cost Breakdown ---");
    utils:log(string `Prompt gen:      ${promptGenUsage.inputTokens} in / ${promptGenUsage.outputTokens} out  |  $${promptGenUsage.costUsd}`);
    utils:log(string `Doc enforcement: ${docEnfUsage.inputTokens} in / ${docEnfUsage.outputTokens} out  |  $${docEnfUsage.costUsd}`);
    utils:log(string `Direct API total:${totalInputTokens} in / ${totalOutputTokens} out  |  $${totalCostUsd}`);
    utils:log(string `Agent SDK:       $${agentCostUsd}`);
    utils:log(string `COMBINED TOTAL:  $${totalCombinedCostUsd}`);

    utils:log("");
    utils:log("=== Pipeline Complete ===");
    utils:log("Artifacts saved under '" + utils:OUTPUT_DIR + "'.");
}
