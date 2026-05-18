---
id: BUG-JIRA-001
title: "Jira digest reports completed tickets as current activity"
status: complete
severity: P2
created: 2026-05-17
completed: 2026-05-17
author: Anthony Coffey
reviewers: []
affected_repos: [_agent]
---

<!--
2026-05-17 — Symptom A diagnosed and Phase 1 fix (FRESH/STALE tagging +
internalDate surfacing + prompt rewrite) shipped to bugsy-jira-digest.json.
Operator verified post-publish: a manual-trigger digest correctly past-tensed
closed tickets, kept them out of Action Items, and gracefully flagged a
missing Received: timestamp on one email (which led to the extractMs() fallback
chain being added in a follow-up — also verified working in the next digest).

Symptom B forked to BUG-AGENT-001 (chat workflow retrieval fix in bugsy.json)
and is tracked there.

Spec marked complete and moved to specs/archive/.
-->


<!--
Severity: P2 — wrong content in a daily-driver digest; workaround = cross-check in Jira directly.
Bump to P1 if it's misleading you into duplicate work or missed deadlines.
-->

## Reviewer Notes

<!-- Leave empty until code review. Reviewer adds feedback here when requesting changes. -->

---

# Bug: Jira digest reports completed tickets as current activity

## Symptom

The twice-daily Jira digest (`bugsy-jira-digest.json` → `#mulberry-street`) keeps mentioning tickets that have already been closed/completed as if they're active. Specifically: tickets that resolved hours or days ago appear in the *Summary* and *Action Items* sections of subsequent digests, often phrased in present tense ("UTT-NNN is in review" / "needs your approval") even though the ticket is `Done`.

## Expected behavior

The digest should describe only state changes that happened **within the current digest window** (since the last cron fire — i.e. the previous 8h, not the previous 24h). Tickets whose latest event is "moved to Done" or equivalent should:

- Appear **once** in the digest immediately after closure, with explicit past-tense framing ("closed by X at HH:MM")
- **Not** reappear in any subsequent digest
- **Not** generate action items, since closed work has no pending action

## Reproduction

1. Wait for a known ticket to be closed in Jira (e.g. assignee marks `Done`).
2. Observe the next digest after the close — usually the closure is reported correctly here.
3. Observe the **digest after that** (8h later). The closed ticket frequently reappears, sometimes with present-tense activity language as if the close hasn't happened.

**Frequency:** intermittent but common — observed across multiple digests over the past week.
**Environment:** prod — `agent-vm`, n8n container, claude-sonnet-4-6 via LiteLLM.

## Root cause (hypothesized — needs verification with a bad-digest sample)

Three contributing factors, all visible in [`agent/n8n/workflows/bugsy-jira-digest.json`](../../../agent/n8n/workflows/bugsy-jira-digest.json):

### 1. The LLM receives no per-email timestamps

The **Aggregate Emails** code node builds the LLM input from `from`, `subject`, `snippet`, and a 1200-char body slice. It does **not** include `internalDate` (Gmail receipt time, ms since epoch) — which sits unused on `j.internalDate` for every email returned by the Gmail node.

The system prompt explicitly tells the LLM:

> REQUIREMENTS:
> 1. THE OUTPUT MUST BE TEMPORALLY ACCURATE, OUTDATED EVENTS SHOULD NOT BE REPORTED AS CURRENT.
> 2. LOOK AT TIMESTAMPS TO VERIFY ORDER OF OPERATIONS

…but **no timestamps are in the payload it receives.** The instruction is unfulfillable. Whatever temporal signal exists has to be inferred from prose inside the email body, which is unreliable for Jira notification emails (they don't consistently lead with a "this comment posted at HH:MM" header).

### 2. The 24h Gmail filter overlaps both daily runs

The Gmail node uses `newer_than:1d`. Both the 8am and 4pm cron fires pull a sliding 24h window:

- **8am run** sees: prior afternoon (yesterday 8am → now) — includes yesterday-afternoon's emails
- **4pm run** sees: prior 24h (yesterday 4pm → now) — includes yesterday-afternoon's emails *again*

So every afternoon's events are processed **twice** — once by the 4pm digest the same day, once by the 8am digest the next morning. The prompt asks the LLM to dedupe ("If something's repeated across emails… mention once") but it has no signal for what's "already-reported vs fresh-this-window" — only that the same content appears multiple times within one run.

Closed-ticket emails are especially prone to repetition because the closing comment is the most recent activity and tends to be the email that survives the 24h cutoff the longest.

### 3. Notification emails include thread context that looks like current activity

Jira notification emails typically include the triggering event at the top **plus** a quoted tail of previous comments/activity for context. The 1200-char body truncation usually captures both. The LLM sees a mix of "this is the new event" and "this is months-old context" presented as one undifferentiated text block, with no markers separating them.

Closed tickets that receive a stray follow-up comment (e.g. someone @-mentions on a closed ticket, or a watcher posts a "thanks!") generate a fresh email whose quoted tail contains the closure note. The LLM can't tell the closure is old context and reports it as the headline event.

## Investigation: what to gather to verify

To confirm the diagnosis, we need to look at one concrete bad-digest example:

1. **Copy the Slack message text** from a digest that reported a completed ticket as current.
2. **Identify the offending ticket** (e.g. UTT-123).
3. **Pull the source emails** that fired that digest from Gmail (search `from:jira@ultrasoundai.atlassian.net UTT-123` filtered to the digest's 24h window).
4. **For each source email, note:** Gmail `internalDate`, the actual triggering Jira event (comment / status / assignee / watch), and whether the closure note appears in the body or in a quoted tail.
5. **Confirm:** does the LLM input (n8n execution log → `Aggregate Emails` output) contain the closure phrasing in a way that's indistinguishable from a fresh closure?

If yes, the three hypothesized causes are real. If no — if the LLM input contains clear signals the closure is old and it's *still* reporting as current — then this is a prompt-engineering bug, not an input-shaping bug, and the fix changes.

## Fix (proposed — sequence the cheapest first)

### Phase 1 — surface timestamps + tighten the window (cheap, high leverage)

**A. Surface `internalDate` per email to the LLM.** In `Aggregate Emails`:

```js
const internalDate = j.internalDate ? new Date(parseInt(j.internalDate, 10)).toISOString() : '?';
return `--- Email ${i + 1} ---\nReceived: ${internalDate}\nFrom: ${from}\nSubject: ${subject}\nSnippet: ${snippet}\nBody: ${body}`;
```

**B. Pass the digest-window boundary as a system-prompt variable.** Compute the cutoff (now - 8h, or now - 16h for the morning run after a weekend) in a small Code node and inject it into the system prompt. Update the prompt to say:

> Only describe events with `Received >= <CUTOFF>`. Anything older is stale context from a previous digest — mention only if it changes interpretation of a fresh event.

**C. Tighten the Gmail filter.** Replace `newer_than:1d` with `after:<unix-timestamp>` where the timestamp is the cutoff from step B. This eliminates the 8h overlap at the source rather than relying on the LLM to filter it out. Gmail's `after:` operator takes a unix timestamp; n8n can compute it via `Math.floor((Date.now() - 8*3600*1000) / 1000)`.

Combined: A surfaces the signal, B teaches the LLM how to use it, C reduces noise so the LLM has less to filter.

### Phase 2 — strip Jira's quoted tail (medium, only if Phase 1 isn't enough)

Add a body-cleanup pass in `Aggregate Emails` that finds Jira's "previous activity" boundary marker (likely a recurring pattern like `---` or `<a name="comment-…">`) and truncates the body there. Needs sample emails to identify the actual marker pattern.

### Phase 3 — persist last-digest timestamp (large, only if cron-overlap math becomes unreliable)

Store `last_digest_ran_at` in postgres (`agent.workflow_state` table or similar). Each run reads it, uses it as the cutoff, and updates it on success. Survives missed runs and cron drift; the dumb `now - 8h` math doesn't.

## Verification

Once Phase 1 lands and the workflow re-imports cleanly:

1. **Sample a "good" run.** Trigger a manual execution when a known ticket has just closed within the window. Confirm the digest reports the closure in past tense, with the right time, and that no closed-tickets-from-prior-window appear.
2. **Sample a "boundary" run.** Manually trigger a run 9 hours after a closure event happened. Confirm the closed ticket is **not** mentioned (it's outside the window now).
3. **Sample a "noisy" run.** Trigger a run when a closed ticket has received a fresh comment from a watcher. Confirm the digest reports the new comment (if relevant) without resurrecting the closure as current activity.
4. **Diff the LLM input.** Compare `Aggregate Emails` output before and after the change — confirm `Received:` lines are present, cutoff is correct, and Gmail `after:` is filtering out emails older than the cutoff.

If any of (1)–(3) regresses, roll back to the pre-change workflow JSON (kept in git history) and re-investigate.

## Regression test

Manual check, since no automated harness exists for n8n workflows on this stack:

- Add a checklist item to `docs/specs/archive/BUG-JIRA-001-*.md` (this spec, post-completion): "Each week, eyeball the morning digest for any ticket reported as in-flight that's actually closed. If you see one in 30 days, reopen this bug."

## Notes

- **Why not switch to the Jira API directly?** Bigger change — needs an API token, the Jira credential isn't currently in n8n, and the email-based design has the nice property of using whatever Jira email subscriptions Anthony already has set up (no per-project config). Keep email as the source unless Phase 3 isn't enough.
- **Related:** the `bugsy-inbox-watcher.json` workflow has a similar shape (Gmail → LLM digest) and may have the same class of bug — worth a look once this one is fixed.
- **The system prompt's existing temporal guardrail is good** ("LOOK AT TIMESTAMPS"), it just has nothing to act on. Phase 1 makes the existing instruction effective rather than rewriting the prompt.

---

## Symptom B (related): RAG mirror appears to be persisting only 1 digest

When asked about Jira digests in Slack, Bugsy can only recall **one** digest's content — never multiple. The RAG mirror branch (`Build RAG Payload` + `POST to RAG Ingest`) was added to this workflow expressly so every digest gets persisted in Qdrant under category `jira-digests`. If retrieval is consistently surfacing only one, either the mirror isn't running on each fire, or the mirror runs but retrieval can't find the older digests.

### Expected behavior

After each cron fire (8am + 4pm CT M-F), Qdrant should contain one additional set of `jira-digests` chunks keyed by a fresh `jira/<ISO>.md` filename. Asking Bugsy "what's been happening in Jira this week" should pull chunks from multiple distinct digests and synthesize across them.

### Context: this hasn't been verified end-to-end yet

The mirror change shipped in this session (2026-05-17, a Sunday). The Jira digest cron is M-F only, so **no automated digest run has fired since the change**. Anything in Qdrant under `jira-digests` is from at most a manual trigger. If only one manual test was run, "only 1 digest in RAG" is the expected state, not a bug — verification needs to wait for at least two automated runs (Monday 8am + 4pm CT) before declaring failure.

That said, several real failure modes are plausible and worth ranking now so we know what to check on Monday afternoon.

### Diagnostic outcomes (resolved)

**1. ✅ Confirm what's actually in Qdrant — DONE.** Operator confirmed multiple digests are landing in Qdrant under `category: jira-digests`. Ingest works.

**2. ✅ Workflow imported + activated — DONE.** Operator initially forgot to publish after import (root cause of the first reading of this symptom). After publishing, ingest started firing on the cron schedule.

**3. ✅ POST node firing successfully — DONE.** Implied by step 1: digests wouldn't be in Qdrant otherwise.

**4. ❌ Retrieval surfaces only one digest — CONFIRMED LIVE BUG.** Field evidence captured 2026-05-17: operator asked Bugsy about all of May's Jira digests; Bugsy returned content from exactly one digest (the May 14 one the operator had previously pasted directly into chat) and explicitly stated "I don't have a rolling archive of every single digest that's gone out" / "we'd need a way to pull from that Qdrant store, which I don't currently have set up."

The `Sources:` line on that response listed: `Bugsy Jira Digest, Marketing Content Calendar: Sharing Dependable Transformation Stories, Content strategy, post-audit (editorial direction and authority), SEO audit, 2026 Q3 (early pull), Content disposition, 2026-Q2 cycle, Editorial calendar, 2026 H2`. Exactly one Jira digest title; five categorically-unrelated content/SEO chunks. The other in-Qdrant Jira digests were outranked at retrieval time.

### Root cause (confirmed)

The retrieval bug has two coupled components:

**RC-B1: No category-aware retrieval in `bugsy.json`'s `Search Qdrant` node** (~line 250):

```json
{ "vector": "<embedded question>", "limit": 15, "with_payload": true }
```

No `filter`. All categories (`bio`, `articles`, `case-studies`, `projects`, `jira-digests`) compete for the same top 15 slots. For a query like "Jira digests in May," the embedded question doesn't strongly match any single Jira chunk's vector (digests are short, ticket-ID-heavy, and embed poorly compared to long narrative content), so most slots get filled by the bigger / more semantically-rich content chunks.

**RC-B2: The LLM prompt biases interpretation toward "info about the boss" and pre-commits to admit-when-limited.** From `bugsy.json`'s AI Agent system message:

> The USER MESSAGE you receive will be wrapped with structured sections:
> - KNOWLEDGE BASE: **pre-retrieved info about the boss**. Use it when the question is about them. If the section says '(none)', proceed without it.
>
> [...]
>
> - If asked to do something you can't actually do (send email, query inbox, run code, etc.): say so plainly. Example: 'Can't reach into your inbox just yet, boss. We'll get there.'
> - NEVER fake capability. Don't claim to have done something you didn't.

This is *correct behavior given a flawed retrieval*: Bugsy saw one Jira digest in the KB, framed the KB as personal-bio scoped, and followed the anti-fake-capability rule to admit "I don't have a Jira archive set up." The hallucinated framing ("we'd need a way to pull from that Qdrant store, which I don't currently have set up") is a *consequence* of RC-B1, not an independent prompt bug — but the prompt phrasing makes the failure mode more confident-sounding than it needs to be.

### Fix (graduated to its own spec)

**Implementation tracked in [BUG-AGENT-001](BUG-AGENT-001-bugsy-retrieves-only-one-jira-digest.md)** (2026-05-17). The fix lives entirely in `agent/n8n/workflows/bugsy.json`; this spec retains the diagnosis-of-record for Symptom B. The detailed sketches below are kept here for reference, but the implementation-of-record is the BUG-AGENT-001 spec — review and verification happen there.

**Fix B-1 — Category-aware retrieval (the actual bug fix):**

Replace the single Qdrant search with a parallel pair, merged before context-building:

1. **Unfiltered search** — current behavior, but with a tighter `limit` (e.g. 10) to leave room for the second branch.
2. **Category-filtered search for `jira-digests`** — runs unconditionally with `limit: 10` and:
   ```json
   {
     "vector": "<embedded question>",
     "limit": 10,
     "with_payload": true,
     "filter": { "must": [{ "key": "category", "match": { "value": "jira-digests" }}]}
   }
   ```
   This guarantees up to 10 Jira-digest chunks always make it into the context regardless of how the question scores against other categories.

Merge step: concatenate both result sets (dedupe by point ID), trim to ~20 total chunks. The `Build Context` node already groups hits into a single context block — minimal downstream change.

**Why unconditional vs intent-routed:** intent routing ("does this question mention 'jira' / 'ticket' / 'UTT-'?") is more elegant but adds a router node and a failure mode (false-negative routing → no Jira hits). For a personal stack with ~5 categories, just always pulling the top 10 from each category-of-interest is simpler and survives the case where the user asks an indirect question that should still hit Jira.

**Future enhancement:** generalize to "top N from every category, then top M overall" — would also fix the same class of bug for bio, projects, etc. Defer until B-1 ships and we see if the symptom recurs in other categories.

**Fix B-2 — Loosen the KB framing in the agent's system message:**

Replace:

> - KNOWLEDGE BASE: pre-retrieved info about the boss. Use it when the question is about them. If the section says '(none)', proceed without it.

with:

> - KNOWLEDGE BASE: pre-retrieved relevant context. May include the boss's personal info (resume, projects, writing), Jira digest history, project notes — whatever embed-matched the question. Use whatever's relevant. If the section says '(none)', proceed without it. If it has content but the question is broader than what's there (e.g. "all of May's Jira digests" but the KB only shows two), acknowledge the partial coverage rather than claiming the archive doesn't exist.

This addresses the secondary symptom (Bugsy claiming the Qdrant store isn't set up) without weakening the "don't fake capability" guardrail. The model can still admit limits — just accurate limits ("I see N digests; ask narrower") instead of categorical denial.

### Verification (Symptom B)

After Fix B-1 + B-2 ships and is imported into n8n:

1. **Direct query test.** Ask Bugsy: "Summarize every Jira digest from May 2026." The Sources line should list multiple distinct `Jira Digest <ISO>` titles (one per distinct digest run that landed in May, capped by `limit: 10` from the filtered branch).
2. **Cross-period query.** Ask: "What's been happening in Jira lately?" The response should weave content from multiple recent digests rather than one.
3. **No-regression check.** Ask: "What's my React experience?" — confirm bio/resume chunks still surface; Jira-digest pollution shouldn't make personal-content queries worse.
4. **Honest-limit framing check.** Ask: "What did Jira digests say in early April 2026?" (a period before the RAG mirror existed). Bugsy should say something like "Don't have digests that far back, boss — the archive starts May 2026" rather than "I don't have any Jira archive set up."

If step 1 returns only one digest, the per-category `limit` is still too low; bump to 20+ and re-test.
