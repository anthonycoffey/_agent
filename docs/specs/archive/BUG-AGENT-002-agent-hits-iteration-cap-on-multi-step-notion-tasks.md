---
id: BUG-AGENT-002
title: "Agent hits 10-iteration cap on multi-step Notion tasks"
status: resolved
severity: P2
created: 2026-05-21
author: ""
reviewers: []
affected_repos: [_agent]
---

<!--
Severity:
  P0 — production-down or data loss; drop everything
  P1 — broken for many users or core flow; fix this sprint
  P2 — broken for some users or workaround exists
  P3 — minor / cosmetic / quality-of-life
-->

## Reviewer Notes

<!-- Leave empty until code review. Reviewer adds feedback here when requesting changes. -->

---

# Bug: Agent hits 10-iteration cap on multi-step Notion tasks

## Symptom

When Bugsy's unified Slack agent (`bugsy.json`) is asked to perform a Notion task
that needs several sequential tool calls (e.g. create a page, then update its
properties, then add comments), the AI Agent node runs out of iterations and
stops short of completing the task. Single-step Notion tasks succeed; only
multi-step sequences fail.

## Expected behavior

Multi-step Notion sequences run to completion within the iteration budget. The
human turns persisted in chat memory contain only the raw question the user
asked — not the RAG-augmented blob.

## Reproduction

1. Open a Slack chat with Bugsy and ask for a multi-step Notion operation
   (e.g. "create a page in <DB>, set its status, and add a comment").
2. Observe the AI Agent stop before finishing — it hits the `maxIterations`
   cap of 10.
3. Inspect the Postgres `n8n_chat_histories` table — human turns store the
   entire augmented context blob (raw question + ~10 RAG chunks) verbatim.

**Frequency:** every time, for tasks needing more than ~10 tool calls
**Environment:** prod — n8n container, `bugsy.json` unified Slack workflow

## Root cause

The **Build Context** node bakes the two-stage RAG retrieval result directly
into `chatInput`. The Postgres Chat Memory node then stores that augmented blob
verbatim as the human turn. Across a multi-turn conversation, every prior human
turn carries ~10 stale RAG chunks, so the agent drags 10 turns × ~10 chunks of
dead context into every call. The bloated context starves the agent's iteration
budget — it burns iterations wading through stale RAG instead of making
progress, and caps out at `maxIterations: 10`.

## Fix

1. Move the RAG context out of `chatInput` and into the AI Agent node's
   `systemMessage` expression. Verify that `$json` (and
   `$('Build Context').item.json...`) evaluates correctly inside `systemMessage`
   on the current n8n version — if not, fall back to a supported expression
   reference.
2. Set `chatInput` to `{{ $('Build Context').item.json.originalQuestion }}` so
   chat memory only ever persists the raw question.
3. Bump the AI Agent `maxIterations` from 10 → 30 to give multi-step Notion
   sequences enough headroom.

## Verification

Run a multi-turn chat that triggers a multi-step Notion task and confirm it
completes. Inspect the Postgres `n8n_chat_histories` table — human turns should
be short (raw question only), with no RAG chunks embedded.

## Regression test

Manual run-through after the fix: assert each human turn row in
`n8n_chat_histories` is the length of a raw question, not a multi-KB augmented
blob. Watch for the iteration cap recurring on long Notion task chains.

## Notes

Verified 2026-05-21: multi-step Notion task (create + update + comment chain)
completed successfully after the fix was imported into n8n. `systemMessage`
expressions (`$('Build Context').item.json.contextBlock`) resolve correctly in
AI Agent typeVersion 3.1 on `n8nio/n8n:latest`.

The original comment in Build Context — "Expressions in the agent's systemMessage
field don't reliably resolve (some versions ignore them), so this is the
bulletproof path" — was written against an older n8n version and is no longer
accurate. Removed the old approach entirely.
