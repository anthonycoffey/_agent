---
id: SPEC-RAG-001
title: "Daily refresh of RAG source repos via cron + ingest"
status: complete
created: 2026-05-18
completed: 2026-05-18
author: Anthony Coffey
reviewers: []
affected_repos: [_agent]
---

<!--
2026-05-18 — Architecture + decisions locked in:
  - Host-side cron + bash script (not n8n-only) — n8n container has no
    host filesystem access and rag-ingest.sh shells out to `docker run`,
    so heavy lifting lives on the host
  - Slack notification on every run (one-line summary daily)
  - Channel: #mulberry-street (existing channel, ID C0AV83XUSTU)
  - Immediate Periscope catch-up via manual `bash ~/agent/scripts/rag-refresh.sh`
    once deployed

2026-05-18 — Implementation shipped, end-to-end verified on the VM:
  - rag-refresh.sh runs cleanly, walks the symlinked repos under
    ~/agent/rag/projects/, git-pulls each, runs rag-ingest.sh projects,
    writes per-run log under ~/agent/logs/rag-refresh/
  - bugsy-rag-refresh-notify workflow imported + activated;
    --notify mode posts a one-line summary to #mulberry-street
  - 4am cron line installed in the operator's crontab

  Spec marked complete and moved to specs/archive/. Daily automation
  is live; new symlinks added under ~/agent/rag/projects/ get picked
  up automatically on the next 4am fire.
-->

Status flipped draft → in-progress. Implementation landed in:
  - agent/scripts/rag-refresh.sh           (the meat)
  - agent/n8n/workflows/bugsy-rag-refresh-notify.json   (the optional notify shim)
  - docs/operations/rag-refresh.md         (install + verify procedure)
-->

## Reviewer Notes

<!-- Leave empty until code review. Reviewer adds feedback here when requesting changes. -->

---

# Feature: Daily refresh of RAG source repos via cron + ingest

## Problem

External-repo content (e.g. [`coffey.codes`](../../../agent/rag/projects/coffey-codes), and now also `@anthonycoffey/periscope` per chat thread 2026-05-18) is added to Bugsy's knowledge base via the clone + symlink pattern: clone to `~/<repo>/`, symlink `~/<repo>/docs` under `~/agent/rag/projects/<repo>`, run `bash ~/agent/rag-ingest.sh projects`. See [`project_rag_source_repos.md`](memory).

Today, refreshes are manual. Whenever a source repo changes (new SEO scripts in `periscope`, new case studies in `coffey.codes`, etc.), Bugsy keeps serving stale information until somebody SSHes in and runs `git pull && bash ~/agent/rag-ingest.sh projects`. Concrete failure mode hit 2026-05-18: Bugsy described `periscope` Phases B+C as "out of scope for now / future SPEC-024 and SPEC-025" when Anthony has already shipped them — because the source repo's updated docs were never re-ingested.

We want a daily automated refresh: pull every source repo, re-ingest, log success/failure. Hands-off after setup.

## Requirements

### Must have

1. WHEN it is 4:00 AM CT on any day of the week, the system SHALL `git pull` every source repo whose docs are symlinked under `~/agent/rag/projects/` and then run `bash ~/agent/rag-ingest.sh projects`.
2. WHEN any `git pull` fails (network error, merge conflict, missing branch), the system SHALL log the failure but CONTINUE to the next repo — one bad repo must not block refresh of the others.
3. WHEN any `git pull` succeeds with no new commits, the system SHALL still run the subsequent re-ingest pass (cheap and ensures Qdrant catches up if a prior ingest was interrupted).
4. WHEN the run completes, the system SHALL emit a single summary line to a structured log on the host (one file per run or appended to a rolling log; user's pick — see Open Questions).
5. The script SHALL be self-discovering — no hardcoded repo list. It walks `~/agent/rag/projects/*`, resolves symlinks, and uses the resolved target's git repo root.
6. The script SHALL be deployed via the existing `git pull` flow (committed to this repo at `agent/scripts/rag-refresh.sh`, executable on the VM via the existing `~/agent` → `~/bugsy/agent` symlink).

### Nice to have

- Slack notification to `#mulberry-street` (or a dedicated `#agent-logs`-style channel) on completion, with per-repo status and total chunk counts.
- An on-demand trigger (e.g. `/refresh-rag` slash command or `bash ~/agent/rag-refresh.sh`) for "run it now" cases like the Periscope catch-up.
- Hold a lock file so a manual run can't collide with the cron-fired run.

### Non-goals (what this does NOT do)

- Does NOT manage repo cloning — repos are still cloned manually the first time per `project_rag_source_repos.md`. The daily job only refreshes already-cloned repos.
- Does NOT touch the `bio`, `articles`, `case-studies` categories — only `projects/` (the symlink-driven category). Other categories are hand-curated and refresh on demand.
- Does NOT manage `.git` credentials — repos must already have working remotes (HTTPS-with-cached-creds or SSH-key auth) on the VM.
- Does NOT replace `rag-ingest.sh`. It wraps it.

## Design

### Architecture: host-side cron, not n8n

The n8n container has no access to the host filesystem and no `git` binary, and `rag-ingest.sh` shells out to `docker run` for its Qdrant cleanup — which doesn't work inside another container without docker-in-docker. So the heavy lifting lives on the host. n8n is involved only (optionally) for Slack notification at the end.

```
host:                                      n8n container:
  cron 0 4 * * *                              webhook /rag-refresh-notify  (optional)
    └─ /home/agent/agent/scripts/rag-refresh.sh      │
         ├─ for each repo under ~/agent/rag/projects/        │
         │    └─ cd <repo-root> && git pull                  │
         ├─ bash ~/agent/rag-ingest.sh projects              │
         └─ curl POST status payload ────────────────────────┘
                                                  └─ Slack post → #mulberry-street
```

### Script: `agent/scripts/rag-refresh.sh`

Self-discovering, idempotent, exit-non-zero only on unrecoverable errors:

```bash
#!/bin/bash
# rag-refresh.sh — git pull every symlinked source repo under
# ~/agent/rag/projects/, then re-run the RAG ingest for that category.
#
# Designed for cron. Continues past individual repo failures.
#
# Usage:
#   bash ~/agent/scripts/rag-refresh.sh          # cron mode (no Slack)
#   bash ~/agent/scripts/rag-refresh.sh --notify # also POST status to n8n

set -o pipefail

PROJECTS_DIR="$HOME/agent/rag/projects"
INGEST_SCRIPT="$HOME/agent/rag-ingest.sh"
LOCK="/tmp/rag-refresh.lock"
LOG_DIR="$HOME/agent/logs/rag-refresh"
NOTIFY=""
[ "$1" = "--notify" ] && NOTIFY=1

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/$(date +%Y-%m-%dT%H-%M-%S).log"

exec > >(tee -a "$LOG") 2>&1

# Lock so manual + cron runs don't collide.
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "another rag-refresh is already running; exiting"
  exit 0
fi

echo "=== rag-refresh @ $(date -Iseconds) ==="

pulled=0; failed=0; up_to_date=0
declare -a failures=()

for link in "$PROJECTS_DIR"/*; do
  [ -L "$link" ] || continue
  target=$(readlink -f "$link") || { echo "skip $link: unreadable"; continue; }
  # Symlink points to <repo>/docs; the repo root is one level up.
  repo_root=$(cd "$target" && git rev-parse --show-toplevel 2>/dev/null) || {
    echo "skip $(basename "$link"): not a git checkout"; continue
  }
  name=$(basename "$repo_root")
  echo "--- $name ($repo_root) ---"
  if out=$(cd "$repo_root" && git pull --ff-only 2>&1); then
    if echo "$out" | grep -q "Already up to date"; then
      up_to_date=$((up_to_date + 1))
    else
      pulled=$((pulled + 1))
    fi
    echo "$out"
  else
    failed=$((failed + 1))
    failures+=("$name")
    echo "PULL FAILED for $name: $out"
  fi
done

echo "--- running rag-ingest.sh projects ---"
bash "$INGEST_SCRIPT" projects || echo "ingest exited non-zero (continuing)"

summary="pulled:$pulled up-to-date:$up_to_date failed:$failed"
[ ${#failures[@]} -gt 0 ] && summary="$summary failed_repos:[${failures[*]}]"
echo "=== done — $summary ==="

if [ -n "$NOTIFY" ]; then
  curl -s -X POST "https://n8n.coffey.codes/webhook/rag-refresh-notify" \
    -H 'content-type: application/json' \
    -d "$(jq -nc --arg s "$summary" --arg log "$LOG" \
          '{summary:$s, log_path:$log, ts:now|todateiso8601}')" \
    || true
fi
```

Key design choices:

- **`git pull --ff-only`** — refuses merges. If the VM-side branch has drifted (someone hand-edited a clone), the pull fails loud rather than creating a merge commit on a server you didn't intend to mutate.
- **Self-discovery via `readlink -f` + `git rev-parse --show-toplevel`** — works regardless of how the symlink points (top-level vs nested docs/ dir), as long as the target is inside a git checkout. Honors the existing `project_rag_source_repos.md` convention without hardcoding repo names.
- **Lock file via `flock`** — prevents cron + manual `--notify` runs from colliding.
- **Per-run log file** — `~/agent/logs/rag-refresh/<ISO>.log`. Easier to bisect failures than a rolling log. Cleanup-aged-logs out of scope for v1; if it becomes a disk issue, add a 30-day prune.
- **Non-zero-exit only on lock contention or scripting bugs** — repo failures and ingest exit codes are tolerated so cron doesn't email mail-spam on transient issues.

### Cron entry

Installed manually on the VM (one-time):

```cron
0 4 * * * /bin/bash $HOME/agent/scripts/rag-refresh.sh --notify >/dev/null 2>&1
```

Uses `--notify` so the run posts a Slack summary. If the notify webhook isn't set up yet, the script still works; the curl just fails silently (`|| true`).

### Optional n8n notification workflow

`agent/n8n/workflows/bugsy-rag-refresh-notify.json` (new), shape cribbed from the existing `bugsy-jira-digest.json` final-Slack-post pattern:

```
[webhook POST /rag-refresh-notify] → [Format Slack message] → [Post to #mulberry-street]
```

Receives the JSON from `rag-refresh.sh`, formats a one-line summary (with `:warning:` emoji if `failed > 0`), posts to Slack with `unfurl_links: false`. Mirrors the FRESH/STALE pattern of past digest fixes.

## Edge cases

- [ ] **Symlink points at a non-git directory.** Skip with a log line, continue.
- [ ] **Symlink target deleted.** `readlink -f` returns the dangling path; `git rev-parse` fails; skip + log.
- [ ] **Repo has uncommitted changes / dirty working tree.** `git pull --ff-only` refuses; logged as failure, continues.
- [ ] **Repo's remote is unreachable** (network blip, GitHub down). Logged as failure, the next day's run picks it up.
- [ ] **`rag-ingest.sh` itself is mid-rewrite and exits non-zero.** The summary still posts; we just continue.
- [ ] **`projects/` dir doesn't exist.** The `for link in $PROJECTS_DIR/*` loop yields a literal `$PROJECTS_DIR/*` which then fails the `[ -L "$link" ]` check; net result is zero repos processed, ingest runs anyway (which is a no-op when the dir is empty). Safe.
- [ ] **Cron runs while a manual `bash rag-refresh.sh` is already running.** `flock -n 9` short-circuits the second invocation with exit 0.

## Acceptance criteria

1. `agent/scripts/rag-refresh.sh` exists, is executable, passes a manual run on the VM (with `--notify` omitted) and prints a one-line summary.
2. The script's per-repo logging is readable in `~/agent/logs/rag-refresh/<ISO>.log`.
3. After deploy, running the script with one source repo intentionally broken (e.g. local commits added on the VM) — script logs the failure, continues to the next repo, ingest still runs, summary reports `failed:1 failed_repos:[<name>]`.
4. Cron line installed; next 4am run completes without manual intervention.
5. (If notification workflow shipped) Slack `#mulberry-street` receives a one-line summary on each run.

## Constraints

- No commits land until each step has been verified per the project's `verify before commit` rule.
- Script must work with the existing `~/agent` → `~/bugsy/agent` symlink — i.e. file paths under `~/agent/scripts/` resolve to `~/bugsy/agent/scripts/` after deploy.
- Must not require new env vars or secrets.
- Lock file in `/tmp` — survives across reboots cleanly (cleared at boot).

## Tasks

- [ ] Write `agent/scripts/rag-refresh.sh` per the design above.
- [ ] Make it executable (`chmod +x`) and ensure git records the executable bit.
- [ ] (Optional, if approved) Write `agent/n8n/workflows/bugsy-rag-refresh-notify.json` cribbing the Slack-post pattern from `bugsy-jira-digest.json`.
- [ ] Document the cron line + manual-trigger one-liner in `docs/workflows/` (or a new `docs/operations/rag-refresh.md` if the workflow doesn't live in n8n).
- [ ] On the VM, install the cron line + verify with `crontab -l`.
- [ ] Manual test: trigger the script by hand, eyeball the log + Slack post.
- [ ] Verify next-morning automated run.

## Open questions (need user input before implementation)

These are picked out below in an `AskUserQuestion` — the spec is paused at `status: draft` until the answers come back.

1. **Slack notification on every run, or only on failure?** Every run is more visible but noisier; on-failure-only is cleaner but you might not notice if the cron silently stops firing.
2. **Notification channel.** `#mulberry-street` (where everything else goes) or a dedicated channel like `#agent-logs`?
3. **Immediate Periscope catch-up.** Run the manual one-liner right now, or wait for the first 4am fire to refresh?

## Notes

- The host-cron decision was a deliberate FOSS-first / "use the right tool" call. An n8n-only design would have required mounting `~/agent/rag/` and the source-repo checkouts into the n8n container, installing git + jq + docker-cli in the container, plus credential management — none of which are required for a 4-line cron entry.
- The `rag-refresh.sh` script is intentionally separate from `rag-ingest.sh`. Refresh = "pull then ingest"; ingest = "embed local files." Keeping them split means the ingest script stays useful for the bio/articles/case-studies categories which don't have git remotes.
- If/when more host-side cron jobs accrete (log rotation, certificate renewal, etc.), this is the first one — establish the pattern of `agent/scripts/*.sh` + per-script logs under `~/agent/logs/<name>/`.
