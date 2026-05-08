-- Migration: 003_job_listings_scoring.sql
-- Add LLM-based fit scoring to job_listings so the fetcher only stores
-- jobs Anthony is highly qualified for. Score 0–100, reason is one short line.
-- Run: docker exec -i agent-postgres psql -U agent -d agent < ~/agent/postgres/migrations/003_job_listings_scoring.sql

ALTER TABLE job_listings
  ADD COLUMN IF NOT EXISTS match_score   INT,
  ADD COLUMN IF NOT EXISTS match_reason  TEXT,
  ADD COLUMN IF NOT EXISTS scored_at     TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_jl_match_score ON job_listings (match_score DESC NULLS LAST);
