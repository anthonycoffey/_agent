# Bugsy

**Anthony Coffey's personal AI agent stack.** Runs 24/7 on a single GCP VM. Combines self-hosted LLMs, n8n workflows, RAG, and a Slack interface to automate the repetitive parts of freelance dev life — job hunting, lead gen, outreach, research — and to build a personal knowledge base that makes every AI interaction smarter over time.

## Reading these docs locally

Source files live in `docs/` in the repo. To browse them as a real site:

```bash
pip install mkdocs-material      # one-time
mkdocs serve                     # from repo root → http://localhost:8000
```

Or just read the markdown files directly in your editor / on GitHub.

## What's in here

These docs explain how Bugsy is put together and how to operate it.

- **[Architecture](architecture/overview.md)** — the containers, how data flows, networking, secrets
- **[Workflows](workflows/bugsy-unified.md)** — what each n8n workflow does and how to extend it
- **[Operations](operations/deploy.md)** — deploying changes, importing workflows, troubleshooting
- **[Reference](reference/env-vars.md)** — env vars, webhook paths, database schemas

## What lives elsewhere

- **`logs/decisions-log.md`** — architecture decision records (why we picked X over Y)
- **`logs/incident-log.md`** — chronological record of deployment incidents and fixes
- **`logs/plans/`** — working plans for in-flight initiatives (these graduate into docs once they ship)
- **`CLAUDE.md`** — project context for Claude Code; covers current state, gotchas, conventions

## The persona

![Bugsy avatar — used as the Slack bot's profile image](assets/bugsy/Bugsy%20-%20Avatar.png){ width="240" align="right" }

Bugsy talks like a 1970s New York Italian-American capo. Calls Anthony "boss." The persona wraps useful output — it's flavor, not noise. If a workflow is doing something for the boss, Bugsy reports back with character but still says the right thing.

The avatar to the right is the Slack bot's profile image. Additional art (portrait, animated mp4, stills) lives in [`docs/assets/bugsy/`](assets/bugsy/README.md).
