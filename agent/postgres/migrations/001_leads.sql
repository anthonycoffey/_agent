-- Migration: 001_leads.sql
-- Creates the leads CRM table and lead_events audit trail.
-- Run against the 'agent' database in the postgres container.
--   docker exec -i postgres psql -U postgres -d agent < 001_leads.sql

CREATE TABLE IF NOT EXISTS leads (
  id           SERIAL PRIMARY KEY,
  domain       TEXT UNIQUE NOT NULL,
  company      TEXT,
  url          TEXT,
  icp_bucket   TEXT,                          -- ICP1 / ICP2 / ICP3 / ICP4
  score        INT,                           -- 1–10
  signals      JSONB,                         -- array of matched signal labels
  status       TEXT DEFAULT 'new',            -- new | contacted | replied | dead
  source       TEXT,                          -- 'daily-hunter' | 'manual' | 'inbound'
  notes        TEXT,
  draft_email  TEXT,
  first_seen   TIMESTAMPTZ DEFAULT now(),
  last_touched TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS lead_events (
  id         SERIAL PRIMARY KEY,
  lead_id    INT REFERENCES leads(id),
  event_type TEXT,   -- 'scored' | 'contacted' | 'replied' | 'status_change' | 'note_added'
  payload    JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Index on domain for fast upsert lookups
CREATE INDEX IF NOT EXISTS idx_leads_domain ON leads (domain);

-- Index on status for CRM list queries
CREATE INDEX IF NOT EXISTS idx_leads_status ON leads (status);

-- Index on score for sorted shortlist queries
CREATE INDEX IF NOT EXISTS idx_leads_score ON leads (score DESC);

-- Index on lead_events.lead_id for joining events per lead
CREATE INDEX IF NOT EXISTS idx_lead_events_lead_id ON lead_events (lead_id);
