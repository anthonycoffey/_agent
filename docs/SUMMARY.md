# Summary

> Table of contents for everything under `docs/`. GitBook-compatible. Keep this in sync when you add a page; the mkdocs `nav:` block is the other place that has to know.

## Overview

- [Docs README — folder rules, lifecycle, prompts](README.md)
- [Index / home](index.md)

## Specs

- [Plans](specs/plans/)
- [Active specs](specs/active/)
    - [SPEC-RAG-001 — Daily refresh of RAG source repos via cron + ingest](specs/active/SPEC-RAG-001-daily-source-repo-refresh.md)
- [Architecture Decision Records (ADRs)](specs/adrs/)
- [Archive](specs/archive/)
    - [BUG-JIRA-001 — Jira digest reports completed tickets as current activity](specs/archive/BUG-JIRA-001-digest-reports-completed-tickets-as-current.md)
    - [BUG-AGENT-001 — Bugsy retrieves only one Jira digest when asked about archived history](specs/archive/BUG-AGENT-001-bugsy-retrieves-only-one-jira-digest.md)
    - [BUG-DOCS-001 — Workflow reference generator creates duplicate stub docs on Windows](specs/archive/BUG-DOCS-001-workflow-reference-generator-creates-duplicate-stubs.md)

## Templates

- [Feature template](templates/feature-template.md)
- [Bug template](templates/bug-template.md)
- [ADR template](templates/adr-template.md)
- [Agent brief template](templates/agent-brief-template.md)

## Documentation

- [Documentation index](documentation/README.md)
- [Development standards (DDD + TDD + git conventions)](documentation/development-standards.md)
- [Agent briefs](documentation/agents/)
- [Guides](documentation/guides/)
- [Deep dives](documentation/deep-dives/)
- [Repo / service references](documentation/repos/)

## Pre-DDD documentation (project-specific instances)

### Architecture (→ documentation/repos/)

- [Stack overview](architecture/overview.md)
- [Networking](architecture/networking.md)
- [Credentials](architecture/credentials.md)

### Workflows (→ documentation/deep-dives/)

- [Bugsy unified](workflows/bugsy-unified.md)
- [Job board](workflows/job-board.md)
- [RAG ingest](workflows/rag-ingest.md)
- [RAG query](workflows/rag-query.md)
- [RAG refresh notify](workflows/bugsy-rag-refresh-notify.md)
- [Inbox watcher](workflows/bugsy-inbox-watcher.md)
- [Jira digest](workflows/bugsy-jira-digest.md)
- [Leads hunter](workflows/bugsy-leads-hunter.md)
- [Research](workflows/bugsy-research.md)

### Operations (→ documentation/guides/)

- [Deploy](operations/deploy.md)
- [n8n import](operations/n8n-import.md)
- [Workflow reference generator](operations/workflow-reference-generator.md)
- [Troubleshooting](operations/troubleshooting.md)

### Reference (→ documentation/repos/)

- [Env vars](reference/env-vars.md)
- [Webhooks](reference/webhooks.md)
- [Database schema](reference/database.md)

## Archive

- [General archive](archive/)
