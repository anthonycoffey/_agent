# Job board

Two workflows that work together to surface remote dev jobs the boss is actually
qualified for. The fetcher applies an **LLM fit score** before anything hits the
table — so the board only shows jobs Anthony is highly likely to interview for.

## Fetcher

`agent/n8n/workflows/bugsy-job-board-fetcher.json` — daily cron, 5:30am CT M-F.

The fetcher pipeline:

1. **Fetch All Sources** — pull 20+ job boards (5 JSON APIs + 16 RSS feeds) concurrently via axios.
2. **Normalize + Filter** — parse each source's shape, dedupe by URL within the batch, filter to listings that mention Anthony's stack.
3. **Get Existing URLs** — Postgres `SELECT array_agg(url) FROM job_listings`. Anything already stored skips the LLM step (saves tokens, prevents re-scoring on schedule jitter).
4. **Filter to New Jobs** — split the deduped batch into N items, one per genuinely-new URL.
5. **Build Score Request** — per item, build a LiteLLM chat-completions payload. The system prompt is the source of truth for fit criteria — see [Scoring profile](#scoring-profile) below.
6. **Score Job** — HTTP POST to `http://litellm:4000/v1/chat/completions` (model: `claude-haiku-4-5`, temp 0.1, max 100 tokens, 30s timeout). One call per job. `onError: continueRegularOutput` so a flaky LLM doesn't crash the run.
7. **Parse Score** — strict JSON parse of `{score, reason}`. Anything that fails to parse defaults to `score=0, reason="parse error: ..."` and gets dropped at the threshold step.
8. **Aggregate Scored** — collect all scored items, apply the threshold (default 75), produce stats. `alwaysOutputData=true` keeps the chain alive on a 0-new-jobs day.
9. **Prepare Insert SQL** — only kept jobs (≥ threshold) get INSERT rows, with `match_score`, `match_reason`, `scored_at` populated.
10. **Upsert to Postgres** — `INSERT ... ON CONFLICT (url) DO NOTHING`.
11. **Format Slack Summary** — `N new jobs cleared the 75 fit score (out of M scored, K dropped)`, plus the top 3 picks by score.
12. **Send to Mulberry Street** — Slack channel `C0AV83XUSTU`.

### Scoring profile

The fit criteria live in the **Build Score Request** Code node's system prompt — that's
the canonical place to update the profile. Right now it scores against:

- **Profile (high score):** React, Next.js, Node, TypeScript, React Native, Flutter, Python/FastAPI, GCP/Firebase, Docker, AI/ML integration (LLM apps, RAG, agent workflows). Bonus for healthtech / fintech.
- **Anti-profile (low score):** Java/Spring Boot, C#/.NET, Salesforce/SAP/Oracle, pure data engineering, ML research roles, embedded/firmware, deep K8s SRE, financial analyst, pure design, game dev, EM/director roles.

The model returns `{"score": 0-100, "reason": "<one short sentence>"}`. The threshold
constant is in the **Aggregate Scored** node (`const THRESHOLD = 75`). Tune it after a
few runs feel right.

### Tuning the threshold

To raise/lower the bar, edit `THRESHOLD` in the **Aggregate Scored** Code node and
re-import. Existing rows in the table are **not** re-scored — old jobs keep whatever
score they got at fetch time. If you change the rubric significantly, consider a
one-shot backfill (re-run the score request against rows where `scored_at` is older
than the rubric change).

## UI

`agent/n8n/workflows/bugsy-job-board-ui.json` — webhook GET `/job-board`. Queries
Postgres ordered by `match_score DESC` and renders a dark-mode HTML board. Live at:

```
https://n8n.coffey.codes/webhook/job-board
```

Header controls:

- Search (title / company / tag / reason)
- Source dropdown
- Status dropdown (new / reviewed / dismissed — localStorage-backed)
- **Min score slider** (default 75) — drag to 0 to see everything, including pre-scoring rows
- Sort: best fit first (default) / newest first / company / source

Each row leads with a colored score badge (green ≥90, blue ≥75, amber ≥50, red <50,
grey for null). Hover the badge for the full LLM rationale; the rationale also appears
inline under the title.

## Schema (`job_listings` table)

| Column | Type | Notes |
|---|---|---|
| `id` | SERIAL PK | |
| `source` | TEXT | Board name (e.g. `remotive`, `wwr-frontend`) |
| `title` | TEXT | |
| `company` | TEXT | |
| `url` | TEXT UNIQUE | Dedup key |
| `location` | TEXT | Always `'Remote'` currently |
| `salary_raw` | TEXT | Raw string from source |
| `tech_tags` | TEXT[] | Matched from STACK keyword list |
| `description` | TEXT | Stripped HTML, max 600 chars |
| `posted_at` | TIMESTAMPTZ | |
| `fetched_at` | TIMESTAMPTZ | Default `now()` |
| `status` | TEXT | `new` \| `reviewed` \| `dismissed` |
| `match_score` | INT | 0–100 LLM fit score (added migration 003). Only jobs ≥ threshold get inserted, so this is non-null on every fetcher-inserted row. |
| `match_reason` | TEXT | One-line LLM rationale that explains the score. |
| `scored_at` | TIMESTAMPTZ | When the score was computed. |

## Known gotchas

- **Some sources have blocked the VM IP** — listings still get stored, but direct access from the VM may fail. Apply to jobs from a personal machine, not routed through Bugsy.
- **UI status (reviewed/dismissed) is stored in browser `localStorage`** — doesn't sync across devices. A future refactor would persist back to `job_listings.status`.
- **Pre-migration rows have `NULL` match_score** — they were stored before the scoring step existed. They show as `—` in the UI and only appear when the min-score slider is at 0.
- **Threshold changes don't backfill** — old rows keep their original score. Re-scoring is a manual one-shot job.
- **LLM scoring adds ~2 minutes to a 100-job run** — sequential HTTP calls at ~1s each. Acceptable for a 5:30am cron.
