# Databases

## Postgres (`agent-postgres`)

`pgvector/pgvector:pg16` — Postgres 16 with the pgvector extension. Single instance, multiple logical databases.

### Databases

| Database | Owner | Purpose |
|---|---|---|
| `agent` | `agent` | App data: `job_listings`, `leads`, `lead_events` |
| `n8n` | `agent` | n8n internal: workflow definitions, credentials (encrypted), executions, chat memory |

### `agent.job_listings`

Populated daily by the job board fetcher. The fetcher LLM-scores every new job and
only inserts ones that clear a fit threshold (default 75) — see
[`workflows/job-board.md`](../workflows/job-board.md).

| Column | Type | Notes |
|---|---|---|
| `id` | SERIAL PK | |
| `source` | TEXT | Board name |
| `title` | TEXT | |
| `company` | TEXT | |
| `url` | TEXT UNIQUE | Dedup key |
| `location` | TEXT | Always `'Remote'` |
| `salary_raw` | TEXT | |
| `tech_tags` | TEXT[] | Matched stack keywords |
| `description` | TEXT | Stripped HTML, max 600 chars |
| `posted_at` | TIMESTAMPTZ | |
| `fetched_at` | TIMESTAMPTZ | Default `now()` |
| `status` | TEXT | `new` / `reviewed` / `dismissed` |
| `match_score` | INT | 0–100 LLM fit score (migration 003). Non-null on rows inserted by the fetcher; null on pre-migration rows. |
| `match_reason` | TEXT | One-line LLM rationale for the score. |
| `scored_at` | TIMESTAMPTZ | When the score was computed. |

### `agent.leads`

CRM table for outbound lead gen.

| Column | Type | Notes |
|---|---|---|
| `id` | SERIAL PK | |
| `domain` | TEXT UNIQUE | |
| `company` | TEXT | |
| `icp_bucket` | TEXT | ICP1–ICP4 |
| `score` | INT | 1–10 |
| `signals` | JSONB | Matched signal labels |
| `status` | TEXT | `new` / `contacted` / `replied` / `dead` |
| `draft_email` | TEXT | LLM-generated outreach draft |

### `agent.lead_events`

Audit trail for the leads CRM.

### Useful queries

```sql
-- Best-fit new jobs from the last 24h
SELECT match_score, title, company, match_reason, url
FROM agent.job_listings
WHERE status = 'new' AND fetched_at > NOW() - INTERVAL '24 hours'
ORDER BY match_score DESC NULLS LAST, posted_at DESC;

-- Score distribution of stored jobs (sanity-check the threshold)
SELECT
  CASE
    WHEN match_score >= 90 THEN '90-100'
    WHEN match_score >= 75 THEN '75-89'
    WHEN match_score >= 50 THEN '50-74'
    WHEN match_score IS NULL THEN 'pre-scoring'
    ELSE '0-49'
  END AS bucket,
  COUNT(*) AS jobs
FROM agent.job_listings
GROUP BY 1 ORDER BY 1;

-- n8n workflows currently active
SELECT name, active, jsonb_path_query(nodes::jsonb, '$[*].parameters.path') AS webhook
FROM workflow_entity
WHERE active = true;

-- Chat memory window for a session
SELECT created_at, role, content
FROM n8n_chat_memory
WHERE session_id = 'slack:slash:U0AUSKT2VRD'
ORDER BY created_at DESC
LIMIT 20;
```

## Qdrant (`agent-qdrant`)

Vector store. Single collection.

### `personal_knowledge`

| Property | Value |
|---|---|
| Vector size | 768 |
| Distance | Cosine |
| Embedding model | `nomic-embed-text` (Ollama) |

### Point payload schema

```json
{
  "text": "chunk content",
  "title": "document title",
  "category": "bio | articles | case-studies | projects",
  "tags": ["tag1", "tag2"],
  "chunk_index": 0,
  "total_chunks": 5,
  "ingested_at": "ISO timestamp"
}
```

### Point IDs

Deterministic UUID derived from `title + chunk_index` (pure JS hash, no `crypto` require). Re-ingesting the same document overwrites its chunks instead of duplicating.

### Useful queries

```bash
# Total point count
docker run --rm --network agent_agent-net curlimages/curl:latest \
  -s http://agent-qdrant:6333/collections/personal_knowledge | jq '.result.points_count'

# Browse payloads
docker run --rm --network agent_agent-net curlimages/curl:latest \
  -s -X POST http://agent-qdrant:6333/collections/personal_knowledge/points/scroll \
  -H "Content-Type: application/json" \
  -d '{"limit":20,"with_payload":true,"with_vector":false}' \
  | jq '.result.points[].payload | {title, chunk_index, total_chunks}'

# Delete by title
docker run --rm --network agent_agent-net curlimages/curl:latest \
  -s -X POST http://agent-qdrant:6333/collections/personal_knowledge/points/delete \
  -H "Content-Type: application/json" \
  -d '{"filter":{"must":[{"key":"title","match":{"value":"Old Doc"}}]}}'
```

## Redis (`agent-redis`)

`redis:7-alpine`. General cache / queue. No long-lived schemas; transient.
