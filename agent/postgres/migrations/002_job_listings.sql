-- Migration: 002_job_listings.sql
-- Niche job board aggregator — stores normalized listings from 30+ sources.
-- Run: docker exec -i agent-postgres psql -U agent -d agent < ~/agent/postgres/migrations/002_job_listings.sql

CREATE TABLE IF NOT EXISTS job_listings (
  id          SERIAL PRIMARY KEY,
  source      TEXT NOT NULL,
  title       TEXT NOT NULL,
  company     TEXT,
  url         TEXT UNIQUE NOT NULL,
  location    TEXT,
  salary_raw  TEXT,
  tech_tags   TEXT[],
  description TEXT,
  posted_at   TIMESTAMPTZ,
  fetched_at  TIMESTAMPTZ DEFAULT now(),
  status      TEXT DEFAULT 'new'   -- new | reviewed | dismissed
);

CREATE INDEX IF NOT EXISTS idx_jl_url      ON job_listings (url);
CREATE INDEX IF NOT EXISTS idx_jl_source   ON job_listings (source);
CREATE INDEX IF NOT EXISTS idx_jl_posted   ON job_listings (posted_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_jl_status   ON job_listings (status);
CREATE INDEX IF NOT EXISTS idx_jl_tags     ON job_listings USING GIN (tech_tags);
CREATE INDEX IF NOT EXISTS idx_jl_fetched  ON job_listings (fetched_at DESC);
