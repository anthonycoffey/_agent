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

## Models available (via LiteLLM at `http://litellm:4000/v1`)

| Model name | Backend |
|---|---|
| `claude-sonnet-4-6` | Anthropic |
| `claude-haiku-4-5` | Anthropic |
| `gpt-4o-mini` | OpenAI |
| `gemini-2.5-pro` | Google |
| `gemini-2.5-flash` | Google |
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
```

Cloudflare Tunnel is the only path in. n8n is the orchestration layer. Postgres holds chat memory and app data. Qdrant holds personal-knowledge embeddings. Ollama runs `nomic-embed-text` for local embeddings. LiteLLM brokers all chat-model calls so the workflow JSON only ever points at one URL.
