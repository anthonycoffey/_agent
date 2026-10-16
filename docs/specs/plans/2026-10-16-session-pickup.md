---
title: "Session pickup — resuming Bugsy after the 2026-05-23 pause"
created: 2026-10-16
author: Anthony Coffey
status: living-doc
related_specs:
  - SPEC-WORKFLOW-001 (draft, unstarted)
  - SPEC-LEADS-001 (draft, unstarted)
  - BUG-AGENT-002 (resolved 2026-05-21)
---

# Session pickup — resuming Bugsy after the 2026-05-23 pause

**Purpose**: the project went quiet after `f521868` on **2026-05-23**. That is a
**~5 month gap**. This doc reconstructs where work actually stopped (which is
*not* where the last roadmap said it would stop), what's stale, and what the
honest next move is. Read this instead of re-deriving it from `git log`.

Companion doc: [`2026-05-19-post-mcp-roadmap.md`](2026-05-19-post-mcp-roadmap.md) —
still the authoritative plan for the two active specs. This doc supersedes its
"suggested next-session order of operations," because work after 2026-05-19 went
in a different direction than that roadmap predicted.

---

## TL;DR

- The **MCP fleet is done and verified** (Atlassian, GitHub, Notion). That chapter is closed.
- After closing it, you did **not** start the two specs the roadmap queued up. You instead
  fixed a real agent bug (BUG-AGENT-002) and then started a **brand-new, unspecced thread:
  an Aider-based autonomous coding agent container.**
- **The Aider thread is where you actually stopped — and it is half-built.** The container
  and runner scripts are committed and debugged; the n8n workflow that's supposed to drive
  them does not exist. Nothing about it is documented anywhere.
- Two implementation-ready specs (`SPEC-WORKFLOW-001`, `SPEC-LEADS-001`) are still sitting
  at **draft, 0% started**, with open questions waiting on you.
- Several docs have drifted, including a **broken link in `CLAUDE.md`** that claims cancelled
  work is "In Progress."
- **Unknown and worth checking first:** whether the VM is still running, whether the crons
  have been firing into Slack for 5 months, and whether any API tokens have expired.

---

## What happened after the 2026-05-19 roadmap

The roadmap said: do the leads-hunter quick win, then resolve open questions and build the
secretary email digest. That's not what happened. The actual commit sequence:

| Date | Commit | What it was |
|---|---|---|
| 2026-05-21 | `4fa19c3` | **BUG-AGENT-002 fix** — RAG context moved out of `chatInput` into the AI Agent's `systemMessage`; chat memory now stores only the raw question; `maxIterations` 10 → 30. Verified, spec archived. |
| 2026-05-22 | `88812b1` | **New thread: Aider coding-agent container.** Added `agent/aider/entrypoint.sh`, `agent/aider/run-agent.sh`, an `aider` service + `aider-workspace` volume in compose, and `GITHUB_TOKEN_AIDER` in `env.template`. |
| 2026-05-22 | `493bd68` | Aider fix — use `${HOME}` in entrypoint for non-root container user. |
| 2026-05-22 | `100d068` | Aider fix — run container as `root` so it can write to the Docker volume. |
| 2026-05-22 | `96ed33d` | README tweak (one line removed). |
| 2026-05-22 | `c61a1fc` | `gemini-3.1-flash-lite` added to LiteLLM config + the CLAUDE.md model table. |
| 2026-05-23 | `f521868` | **Last commit.** Roadmap section deleted from the README. Pushed to `origin/main` but never fetched into this clone, so it only surfaced on the first push attempt of this session. |

Two of the three Aider commits are *fixes to the first one* — that's the signature of
hands-on debugging against the live container. You were in the middle of getting it to run.

Repo shape note: **everything is linear on `main`.** No branches, no open PRs, no GitHub
issues. There is no in-flight work hiding anywhere but the working tree (which is clean).

---

## The Aider thread — what exists vs. what's missing

This is the real pickup point. The intent is legible from the script headers.

**Intended end state** (from `agent/aider/run-agent.sh`): a GitHub issue triggers an n8n
workflow → n8n's SSH node runs `docker exec -d agent-aider /agent/run-agent.sh --repo-name=…
--issue-number=… --issue-title=… --issue-body=…` → the script cuts a branch
(`agent/issue-<N>-<epoch>`), runs Aider against `claude-sonnet-4-6` through LiteLLM, pushes,
opens a **draft** PR, and comments the PR link back on the issue. Logs land at
`/tmp/aider-issue-<N>.log` inside the container.

### Built and committed

- `aider` service in `agent/docker-compose.yml`: `paulgauthier/aider:latest`, `user: root`,
  parked with `tail -f /dev/null`, entrypoint + runner bind-mounted read-only with
  `create_host_path: false`, `aider-workspace` named volume at `/workspace`,
  `OPENAI_API_BASE` → `http://litellm:4000/v1`, `depends_on: [litellm]`.
- `agent/aider/entrypoint.sh` — sets git identity (`Bugsy <bugsy@coffey.codes>`), writes
  `~/.git-credentials` from `GITHUB_TOKEN_AIDER`, writes `~/.aider.conf.yml`
  (`auto-commits: true`), then parks.
- `agent/aider/run-agent.sh` — the full branch → aider → push → draft PR → issue comment flow.
- `GITHUB_TOKEN_AIDER` documented in `agent/env.template` (deliberately separate from the
  read-only `GITHUB_TOKEN_MCP`).

### Missing

- **No n8n workflow.** Nothing in `agent/n8n/workflows/` references aider. The trigger side
  of the design — the GitHub issue webhook or poller, the SSH node, the arg marshalling — does
  not exist yet.
- **No repos cloned into `/workspace`.** `run-agent.sh` hard-fails if `/workspace/<repo>/.git`
  is absent, and tells you to clone manually. Unknown whether that was ever done on the VM.
- **No spec.** There is no `SPEC-*` for this. The design lives only in shell comments.
- **No documentation at all.** `aider` appears nowhere in `CLAUDE.md`, `docs/`, or `README.md` —
  not in the container table, not in `docs/reference/env-vars.md`, not as a `docs/workflows/` page.
  This is the single biggest violation of the project's own documentation-discipline rule.
- **Never verified end-to-end.** No commit claims a successful agent run, and the
  verify-before-commit convention means a working run would have said so.

### Open questions this thread never answered

1. What triggers it — a GitHub webhook into n8n, a poller on labelled issues, or a Slack
   command to Bugsy ("skip, take a crack at issue 42")?
2. Which repos are in scope? `run-agent.sh` defaults `--repo-owner=anthonycoffey`; the
   workspace clone step is manual, so scope is whatever got cloned.
3. Is there an approval gate? Right now a trigger goes straight to a pushed branch and a draft
   PR with no human in the loop before the push. That cuts against the README's own design
   principle — *"human in the loop for anything that sends"* — and when the README still carried
   a roadmap, autonomous code changes sat in its furthest-out "Beyond" bucket, scoped to
   low-risk edits like deps, docs and typos. This thread jumped the queue.
4. Cost / blast-radius ceiling — nothing caps how long Aider runs or how much it spends per issue.
5. `GITHUB_TOKEN_AIDER` is a write-scoped PAT. Was it ever actually minted and put in `.env`?

---

## State of the two active specs — both still at zero

Neither was touched after being drafted on 2026-05-19. Both are implementation-ready
*except* for operator decisions.

### SPEC-WORKFLOW-001 — Secretary email digest

[`../active/SPEC-WORKFLOW-001-secretary-email-digest.md`](../active/SPEC-WORKFLOW-001-secretary-email-digest.md)

Replaces `bugsy-jira-digest.json` + `bugsy-inbox-watcher.json` with two broader digests
(`bugsy-work-email-digest.json` on `0 8,16 * * 1-5`, `bugsy-personal-email-digest.json` on
`0 7 * * *`), and turns each action item into a Notion kanban card. Both old workflow files
**still exist on disk** — nothing was deleted, so the spec is 0% applied.

Four open questions, all small, all yours:

1. Which Notion database hosts the action-item cards? (Spec leans Option A — your existing
   Project Board — based on your "I'd rather not open one more thing" comment.)
2. Default Status property value for new cards?
3. Confirm 7am CT daily for the personal inbox?
4. RAG mirror in v1 or v2?

### SPEC-LEADS-001 — Leads hunter rework

[`../active/SPEC-LEADS-001-leads-hunter-rework.md`](../active/SPEC-LEADS-001-leads-hunter-rework.md)

Three phases: (1) kill Slack link unfurls + tighten the digest format — ~10 minutes,
independently shippable; (2) lift scoring to the job-board fetcher's batched-LLM-rubric depth
and add **agency bias**; (3) optional GitHub-MCP "recent engineering activity" signal.

**Phase 1 was explicitly flagged as the quick win to ship first — and it never shipped.** If
the VM has been running this whole time, `#mulberry-street` has been collecting the unfurl
noise you complained about every weekday morning since May.

Four open questions: score scale (1–10 vs 0–100), threshold value (75?), what counts as an
"agency," and whether below-threshold leads still get inserted to `agent.leads`.

---

## Documentation drift found during this audit — fixed 2026-10-16

The DDD discipline held up well through the MCP work. It slipped on the Aider thread and on a
pile of stale pointers. **All of the below was corrected in the same commit as this doc**; the
list is kept as the record of what was wrong, since a few items are worth not re-introducing.

| # | Drift | Fix applied |
|---|---|---|
| 1 | **Broken link + false "In Progress" claim.** CLAUDE.md's *Current State & Next Steps* listed "SPEC-MCP-001 Phase 1.4" as next-up and linked `docs/specs/active/SPEC-MCP-001-…md` — a file that doesn't exist, for a phase **cancelled** on 2026-05-19. | *Next Up* rewritten around the three things actually open (Aider, the two draft specs), with Phase 1.4 moved to an explicit **Cancelled** note. Link repointed at `archive/`. |
| 2 | **Aider was completely undocumented.** Container, scripts, and `GITHUB_TOKEN_AIDER` committed; nothing in CLAUDE.md's container table, `docs/reference/env-vars.md`, or `docs/` mentioned them. | Container rows added to CLAUDE.md + `docs/architecture/overview.md`; new **Aider coding-agent runner** section in the overview (design, the two manual setup steps, what's missing); `GITHUB_TOKEN_AIDER` + the LiteLLM-key reuse documented in `env-vars.md`; `agent/aider/` added to the repo tree. |
| 3 | **`evolution-api` + `evolution-data` still in compose** after `bugsy-whatsapp.json` was retired, and absent from the container table. | Kept but documented as **parked** in CLAUDE.md, the overview, `env-vars.md`, and a compose comment, with the removal procedure (service + volume + `EVOLUTION_*` together) written down. Rationale logged in `logs/decisions-log.md`. |
| 4 | **README was the most stale file in the repo.** Stack list stopped at Open WebUI; repo-layout tree showed a `docs/` shape that no longer exists; linked `docs/decisions.md` and `docs/incident-log.md` after they moved to `logs/`. | Stack and repo-layout sections rewritten against the real tree; log links repointed. The stale six-phase roadmap was **not** reworked: the operator had already deleted that section outright in `f521868` (2026-05-23, a commit this clone had never fetched), and that deletion stands. |
| 5 | **`docs/SUMMARY.md` archive list was missing BUG-AGENT-002.** | Row added (plus a row for this doc under Plans). |
| 6 | **`agent/motd` still said "Next up: MCP server fleet — see SPEC-MCP-001."** | Rewritten to name the two draft specs, the half-built Aider thread, and this pickup doc. Needs `sudo cp ~/bugsy/agent/motd /etc/motd` on the VM to take effect. |

Found while fixing those, and also corrected:

| # | Drift | Fix applied |
|---|---|---|
| 7 | **`docs/workflows/bugsy-unified.md` documented the pre-BUG-AGENT-002 architecture** and asserted the opposite of what's now true: that `Build Context` bakes RAG into `chatInput`, and that this is "the bulletproof path because the langchain agent's `systemMessage` field doesn't reliably evaluate expressions." Commit `4fa19c3` changed the JSON but never touched this page. | Narrative rewritten; node-reference blocks regenerated from the JSON with `node agent/n8n/scripts/generate-workflow-reference.mjs`. The architectural decision — and the fact that it *reverses* an earlier documented call — is now a row in `logs/decisions-log.md`, which had no entry newer than May 8. |
| 8 | **12 more broken relative links across `docs/`, `README.md`, and `logs/incident-log.md`** — mostly specs that moved `active/` → `archive/` (SPEC-MCP-001, SPEC-RAG-001, BUG-JIRA-001, BUG-AGENT-001), plus a `bugsy-rag-ingest.md` page that is really `rag-ingest.md`, a truncated `BUG-AGENT-001-...` placeholder, `docs/decisions.md` → `logs/decisions-log.md`, and an asset path that resolved to `docs/assets/assets/`. | All repointed. A link sweep now reports zero broken relative links across every tracked `.md`. |
| 9 | **Dead references inside non-markdown files**, which no markdown link check would catch: the `aider` compose comment pointed at `docs/workflows/github-agent-pipeline.md` (never written), and `agent/env.template` pointed at the pre-archive SPEC-MCP-001 path. | Both repointed; the compose comment now carries the half-built warning too. |
| 10 | **CLAUDE.md's repo tree was wrong in three places** — it put the reference generator under `agent/n8n/workflows/scripts/` (it's `agent/n8n/scripts/`) and omitted `agent/backup.sh` and `agent/context/`. | Corrected. |
| 11 | **`docs/README.md` — the DDD entry point — had never actually been published.** mkdocs drops a `README.md` when an `index.md` exists in the same folder, so the page `mkdocs.yml` listed under *DDD → Overview* was silently excluded from every build. | Renamed to `docs/ddd.md` (it is a DDD overview, not a folder readme) and repointed from `mkdocs.yml`, `docs/SUMMARY.md`, and CLAUDE.md's repo tree. The page now renders on the site. |
| 12 | **16 links from `docs/` into repo source** (`../../CLAUDE.md`, `../../agent/docker-compose.yml`, workflow JSON, `rag-refresh.sh`, the logs) resolved on GitHub but were dead on the generated site — the docs site being the intended reading surface. | Rewritten as absolute `github.com/anthonycoffey/_agent/blob/main/...` URLs, which work from both surfaces. With that and the renames, **`mkdocs build --strict` now passes** (it aborted with 24 warnings before this pass), so it's usable as a gate from here on. |
| 13 | **The `active` flag in exported workflow JSON is not trustworthy, and the docs presented it as fact.** `bugsy.json` says `active: false` while being the live Slack assistant; `bugsy-inbox-watcher.json` says `active: true` while switched off. The generator faithfully renders the wrong value into every workflow page's `**Active:**` line. CLAUDE.md also pointed readers at an "Active column" that doesn't exist in its table. | Gotcha documented in CLAUDE.md above the workflow table — the n8n UI is the only authority. Generated blocks left alone deliberately; hand-editing them would just be overwritten on the next run. |

Not drift, just worth knowing: `mkdocs.yml` nav and `docs/workflows/` still carry
`bugsy-inbox-watcher` and `bugsy-jira-digest` pages — correct for now, since those workflows
still exist. They get deleted as part of SPEC-WORKFLOW-001.

---

## Unknowns that need checking on the VM before planning anything

Five months is long enough that the running system may not match the repo. None of this is
knowable from the checkout:

- [ ] **Is `agent-vm` still up?** (GCP billing has been accruing either way if it is.)
- [ ] **Are the crons still firing?** Job board 5:30am, leads hunter 6:00am, jira digest
      8am/4pm, rag-refresh 4am. If so, `job_listings` has ~5 months of rows and
      `#mulberry-street` has a long backlog.
- [ ] **Have any tokens expired?** `ATLASSIAN_API_TOKEN`, the Notion/GitHub MCP bearers,
      Slack and Gmail OAuth creds. Expired Atlassian auth is a known failure mode (see the
      Bugsy agent brief).
- [ ] **Did the Aider container ever come up clean, and is anything in `/workspace`?**
- [ ] **Does the n8n runtime still match the repo JSON?** n8n keeps its own copy in Postgres;
      the repo is only a mirror. Specifically: does the running `bugsy.json` have the
      BUG-AGENT-002 fix (`maxIterations: 30`, RAG in `systemMessage`) imported, or just
      committed?
- [ ] **Container image drift.** Most services pin `:latest`. A `docker compose pull` after
      5 months will move n8n, Aider, and the MCP servers several versions — expect breakage,
      and do it deliberately rather than as a side effect.

---

## Recommended order of operations

Deliberately ordered cheapest-and-most-informative first.

1. ~~**Fix the doc drift.**~~ Done 2026-10-16 — all 13 items above, same commit as this doc.
2. **Recon the VM** (30 min, no code). Walk the checklist above. Everything below depends on
   knowing whether you're resuming a running system or restarting a cold one.
3. **Ship SPEC-LEADS-001 Phase 1** (~10 min + a verification run). The quick win that got
   skipped. Immediate daily-quality payoff, zero open questions blocking it.
4. **Pick ONE of the two real threads.** They're genuinely different bets:
   - **SPEC-WORKFLOW-001 (secretary digest)** — the planned path. Answer 4 small questions and
     build. Highest daily-utility-per-hour; replaces a workflow that's now redundant; well-specced.
   - **Aider coding agent** — the shiny path you actually wandered onto. Needs a spec, a
     trigger design, and an approval-gate decision before more code. Bigger blast radius.
   - *Recommendation:* finish the secretary digest first, and **write the Aider spec before
     touching its code again** — the half-built state is exactly the thing specs exist to
     prevent. Apply the README's own test to Aider: *"Will you actually use it in two weeks,
     or is it shiny?"*
5. **SPEC-LEADS-001 Phase 2** (scoring rework + agency bias) once a digest thread lands.
6. **Revisit the deferred list** from the May roadmap: `/research` → auto-Notion page,
   job-board fit → Notion kanban, daily GitHub commit digest, GSC bundle MCP (was Phase 1.4).

---

## Orientation reads, in order

1. `CLAUDE.md` — current-state context (last meaningfully updated 2026-05-19; note drift item 1).
2. [`2026-05-19-post-mcp-roadmap.md`](2026-05-19-post-mcp-roadmap.md) — why the MCP chapter
   closed the way it did, plus the "what's redundant now" audit.
3. [`docs/documentation/agents/bugsy.md`](../../documentation/agents/bugsy.md) — the agent
   brief. Best single orientation read: interfaces, state, failure modes, gotchas.
4. The two active specs — both are self-contained and assume no conversation history.
5. `agent/aider/run-agent.sh` — the only existing description of the Aider design.

## Notes

- The DDD setup did its job: five months later, the MCP work and both draft specs are fully
  reconstructable from `docs/` with no reliance on chat history. The one piece that *isn't*
  reconstructable from docs — the Aider thread — is precisely the one that skipped the spec step.
- Nothing is lost or broken in the repo. The working tree is clean, `main` is pushed, no
  dangling branches. The risk here is entirely about the gap between the repo and the
  five-months-running VM.
