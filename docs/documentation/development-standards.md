---
title: Development Standards
status: living-document
last_reviewed: 2026-05-14
---

# Development Standards

How we work. Mostly stable, occasionally amended via ADR.

## The process: spec-first, verified-before-commit

```
plan  →  spec  →  test  →  implement  →  verify  →  review  →  ship
                                            ↑
                                            └── commit happens HERE, not before
```

1. **Plan.** For non-trivial work, write a brief plan in the conversation or a `docs/specs/plans/` file. Reach alignment before writing code.
2. **Spec.** Anything more than a one-line fix gets a spec via `/new-spec` → `docs/specs/active/`. The spec lives next to the code, gets reviewed like code, and stays as history.
3. **Test (TDD where it applies).** RED → GREEN → REFACTOR. Write the failing test first, watch it fail, write the minimum code to make it pass, then refactor. Where automated tests aren't practical (n8n workflows, infra), the equivalent is "describe the verification step that proves it works" before writing the change.
4. **Implement.** Smallest change that satisfies the spec. No drive-by refactors, no scope creep.
5. **Verify.** Run the verification step. For code: run the tests. For n8n workflows: import the local JSON, trigger, observe the side effect. For infra: actually exercise the path that was broken.
6. **Review.** Self-review the diff. Read it cold like a stranger would. Fix the embarrassing stuff before asking anyone else to look.
7. **Ship.** Commit, push, deploy. The commit message describes *observed* behavior, not aspiration.

## Spec lifecycle

```
draft → ready → in-progress → review-pending → complete  →  specs/archive/
                                                  ↓
                                              (any state)
                                                  ↓
                                              deprecated  →  specs/archive/
```

| Status | Means | Lives in |
|---|---|---|
| `draft` | Being written. Not ready for review. | `specs/active/` |
| `ready` | Reviewed; available to pick up. | `specs/active/` |
| `in-progress` | Implementation in flight. | `specs/active/` |
| `review-pending` | Code is up; spec waits for PR to land. | `specs/active/` |
| `complete` | Shipped. | Move to `specs/archive/` |
| `deprecated` | Abandoned. Can happen at any state. | Move to `specs/archive/` |

**ADRs are exempt.** Once accepted, ADRs live in `specs/adrs/` forever. If a decision changes, write a *new* ADR that supersedes the old one — never edit or archive an existing ADR. The `supersedes` and `superseded_by` frontmatter fields create the chain.

## Git conventions

### Branching

- `main` is the ship branch. All work lands here via PR or direct commit once verified.
- For multi-commit work, use a topic branch: `feat/<short-slug>`, `fix/<short-slug>`, `chore/<short-slug>`, `docs/<short-slug>`. Rebase onto `main` before merging.

### Commit messages

[Conventional Commits](https://www.conventionalcommits.org/). Format: `<type>(<scope>): <summary>`.

| Type | Use for |
|---|---|
| `feat` | New behavior the user / operator can see |
| `fix` | Behavior corrected to match what was already intended |
| `chore` | Internal maintenance — bumps, renames, config tweaks |
| `docs` | Documentation-only change |
| `refactor` | Code change with no behavior change |
| `test` | Adding or fixing tests |

Examples:

- `feat(jira-digest): mirror digest into Qdrant via /rag-ingest`
- `fix(rag-ingest): handle empty chunk array from short docs`
- `chore(tf): update VM machine type`
- `docs(ddd): scaffold templates, specs, and slash commands`

**Never** add a `Co-Authored-By: Claude` trailer. **Never** skip pre-commit hooks (`--no-verify`) unless explicitly authorized.

### When to commit (verify first)

**One commit per verified change.** A commit is a claim that the change works. Don't push speculation.

Specifically:

- After making a code or workflow change, wait for the verification step (test pass, n8n run success, manual confirmation) **before** running `git add`.
- If you make a follow-up fix to your own unpushed work, squash it into the original commit (`git commit --amend` or interactive rebase) — don't ship a separate "fix typo" commit unless the original was already pushed.
- Commit messages are past-tense statements of fact, not future-tense hopes. `fix(x): handle null Y` (we observed it work) — not `fix(x): should handle null Y` (we hope).

This keeps `git blame` useful and the history readable for the next person.

### n8n workflows specifically

Workflow JSON in `agent/n8n/workflows/` follows a **file-based import flow**:

1. Edit the local JSON.
2. In n8n UI → ⋮ → **Import from File** → pick the local file. Save → activate.
3. Trigger and verify end-to-end.
4. Only then commit and push.

Do **not** push first and import via raw GitHub URL — that pollutes history with unverified changes. See `CLAUDE.md` "How to Deploy Changes → n8n workflow changes" for the canonical procedure.

## TDD when automated tests are practical

For code that can run in CI (Python scripts, Node tooling, Terraform validators):

1. **RED:** Write a failing test that captures the desired behavior. Run it. Watch it fail for the right reason.
2. **GREEN:** Write the minimum code to make the test pass. Don't over-engineer.
3. **REFACTOR:** Clean up the implementation. Tests still pass.

For code that doesn't have a practical test harness (n8n workflows, MkDocs config, cloud-init userdata):

1. Document the verification step in the spec's **Acceptance criteria** before writing code.
2. Walk through it manually after implementing.
3. Capture the result in the PR description.

The point isn't religious adherence to test-first — the point is to know *what done looks like* before you start.

## Documentation discipline

When you change behavior, ship the doc change in the same commit. Specifically:

| You changed... | Update... |
|---|---|
| A workflow's behavior, schedule, inputs, outputs | `docs/workflows/<workflow>.md` |
| Database schema | `docs/reference/database.md` and the relevant spec |
| Webhook path or contract | `docs/reference/webhooks.md` |
| Env var, secret, or model config | `docs/reference/env-vars.md` |
| Container, network, or ingress topology | `docs/architecture/*.md` |
| A non-obvious tradeoff worth recording | A new ADR in `docs/specs/adrs/` |
| An incident + fix | `logs/incident-log.md` (one entry per incident) |
| The development process itself | This file |

A new feature should ship with: a spec (`docs/specs/active/`), code, tests or a manual verification step, updated reference docs, and ideally an ADR if a non-obvious choice was made.

## Agent briefs

When a new service / repo joins the project, write an agent brief in `docs/documentation/agents/<service>.md` using the template. It exists so an AI agent (or new developer) can ramp up without re-discovering everything from the code.

A good agent brief covers: what the service does, how to run it locally, its interfaces (in / out), what it persists, known failure modes, and gotchas that have bitten us before.

This is especially important in this project because Bugsy itself is an AI agent stack — the agent briefs are operational, not theoretical.

## What this document is not

- **Not policy.** It's a description of how we work, updated when how-we-work changes. Disagreements get resolved by an ADR, not by ignoring this doc.
- **Not exhaustive.** Specifics for individual services live in their agent briefs and repo docs. This is the cross-cutting "always true" stuff.
