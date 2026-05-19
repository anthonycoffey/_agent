---
id: SPEC-LEADS-001
title: "Leads hunter rework — formatting, scoring depth, agency bias"
status: draft
created: 2026-05-19
author: Anthony Coffey
reviewers: []
affected_repos: [_agent]
---

<!--
2026-05-19 — Drafted during the post-MCP audit (see plan
docs/specs/plans/2026-05-19-post-mcp-roadmap.md). Operator's actual words:

  "the daily lead hunter prints a bunch of link previews to #mulbery-street
   (which i hate) .. lets optimize the formatting and ensure this isnt a
   stupid workflow (how is it scoring jobs to ensure its a good fit? if
   not as good as our job board scoring system, lets enhance it.. i would
   like to see more agencys popping up in the suggestions)"

Three problems to solve in order of effort:
  1. Slack formatting — link previews are noisy, unfurls need disabling +
     output structure tightened (10 min, ship standalone)
  2. Scoring depth — current rubric is shallower than the job-board
     fetcher's LLM batch-scoring; lift to that quality bar
  3. Agency bias — the boss is a freelance dev pitching agency clients;
     scoring should favor agencies over direct-hire startups

Status: draft. Pickup from a fresh session: this spec is phased; Phase 1
is independently shippable as a quick win, Phases 2 and 3 need a brief
investigation of the current workflow before final design.
-->

## Reviewer Notes

<!-- Leave empty until code review. Reviewer adds feedback here when requesting changes. -->

---

# Feature: Leads hunter rework — formatting, scoring depth, agency bias

## Problem

`bugsy-leads-hunter.json` runs every weekday morning, posts top leads to `#mulberry-street`. Operator's feedback (2026-05-19):

1. **The Slack output is noisy.** A bunch of link previews / unfurls clutter the channel. Hard to scan; doesn't read like a curated daily brief.
2. **Scoring quality is opaque / probably weak.** The current scoring (`agent.leads.score`: 1–10 + `icp_bucket`: ICP1–ICP4) is shallower than what the job-board fetcher does (LLM batch-score against an explicit fit rubric, threshold ≥75). The operator's suspicion: leads-hunter scoring is less rigorous than job-board scoring even though leads are arguably higher-stakes.
3. **Agencies aren't surfacing enough.** Anthony's actual buyer is agencies hiring freelance devs / sub-contracting work — not direct-hire startups. The current scoring presumably weights all ICP buckets similarly; agencies should bias upward.

## Requirements

### Must have

1. WHEN the leads-hunter workflow posts to Slack, link previews SHALL be disabled (`unfurl_links: false` + `unfurl_media: false` on the Slack node, same pattern as the existing Jira digest workflow).
2. WHEN the workflow posts, the output SHALL be a single compact message — not one link-per-line with unfurls. Suggested shape: one summary line + a tight `*top N*` list with each lead as one line containing company name, score, one-line "why," and a single URL.
3. The scoring path SHALL be lifted to match (or exceed) the depth of `bugsy-job-board-fetcher.json`'s LLM-batch-scoring approach. Concretely: an explicit fit rubric in the prompt, an LLM batch call (not per-lead), a numeric score, and a one-line rationale.
4. The fit rubric SHALL include **agency type as a positive signal** with non-trivial weight. Defining what counts as "agency" is part of Phase 2 — see Design.

### Nice to have

- **GitHub MCP signal** — each candidate lead's GitHub org (if findable) gets a "recent commit activity" signal added to the score. Strong recent activity = active engineering org = more likely to need contract help. (Phase 3 optional.)
- A configurable threshold (e.g. `LEADS_SCORE_THRESHOLD=75`) parallel to the job-board's, so only leads above the bar even reach Slack.
- Per-lead deep-link to a Notion page that gets auto-created from the research output. (Cross-spec with `bugsy-research`; deferred.)

### Non-goals

- Does NOT add an outreach-drafting step. The `draft_email` column on `agent.leads` already exists; whether to populate it on every score or only on-demand is its own decision. This spec focuses on discovery + scoring quality.
- Does NOT replace SearXNG as the discovery engine. The query set may get tuned (more agency-targeting queries) but the architecture stays SearXNG-driven.
- Does NOT touch `agent.leads` table schema (the columns are sufficient). If a new column becomes necessary (e.g. `agency_signal` bool), call it out and migrate.

## Design

### Phasing — three independent slices

**Phase 1 (quick win, ship standalone): Slack formatting fix**

One-node change in `bugsy-leads-hunter.json`'s Slack post node:
- Set `otherOptions.unfurl_links: false`
- Set `otherOptions.unfurl_media: false`
- Set `otherOptions.mrkdwn: true` (probably already on)
- Tighten the message body — switch from "here's each lead with its URL on its own line (which Slack then unfurls)" to a compact `*Top 5 leads*` list with one line per lead:
  ```
  *Top 5 leads — 2026-05-19*
  1. *Acme Co* (8/10, ICP2) — recently raised Series A, fintech, ~20 eng. <https://acme.co|website>
  2. *Beta LLC* (7/10, ICP3) — content marketing agency, hiring fast. <https://...|website>
  ...
  ```

This is a ~10-minute change. Doesn't depend on Phase 2/3. Ship it standalone.

**Phase 2 (real spec): scoring rework + agency bias**

This is where the investigation happens. Steps:

1. **Read the current `bugsy-leads-hunter.json`** to document the existing scoring path — what queries it runs, how it scores, where the `score` and `icp_bucket` values come from, what prompts the LLM sees today.
2. **Compare against `bugsy-job-board-fetcher.json`** — that workflow's batched LLM scoring is the quality bar. Document the delta in the spec body (will be inserted in Phase 2 of implementation).
3. **Define an explicit fit rubric** in the system prompt. Rubric dimensions (initial proposal, refine after seeing current state):
   - **Agency type** (positive, high weight): is this organization a software / digital / marketing / creative agency that sub-contracts engineering work? Independent freelance platforms / staffing agencies count.
   - **Tech stack overlap** (positive, medium): do they work in stacks Anthony has (React, Node, TypeScript, Next.js, etc.)?
   - **Eng team size** (positive, medium): small enough that contract help is realistic; not so small they have no budget. Sweet spot ~5–50 eng.
   - **Active hiring signal** (positive, medium): recent job postings, GitHub activity, public engineering blog posts.
   - **Direct-hire-only red flag** (negative): if the org appears to ONLY hire FTE with no freelance/contract path, score down.
   - **B2B SaaS / digital product** (positive, light): companies that ship software products vs companies that just have a website.
   - **Geography fit** (positive, light): US-friendly hours, timezone overlap.
4. **Implement the score as an LLM batch call** — pass the rubric + the candidate leads to the model, get back an array of `{ domain, score: 0-100, why: string }` matching the job-board pattern.
5. **Threshold filter** — only leads scoring above the threshold (`LEADS_SCORE_THRESHOLD`, default 75) get inserted to `agent.leads` and posted to Slack.

Schema impact: `agent.leads` already has `score INT` + a `signals JSONB` column. The new rubric outputs map cleanly:
- `score`: switch from 1-10 to 0-100 (or keep 1-10 if the operator prefers; mostly cosmetic). Migration if scale changes.
- `signals`: stays as the JSONB bag for the matched-rubric flags ("agency_type", "stack_match", "recent_hiring", etc.).

**Phase 3 (optional, GitHub MCP enhancement): activity signal**

After Phase 2 ships and proves stable, optionally add a "recent engineering activity" signal that calls the github MCP. For each candidate lead with a discoverable GitHub org, pull recent commit counts / open issues — strong activity = positive signal, dormant repos = neutral (or slight negative). Mark it as a `signals.github_activity` value.

Defer this until Phase 2 is verified; the github MCP call adds latency and cost.

### Why this isn't redundant with the atlassian / notion / github MCPs

Brief audit (relevant because the parent post-MCP audit was specifically asking which workflows were redundant):

- **Atlassian MCP** — covers internal Jira state, not external company discovery. Not redundant.
- **GitHub MCP** — covers Anthony's repos, not arbitrary companies. Not redundant; Phase 3 USES it as a signal source but the workflow remains essential.
- **Notion MCP** — irrelevant to lead discovery.
- **SearXNG** — the actual discovery engine. No MCP replaces this. Not redundant.

The leads-hunter pattern (discover via SearXNG → score via LLM → store + Slack) is the right architecture. The fix is **inside** that pattern, not a replacement of it.

## Edge cases

- [ ] Phase 1 formatting fix changes the Slack message structure but doesn't change what's posted. If the operator was using the unfurled previews to spot-check leads, that's now manually-click-through. Acceptable per their stated preference.
- [ ] Phase 2: the LLM scores leads as agencies when they're actually direct-hire shops with "agency"-flavored marketing. False positives are inevitable; the operator triages.
- [ ] Phase 2: if the new threshold (e.g. ≥75) is too tight, no leads make the cut some days. Empty-day output should be a one-line "no qualifying leads today" — not a silent void.
- [ ] Phase 3: GitHub org name discovery is non-trivial (companies don't always have one, or have multiple under different naming). Tolerate misses; don't fail the workflow.

## Acceptance criteria

### Phase 1

1. `bugsy-leads-hunter.json` Slack post node has `unfurl_links: false` + `unfurl_media: false`.
2. The posted message structure is the tight one-line-per-lead format described above; no full URL unfurls in the channel.
3. Manual trigger: the next leads-hunter run produces a digest the operator likes the look of.

### Phase 2

1. The workflow's scoring is now an LLM batch call against the explicit fit rubric (matching the depth pattern of `bugsy-job-board-fetcher.json`).
2. Agency-type signal weighted in the rubric; manual trigger produces leads where agencies are visibly over-represented vs the pre-rework baseline.
3. `agent.leads.signals` JSONB now contains the matched rubric flags (e.g. `{"agency_type": true, "stack_match": true, "recent_hiring": false}`).
4. Threshold filter rejects below-cutoff leads; only top fits hit Slack.

### Phase 3 (if pursued)

1. Each lead with a discoverable GitHub org has a `signals.github_activity` value.
2. Manual trigger shows the activity signal influencing the score in expected directions.

## Constraints

- Doesn't touch SearXNG configuration — query set may be tuned in Phase 2 but the search engine stays.
- Same Slack channel (`#mulberry-street`).
- Same workflow file (`bugsy-leads-hunter.json`) — not splitting into a new workflow.
- Per the project's verify-before-commit rule: each phase ships as its own commit after a manual-trigger verifies it works.

## Tasks

### Phase 1 — Slack formatting (quick win, single commit)

- [ ] Open `agent/n8n/workflows/bugsy-leads-hunter.json` and find the Slack post node.
- [ ] Set `otherOptions.unfurl_links: false`, `otherOptions.unfurl_media: false`, `otherOptions.mrkdwn: true`.
- [ ] Rewrite the message-text expression to produce a compact `*Top N — date*` list with `1. *Company* (score/10, ICP) — one-line why. <URL|website>` per lead.
- [ ] Test: manual-trigger the workflow, eyeball Slack output.
- [ ] Commit + push.

### Phase 2 — Scoring rework

- [ ] Read `bugsy-leads-hunter.json` and `bugsy-job-board-fetcher.json` side-by-side. Document the current scoring path + the delta in this spec's Notes section.
- [ ] Draft the explicit fit rubric (refining the proposal in Design). Validate with operator.
- [ ] Re-implement the scoring node as an LLM batch call (claude-haiku-4-5 via LiteLLM, matching the job-board pattern).
- [ ] Add the `LEADS_SCORE_THRESHOLD` env var (default 75) and a filter step.
- [ ] Update `agent.leads.signals` JSONB writes to include the matched rubric flags.
- [ ] Manual-trigger; eyeball that agencies surface more frequently and that low-fit leads no longer make Slack.
- [ ] Commit.

### Phase 3 — GitHub MCP signal (optional)

- [ ] Add a per-lead "discover GitHub org" step (heuristic: try `github.com/<slugified-company-name>`, or use the website to find a `Source on GitHub` link).
- [ ] If found, call the github MCP for the org's recent commit activity.
- [ ] Fold into the scoring rubric as a `signals.github_activity` value.
- [ ] Manual-trigger; verify the new signal influences expected leads.
- [ ] Commit.

## Open questions for the operator

1. **Score scale.** Keep 1-10 for consistency with the existing `agent.leads.score` column? Or move to 0-100 to match the job-board pattern? (If moving, a small migration is needed.)
2. **Threshold value.** Default proposal: 75/100 (matching job-board). Adjust based on early Phase 2 results.
3. **"Agency" definition.** Should the rubric distinguish between software agencies (build apps for clients) vs marketing/creative agencies (need a developer occasionally) vs staffing/recruitment agencies (place contractors)? Different fit profiles. Operator's preference.
4. **Threshold-rejected leads — still record them?** Insert below-threshold leads to `agent.leads` with their score (just don't Slack-post)? Or filter them out before insert? Insert lets you see what's getting filtered later.

## Notes

- Phase 1 is independently shippable and immediately improves the daily Slack experience. Don't gate it on Phase 2.
- Phase 2's investigation step is the load-bearing piece — without reading the current workflow, the spec can't lock down "what's actually being lifted from where." That work happens IN the implementation session, not in the spec.
- The job-board fetcher's scoring is the quality bar to match because the operator explicitly named it (*"how is it scoring jobs to ensure its a good fit? if not as good as our job board scoring system, lets enhance it"*). Lift the pattern; adjust the rubric.
