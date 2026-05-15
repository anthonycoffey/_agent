# Documentation

Reference material for how the system works — distinct from `../specs/` (what we're building or have decided) and `../templates/` (canonical document shapes).

## The four buckets

| Bucket | Purpose | Examples |
|---|---|---|
| [`agents/`](agents/) | Briefs for AI agents touching a service: interfaces, state, gotchas | `bugsy.md` — what Bugsy is, how its workflows wire together |
| [`guides/`](guides/) | Procedural how-to documentation for humans | Deploy steps, n8n import, troubleshooting walkthroughs |
| [`deep-dives/`](deep-dives/) | Narrow-focus technical writeups on one specific thing | A workflow, an algorithm, a tricky integration |
| [`repos/`](repos/) | Comprehensive technical reference for a repo or deployed service | Stack overview, env vars, DB schema, webhook contracts |

## How this maps to existing project docs

This project predates the DDD migration. The pre-existing `docs/` subfolders already serve these roles; we did **not** physically relocate them (to avoid breaking mkdocs nav, internal cross-links, and the `generate-workflow-reference.mjs` output path). The mapping:

| New DDD bucket | Where it lives in this project | Notes |
|---|---|---|
| `agents/` | `agents/` (new — will hold the Bugsy agent brief) | Project-specific instance pending; see [development-standards.md](development-standards.md#agent-briefs) |
| `guides/` | [`../operations/`](../operations/) | Deploy, n8n import, troubleshooting, generator script |
| `deep-dives/` | [`../workflows/`](../workflows/) | One deep dive per n8n workflow |
| `repos/` | [`../architecture/`](../architecture/) + [`../reference/`](../reference/) | Architecture = system-level repo doc; reference = structural reference (env, webhooks, DB) |

**Going forward.** New docs in any of these four categories should go into the DDD-canonical location (`documentation/agents/`, `documentation/guides/`, etc.). Existing docs stay where they are unless an ADR justifies moving them.

## Where new docs go

Pick by intent, not by file size:

- Are you teaching a human how to do a thing step-by-step? → `guides/` (or `../operations/`)
- Are you explaining one specific technical thing in depth? → `deep-dives/` (or `../workflows/` if it's a workflow)
- Are you describing a whole service / repo for someone who needs the full picture? → `repos/` (or `../architecture/`)
- Are you writing a brief for an AI agent to onboard onto a service? → `agents/`

If it doesn't fit any of these, it's probably a spec or an ADR, not documentation. See [`../README.md`](../README.md).

## Standards

All documentation in this folder must follow [development-standards.md](development-standards.md): conventions for git, TDD, the spec lifecycle, and the relationship between specs, ADRs, and reference docs.
