---
title: Bugsy Jira Digest
tags: [bugsy, jira, gmail, slack, digest, scheduled, claude-sonnet-4-6]
n8n_workflows: [bugsy-jira-digest]
---

# Jira digest

`agent/n8n/workflows/bugsy-jira-digest.json` — twice-a-day digest of Jira notification mail from `jira@ultrasoundai.atlassian.net`, posted to `#mulberry-street` (channel id `C0AV83XUSTU`) with summary + action items and every ticket key linkified to the UltrasoundAI workspace.

## Schedule

Cron `0 8,16 * * 1-5` in `America/Chicago` — **8:00 AM and 4:00 PM CT, Mon–Fri**. No state in Postgres; each run queries `newer_than:1d` so there's intentional overlap between runs (the LLM is told to dedupe).

## Pipeline

```mermaid
flowchart LR
  S[Schedule 8am+4pm CT] --> G[Gmail Get Jira Mail]
  G --> A[Aggregate Emails]
  A --> L[Write Digest — claude-sonnet-4-6]
  L --> SL[Post to Mulberry Street]
  L --> RP[Build RAG Payload]
  RP --> RI[POST to RAG Ingest]
```

- **Gmail — Get Jira Mail** uses Gmail search `from:jira@ultrasoundai.atlassian.net newer_than:1d`. `alwaysOutputData: true` so the downstream chain runs even on empty inboxes.
- **Aggregate Emails** strips HTML, truncates each body to 1200 chars, and folds all messages into one big text block with `--- Email N ---` separators. Outputs `{ count, emails }`. Returns `(no Jira mail in the window)` when the inbox is empty so the LLM can produce a quiet-shift one-liner.
- **Write Digest** is a single-shot LLM call against `claude-sonnet-4-6` via LiteLLM. System prompt enforces persona (sparing, max two flourishes), output structure (`*Summary*` + `*Action Items*`), and the strict link-format rule for ticket IDs.
- **Post to Mulberry Street** sends the result to channel `C0AV83XUSTU` with `unfurl_links: false` and `unfurl_media: false` so the linkified ticket IDs don't blow up the message with Atlassian previews.
- **Build RAG Payload** (parallel branch) wraps the digest body in YAML frontmatter and builds the `/rag-ingest` request body. See [RAG ingestion](#rag-ingestion) below.
- **POST to RAG Ingest** fires the request at `https://n8n.coffey.codes/webhook/rag-ingest` with `onError: continueRegularOutput` so a RAG failure can't break the Slack branch (which runs concurrently off the same `Write Digest` output).

## Output format

Two sections in Slack mrkdwn:

```
*Summary*
<2-5 short paragraphs, grouped by ticket where useful>

*Action Items*
• <one bullet per action, ticket IDs as <https://ultrasoundai.atlassian.net/browse/UTT-123|UTT-123>>
```

Empty-inbox runs collapse to a single in-voice line.

## RAG ingestion

Each digest is mirrored into Qdrant via the same `/rag-ingest` webhook the bulk `rag-ingest.sh` helper uses — but **without ever writing a file under `~/agent/rag/`**. The content is held in-memory by n8n, chunked, embedded, and upserted directly.

**Why this is safe vs. the bulk script.** `rag-ingest.sh` only walks four hardcoded category directories (`bio`, `articles`, `case-studies`, `projects`) and its orphan-purge pass is category-scoped + exact-match on filename. Because this branch uses category `jira-digests` and filename prefix `jira/…`, the shell script literally has no knowledge of these points and can never purge them, even on a clean re-run with no Jira files on disk.

**Payload contract** (built in **Build RAG Payload**):

```json
{
  "category": "jira-digests",
  "filename": "jira/<ISO8601-execution-start>.md",
  "content": "---\ntitle: Jira Digest <ISO>\ntags: [jira, digest, work-email]\n---\n\n<digest mrkdwn body>"
}
```

- **Filename** uses `$now.toISO()` captured at execution start. Each cron fire (8am + 4pm CT) produces its own document; a retry of the *same* execution overwrites in-place (Qdrant point IDs are deterministic UUIDs seeded by `filename + chunk_index`, see [bugsy-rag-ingest.md](bugsy-rag-ingest.md)). Distinct fires never collide.
- **Tags** are static. We rely on Qdrant's payload filtering (`category = "jira-digests"`) to scope retrieval, not per-ticket tags — Bugsy's RAG retriever already pulls by semantic similarity, and the digest body itself carries the linkified ticket IDs the embedder will index.
- **Frontmatter title** carries the run timestamp so a recall like "what did the Jira digest say this morning?" surfaces the right doc.

**Failure mode.** The HTTP node uses `onError: continueRegularOutput`. If the webhook is down, returns non-2xx, or times out, the Slack post still ships — only the RAG enrichment is missed for that fire, and the next fire fills the gap. No retry, no alert.

## Why `<URL|TEXT>` for ticket IDs

Slack mrkdwn link syntax is `<URL|display>`. When display text is supplied (not just a bare URL), Slack typically suppresses link previews on its own — and the node also sets `unfurl_links` + `unfurl_media` to `false` belt-and-suspenders. A message with 15 tickets stays a single tight digest instead of a tower of unfurled cards.

## Credentials

| Slot | Credential | Notes |
|---|---|---|
| Gmail | `Gmail - Bugsy (anthony@bitmotive.com)` | OAuth2, work account. The credential id `ScdvtlZU9jnWCan2` is bound in the JSON — re-binding only needed if you build a fresh n8n instance. |
| LiteLLM | `LiteLLM - local proxy` | Already in n8n — same one every other workflow uses. |
| Slack | `Slack - Bugsy` | Already in n8n. |

## Temporal accuracy guardrail

The system prompt closes with two hard requirements:

```
REQUIREMENTS:
1. THE OUTPUT MUST BE TEMPORALLY ACCURATE, OUTDATED EVENTS SHOULD NOT BE REPORTED AS CURRENT.
2. LOOK AT TIMESTAMPS TO VERIFY ORDER OF OPERATIONS
```

Without this, the LLM tends to flatten the email feed into "what's happening" without respecting that comment timestamps may be hours apart — so an early-morning status change followed by an afternoon revert would get reported as "status changed to X" instead of "X then reverted to Y." Keeping these front-and-center makes the digest a trustworthy timeline view, not a soup of recent verbs.

## Tuning

- **Cadence too sparse?** Change cron to `0 8,12,16 * * 1-5` (3x/day) or `0 8-18/2 * * 1-5` (every 2h in business hours).
- **Different project key?** Sender filter is workspace-scoped (`jira@<workspace>.atlassian.net`) so it auto-includes every project you receive mail for. The Jira URL pattern in the system prompt is hardcoded to `ultrasoundai.atlassian.net` — edit there if you need a different host.
- **Too noisy?** Tighten the Gmail filter, e.g. `from:jira@ultrasoundai.atlassian.net AND -subject:"watching"` to drop "you are now watching" emails.
- **Want richer action items?** Bump model to `claude-opus-4-7` (slower, smarter) or feed more body bytes — raise the 1200-char truncate in `Aggregate Emails`.

## See also

- [Inbox Watcher](bugsy-inbox-watcher.md) — per-email triage on the personal Gmail (different pattern, currently inactive)

<!-- NODE-REF:START:bugsy-jira-digest — auto-generated by agent/n8n/scripts/generate-workflow-reference.mjs; do not edit by hand -->

## Node reference: Bugsy — Jira Digest (work email)

> Auto-generated from `agent/n8n/workflows/bugsy-jira-digest.json` on 2026-05-15. Run `node agent/n8n/scripts/generate-workflow-reference.mjs` to refresh.

**Active:** `false` · **Nodes:** 7 · **Execution order:** `v1`

### Flow

```mermaid
flowchart TD
  schedule_8am_4pm_ct_m_f["Schedule (8am + 4pm CT M-F)"]
  gmail_get_jira_mail["Gmail — Get Jira Mail"]
  aggregate_emails["Aggregate Emails"]
  write_digest["Write Digest"]
  post_to_mulberry_street["Post to Mulberry Street"]
  build_rag_payload["Build RAG Payload"]
  post_to_rag_ingest["POST to RAG Ingest"]
  schedule_8am_4pm_ct_m_f --> gmail_get_jira_mail
  gmail_get_jira_mail --> aggregate_emails
  aggregate_emails --> write_digest
  write_digest --> post_to_mulberry_street
  write_digest --> build_rag_payload
  build_rag_payload --> post_to_rag_ingest
```

### Nodes

#### Schedule (8am + 4pm CT M-F)
*Type:* `n8n-nodes-base.scheduleTrigger`

- **Schedule:** cron `0 8,16 * * 1-5`
- **Timezone:** `America/Chicago`

#### Gmail — Get Jira Mail
*Type:* `n8n-nodes-base.gmail`

- **Resource:** `message`
- **Operation:** `getAll`

- **Credential (gmailOAuth2):** `Gmail - Bugsy (anthony@bitmotive.com)`

#### Aggregate Emails
*Type:* `n8n-nodes-base.code`

```javascript
const emails = $('Gmail — Get Jira Mail').all();

// Strip HTML so the LLM gets clean text instead of markup
const stripHtml = (s) => String(s || '')
  .replace(/<style[\s\S]*?<\/style>/gi, ' ')
  .replace(/<script[\s\S]*?<\/script>/gi, ' ')
  .replace(/<[^>]+>/g, ' ')
  .replace(/&nbsp;/g, ' ')
  .replace(/&amp;/g, '&')
  .replace(/&lt;/g, '<')
  .replace(/&gt;/g, '>')
  .replace(/\s+/g, ' ')
  .trim();

if (!emails.length || (emails.length === 1 && !emails[0].json?.id)) {
  return [{ json: { count: 0, emails: '(no Jira mail in the window)' } }];
}

const lines = emails.map((it, i) => {
  const j = it.json || {};
  const from = (j.from && j.from.text) ? j.from.text : (j.from || j.From || '?');
  const subject = j.subject || j.Subject || '?';
  const snippet = j.snippet || '';
  const body = stripHtml(j.text || j.html || '').substring(0, 1200);
  return `--- Email ${i + 1} ---\nFrom: ${from}\nSubject: ${subject}\nSnippet: ${snippet}\nBody: ${body}`;
}).join('\n\n');

return [{ json: { count: emails.length, emails: lines } }];
```

#### Write Digest
*Type:* `@n8n/n8n-nodes-langchain.openAi`

- **Model:** `claude-sonnet-4-6`
- **Temperature:** `0.5`

**SYSTEM message:**
```text
You are Bugsy, the boss's right-hand. Voice: 1970s NY Italian-American mobster — confident, warm, direct with the classic new yorker accent. Use voice flourishes (capisce, boss, skip, hey! ho!) SPARINGLY — at MOST two across the whole digest, ideally in the opener and closer. Underneath the voice the content must be CORRECT, ACCURATE, and PROFESSIONAL.

You're reading a digest of Jira notification emails from ultrasoundai.atlassian.net (subject prefix '[JIRA]', project key UTT). Produce ONE Slack message in Slack mrkdwn with two sections:

*Summary*
What's moved on the project since the last digest. Group activity by ticket where it makes sense. Call out: blockers, status changes, priority shifts, deadlines, who's waiting on whom. Just a few short paragraphs. Condensed, succinct; not chatty.

*Action Items*
Concrete things the boss has to DO. One bullet per item starting with •. Cover:
- tickets newly assigned to him
- @mentions calling him out
- review or approval requests
- status changes that need a response from him
- threads where someone is waiting on his input
- work that obviously needs a ticket but doesn't have one — suggest creating, label '(no ticket yet)'

FORMATTING RULES — strict:
- EVERY ticket ID (UTT-NNN) must be a hyperlink in this exact form: <https://ultrasoundai.atlassian.net/browse/UTT-NNN|UTT-NNN>. No bare 'UTT-123' anywhere.
- Slack markdown only: *bold*, _italic_, `code`, bullets with •.
- No markdown headers (no `#`), no tables.
- No closing signature.
- Keep it tight. If something's repeated across emails (same comment quoted back), mention once.

If the input is '(no Jira mail in the window)': respond with a one-liner in voice, e.g. 'Quiet shift, boss — nothin' worth ya time on the Jira front.'

Output the message body ONLY — no preamble, no 'Here is your digest:'.

REQUIREMENTS:
1. THE OUTPUT MUST BE TEMPORALLY ACCURATE, OUTDATED EVENTS SHOULD NOT BE REPORTED AS CURRENT.
2. LOOK AT TIMESTAMPS TO VERIFY ORDER OF OPERATIONS
```

**USER message:**
```text
={{ $json.emails }}
```

- **Credential (openAiApi):** `LiteLLM - local proxy`

#### Post to Mulberry Street
*Type:* `n8n-nodes-base.slack`

- **Resource:** `message`
- **Operation:** `post`
- **Channel:** `mulberry-street (C0AV83XUSTU)`

**Text:**
```text
={{ $json.message.content }}
```

- **Credential (slackApi):** `Slack - Bugsy`

#### Build RAG Payload
*Type:* `n8n-nodes-base.code`

```javascript
const body = $input.first().json.message.content;
const ts = $now.toISO();
const filename = `jira/${ts}.md`;
const frontmatter = `---\ntitle: Jira Digest ${ts}\ntags: [jira, digest, work-email]\n---\n\n`;
return [{ json: {
  category: 'jira-digests',
  filename,
  content: frontmatter + body,
} }];
```

#### POST to RAG Ingest
*Type:* `n8n-nodes-base.httpRequest`

- **Method:** `POST`
- **URL:** `https://n8n.coffey.codes/webhook/rag-ingest`
- **Timeout:** 60000ms

**Headers:**
- `Content-Type`: `application/json`

**Body:**
```json
={{ JSON.stringify($json) }}
```

- **On error:** `continueRegularOutput`

<!-- NODE-REF:END:bugsy-jira-digest -->
