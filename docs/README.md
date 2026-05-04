# Bugsy docs

These markdown files are the source for the project documentation site. They render via [MkDocs Material](https://squidfunk.github.io/mkdocs-material/), driven by `mkdocs.yml` at the repo root.

## Reading them

**Quick read:** open the `.md` files directly in your editor or on GitHub. They're written to be readable as plain markdown.

**Nice browsable site (recommended for actual reading):**

```bash
pip install mkdocs-material   # one-time, ~30 MB of deps
mkdocs serve                  # run from the repo root
```

Then open http://localhost:8000. Hot-reloads on file save.

## Structure

| Section | What it covers |
|---|---|
| `index.md` | Top-level overview, links into the rest |
| `architecture/` | What's in the stack and how it's wired |
| `workflows/` | What each n8n workflow does |
| `operations/` | How to deploy, import, troubleshoot |
| `reference/` | Env vars, webhook paths, DB schemas |

## What lives elsewhere

- `logs/decisions-log.md` — architecture decisions (why we picked X over Y)
- `logs/incident-log.md` — incidents and fixes (chronological)
- `logs/plans/` — working plans for in-flight work; graduate into docs once shipped
- `CLAUDE.md` (repo root) — context for Claude Code

## Editing

Just edit the markdown files and commit. No build step, no deploy — `mkdocs serve` re-renders on save when you're reading locally. If you add a new page, also add it to the `nav:` block in `mkdocs.yml` so it shows up in the sidebar.
