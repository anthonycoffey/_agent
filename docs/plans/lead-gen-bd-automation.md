# Lead-Gen & BD Automation — Build Plan

**Status:** Planned  
**Priority order:** Tier 1 → Tier 2 → Tier 3  
**Context loaded by all workflows:** `agent/context/coffey-codes-bd-profile.md`  
**Model defaults:** Gemini 2.5 Pro for synthesis; Gemini 2.5 Flash for classification/scoring; Claude for anything that needs careful prose  

---

## Tier 1 — Foundation (build first)

### 1A. `/leads` — Daily Lead Hunter

**What it does:**  
Scheduled workflow (runs nightly) that searches for fresh prospects matching Anthony's ICPs, scores them against the BD profile's 13 buying signals, and DMs Bugsy a ranked shortlist each morning.

**Trigger:** n8n Schedule node — runs at 06:00 America/Chicago every weekday

**Signal queries to run (SearXNG):**
- `site:linkedin.com/jobs "senior backend engineer" OR "senior full-stack engineer" Austin "$140,000"` (Signal 1: high-comp eng hire)
- `site:techcrunch.com OR news.ycombinator.com "seed" OR "series A" SaaS 2025` (Signal 2: recent raise)
- `site:linkedin.com/jobs "tech debt" OR "legacy modernization" OR "platform overhaul"` (Signal 3: explicit problem signal)
- `site:linkedin.com/jobs "AI engineer" OR "ML engineer" employees:<30` (Signal 5: premature ML hire)
- `"senior engineer" site:linkedin.com/jobs posted:past-week` (Signal 10: stale eng posting)

**Flow:**
1. Schedule trigger → run 4–5 SearXNG queries in sequence
2. Deduplicate results by domain/company name (Code node)
3. For each unique company: fetch homepage (HTTP Request) + pull LinkedIn snippet if available
4. Score each prospect (Gemini Flash) — output JSON `{company, url, score, signals[], reason, icpCategory}`
5. Filter: score ≥ 4 only
6. Store new prospects in Postgres `leads` table (upsert by domain, skip already-seen)
7. Sort by score desc, take top 5
8. Format Slack message (Bugsy voice, one block per lead with score badge and top signal)
9. DM to boss

**Postgres schema — `leads` table:**
```sql
CREATE TABLE leads (
  id          SERIAL PRIMARY KEY,
  domain      TEXT UNIQUE NOT NULL,
  company     TEXT,
  url         TEXT,
  icp_bucket  TEXT,          -- ICP1/ICP2/ICP3/ICP4
  score       INT,           -- 1–10
  signals     JSONB,         -- array of matched signal labels
  status      TEXT DEFAULT 'new',  -- new | contacted | replied | dead
  source      TEXT,          -- 'daily-hunter' | 'manual' | 'inbound'
  notes       TEXT,
  draft_email TEXT,
  first_seen  TIMESTAMPTZ DEFAULT now(),
  last_touched TIMESTAMPTZ
);
```

**Slack output format (one block per lead):**
```
🔥 *[Score: 8/10]* Acme SaaS — acmesaas.com
ICP: ICP-2 (AI initiative, 60 employees)
📌 Signals: senior eng hire ($155k) · open AI engineer role · Austin-based
→ /research acmesaas.com to go deep
```

---

### 1B. Inbound Contact Form Enrichment

**What it does:**  
When someone submits Anthony's coffey.codes contact form, Bugsy auto-researches them, scores the lead, and DMs Anthony a brief before the first reply. Saves a Gmail draft response.

**Trigger:** n8n Webhook — coffey.codes form POSTs to `https://n8n.coffey.codes/webhook/inbound-lead`  
*(Note: contact form has no backend wired yet — this workflow is the backend)*

**Flow:**
1. Webhook receives `{name, email, company, message}`
2. Acknowledge (return 200 immediately; async from here)
3. Extract domain from email → SearXNG company lookup + homepage fetch
4. Bugsy Brain (Gemini Pro): score lead, identify ICP bucket, surface buying signals, draft a personalized first-reply email
5. Upsert into `leads` table (source: 'inbound', status: 'new')
6. Save draft reply in Gmail (`draft_email` field + Gmail Draft node)
7. DM boss: lead brief + "Draft reply saved in Gmail — review before sending"

**Key:** the draft email tone must follow BD profile §8 voice rules — professional, prospect-problem-first, 4-6 sentences, soft CTA.

---

### 1C. Postgres CRM — Schema + Maintenance

**What it does:**  
Lightweight CRM in the existing Postgres instance. Leads table (above) plus a `lead_events` audit trail. No external CRM needed.

**Additional schema:**
```sql
CREATE TABLE lead_events (
  id         SERIAL PRIMARY KEY,
  lead_id    INT REFERENCES leads(id),
  event_type TEXT,   -- 'scored' | 'contacted' | 'replied' | 'status_change' | 'note_added'
  payload    JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

**Bugsy slash commands that touch the CRM (wire up later):**
- `/leads list` — today's new leads from Postgres
- `/leads status <domain> <new|contacted|replied|dead>` — update lead status
- `/leads note <domain> <text>` — append a note

These can be extensions of the existing `/leads` Slack slash command once the daily hunter is running.

---

## Tier 2 — Conversion Tools (build after Tier 1 is running)

### 2A. `/proposal <domain>` — Proposal Drafter

**What it does:**  
Pulls the lead record from Postgres, re-fetches any fresh signals, then generates a structured proposal outline tailored to that company's specific pain points and ICP bucket.

**Flow:**
1. `/proposal acmesaas.com` hits Slack slash command → webhook
2. Fetch lead from Postgres by domain
3. Re-run targeted SearXNG searches for fresh context
4. Bugsy Brain (Gemini Pro): generate proposal outline
   - Problem framing (based on their signals)
   - Proposed engagement type (project vs. retainer) + rationale
   - Scope bullets (3–5)
   - Suggested budget anchor from BD profile pricing table
   - Next step CTA
5. Save as Gmail draft + paste into Slack thread
6. Update `leads` table `last_touched`

**Output format:** structured markdown → converted to Gmail draft

---

### 2B. `/follow-up <domain>` — Follow-Up Email Drafter

**What it does:**  
Drafts a follow-up email for a prospect already in the CRM. Checks `lead_events` to understand what was said before; makes sure the follow-up doesn't repeat the same angle.

**Flow:**
1. Fetch lead + all events from Postgres
2. Bugsy Brain: given prior outreach history, draft a fresh follow-up that advances the conversation (different hook, references something new like a product update or press hit if findable)
3. Save Gmail draft + DM boss

**Key rules:**
- Never follow up more than 3x total (check `lead_events` count; warn boss if at limit)
- Each follow-up must use a new conversation hook, not "just checking in"

---

### 2C. `/persona <domain>` — Buyer Research Brief

**What it does:**  
Deep-dive on the specific decision maker (CTO, founder, etc.) at a target company. Research their background, public opinions, tech preferences, and known pain points. Output a "how to talk to this person" brief.

**Flow:**
1. `/persona acmesaas.com` → fetch lead from Postgres
2. SearXNG searches: `"[CTO name] [company]"`, LinkedIn, Twitter/X, HackerNews, podcast appearances
3. Bugsy Brain: synthesize a "buyer persona brief"
   - Background + tenure
   - Technical opinions / stack preferences
   - Public pain points or wins they've talked about
   - Suggested conversation openers
   - What to avoid (e.g., if they've publicly criticized a tool Anthony uses)
4. Output to Slack DM as formatted brief

---

## Tier 3 — Growth (build when Tier 2 is stable)

### 3A. Trigger-Event Monitor

**What it does:**  
Daily scan for trigger events at companies already in the `leads` table or on a watchlist. Pings boss when something changes.

**Events to watch:**
- New funding announcements (SearXNG news search per domain)
- New senior eng job postings (LinkedIn via SearXNG)
- Product launches or press hits
- CTO/founder new LinkedIn posts (via SearXNG or RSS)

**Flow:**
1. Schedule: every weekday morning before `/leads` runs
2. Fetch all leads with `status NOT IN ('dead')` from Postgres
3. For each: run targeted SearXNG news/jobs searches
4. Gemini Flash: classify whether a trigger event occurred; extract event summary
5. If yes: DM boss with event + suggested next action ("This is the moment to reach out — want me to draft something?")
6. Log event to `lead_events`

---

### 3B. Content Opportunity Finder

**What it does:**  
Finds questions, pain points, and conversations in target communities where Anthony could post useful content (SEO-seeded blog posts, LinkedIn posts, HN comments). Surfaces them as a weekly content brief.

**Trigger:** Weekly schedule (Monday morning)

**Sources to scan (SearXNG):**
- `site:reddit.com/r/node OR site:reddit.com/r/webdev "how do I" OR "struggling with" OR "anyone dealt with"`
- `site:news.ycombinator.com "Ask HN" node OR python OR "legacy system" OR "tech debt"`
- LinkedIn trending topics in software engineering / AI (if accessible via SearXNG)

**Flow:**
1. Run 4–6 SearXNG queries across subreddits + HN
2. Gemini Flash: score each thread for content opportunity (Anthony's expertise match + audience quality)
3. Gemini Pro: generate a content brief — "Here are 3 things worth writing about this week, with a suggested angle for each"
4. DM boss on Monday morning

---

### 3C. GitHub Maintainer Scout

**What it does:**  
Finds maintainers of active open-source repos in Anthony's stack (Node, Python, React, TypeScript) who show capacity strain signals (stale issues, help-wanted labels, maintainer burnout posts). These are potential consulting clients.

**Trigger:** Weekly schedule

**Flow:**
1. SearXNG GitHub searches: `site:github.com label:"help wanted" OR label:"good first issue" is:open language:TypeScript stars:>100`
2. For repos with high issue-to-contributor ratios: extract maintainer profiles
3. SearXNG: lookup maintainer → do they run a company? Are they a solo maintainer with commercial users?
4. Gemini Flash: score fit (ICP match, budget likelihood, reachability)
5. Top 3 → DM boss with "here's a maintainer worth reaching out to and why"

---

## Implementation Order

| Phase | Workflow | Est. complexity | Dependency |
|---|---|---|---|
| 1 | Postgres schema setup (1C) | Low | None — run first |
| 2 | `/leads` daily hunter (1A) | Medium | Postgres + SearXNG |
| 3 | Inbound enrichment webhook (1B) | Medium | Postgres + coffey.codes form wiring |
| 4 | `/proposal` drafter (2A) | Medium | Postgres leads data |
| 5 | `/follow-up` drafter (2B) | Low | Postgres lead_events |
| 6 | `/persona` research (2C) | Medium | SearXNG |
| 7 | Trigger-event monitor (3A) | Medium | Postgres leads table |
| 8 | Content opportunity finder (3B) | Low | SearXNG |
| 9 | GitHub maintainer scout (3C) | Medium | SearXNG |

---

## Shared Infrastructure Notes

- **SearXNG:** already running at `http://searxng:8080` — all workflows use it via n8n HTTP Request node with `?q=<query>&format=json`
- **Postgres:** already running; just need to run the DDL to create `leads` and `lead_events` tables
- **Model routing:** classification/scoring → `gemini-2.5-flash`; synthesis/drafting → `gemini-2.5-pro`; prospect-facing prose → `claude-sonnet-4-6` if quality bar demands it
- **BD context:** every workflow embeds `coffey-codes-bd-profile.md` in its system prompt — Bugsy uses it to qualify, score, and draft without re-inventing the rules
- **Voice rule:** all outbound copy (emails, proposals, follow-ups) uses §8 professional voice. Bugsy's mobster persona only appears in Slack messages TO Anthony.
- **No hardcoding:** user IDs, channel IDs, and team IDs are never baked into workflow nodes — always extracted from runtime payload or n8n credentials

---

## Open Questions (do not implement until resolved)

1. **Contact form backend** — coffey.codes form has no backend yet. Tier 1B workflow IS the backend. Need to wire the form's submit action to POST to the n8n webhook URL.
2. **LinkedIn scraping** — SearXNG can surface LinkedIn job postings but not authenticated profile data. Buyer persona research (2C) may have gaps on private profiles.
3. **Gmail send permission** — current Gmail credential is scoped for drafts only. If we ever want Bugsy to send (not just draft), re-authorize with `gmail.send` scope.
4. **Slack `/leads` command** — needs to be created in Slack App dashboard before 1A can be wired up. Currently only `/research` and `/bugsy` exist.
