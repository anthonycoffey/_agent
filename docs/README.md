# Bugsy docs

This folder is the canonical home for **all project documentation and specifications** — both reference docs (how the system works) and specs (what we're building / have built / decided).

The project follows **Document Driven Development (DDD)** (see [SPEC-DDD-001 source](specs/adrs/) for the canonical spec): every meaningful change starts as a document, gets reviewed like code, ships with code, and lives forever as history.

## Reading them

**Quick read:** open `.md` files directly in your editor or on GitHub.

**Nice browsable site (recommended):**

```bash
pip install mkdocs-material   # one-time
mkdocs serve                  # from the repo root
```

Then open http://localhost:8000. Hot-reloads on save.

## Folder rules

| Folder | Purpose | Audience |
|---|---|---|
| [`templates/`](templates/) | Canonical document templates. Never modify without an ADR. | All |
| [`specs/plans/`](specs/plans/) | Multi-phase project plans and roadmaps | All |
| [`specs/active/`](specs/active/) | Current feature and bug specs — anything not yet shipped | All |
| [`specs/adrs/`](specs/adrs/) | Architecture Decision Records — **permanent, never archived** | All |
| [`specs/archive/`](specs/archive/) | Completed or deprecated specs | Historical reference |
| [`documentation/`](documentation/) | How the system works (agents, guides, deep-dives, repo refs) | Developers + agents |
| [`archive/`](archive/) | General archive for deprecated non-spec docs | Historical reference |

**Pre-DDD folders that still live at this level:**

| Folder | Maps to | Why it didn't move |
|---|---|---|
| [`architecture/`](architecture/) | `documentation/repos/` (deployed-system reference) | mkdocs nav + many cross-links — kept in place to avoid churn |
| [`workflows/`](workflows/) | `documentation/deep-dives/` (one deep dive per workflow) | Same — also written to by `agent/n8n/scripts/generate-workflow-reference.mjs` |
| [`operations/`](operations/) | `documentation/guides/` (how-to procedures) | Same |
| [`reference/`](reference/) | `documentation/repos/` (env, webhooks, DB schema) | Same |

New docs go into the DDD-canonical locations; the four pre-DDD folders are treated as the project's existing instances of the corresponding `documentation/` buckets. Both layouts coexist, indexed together in [`SUMMARY.md`](SUMMARY.md).

## Spec lifecycle

```
draft → ready → in-progress → review-pending → complete
                                                  ↓
                                              (move to specs/archive/)

  ↓ at any point
deprecated  →  (move to specs/archive/)
```

- **draft** — being written; not yet ready for review
- **ready** — peer-reviewed, ready to be picked up
- **in-progress** — implementation in flight
- **review-pending** — code is up; spec waits for the PR to land before flipping to `complete`
- **complete** — shipped; move the file into `specs/archive/`
- **deprecated** — abandoned at any stage; also moves into `specs/archive/`

**ADRs are exempt.** Once accepted, they live in `specs/adrs/` forever. If the decision changes, write a new ADR that supersedes the old one — don't edit history.

## How to start a new spec / bug / ADR / agent brief

Use the slash commands:

| Command | What it does |
|---|---|
| `/new-spec` | Feature spec from `templates/feature-template.md` → `specs/active/` |
| `/new-bug` | Bug spec from `templates/bug-template.md` → `specs/active/` |
| `/new-adr` | ADR from `templates/adr-template.md` → `specs/adrs/` |
| `/new-agent-brief` | Agent brief from `templates/agent-brief-template.md` → `documentation/agents/` |

Each command reads the template, asks for required fields, fills in today's date, drops the file in the right folder, and opens it for editing.

## Prompt templates for working with Claude

When asking Claude to work on something with DDD:

> "Read `docs/specs/active/SPEC-XXX-NNN.md` and implement the **Tasks** section. Run the verification steps under **Acceptance criteria** before reporting done. Don't commit anything I haven't confirmed works."

When asking Claude to file a new bug:

> "Create a bug spec via `/new-bug` for: <one-line description>. Severity P<N> because <reason>. I'll fill in the rest."

## What lives elsewhere (and why)

- [`../CLAUDE.md`](../CLAUDE.md) — project context for Claude Code. Per DDD non-goals, root files like CLAUDE.md and the repo's top-level README are intentionally not moved under `docs/`.
- [`../logs/decisions-log.md`](../logs/decisions-log.md) — informal one-liner decision log. ADRs in `specs/adrs/` are the formal mechanism going forward; this older log is preserved for history.
- [`../logs/incident-log.md`](../logs/incident-log.md) — chronological incident record.
- [`../logs/plans/`](../logs/plans/) — pre-DDD working plans; new plans should live under `specs/plans/`.
