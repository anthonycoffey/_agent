# Job board

Two workflows that work together to surface remote dev jobs.

## Fetcher

`agent/n8n/workflows/bugsy-job-board-fetcher.json` — daily cron, 5:30am CT M-F. Pulls 20+ job boards (5 JSON APIs + 16 RSS feeds) concurrently via axios, normalizes, dedupes by URL, upserts to the `job_listings` Postgres table, posts a Slack summary.

## UI

`agent/n8n/workflows/bugsy-job-board-ui.json` — webhook GET `/job-board`. Queries Postgres and renders a dark-mode HTML job board with filter/sort/status controls. Live at:

```
https://n8n.coffey.codes/webhook/job-board
```

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
| `fetched_at` | TIMESTAMPTZ | Default now() |
| `status` | TEXT | `new` \| `reviewed` \| `dismissed` |

## Known gotchas

- **Some sources have blocked the VM IP** — listings still get stored, but direct access from the VM may fail. Apply to jobs from a personal machine, not routed through Bugsy.
- **UI status (reviewed/dismissed) is stored in browser `localStorage`** — doesn't sync across devices. A future refactor would persist back to `job_listings.status`.
