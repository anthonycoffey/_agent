---
id: BUG-AGENT-001
title: "Bugsy retrieves only one Jira digest when asked about archived history"
status: complete
severity: P2
created: 2026-05-17
completed: 2026-05-17
author: Anthony Coffey
reviewers: []
affected_repos: [_agent]
parent_spec: BUG-JIRA-001
---

<!--
Forked from BUG-JIRA-001 Symptom B during implementation phase. BUG-JIRA-001
remains the diagnosis-of-record; this spec is implementation-of-record for
the bugsy.json fix.

2026-05-17 — Fix B-1 (two-stage retrieval with category-filtered jira-digests
search) + Fix B-2 (loosened KB framing in Build Context and AI Agent system
message) shipped. Implementation hit an n8n parser quirk: jsonBody templates
greedily match the first }} as end-of-template, so nested object literals
needed every consecutive }} space-separated. Documented in the spec's
"Gotcha discovered during implementation" section and saved as a project
memory.

Operator verified: a Slack query for May digests now surfaces 6 distinct
Jira Digest <ISO> titles in the Sources line, weaves content across them,
and uses natural partial-coverage framing ("RAG is actually pulling some
digests this time") instead of the prior categorical "no archive set up"
hallucination. SEO/marketing chunks still surface for non-Jira queries —
no regression on other categories.

Spec marked complete and moved to specs/archive/.
-->

## Reviewer Notes

<!-- Leave empty until code review. Reviewer adds feedback here when requesting changes. -->

---

# Bug: Bugsy retrieves only one Jira digest when asked about archived history

## Symptom

When asked about Jira digest history (e.g. "summarize every Jira digest from May 2026"), Bugsy returns content from exactly one digest — typically the one the operator has pasted into chat most recently — and then hallucinates that no archive exists ("we'd need a way to pull from that Qdrant store, which I don't currently have set up"). The Sources line on one captured failure showed `Bugsy Jira Digest` once alongside five categorically-unrelated content/SEO chunks (marketing calendar, SEO audit, content strategy, etc.).

The Jira digest RAG-mirror is working — multiple digests exist in Qdrant under `category: jira-digests`. The bug is on the retrieval side.

## Expected behavior

When asked about Jira digests:
- The Sources line should list multiple distinct `Jira Digest <ISO>` titles.
- The response body should weave content from several recent digests, not just one.
- If the archive is genuinely partial (e.g. asking about a time period before the mirror existed), Bugsy should acknowledge the actual scope of what it has ("archive starts May 14, 2026, boss") rather than claiming no archive exists.

When asked about non-Jira topics (bio queries, project history, etc.), retrieval quality should not regress — Jira chunks shouldn't crowd out personal-content chunks.

## Reproduction

1. Confirm ≥ 2 distinct Jira digests exist in Qdrant:
   ```bash
   curl -s -X POST http://localhost:6333/collections/personal_knowledge/points/scroll \
     -H 'content-type: application/json' \
     -d '{"filter":{"must":[{"key":"category","match":{"value":"jira-digests"}}]},"limit":200,"with_payload":true}' \
     | jq -r '.result.points[].payload.title' | sort -u | wc -l
   ```
2. In Slack, ask Bugsy: "What were all the Jira digests in May 2026?"
3. Observe: Sources line shows one `Jira Digest <ISO>` title; body contains only that one digest's content; closing line claims no archive access.

**Frequency:** consistent across multiple sessions / sessions / weeks. Reproducible 2026-05-17.
**Environment:** prod — `agent-vm`, n8n container, Qdrant 1.x, claude-sonnet-4-6 via LiteLLM.

## Root cause

Two coupled components in `agent/n8n/workflows/bugsy.json`:

### RC-1: No category-aware retrieval in the `Search Qdrant` node (~line 250)

Current query:

```json
{ "vector": "<embedded question>", "limit": 15, "with_payload": true }
```

No filter. All categories (`bio`, `articles`, `case-studies`, `projects`, `jira-digests`) compete for 15 slots. Jira-digest chunks lose because:

- Each digest is short (1–3 KB) → ~3–8 chunks per digest, vs. 50+ chunks for long-form content like SEO audits or content strategy decks.
- Digest text is dominated by ticket IDs and status verbs, which embed less richly than narrative content.
- Across a month of digests there are ~150–300 total Jira chunks competing against ~thousands of chunks in other categories.

Net effect: most queries about Jira pull at most one digest chunk, even when the user's question is unambiguously about Jira.

### RC-2: KB framing in the AI Agent system message

The agent's system message says:

> The USER MESSAGE you receive will be wrapped with structured sections:
> - KNOWLEDGE BASE: **pre-retrieved info about the boss**. Use it when the question is about them.

…and elsewhere:

> - If asked to do something you can't actually do (send email, query inbox, run code, etc.): say so plainly.
> - NEVER fake capability.

So when Bugsy gets a single Jira digest in context but is asked about an archive, it correctly applies the "don't fake capability" rule and admits limits — but the KB-is-personal-info framing makes the admission categorical ("no archive set up") instead of accurate ("the retrieval surfaced one digest"). This is a *consequence* of RC-1, but the prompt phrasing makes the failure mode louder than it needs to be.

The same flawed framing also lives in the `Build Context` node, which prepends `=== KNOWLEDGE BASE — boss's personal info pulled fresh for this question ===` to the augmented input. Both surfaces need the fix.

## Fix

### Fix B-1 — Add category-filtered parallel search (`bugsy.json`)

Splice a new HTTP Request node `Search Qdrant — Jira Digests` between `Search Qdrant` and `Build Context`. It runs the same embedding against Qdrant but with a category filter:

```json
{
  "vector": "<embedded question>",
  "limit": 10,
  "with_payload": true,
  "filter": { "must": [{ "key": "category", "match": { "value": "jira-digests" }}]}
}
```

Wiring is sequential (not parallel-with-merge) for simplicity — adds ~50ms latency, which is invisible against the multi-second LLM call downstream:

```
Embed Question → Search Qdrant (limit 10, unfiltered)
              → Search Qdrant — Jira Digests (limit 10, filtered)
              → Build Context
```

`Build Context` updates to pull from both upstream nodes by name (`$('Search Qdrant').first()` + `$('Search Qdrant — Jira Digests').first()`), dedupe by point ID (keeping the higher-scoring hit on collision), and sort by score before building the context block.

The existing `Search Qdrant` limit drops from 15 → 10 to leave token budget for the filtered branch. Combined max is ~20 chunks (~8 KB of context), well within Sonnet's window.

### Fix B-2 — Loosen KB framing in two places

**In `Build Context`'s augmented input header**, replace:

```
=== KNOWLEDGE BASE — boss's personal info pulled fresh for this question ===
When the question relates to the boss (skills, background, projects, history, preferences), USE the content below directly.
```

with:

```
=== KNOWLEDGE BASE — pre-retrieved relevant context ===
May include the boss's personal info (resume, projects, writing), Jira digest history, or other indexed material — whatever embed-matched. USE the relevant parts directly. Cite specifics (digest dates, ticket IDs, project names). If the question seems broader than the content shown, acknowledge partial coverage — never claim the archive doesn't exist when there's content here.
```

**In the AI Agent `systemMessage`**, replace:

```
- KNOWLEDGE BASE: pre-retrieved info about the boss. Use it when the question is about them.
```

with:

```
- KNOWLEDGE BASE: pre-retrieved relevant context (may include personal info, Jira digest history, project notes — whatever embed-matched the question). Use whatever's relevant. If the section has content but the question is broader than what's shown (e.g. "all of May's Jira digests" but only two appear), acknowledge partial coverage from the archive rather than claiming the archive doesn't exist.
```

This keeps the "don't fake capability" rule intact — the model can still admit limits, just accurately ("I have N digests since X; ask narrower") instead of categorically ("no archive set up").

## Verification

After file-based import + activate in n8n:

1. **Direct Jira query.** Ask Bugsy: "Summarize every Jira digest from May 2026." Sources line should list multiple distinct `Jira Digest <ISO>` titles. Response body should reference content from several digests.
2. **Cross-period query.** Ask: "What's been happening in Jira lately?" Response should weave content from multiple recent digests, not one.
3. **Honest-limit framing.** Ask: "What did Jira digests say in early April 2026?" (predates the mirror). Bugsy should respond with something like "Archive starts May 2026, boss — nothin' from April on file" — NOT "I don't have a Jira archive set up."
4. **Bio no-regression check.** Ask: "What's my React experience?" Personal-content chunks should still surface as before; Jira-digest pollution shouldn't degrade personal queries.
5. **No-Jira topic check.** Ask: "Tell me about my marketing content calendar." Marketing/SEO chunks should surface normally; the filtered Jira search runs but its 10 chunks should rank low against unrelated questions and not crowd the context.

If step 1 returns only one digest, bump the filtered `limit` from 10 to 20+ and re-test. If step 3 still claims no archive, the prompt edits didn't land — re-check the imported `Build Context` and `AI Agent` nodes.

## Regression test

Manual check (no automated harness for the chat workflow):

- Once a month, ask Bugsy "What were the Jira digests this past week?" Confirm multiple distinct digests surface. If only one appears, this bug has regressed.

## Notes

- Fix B-1 is a structural change to the chat workflow's retrieval graph. The sequential wiring (one search after the other) was chosen over parallel-with-merge because Build Context already pulls from multiple nodes by name and sequential adds negligible latency.
- A future-enhancement candidate: generalize "top N per category, top M overall" so other under-represented categories (projects, articles) also get guaranteed slots. Defer until we see if the symptom recurs for non-Jira categories.
- Per the file-based n8n import workflow established this week, the change is made locally, imported into n8n by the operator, verified via the steps above, and only THEN committed to git.

## Gotcha discovered during implementation

The n8n expression parser in `jsonBody` fields (HTTP Request node) greedily matches the first `}}` it sees as end-of-template. A JavaScript object literal expression like:

```js
={{ JSON.stringify({ filter: { must: [{ key: 'category', match: { value: 'x' }}]}}) }}
```

…will be parsed as `={{ JSON.stringify({ filter: { must: [{ key: 'category', match: { value: 'x' }}` followed by garbage, producing an `invalid syntax` error. **Fix:** space-separate every pair of consecutive closing braces so the only literal `}}` in the field is the n8n template closer at the very end:

```js
={{ JSON.stringify({ filter: { must: [ { key: 'category', match: { value: 'x' } } ] } }) }}
```

This is a parser limitation, not a JS problem. The same expression inside a Code node's `jsCode` (which is treated as a literal string, not parsed as a template) works fine without the spacing.
