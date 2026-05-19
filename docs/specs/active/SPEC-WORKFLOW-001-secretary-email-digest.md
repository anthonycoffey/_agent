---
id: SPEC-WORKFLOW-001
title: "Secretary email digest — replaces jira-digest, covers both inboxes"
status: draft
created: 2026-05-19
author: Anthony Coffey
reviewers: []
affected_repos: [_agent]
---

<!--
2026-05-19 — Drafted during the post-MCP audit (see plan
docs/specs/plans/2026-05-19-post-mcp-roadmap.md). Decisions captured in
the conversation:
  - Both inboxes (Bitmotive work + coffey.codes personal), TWO separate workflows
  - Inbox-watcher (experiment, currently inactive) gets DELETED as part of this work
  - Slack post format only — NO digest-page to Notion
  - YES kanban-card creation in Notion for each Action Item
    (operator: "i dont care if it creates bad cards, ill dump them ...
    maybe this will inspire me to use it more")
  - Existing jira-digest workflow gets DELETED — replaced by the work-email
    digest. Jira-specific questions are now MCP-tool driven at chat time.

Status: draft. Pickup from a fresh session: this spec is implementation-
ready except for the small open questions in the "Open questions" section.
-->

## Reviewer Notes

<!-- Leave empty until code review. Reviewer adds feedback here when requesting changes. -->

---

# Feature: Secretary email digest (replaces jira-digest, covers both inboxes)

## Problem

`bugsy-jira-digest.json` was designed when Bugsy had **no live Jira access**. It scraped Jira email notifications as a poor-man's change-feed and summarized them twice a day. That made sense when email was the only path to Jira state.

With the Atlassian MCP shipped (SPEC-MCP-001 Phase 0), Bugsy can now query Jira directly at chat time. The jira-digest workflow is left doing redundant work — emails are a strictly inferior data source to the live API.

But there's a real underlying need the jira-digest was meeting: a **scheduled, batched, secretary-style review of what's happening** that the operator reads passively in Slack rather than querying actively. That need extends beyond Jira:

- Vendor / contract / billing emails
- Scheduling threads (when's this meeting, who's available)
- @-pings from collaborators and clients outside any tool with an MCP
- Newsletters with one actually-useful link buried in promo material
- Anything in the personal inbox that needs follow-up

These don't show up anywhere queryable. Email is the only catch-all, and a daily digest is the right pattern.

Reframe: `bugsy-jira-digest` → **two secretary digests**, one per inbox, broader scope, kanban-card creation for action items.

`bugsy-inbox-watcher.json` (experiment, currently inactive) is also redundant in this reframe and gets removed.

## Requirements

### Must have

1. WHEN the cron fires for the work inbox (Bitmotive), the workflow SHALL pull recent Gmail, tag emails FRESH (≥9h cutoff or matching cron interval) / STALE, and post one secretary-style digest to `#mulberry-street` in Slack.
2. WHEN the cron fires for the personal inbox (coffey.codes), a separate workflow SHALL do the same against the personal Gmail.
3. The digest SHALL surface (in roughly this priority): action items requiring the operator's response, scheduling threads, important @-mentions or named follow-ups, vendor/billing/contract stuff, and a brief catch-all of FYI threads.
4. EACH identified action item SHALL create one card on a Notion database (kanban) via the Notion MCP. Each card includes the action item text + the email subject + sender + a one-sentence context summary.
5. The existing `bugsy-jira-digest.json` workflow SHALL be **deleted** (not just deactivated). Replaced by the two new digests.
6. The existing `bugsy-inbox-watcher.json` workflow SHALL also be deleted (was an early experiment, currently inactive).
7. The digest body itself SHALL NOT be written to Notion (Slack post only). RAG mirror to Qdrant is fine; see Nice-to-have.

### Nice to have

- Mirror each digest to Qdrant under category `email-digests-work` / `email-digests-personal` (parallel branch to `/rag-ingest`), same pattern as the current `bugsy-jira-digest` RAG mirror. So future chat queries like "what was that email from X last Tuesday?" can recall the digest.
- A daily-summary message at the end of the personal-inbox digest that calls out *patterns* (e.g. "3 newsletters waiting; 2 unread follow-ups from Thursday").
- Per-card Notion property: a "Source" property linking back to the Gmail thread URL. Lets the operator click through.
- Configurable card-target Notion location — env var or workflow-level setting so the operator can re-point the target without re-editing the workflow.

### Non-goals

- Does NOT auto-reply, auto-archive, or label individual emails. The current `bugsy-inbox-watcher.json` did some of this; the secretary digest deliberately doesn't. Surgical Gmail automation, if needed later, is its own spec.
- Does NOT include calendar integration. Scheduling emails get surfaced; actually creating calendar events is out of scope.
- Does NOT replace `bugsy.json`'s on-demand chat capability. The digest is passive (scheduled summary); on-demand is reactive (operator asks).

## Design

### Two workflows, one shared shape

Both digests follow the same node graph as the soon-to-be-deleted `bugsy-jira-digest.json` — just with different Gmail credentials, filters, and posting cadences:

```
Schedule → Gmail (Get Mail, newer_than:Nd) → Aggregate Emails (FRESH/STALE tagging)
                                              ↓
                                              Write Digest (LLM)
                                              ↓
                                              ├─→ Post to #mulberry-street (Slack)
                                              ├─→ Build RAG Payload → POST /rag-ingest
                                              └─→ Extract Action Items → loop → Create Notion Card (MCP tool)
```

Reuse the FRESH/STALE infrastructure from `bugsy-jira-digest.json` directly. That's:
- `Aggregate Emails` Code node — strip HTML, tag FRESH/STALE based on a cutoff, surface `Received:` ISO timestamps, header with `DIGEST WINDOW` block
- LLM system prompt — knows the FRESH/STALE convention

The LLM system prompt **broadens** from "Jira-only" to "secretary-style summary of all email." Persona stays the same (Bugsy voice, sparingly used). Output sections:

```
*Summary*
What's moved this window. Group by topic (project, vendor, person). Past-tense for resolved threads; present-tense for active ones.

*Action Items*
• <one bullet per concrete thing the boss has to do, starting with a verb>
• <each bullet is short enough to become a kanban card title>
```

The Action Items section needs to be structurally extractable — the downstream node parses bullets into individual card creations.

### Cadence

**Work inbox (Bitmotive):**
- Cron `0 8,16 * * 1-5` — 8am + 4pm CT M-F. Same as the current jira-digest. Work happens during work hours.
- Gmail filter: `newer_than:1d` (no `from:jira@…` filter — broader scope)
- Credential: `Gmail - Bugsy (anthony@bitmotive.com)` (existing, reused)

**Personal inbox (coffey.codes):**
- Cron `0 7 * * *` — 7am CT daily, including weekends. Personal email doesn't respect M-F.
- Gmail filter: `newer_than:1d`
- Credential: `Gmail - Bugsy (anthony@coffey.codes)` (existing, reused — currently used by `bugsy-research`)

Both write to the **same Slack channel** (`#mulberry-street`, ID `C0AV83XUSTU`). The digest headers should make clear which inbox each one came from (e.g. *"Work-email digest @ 8:00am CT"* vs *"Personal-email digest @ 7:00am CT"*) so they don't get visually confused in the channel.

### Notion kanban card creation

Each Action Item bullet from the LLM digest becomes one Notion page-in-a-database call. The flow:

1. After `Write Digest` produces the markdown, a downstream **Code node** parses the `*Action Items*` section, splitting on the `• ` bullet leader.
2. For each bullet, the workflow makes a Notion MCP `create-page-in-data-source` call with the bullet as the title, plus body content (email subject, sender, the digest's one-sentence context).
3. Cards land on the operator's chosen Notion database (see **Open questions** for which database).

If the LLM identifies zero action items, no cards get created — the empty-loop-iterates-zero-times pattern.

The card payload should include enough context that the operator can decide what to do without going back to the digest:

```
Title: "<action item bullet text>"
Properties:
  Status: To Do (default)
  Source: "<email subject>"  (or a Notion URL property pointing at the Gmail thread, if that's feasible)
  Inbox: "Work" | "Personal"
Body (page content):
  <one-sentence context summary>
  Email from: <sender>
  Received: <ISO timestamp>
  [optional: link to the original digest in Slack]
```

### What gets deleted

This spec's implementation ALSO deletes:
- `agent/n8n/workflows/bugsy-jira-digest.json`
- `agent/n8n/workflows/bugsy-inbox-watcher.json`
- `docs/workflows/bugsy-jira-digest.md`
- `docs/workflows/bugsy-inbox-watcher.md`
- Any `CLAUDE.md` table-row entries for those workflows
- Any `mkdocs.yml` / `SUMMARY.md` nav references to those workflow doc pages

The two new workflow files get created:
- `agent/n8n/workflows/bugsy-work-email-digest.json`
- `agent/n8n/workflows/bugsy-personal-email-digest.json`
- `docs/workflows/bugsy-work-email-digest.md`
- `docs/workflows/bugsy-personal-email-digest.md`

OR, alternatively, one file `bugsy-email-digest.json` that's parameterized — but n8n workflows can't easily parameterize cron schedules + credentials at activation time, so two files is cleaner.

### RAG mirror (nice-to-have)

Parallel branch posts each digest to `/rag-ingest` under category `email-digests` (one category for both inboxes; the digest title/body distinguishes them). Same shape as the existing jira-digest RAG mirror. Filename pattern: `email/<inbox>/<ISO>.md`.

Bugsy already does two-stage retrieval with a category filter for `jira-digests` (per BUG-AGENT-001). If `email-digests` becomes a similarly-stale-prone category, add it to the filtered retrieval branch in `bugsy.json`. Not blocking for v1 — RAG mirror can be added in a follow-up.

## Edge cases

- [ ] **Empty inbox window.** Same as jira-digest — the LLM produces a one-line "Quiet shift, boss" message; zero cards created.
- [ ] **One email triggers multiple action items.** The LLM might produce 5 bullets from a single long email. That's fine — 5 cards get created. Operator can dedupe by archiving cards they don't want.
- [ ] **LLM hallucinates an action item.** E.g. spam-flavored email leads to "follow up on weight-loss offer." The card gets created with bad content; operator archives it. Acceptable failure mode per the operator's "I'll dump them" stance.
- [ ] **Notion MCP transient failure.** If the create-card call fails for any specific item, log it and continue with the rest. Don't fail the whole workflow. Use `onError: continueRegularOutput` on the Create Notion Card node.
- [ ] **Gmail returns 0 emails AND the LLM still gets called.** Same as jira-digest — `alwaysOutputData: true` on the Gmail node, LLM gets the "(no email in the window)" sentinel and returns the in-voice quiet-shift line.
- [ ] **Card title too long for Notion.** Notion truncates ~2000 chars on title; action item bullets shouldn't ever approach that. If they do, truncate in the parser code node.
- [ ] **Two simultaneous digest runs (work + personal overlapping)** — shouldn't happen given different cadences, but the cards each go through their own create call so there's no contention.

## Acceptance criteria

1. `bugsy-work-email-digest.json` exists, runs on `0 8,16 * * 1-5` CT, fetches Bitmotive Gmail with `newer_than:1d` filter, posts a secretary digest to `#mulberry-street`, creates Notion cards for action items.
2. `bugsy-personal-email-digest.json` exists, runs on `0 7 * * *` CT, fetches personal Gmail, posts to the same Slack channel with a clearly distinguished header, creates Notion cards.
3. `bugsy-jira-digest.json` is deleted from `agent/n8n/workflows/`; corresponding `docs/workflows/bugsy-jira-digest.md` is deleted; CLAUDE.md workflow table no longer lists it.
4. `bugsy-inbox-watcher.json` is deleted; same cleanup as above.
5. The operator manually triggers one work-inbox run and one personal-inbox run, verifies the digest reads well in Slack, and confirms the action-item cards appeared on the chosen Notion database.
6. (Regression) Bugsy's chat `atlassian` tool still answers Jira questions live — no functionality regression from removing the jira-digest workflow.

## Constraints

- Reuse existing Gmail credentials. No new credentials in n8n.
- Notion card creation uses the existing `MCP — Notion` node + bearer credential. No new wiring on the auth side.
- Per the project's verify-before-commit rule: implementation ships as one commit after both workflows run cleanly end-to-end and produce real cards.
- Per the file-based n8n import workflow: edit local JSON, import via the n8n UI from the local file, verify, then commit.

## Tasks

### Pre-work

- [ ] Read the existing `bugsy-jira-digest.json` to lift the FRESH/STALE Aggregate Emails code + LLM system prompt verbatim — they're the right starting point.
- [ ] Operator decides which Notion database the cards land on (see Open questions).

### Build

- [ ] Create `agent/n8n/workflows/bugsy-work-email-digest.json` — copy jira-digest, broaden Gmail filter (drop `from:jira@`), update LLM system prompt to "secretary mode," add parallel branch for Notion card creation.
- [ ] Create `agent/n8n/workflows/bugsy-personal-email-digest.json` — same template, different cred + cron.
- [ ] Add a small Code node (`Extract Action Items`) that parses the LLM output's `*Action Items*` section into an array of bullet items.
- [ ] Add a Loop/Split In Batches node + the existing MCP — Notion tool node (or a new HTTP Request node calling the notion MCP directly) to create one card per bullet.
- [ ] Test: trigger both workflows manually, eyeball Slack output, eyeball Notion database for cards.

### Cleanup

- [ ] `git rm agent/n8n/workflows/bugsy-jira-digest.json`
- [ ] `git rm agent/n8n/workflows/bugsy-inbox-watcher.json`
- [ ] `git rm docs/workflows/bugsy-jira-digest.md`
- [ ] `git rm docs/workflows/bugsy-inbox-watcher.md`
- [ ] Update `CLAUDE.md` workflow table — remove jira-digest + inbox-watcher rows, add work-email-digest + personal-email-digest rows.
- [ ] Update `mkdocs.yml` nav — remove the two old entries, add two new ones.
- [ ] Update `docs/SUMMARY.md` — same nav cleanup.
- [ ] Update `docs/architecture/credentials.md` — adjust the "used by" column on the Gmail credentials.
- [ ] In `bugsy.json` AI Agent's system prompt, scan for any text that references the "jira-digest" workflow specifically and update to mention the secretary digests instead.

### Verify before commit

- [ ] Both workflows imported into n8n, activated, manual-triggered once each.
- [ ] Action-item cards visible on the chosen Notion database.
- [ ] No regression on Bugsy chat (Jira queries still work via atlassian MCP).
- [ ] Commit message captures observed behavior, not speculation.

## Open questions for the operator

1. **Which Notion database hosts the Action Item cards?**
   - **Option A:** existing Project Board (the boss's main kanban). Cards land alongside manual tasks. Pro: one tracker. Con: digest cards may dilute the signal in your main board.
   - **Option B:** a new dedicated database — e.g. "Inbox Actions" — connected to the Bugsy integration. Pro: clean separation; you can promote items to Project Board manually. Con: another surface to check.
   - **Operator's hint from the conversation:** *"i dont care if it creates bad cards, ill dump them ... maybe this will inspire me to use it more (i prefer this over trello because trello becomes one more thing i have to open and check)"* — this leans toward Option A (the kanban they already use), so they actually see the cards.

2. **Default card Status property value.** "To Do"? "Inbox"? "New from Bugsy"? Whichever column the operator wants new cards to land in.

3. **Cadence on the personal inbox.** Daily at 7am CT was my default proposal; operator hasn't pushed back. Confirm or adjust.

4. **RAG mirror for the secretary digest.** Nice-to-have in this spec. Could be included in v1 (low marginal cost, follows existing pattern) or deferred to v2. Operator's call.

## Notes

- The FRESH/STALE infrastructure from `bugsy-jira-digest.json` was built specifically because the LLM was hallucinating closed-ticket activity as current. Same risk applies to a secretary digest on a longer time horizon — keep it.
- This is the first workflow that does **proactive Notion writes**. The on-demand chat workflow (`bugsy.json`) only writes when asked. A scheduled workflow writing cards is a different blast-radius profile. The mitigation is operator transparency — every card has source / inbox / received-timestamp so misfires are obvious and the operator can archive them.
- If the Notion MCP rate-limits or chokes on bulk card creation, throttle with `Split In Batches` + a sleep. Hasn't been an issue at the current scale, but worth knowing.
