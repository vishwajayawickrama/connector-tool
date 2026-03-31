# Example Doc Generator

An AI-driven pipeline that automates WSO2 Integrator low-code connector documentation. It uses **Ballerina** to orchestrate prompt generation via the Claude API, then runs a **Python agent server** (Claude Agent SDK + Playwright MCP) that operates a **code-server** instance to capture screenshots and produce step-by-step workflow guides.

```
Goal → Claude generates execution prompt → Agent executes via Playwright MCP → Artifacts (docs + screenshots)
```

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Ballerina | 2201.13.1 | [ballerina.io/downloads](https://ballerina.io/downloads/) |
| Python | 3.11+ | [python.org](https://www.python.org/downloads/) |
| uv | latest | [docs.astral.sh/uv](https://docs.astral.sh/uv/getting-started/installation/) |
| Node.js | LTS+ | [nodejs.org](https://nodejs.org/) |
| Claude Code CLI | latest | [claude.ai/code](https://claude.ai/code) |
| code-server | latest | auto-installed by pipeline |

## Setup

**1. Create Config.toml** (Ballerina pipeline config)

```bash
cp Config.toml.example Config.toml
# Fill in llmApiKey and userGoal
```

**2. Create .env** (Python scripts config)

```bash
cp .env.example .env
# Fill in DOCS_INTEGRATOR_FORK and adjust any non-default values
```

**3. Export Anthropic API key** (required by the Python agent server)

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

**4. Install dependencies**

```bash
make setup
```

**5. Run the pipeline**

```bash
make run CONNECTOR=mysql
# or directly:
bal run -- mysql
```

Artifacts are saved under `artifacts/` (git-ignored).

## Configuration

Configuration is split between two files:

### `Config.toml` — Ballerina pipeline

Copy `Config.toml.example` to get started.

| Key | Required | Default | Description |
|-----|----------|---------|-------------|
| `llmApiKey` | ✅ | — | Anthropic API key for Ballerina AI calls |
| `codeServerPort` | No | `8080` | Port for the code-server instance |
| `agentServerPort` | No | `8765` | Port for the Python agent server |

> **Connector name** is passed as a CLI argument, not a configurable: `make run CONNECTOR=mysql` or `bal run -- mysql`.

> **Never commit `Config.toml`** — it is git-ignored.

### `.env` — Python scripts

Copy `.env.example` to get started. Used by `publish_docs.py`, `publish_sample.py`, `agent_server.py`, and `crop_screenshots.py`.

| Key | Required | Default | Description |
|-----|----------|---------|-------------|
| `CODE_SERVER_PORT` | No | `8080` | code-server port |
| `AGENT_SERVER_PORT` | No | `8765` | Agent server port |
| `INTEGRATION_SAMPLES_REPO` | No | `../integration-samples` | Local path to integration-samples fork |
| `DOCS_INTEGRATOR_REPO` | No | `../docs-integrator` | Local path to docs-integrator fork |
| `INTEGRATION_SAMPLES_UPSTREAM` | No | `wso2/integration-samples` | GitHub org/repo for samples PRs |
| `INTEGRATION_SAMPLES_BASE_BRANCH` | No | `main` | Base branch for samples PRs |
| `DOCS_INTEGRATOR_FORK` | ✅ | — | Your fork of docs-integrator (org/repo) |
| `DOCS_INTEGRATOR_UPSTREAM` | No | `wso2/docs-integrator` | GitHub org/repo for docs PRs |
| `DOCS_INTEGRATOR_BASE_BRANCH` | No | `dev` | Base branch for docs PRs |

> **Never commit `.env`** — it is git-ignored.

## Project Structure

```
example-doc-generator/
├── main.bal                        # Pipeline entry point (17-step orchestration)
├── config.bal                      # All configurable fields
├── Ballerina.toml                  # Package manifest
├── Config.toml.example             # Configuration template
├── Makefile                        # Common commands
│
├── modules/
│   ├── ai_client/ai_client.bal     # Anthropic API calls (generate, slug, enforce)
│   ├── agent_client/agent_client.bal  # REST client for the Python agent server
│   ├── prompts/
│   │   ├── system_prompt.bal       # XML-tagged execution prompt template
│   │   ├── user_prompt.bal         # User message builder
│   │   └── doc_enforcement_prompt.bal  # Doc structure enforcement prompt
│   └── utils/                      # Logger, file I/O, code-server & agent server utils
│
├── python/
│   ├── agent_server.py             # aiohttp server wrapping Claude Agent SDK
│   ├── crop_screenshots.py         # Crops UI chrome from screenshots
│   ├── publish_sample.py           # Publishes integration sample PR + cleans workspace
│   ├── publish_docs.py             # Publishes docs to docs-integrator fork + creates PR
│   └── requirements.txt
│
├── .mcp.json                       # Playwright MCP config for Claude Code subagent
├── .claude/settings.json           # Permissions + model for Claude Code subagent
│
└── artifacts/                      # All generated output (git-ignored)
    ├── execution-prompt/           # Generated execution prompts
    ├── workflow-docs/              # Step-by-step connector guides (Markdown)
    ├── screenshots/                # Captured browser screenshots (cropped)
    └── run-log/                    # JSON run logs (cost, tokens, timing)
```

## Makefile Reference

```
Setup
  make setup                Install all deps (Python venv + Playwright + Ballerina build)
  make setup-python         Create python/.venv and install Python deps
  make setup-bal            Build the Ballerina project

Run
  make run CONNECTOR=mysql  Run the full pipeline for a connector
  make start-agent          Start the Python agent server in the foreground
  make stop-agent           Send shutdown to the agent server

Publish
  make publish-docs         Publish docs + create PR to docs-integrator
  make publish-docs-dry     Dry run — print planned actions, no changes
  make cleanup              Publish integration sample PR + delete local project
  make cleanup-dry          Dry run for cleanup

Screenshots
  make crop-screenshots     Crop UI chrome from all screenshots
  make crop-screenshots-dry Preview what would be cropped (no changes)

Artifacts
  make clean                Remove artifacts/, target/, Dependencies.toml, python/.venv
  make clean-artifacts      Remove only the artifacts/ directory
```

Run `make help` for the full list with configurable variables.

## Pipeline Phases

| Phase | Steps | Description |
|-------|-------|-------------|
| Pre-flight | 1–2 | Validate API key; check Claude Code CLI is installed |
| Infrastructure | 3–5 | Install/start code-server; install/start Python agent server |
| Prompt generation | 6–10 | Build prompts → call Claude → generate slug → save execution prompt |
| Agent execution | 11 | POST prompt to agent server; stream logs until done |
| Post-processing | 12–17 | Enforce doc structure; inject Devant button; append examples link; crop screenshots; write run log |

## Python Agent Server

`python/agent_server.py` wraps the Claude Agent SDK as a lightweight HTTP server.

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/run` | Submit job: `{ "prompt_path": "..." }` → `{ "job_id": "..." }` |
| `GET` | `/jobs/<id>` | Poll: `{ "status": "queued\|running\|done\|error", "logs": [...], "cost": {...} }` |
| `GET` | `/health` | `{ "status": "ok" }` |
| `POST` | `/shutdown` | Graceful stop |

```bash
make start-agent                                    # start in foreground
make stop-agent                                     # send shutdown
cd python && .venv/bin/python agent_server.py --port 9000  # custom port
```

## GitHub Actions

Two workflows are included under `.github/workflows/`:

| Workflow | Trigger | Description |
|----------|---------|-------------|
| `connector-docs-automation.yml` | `workflow_dispatch` | Runs the full pipeline and uploads artifacts |
| `publish-connector-docs.yml` | `workflow_run` / `workflow_dispatch` | Places generated docs into docs-integrator and creates a PR |

### Required Secrets

Add these under **Settings → Environments → `docs-automation` → Secrets**:

| Secret | Description |
|--------|-------------|
| `LLM_API_KEY` | Anthropic API key — used for all Claude calls |
| `DOCS_INTEGRATOR_TOKEN` | GitHub PAT with `repo` scope — used to push branches to your docs-integrator fork and open PRs against the upstream |

### Required Environment

Create a GitHub environment named **`docs-automation`** at **Settings → Environments → New environment**.

### Workflow Inputs (`connector-docs-automation.yml`)

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `userGoal` | ✅ | — | Integration to document |
| `docsIntegratorFork` | ✅ | — | Your fork of docs-integrator (e.g. `your-org/docs-integrator`) |
| `codeServerPort` | No | `8080` | code-server port |
| `agentServerPort` | No | `8765` | Agent server port |
| `docsIntegratorUpstream` | No | `wso2/docs-integrator` | Upstream repo for docs PRs |
| `docsIntegratorBaseBranch` | No | `dev` | Base branch for docs PRs |
| `integrationSamplesUpstream` | No | `wso2/integration-samples` | Upstream repo for samples PRs |
| `integrationSamplesBaseBranch` | No | `main` | Base branch for samples PRs |

## Troubleshooting

| Error | Fix |
|-------|-----|
| API key validation failed | Set `llmApiKey` in `Config.toml` and `export ANTHROPIC_API_KEY=...` |
| Claude Code CLI not found | Install from [claude.ai/code](https://claude.ai/code), verify with `claude --version` |
| Agent server not ready | Run `make start-agent` to see Python errors; check `curl http://localhost:8765/health` |
| `uv: command not found` | `curl -LsSf https://astral.sh/uv/install.sh \| sh && source ~/.zshrc` |
| `claude_agent_sdk` import error | `make setup-python` |
| code-server install failed | `curl -fsSL https://code-server.dev/install.sh \| sh` |
| Ballerina build errors | `bal clean && make setup-bal` |
| Playwright MCP missing | `npm install -g @playwright/mcp@latest` |
