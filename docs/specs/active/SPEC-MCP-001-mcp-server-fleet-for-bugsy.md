---
id: SPEC-MCP-001
title: "MCP server fleet for Bugsy's brain and n8n workflows"
status: in-progress
created: 2026-05-18
author: Anthony Coffey
reviewers: []
affected_repos: [_agent]
---

<!--
2026-05-18 — Plan approved. Status flipped draft → ready.

Locked-in scoping decisions (from the 2026-05-18 conversation):
- Consumers: Bugsy's AI Agent (bugsy.json) + n8n workflows on the VM
- Claude Code on the laptop is configured separately, out of scope
- Atlassian = Jira only (no Confluence)
- P1 lineup: Atlassian, GitHub, Slack, GSC/GA4/Bing bundle
- Read-only first; write surfaces come in a follow-up spec
- No Cloudflare Tunnel exposure (agent-net only)
- Langfuse + Caddy explicitly retired from the older plan

2026-05-18 — Phase 0 verified end-to-end. Bugsy successfully answered
a live Jira ticket query in Slack using the atlassian MCP tool (not
RAG-cached digest content). Follow-up tweaks landed alongside:
- TOOLSETS=all set explicitly on agent-mcp-atlassian to silence the
  v0.22.0 deprecation warning seen in container logs
- Smoke-test instructions in this spec corrected: the SSE endpoint is
  at /sse (not /), reachability tests must run from inside agent-net
  (host's localhost:9000 is unpublished by design)

2026-05-18 — Phase 1.2 implementation landed (pending VM verification).
GitHub MCP wired in. Notable differences from Phase 0:
- Image: ghcr.io/github/github-mcp-server:latest, started with
  `http --port 8082 --read-only`. Uses Streamable HTTP transport
  (not SSE — different from sooperset/mcp-atlassian).
- n8n MCP Client Tool node configured with serverTransport=httpStreamable
  (the v1.2 default) instead of sse, pointed at
  http://mcp-github:8082/readonly.
- Defense-in-depth read-only: PAT scoped read-only (fine-grained, only
  Contents/PRs/Issues/Metadata read) + server's --read-only flag +
  /readonly mount path (chi router middleware enforces it regardless
  of the flag). Three layers.
- Auth: GITHUB_PERSONAL_ACCESS_TOKEN env var on the container (not
  routed through n8n credentials; same simplification as Phase 0).

Pending: VM-side verification — set GITHUB_TOKEN_MCP in .env, bring up
mcp-github, import the updated bugsy.json, ask Bugsy a GitHub question
(open PRs on coffey.codes, recent commits to periscope, etc).

2026-05-18 — Phase 0 implementation landed (pending VM verification).
Status flipped ready → in-progress. Research confirmed the moving parts:

- MCP server image: ghcr.io/sooperset/mcp-atlassian:latest, run with
  `--transport sse --port 9000`. Env vars: JIRA_URL, JIRA_USERNAME,
  JIRA_API_TOKEN, READ_ONLY_MODE=true.
- n8n node: @n8n/n8n-nodes-langchain.mcpClientTool, typeVersion 1.2.
  Parameters used: endpointUrl, serverTransport='sse', authentication='none',
  include='all'. Output goes via NodeConnectionTypes.AiTool → AI Agent.
- n8n env var: N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true (added to the
  n8n service block in docker-compose.yml) so the AI Agent shows the
  ai_tool connection slot.
- Architectural choice for Phase 0: Pattern A (self-hosted container on
  agent-net) over Pattern B (remote mcp.atlassian.com) — simpler auth
  (API token vs OAuth), no Cloudflare Tunnel involvement, fits the
  existing docker-compose pattern.

Files touched:
  agent/docker-compose.yml                    + mcp-atlassian service,
                                              + N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE
  agent/env.template                          + ATLASSIAN_URL, EMAIL, TOKEN block
  agent/n8n/workflows/bugsy.json              + MCP Client Tool node,
                                              + ai_tool connection,
                                              + TOOLS section in agent prompt
  docs/workflows/bugsy-unified.md             auto-gen refresh
-->

## Reviewer Notes

<!-- Leave empty until code review. Reviewer adds feedback here when requesting changes. -->

---

# Feature: MCP server fleet for Bugsy's brain and n8n workflows

## Problem

Bugsy's AI Agent (`@n8n/n8n-nodes-langchain.agent` inside [`bugsy.json`](../../../agent/n8n/workflows/bugsy.json)) is currently **knowledge-only** — at the moment it answers a question, the only context it has is whatever the upstream RAG pipeline pre-retrieved. It cannot:

- Look up a Jira ticket's *current* status (the RAG mirror surfaces yesterday's digest; live state is invisible)
- Read a GitHub PR or issue
- Search Slack history
- Pull a Google Search Console metric for an SEO question

The result is staleness — the [Periscope incident, 2026-05-18](../archive/) was a clean example: Bugsy described Phases B+C as "out of scope / future" when they had already shipped, because the source-of-truth (the new repo) wasn't in any pre-retrieved context. The RAG mirror eventually catches up, but only after the cron fires.

The fix is **tools** — Model Context Protocol (MCP) servers that the agent can invoke at decision time to read live state from the systems Anthony actually uses.

## Requirements

### Must have

1. WHEN Bugsy's AI Agent decides a question requires live data from one of the supported systems (Jira, GitHub, Slack, GSC), it SHALL be able to invoke an MCP-backed tool and incorporate the result into its answer.
2. WHEN Bugsy's n8n workflows (job board, leads hunter, research, etc.) need the same live data, they SHALL be able to call the same MCP servers — no duplicate integration logic per workflow.
3. MCP servers SHALL run as docker-compose services on the existing `agent-net` network (matching the established stack pattern), unless the official source publishes a remote-hosted MCP that's reachable by URL (Atlassian's `mcp.atlassian.com` falls into this category).
4. Authentication credentials SHALL live in the existing `.env` pattern. No secrets committed to git.
5. Every MCP added SHALL have a smoke-test verification (a chat exchange or workflow run that proves the agent used the live tool, not RAG-cached info).

### Nice to have

- A simple internal directory page in `docs/` listing every MCP, its capabilities, and the env vars it needs.
- Per-MCP log routing into `~/agent/logs/mcp/<name>/` so failures are debuggable without `docker logs`.
- A small `agent/scripts/mcp-health.sh` that pings every MCP container and reports up/down — runnable from cron or via Slack slash command.

### Non-goals (what this does NOT do)

- Does NOT expose MCPs to Claude Code on the laptop. Claude Code is already MCP-configured separately; that integration stays out of scope.
- Does NOT include Langfuse (deferred — separate spec when LLM observability becomes a real need).
- Does NOT include Caddy (retired — Cloudflare Tunnel covers ingress, Docker network covers internal routing).
- Does NOT add Confluence to the Atlassian MCP scope (Jira only — user's wiki lives elsewhere).
- Does NOT scope a P2 set (Gmail, Calendar, Sentry, Periscope-as-MCP, SearXNG-as-MCP). Those land in follow-up specs once the P1 four are stable.

## Design

### Architecture

Two patterns, picked per-MCP based on what the vendor publishes:

**Pattern A: Self-hosted container on `agent-net`** (for community / official-local MCPs)

```
agent-vm:
  agent-net (existing docker network):
    agent-n8n
    agent-mcp-<name>      ← new container per MCP
      image: <vendor/community image>
      transport: SSE on port 8800 (consistent across MCPs)
      env: API_TOKEN from .env
      restart: unless-stopped

n8n MCP Client Tool node:
  endpoint: http://agent-mcp-<name>:8800/sse
```

**Pattern B: Remote vendor-hosted SSE endpoint** (for officially-hosted MCPs)

```
n8n MCP Client Tool node:
  endpoint: https://mcp.<vendor>.com/v1/sse
  auth: OAuth flow or bearer token from .env
```

No Caddy, no reverse proxy. Docker service names resolve inside `agent-net`; remote endpoints are reached via the existing outbound path (Cloudflare Tunnel handles inbound, but these are outbound calls so the tunnel isn't involved).

### Wiring into Bugsy's AI Agent

The langchain Agent node in `bugsy.json` currently has no tools attached — its `systemMessage` is the entire instruction surface. To use MCPs we attach MCP Client Tool nodes as tool inputs to the AI Agent, alongside the existing memory + chat-model connections:

```
[Embed Question] → [Search Qdrant ...] → [Build Context] → [AI Agent] → ...
                                                              ↑ ↑ ↑ ↑
                                              [Postgres Chat Memory]
                                              [OpenAI Chat Model]
                                              [MCP Tool: atlassian]    ← new
                                              [MCP Tool: github]       ← new
                                              [MCP Tool: slack]        ← new
                                              [MCP Tool: gsc-bundle]   ← new
```

The system prompt updates to mention the available tools so the agent knows when to reach for them — example addition: *"If asked about a specific Jira ticket (UTT-NNN) or its current status, use the atlassian tool rather than answering from KB content (which may be stale)."*

### P1 lineup (this spec)

| Order | MCP | Pattern | Why first | Verification question |
|---|---|---|---|---|
| 1 | Atlassian (Jira) | B — remote SSE at `mcp.atlassian.com/v1/sse` | Highest direct payoff; closes the stale-Jira-digest gap; vendor-hosted = least setup | "Boss — what's UTT-299's status?" → agent calls the tool, reports live state |
| 2 | GitHub | A — `ghcr.io/github/github-mcp-server` on `agent-net` | Single biggest unlock for agentic coding; the user lives in PRs | "What PRs are open on coffey.codes?" → agent calls the tool, lists live PRs |
| 3 | Slack | A — community `mcp-slack` container on `agent-net` | Bugsy currently can post but not read; reading history closes the loop | "What did we say last week about Periscope?" → agent searches Slack via tool |
| 4 | GSC / GA4 / Bing bundle | A — the user's existing MCP in a container on `agent-net` | Already exists, just needs containerization + wiring | "Top GSC queries for coffey.codes this week?" → agent calls the tool |

### Phase 0 — de-risk before fleet build

Before standing up all four, ship **just Atlassian** end-to-end:

1. Configure an Atlassian API token / OAuth in `.env`
2. Add an MCP Client Tool node in `bugsy.json` pointed at `https://mcp.atlassian.com/v1/sse`
3. Wire it into the AI Agent
4. Update the agent's system prompt to mention the tool
5. Import + activate the updated workflow
6. Test: ask Bugsy "what's UTT-299's status?" in Slack and confirm the response references live ticket state (different from any RAG-cached digest)

If Phase 0 works cleanly, Phases 1.2–1.4 each follow the same pattern with their own MCP server. If Phase 0 surfaces a blocker (e.g. n8n's AI Agent doesn't propagate MCP tool results well, or auth flow is messier than expected), we learn it once and revise the spec.

### Open questions for Phase 0

These get answered during Phase 0 implementation — calling them out so they're explicit:

- **Does n8n's `@n8n/n8n-nodes-langchain.agent` v3.1 support MCP Client Tool nodes as tool inputs?** Recent n8n versions added the MCP Client Tool node; verify it integrates with the existing agent shape.
- **What auth flow does the Atlassian remote MCP need?** OAuth with redirect (won't fit a headless agent context) vs API token in a header. If OAuth-only, fall back to a self-hosted community Jira MCP.
- **How are tool results surfaced in the agent's response?** Inline citation? Silent grounding? May want to teach the system prompt to say "checked Jira: ..." for transparency.

### Credentials map

| MCP | Auth | `.env` key(s) | Where it lives in the container/endpoint |
|---|---|---|---|
| Atlassian (Jira) | API token + email, OR OAuth | `ATLASSIAN_EMAIL`, `ATLASSIAN_API_TOKEN`, `ATLASSIAN_DOMAIN` | Passed as headers by the MCP Client Tool node |
| GitHub | PAT (fine-grained scope: repo read) | `GITHUB_TOKEN_MCP` (separate from any existing) | Env var on the `agent-mcp-github` container |
| Slack | Existing Bugsy app token | `SLACK_BOT_TOKEN` (already in n8n credential — export to .env too) | Env var on the `agent-mcp-slack` container |
| GSC bundle | OAuth refresh token or service account JSON | `GSC_SERVICE_ACCOUNT_JSON` (or similar) | Mounted into the container |

No new secrets manager — `.env` continues to be the source. Terraform doesn't manage these; they're hand-added to the deployed `.env` on the VM.

## Edge cases

- [ ] **MCP server is down when the agent tries to call it.** The langchain agent should treat a tool failure as a recoverable error and either retry or answer without it. Confirm during Phase 0.
- [ ] **MCP returns a huge response** (e.g. listing every PR in a repo). Make sure the agent doesn't try to stuff 100 KB into its next reasoning step. Some MCPs support pagination/limits in tool args.
- [ ] **Auth token expires.** The agent gets a 401 from the tool. Health check script flags it; manual rotation in `.env`. No silent failure.
- [ ] **Tool tries to write** (e.g. `slack.send_message`). For MVP, restrict to **read-only** tool surfaces on every MCP. Writing comes later, behind an explicit confirmation step. Document the policy in the agent's system prompt.

## Acceptance criteria

1. **Phase 0:** Atlassian MCP integrated; a Bugsy Slack chat asking about a specific Jira ticket gets a response that demonstrably reflects live Jira state (e.g. status changed today by someone, agent reports the new status).
2. **Phase 1.2:** GitHub MCP integrated; chat asking "what PRs are open on coffey.codes?" lists live PRs.
3. **Phase 1.3:** Slack MCP integrated; chat asking about a past Slack conversation surfaces the actual messages, not invented summaries.
4. **Phase 1.4:** GSC/GA4/Bing MCP integrated; chat asking about SEO metrics returns numbers the user can cross-check in the GSC console.
5. **Per-MCP:** The `docker compose ps` output on the VM shows the MCP container healthy and running; the corresponding env vars are set; n8n execution log shows successful tool invocations.
6. **No regression:** Existing Bugsy chat behavior (RAG-grounded answers about bio/projects/digests) continues to work — MCPs are additive, not replacement.

## Constraints

- All MCP traffic stays inside `agent-net` or out via the existing Cloudflare Tunnel egress path. No new public endpoints exposed.
- Read-only access until a follow-up spec adds write surfaces with explicit confirmation.
- No new persistent storage unless an MCP requires it (most don't — they proxy live APIs).
- Container image versions pinned, not `:latest` — security + reproducibility.
- Per the project's [verify-before-commit rule](../../documentation/development-standards.md): each phase ships as its own commit after the verification in Acceptance Criteria succeeds.

## Tasks

### Phase 0 — Atlassian (de-risk)

- [ ] Add `ATLASSIAN_EMAIL`, `ATLASSIAN_API_TOKEN`, `ATLASSIAN_DOMAIN` to `agent/env.template` (and the user adds real values to the VM's `.env`)
- [ ] Add an MCP Client Tool node to `bugsy.json` pointed at the Atlassian remote MCP endpoint
- [ ] Wire it into the AI Agent
- [ ] Update the agent's `systemMessage` to teach it when to use the tool and how to attribute the result
- [ ] File-based import into n8n + activate
- [ ] Smoke test (see Acceptance Criteria #1)
- [ ] If blocked: document the blocker, fall back to a self-hosted Jira MCP container, retry

### Phase 1.2 — GitHub

- [ ] Add `agent-mcp-github` service to `docker-compose.yml` (image, env, network)
- [ ] Add `GITHUB_TOKEN_MCP` to `env.template`
- [ ] Add MCP Client Tool node to `bugsy.json` pointed at `http://agent-mcp-github:8800/sse`
- [ ] Smoke test, then ship

### Phase 1.3 — Slack

- [ ] Identify the right community Slack MCP (verify activity / maintenance status)
- [ ] Add `agent-mcp-slack` service to compose
- [ ] Export Slack bot token into `.env` (parallel to the existing n8n credential)
- [ ] Wire into `bugsy.json`, smoke test, ship

### Phase 1.4 — GSC / GA4 / Bing bundle

- [ ] Containerize the existing MCP the user already runs locally
- [ ] Mount the service-account JSON
- [ ] Wire into `bugsy.json`, smoke test, ship

### Cross-phase

- [ ] Per-MCP doc page under `docs/architecture/mcp/<name>.md` capturing endpoint, auth, capabilities, gotchas
- [ ] Update `docs/architecture/overview.md` to show MCP servers in the stack diagram
- [ ] Update Bugsy's agent brief at `docs/documentation/agents/bugsy.md` (create it if missing) to list available tools
- [ ] Optional: `agent/scripts/mcp-health.sh` that pings every MCP, slacks a warning if any is down

## Notes

- **Why phased.** This is the first time MCPs touch this stack. The Phase 0 de-risk catches integration gotchas with a single, high-value MCP before we invest in three more. If Atlassian flushes a problem with the n8n MCP Client Tool ↔ AI Agent wiring, we want to find it once and adapt.
- **Why read-only first.** Write tools (slack.send, github.create_issue, etc.) introduce blast-radius issues that need explicit confirmation flows. Land reads, prove the value, then build the confirmation UX once we've seen real usage patterns.
- **Why no Cloudflare Tunnel exposure.** Per the locked-in scope: Claude Code on the laptop is already MCP-configured via a separate setup. The MCPs in this spec exist to serve Bugsy's brain + n8n workflows, both of which live on the VM. Internal docker-net access only.
- **What this doesn't fix.** The Jira digest workflow ([archive/BUG-JIRA-001](../archive/BUG-JIRA-001-digest-reports-completed-tickets-as-current.md)) still operates on email — MCP integration is for **chat-time queries**, not the daily digest. If the digest itself needs to consult live Jira, that's a separate follow-up.
