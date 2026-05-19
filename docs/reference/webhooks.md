---
title: Bugsy Webhooks
tags: [bugsy, webhooks, n8n, cloudflare-tunnel, http, api]
---

# Webhooks

All webhooks are exposed via Cloudflare Tunnel at `https://n8n.coffey.codes/webhook/<path>`.

| Path | Method | Workflow | Caller | Notes |
|---|---|---|---|---|
| `/slack-bugsy` | POST | `bugsy.json` (unified) | Slack Event API | DMs + @mentions. Handles URL-verification challenge. |
| `/ask` | POST | `bugsy.json` (unified) | Slack slash command `/ask` (formerly `/bugsy`) | ACKs immediately, replies async via `response_url`. |
| `/rag-query` | POST | `bugsy-rag-query.json` | Scripts, testing | JSON-API. No memory. See [RAG query](../workflows/rag-query.md). |
| `/rag-ingest` | POST | `bugsy-rag-ingest.json` | `rag-ingest.sh`, `bugsy-jira-digest.json` (RAG mirror branch) | Pushes a markdown doc into Qdrant. The Jira digest workflow uses this to mirror each generated digest under category `jira-digests`. |
| `/rag-refresh-notify` | POST | `bugsy-rag-refresh-notify.json` | `agent/scripts/rag-refresh.sh --notify` | Notification shim — the 4am cron job posts run summaries here; the workflow formats and Slacks them to `#mulberry-street`. |
| `/job-board` | GET | `bugsy-job-board-ui.json` | Browser | HTML view of the job listings table. |
| `/bugsy-research` | POST | `bugsy-research.json` | Slack slash command `/research <target>` | On-demand prospect brief. |

Cron- and Gmail-triggered active workflows (`bugsy-job-board-fetcher`, `bugsy-leads-hunter`, `bugsy-jira-digest`) have no inbound webhook — see each workflow's doc page for trigger details.

**Internal-only MCP endpoints** (not on the Cloudflare Tunnel; only reachable inside the `agent-net` Docker network):

| Endpoint | Container | Notes |
|---|---|---|
| `http://mcp-atlassian:9000/sse` | `mcp-atlassian` | SSE transport. No client auth (single-tenant via env-var). |
| `http://mcp-github:8082/readonly` | `mcp-github` | Streamable HTTP. Per-request Bearer auth required. |
| `http://mcp-notion:3000/mcp` | `mcp-notion` | Streamable HTTP. Per-request Bearer auth required. |

n8n's MCP Client Tool nodes connect to these internally. See [SPEC-MCP-001](../specs/active/SPEC-MCP-001-mcp-server-fleet-for-bugsy.md) for the fleet design.


## Payload examples

### `/ask` (Slack slash command)
```
POST /webhook/ask
Content-Type: application/x-www-form-urlencoded

text=tell me about my expertise&user_id=U0AUSKT2VRD&user_name=anthony&channel_id=C...&response_url=https://hooks.slack.com/commands/...
```

### `/slack-bugsy` (Slack Event API)
```json
POST /webhook/slack-bugsy
{
  "type": "event_callback",
  "event": {
    "type": "message",
    "channel": "C...",
    "user": "U...",
    "text": "<@U_BUGSY> tell me about my expertise",
    "ts": "1716580000.123456",
    "channel_type": "im"
  }
}
```

### `/rag-query`
```json
POST /webhook/rag-query
{
  "question": "what are my strongest skills?",
  "top_k": 15
}
```

### `/rag-ingest`
```json
POST /webhook/rag-ingest
{
  "category": "bio",
  "filename": "bio/resume.md",
  "content": "---\ntitle: My Resume\ntags: [resume, react]\n---\n\nResume body here..."
}
```

`filename` is optional but recommended — it becomes the Qdrant point ID seed (rename-safe, collision-free across repos). The default `rag-ingest.sh` helper always sends it. When omitted, the workflow falls back to title-keyed IDs for backwards compatibility with legacy callers.
