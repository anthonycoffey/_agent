---
title: Bugsy Architecture Overview
tags: [bugsy, architecture, gcp, docker, vm, single-vm, cloudflare-tunnel]
---

# Overview

Bugsy is a single-VM stack. One Compute Engine instance on GCP runs Docker Compose with all services. Internal services talk over a private docker network (`agent_agent-net`). Only Cloudflare Tunnel exposes anything to the internet.

## VM

| Property | Value |
|---|---|
| Provider | GCP Compute Engine |
| Name | `agent-vm` |
| RAM | 16 GB |
| OS | Ubuntu |
| Managed by | Terraform (`tf/`) |
| Repo on VM | `~/bugsy/` (git clone) |
| App dir | `~/agent/` → symlink to `~/bugsy/agent/` |

Cloud-init bootstraps the VM on first boot only. Any changes after that are deployed via `git pull` on the VM.

## Containers

| Container | Image | Role |
|---|---|---|
| `agent-postgres` | pgvector/pgvector:pg16 | Primary DB for app data + n8n internal DB + pgvector extension |
| `agent-qdrant` | qdrant/qdrant | Vector store for RAG (`personal_knowledge` collection) |
| `agent-redis` | redis:7-alpine | Cache / queue |
| `agent-ollama` | ollama/ollama | Local inference (CPU-only currently) — embedding model lives here |
| `agent-litellm` | ghcr.io/berriai/litellm | OpenAI-compatible proxy in front of Anthropic, OpenAI, Google, local models |
| `agent-openwebui` | ghcr.io/open-webui/open-webui | Chat UI (port 3000, internal) |
| `agent-n8n` | n8nio/n8n | Workflow automation, webhooks, AI Agent runtime |
| `agent-cloudflared` | cloudflare/cloudflared | Public ingress (Cloudflare Tunnel) |
| `agent-searxng` | searxng/searxng | Self-hosted metasearch for research workflows |
| `agent-mcp-atlassian` | ghcr.io/sooperset/mcp-atlassian | Live Jira read tool for Bugsy's AI Agent. SSE on :9000 (internal). |
| `agent-mcp-github` | ghcr.io/github/github-mcp-server | Live GitHub read tool (PRs, issues, code search). Streamable HTTP on :8082 (internal). |
| `agent-mcp-notion` | mcp/notion | Live Notion read/write tool — pages, blocks, databases, kanban properties, archives, comments, schema. Streamable HTTP on :3000 (internal). |
| `agent-aider` | paulgauthier/aider | AI coding-agent runner. Parked with `tail -f /dev/null`; work is started by `docker exec` into `/agent/run-agent.sh`. Talks to LiteLLM, not to a provider directly. **Half-built** — see [the Aider runner](#aider-coding-agent-runner) below. |
| `agent-evolution-api` | evoapicloud/evolution-api | **Parked.** WhatsApp bridge left from the retired `bugsy-whatsapp.json` experiment. Still `restart: unless-stopped`, still holds an `evolution` Postgres DB and redis db 6, but no workflow calls it. |

## Models available (via LiteLLM at `http://litellm:4000/v1`)

| Model name | Backend |
|---|---|
| `claude-sonnet-4-6` | Anthropic |
| `claude-haiku-4-5` | Anthropic |
| `gpt-4o-mini` | OpenAI |
| `gemini-2.5-pro` | Google |
| `gemini-2.5-flash` | Google |
| `gemini-3.1-flash-lite` | Google |
| `qwen3` | Ollama local (qwen3:8b) |
| `nomic-embed-text` | Ollama local (embeddings, 768-dim) |

## Data flow at a glance

```mermaid
flowchart LR
  Slack[Slack] --> CF[Cloudflare Tunnel]
  CF --> N8N[n8n]
  N8N --> Postgres
  N8N --> Qdrant
  N8N --> Ollama
  N8N --> LiteLLM
  LiteLLM --> Anthropic
  LiteLLM --> OpenAI
  LiteLLM --> Google
  LiteLLM --> Ollama

  N8N -.live tools.-> MCP_ATL[mcp-atlassian]
  N8N -.live tools.-> MCP_GH[mcp-github]
  N8N -.live tools.-> MCP_NTN[mcp-notion]
  MCP_ATL --> Jira[(Jira API)]
  MCP_GH --> GitHub[(GitHub API)]
  MCP_NTN --> Notion[(Notion API)]
```

Cloudflare Tunnel is the only path in. n8n is the orchestration layer. Postgres holds chat memory and app data. Qdrant holds personal-knowledge embeddings. Ollama runs `nomic-embed-text` for local embeddings. LiteLLM brokers all chat-model calls so the workflow JSON only ever points at one URL.

The three MCP containers (`mcp-atlassian`, `mcp-github`, `mcp-notion`) give the AI Agent inside `bugsy.json` **live tools** for Jira, GitHub, and Notion. They sit on the same `agent-net` network — no Cloudflare exposure. Bugsy uses them to answer questions that need current state (e.g. "what's UTT-299's status?", "what PRs are open on coffey.codes?", "what's on the kanban this week?") instead of relying on the RAG-cached snapshots which go stale within hours. See [SPEC-MCP-001](../specs/archive/SPEC-MCP-001-mcp-server-fleet-for-bugsy.md) for the fleet design and per-MCP details.

## Aider coding-agent runner

**Status: half-built. Not wired to anything.** Added 2026-05-22, never run end-to-end.

`agent-aider` is a parked container (`tail -f /dev/null`) holding a checkout area and a runner
script. It is not a service in the request-handling sense — nothing listens on a port. Work is
started by exec'ing into it:

```bash
docker exec -d agent-aider /agent/run-agent.sh \
  --repo-name=coffey.codes --issue-number=42 \
  --issue-title="Fix the nav bug" --issue-body="Steps to reproduce..."
```

`run-agent.sh` then cuts a branch (`agent/issue-<N>-<epoch>`), runs Aider against
`claude-sonnet-4-6` **through LiteLLM** (so no provider key lives in this container), pushes the
branch, opens a **draft** PR, and comments the PR link back on the issue. Logs land inside the
container at `/tmp/aider-issue-<N>.log`.

Two setup steps are manual and currently unverified on the VM:

1. **Repos must be cloned into `/workspace` by hand** — `run-agent.sh` hard-fails if
   `/workspace/<repo>/.git` is missing. The `aider-workspace` named volume persists them.
2. **`GITHUB_TOKEN_AIDER` must be a write-scoped PAT** (Contents, Pull requests, Issues = r/w),
   deliberately separate from the read-only `GITHUB_TOKEN_MCP`.

What's missing: **the n8n workflow that drives it.** The script's header documents the intended
trigger (n8n SSH node → `docker exec`), but no workflow in `agent/n8n/workflows/` references
aider, so there is no trigger, no approval gate, and no run cap. Design that before adding code —
as it stands a trigger would go straight from issue to pushed branch with no human in the loop,
which cuts against the project's "human in the loop for anything that sends" principle.
