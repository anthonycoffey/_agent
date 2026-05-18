---
title: Daily RAG source-repo refresh
tags: [bugsy, rag, cron, ops]
---

# Daily RAG source-repo refresh

Bugsy's RAG index includes content from external git repos symlinked under `~/agent/rag/projects/` (e.g. `coffey.codes`, `periscope`). Without automation, those repos go stale and Bugsy quotes outdated info. This procedure refreshes them every morning.

For the architectural reasoning, see [SPEC-RAG-001](../specs/active/SPEC-RAG-001-daily-source-repo-refresh.md) (once archived: `specs/archive/`).

## What the script does

[`agent/scripts/rag-refresh.sh`](../../agent/scripts/rag-refresh.sh) runs on the host VM:

1. Walks every symlink under `~/agent/rag/projects/`
2. For each: resolves to a git repo root via `git rev-parse --show-toplevel`
3. `git pull --ff-only` in that root (no merge commits; pull fails loud if branches diverged)
4. Tallies `pulled` / `up-to-date` / `failed`
5. Runs `bash ~/agent/rag-ingest.sh projects` to re-embed everything
6. With `--notify`, POSTs a one-line JSON summary to `https://n8n.coffey.codes/webhook/rag-refresh-notify`, which formats and posts to `#mulberry-street`

Self-discovering — no hardcoded repo list. Any new repo you add via the [clone + symlink pattern](../../CLAUDE.md) is picked up automatically on the next run.

## Logs

Each run writes a full log to `~/agent/logs/rag-refresh/<ISO>.log`. One file per run; no rolling. Grep that directory to bisect failures across days.

## Installing the daily 4am cron

One-time setup on the VM:

```bash
# Append the cron line (idempotent — uses `crontab -l` + grep to avoid duplicates).
(crontab -l 2>/dev/null | grep -v 'rag-refresh.sh'; \
 echo '0 4 * * * /bin/bash $HOME/agent/scripts/rag-refresh.sh --notify >/dev/null 2>&1') \
  | crontab -

# Verify
crontab -l | grep rag-refresh
```

Cron's `0 4 * * *` interprets in the VM's configured timezone. Per the existing stack (see `agent/docker-compose.yml` `TZ` env var and other n8n cron entries), that should already be `America/Chicago`, giving you **4:00 AM CT every day**. Confirm with:

```bash
date  # should show CDT/CST
```

If the VM clock is in UTC instead, change the cron to `0 9 * * *` for 4am CT in the summer (CDT = UTC−5) or `0 10 * * *` in the winter (CST = UTC−6). Long-term cleanest: ensure the VM is in `America/Chicago` and leave the cron at `0 4 * * *`.

## Manual trigger (catch-up runs)

To refresh on-demand without waiting for cron:

```bash
# Silent — log only, no Slack post
bash ~/agent/scripts/rag-refresh.sh

# With Slack post to #mulberry-street
bash ~/agent/scripts/rag-refresh.sh --notify
```

A `flock` guards against a manual run colliding with the cron-fired run — the second invocation exits cleanly with no action.

## Verifying after a run

Inside the VM:

```bash
# Latest log
ls -t ~/agent/logs/rag-refresh/ | head -1
cat ~/agent/logs/rag-refresh/$(ls -t ~/agent/logs/rag-refresh/ | head -1)

# Should end with: === done — pulled:N up-to-date:M failed:0 ===
```

In Slack `#mulberry-street`:

- Success: `:white_check_mark: *rag-refresh* \`pulled:2 up-to-date:1 failed:0\` _at 2026-05-18T09:00:00Z_`
- Failure: `:warning: *rag-refresh* — needs a look \`pulled:1 ... failed:1 failed_repos:[periscope]\` _at ..._\nlog: \`/home/agent/agent/logs/rag-refresh/...log\``

## Importing the notification workflow

[`agent/n8n/workflows/bugsy-rag-refresh-notify.json`](../../agent/n8n/workflows/bugsy-rag-refresh-notify.json) holds the n8n side. Three nodes: webhook → format → Slack post. Per the [file-based import flow](../../CLAUDE.md):

1. n8n UI → ⋮ → **Import from File** → pick the local JSON
2. Save → **Activate**
3. Test by running the script manually with `--notify` and watching `#mulberry-street`

## Troubleshooting

| Symptom | Likely cause | Where to look |
|---|---|---|
| Cron silently doesn't fire | VM clock in wrong TZ, or cron daemon stopped | `systemctl status cron`; `date`; `grep CRON /var/log/syslog` |
| `PULL FAILED` for a repo every day | Local commits on the VM diverged from remote, or remote auth broken | `cd ~/<repo> && git status` — likely uncommitted/local-only changes; clean up or move to a branch |
| Slack post never arrives | Notify workflow not active, or webhook URL wrong | n8n UI → workflow → check Active + execution history |
| `ingest exited non-zero` line in log | Single chunk timeout on Ollama embed | Usually self-healing on next run; investigate if it persists for the same file |
| Log dir filling disk | Per-run files accumulating | One-shot cleanup: `find ~/agent/logs/rag-refresh -mtime +30 -delete`. Long-term: add a prune to the script. |

## What it doesn't do

- Doesn't clone new repos. First-time additions still follow the [clone + symlink pattern](../../CLAUDE.md). Once the symlink is in place, the daily job picks it up automatically.
- Doesn't refresh the `bio`, `articles`, or `case-studies` categories — those are hand-curated and have no git remote. Refresh them with `bash ~/agent/rag-ingest.sh <category>` when you change a file.
- Doesn't manage `.git` credentials. Repos must already authenticate cleanly (HTTPS-with-cached-creds or SSH key) from the agent user on the VM.
