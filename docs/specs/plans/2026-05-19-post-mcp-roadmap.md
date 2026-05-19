---
title: "Post-MCP roadmap — what's next after the MCP fleet"
created: 2026-05-19
author: Anthony Coffey
status: living-doc
related_specs:
  - SPEC-MCP-001  (archived 2026-05-19)
  - SPEC-WORKFLOW-001 (draft)
  - SPEC-LEADS-001 (draft)
---

# Post-MCP roadmap — what's next after the MCP fleet

**Purpose**: this is the session-pickup doc. The conversation that ended on 2026-05-19 was approaching context limits; this plan captures end-of-session state + decisions + what's drafted vs deferred so a fresh-context Claude (or future-Anthony) can resume cleanly.

## State of the world, end of 2026-05-19

### MCP fleet — closed

- **SPEC-MCP-001 — complete.** 3 of 4 P1 MCPs shipped + verified (Atlassian, GitHub, Notion). Phase 1.4 (GSC/GA4/Bing bundle MCP) **cancelled** — the existing GSC-bundle MCP that runs locally for Claude Code remains in place; replicating it as a container for Bugsy was deemed lower-priority. Spec archived.
- **SPEC-MCP-002 — complete, archived.** Notion page creation.
- **SPEC-MCP-003 — complete, archived.** Notion full read/write/edit/archive/comment/schema. The system prompt is the only behavioral gate ("yolo" state, operator-approved).

### What's redundant now / what's new pain

The post-MCP audit (final exchange of the 2026-05-19 session) identified:

- **Redundant in current shape:** `bugsy-jira-digest.json` — its data source (parsed Gmail) is strictly worse than calling Jira via the atlassian MCP at chat time. The DIGEST PATTERN is still valuable; the JIRA SCOPE is what's redundant. Pivot to general email digest. **Captured in SPEC-WORKFLOW-001 (draft).**
- **Cleanup:** `bugsy-inbox-watcher.json` — early experiment, currently inactive, overlapping with the new digest. Gets deleted as part of SPEC-WORKFLOW-001.
- **Quality gap:** `bugsy-leads-hunter.json` posts Slack messages with link-unfurl noise, and its scoring rubric is shallower than the job-board fetcher's. Operator wants agency-bias. **Captured in SPEC-LEADS-001 (draft).**

### What's NOT redundant (confirmed during audit)

- `bugsy-job-board-fetcher.json` — no MCP covers job boards
- `bugsy-job-board-ui.json` — HTML view; unaffected
- `bugsy-research.json` — generic company research isn't covered by any MCP
- `bugsy-rag-ingest.json` / `bugsy-rag-query.json` / `bugsy-rag-refresh-notify.json` — MCPs are live; RAG is indexed corpus; both useful for different reasons
- `bugsy.json` — the AI Agent itself, downstream consumer of everything

## Active specs (drafts; pickup work for next session)

### SPEC-WORKFLOW-001 — Secretary email digest

[`docs/specs/active/SPEC-WORKFLOW-001-secretary-email-digest.md`](../active/SPEC-WORKFLOW-001-secretary-email-digest.md)

**Replaces:** `bugsy-jira-digest.json`, `bugsy-inbox-watcher.json` (both deleted as part of impl)

**Builds:** Two new workflows —
- `bugsy-work-email-digest.json` (cron 8am+4pm CT M-F, Bitmotive Gmail)
- `bugsy-personal-email-digest.json` (cron 7am CT daily, coffey.codes Gmail)

**Key feature:** action items from the digest become Notion kanban cards automatically.

**Open questions** (resolve before implementation):
1. Which Notion database hosts action-item cards? (Existing Project Board vs new dedicated)
2. Default Status property value for new cards?
3. Confirm personal-inbox cadence (7am CT daily)
4. RAG mirror in v1 or v2?

### SPEC-LEADS-001 — Leads hunter rework

[`docs/specs/active/SPEC-LEADS-001-leads-hunter-rework.md`](../active/SPEC-LEADS-001-leads-hunter-rework.md)

**Three-phase rework of `bugsy-leads-hunter.json`:**

1. **Phase 1 (quick win):** Disable Slack link unfurls, tighten output format to a compact `*Top N*` list. Ships standalone.
2. **Phase 2:** Lift scoring to LLM-batch-rubric depth matching the job-board fetcher's quality bar. Add **agency bias** to the rubric. Investigation step: read the current workflow first.
3. **Phase 3 (optional):** GitHub MCP "recent engineering activity" signal as a positive scoring factor.

**Open questions:**
1. Score scale: keep 1-10 or move to 0-100?
2. Threshold value (proposing 75 to match job-board)?
3. "Agency" sub-typing (software / marketing / staffing)?
4. Insert below-threshold leads to `agent.leads` or filter pre-insert?

## Deferred work (mentioned but not specced)

Captured during the audit; the operator decided not to spec these now ("nail the email digest first" / "we paused here"):

- **`research` → auto-Notion-page** — when `/research <target>` completes, brief lands as a Notion page in addition to Slack DM. Builds a durable research archive.
- **Job-board fit → Notion kanban** — each fit-scored job becomes a card on a "Job applications" kanban (replaces the localStorage-based status on the HTML UI).
- **Daily GitHub commit digest** — small new cron workflow: "what shipped across your repos in the last 24h?" Different from the email digest (code-focused).
- **GSC bundle MCP for Bugsy** — formerly SPEC-MCP-001 Phase 1.4, cancelled. Re-spec as SPEC-MCP-004 if/when needed.

## Suggested next-session order of operations

1. **Quick wins first** (no spec; just chore commits):
   - Apply Phase 1 of SPEC-LEADS-001 — disable unfurls, tighten formatting. 10 minutes. Improves Slack signal-to-noise starting next morning's run.
   - (Or defer to inside the SPEC-LEADS-001 implementation; either works.)
2. **Resolve open questions on SPEC-WORKFLOW-001** (4 small decisions).
3. **Implement SPEC-WORKFLOW-001** — the bigger, more disruptive change (deletes two workflows, adds two new ones, introduces proactive Notion writes).
4. **Resolve open questions on SPEC-LEADS-001** (Phase 2 specifically).
5. **Implement SPEC-LEADS-001** Phase 2 (and optionally Phase 3).
6. **Revisit deferred work** — pick one or two for a third spec wave.

## Useful pointers for a fresh session

- **`CLAUDE.md`** — full current-state context. Updated 2026-05-19 to reflect the MCP fleet + Notion writes + DDD scaffold.
- **`docs/documentation/agents/bugsy.md`** — agent brief for Bugsy. Captures interfaces, state, failure modes, gotchas. Good orientation read.
- **`docs/specs/archive/`** — every completed spec with verification notes. The recent MCP work is all there.
- **`docs/documentation/development-standards.md`** — DDD + TDD + git conventions, including the verify-before-commit rule and the file-based n8n workflow flow.
- **`docs/reference/env-vars.md`** + **`docs/reference/webhooks.md`** — refreshed 2026-05-19 to reflect everything currently deployed.

## Notes

- The conversation context that produced this roadmap was getting heavy by the end. Per the operator's "context is inflated" call, all the planning was captured here + in the two new spec drafts before pausing. A fresh-context Claude should be able to pick up either spec without re-deriving the full conversation history.
- The DDD discipline is paying off here exactly as designed — the lift from "session ending soon" to "ready to resume in a new session" is just writing these three files and the SPEC-MCP-001 close-out. No work product is lost in chat history.
