#!/bin/bash
# rag-refresh.sh — git pull every symlinked source repo under
# ~/agent/rag/projects/, then re-run the RAG ingest for the projects category.
#
# Designed for cron (4am CT daily). Continues past individual repo failures.
#
# Usage:
#   bash ~/agent/scripts/rag-refresh.sh              # silent (no Slack notification)
#   bash ~/agent/scripts/rag-refresh.sh --notify     # also POST status to n8n
#
# See:
#   docs/specs/archive/SPEC-RAG-001-daily-source-repo-refresh.md
#   docs/operations/rag-refresh.md

set -o pipefail

PROJECTS_DIR="$HOME/agent/rag/projects"
INGEST_SCRIPT="$HOME/agent/rag-ingest.sh"
LOCK="/tmp/rag-refresh.lock"
LOG_DIR="$HOME/agent/logs/rag-refresh"
NOTIFY_URL="https://n8n.coffey.codes/webhook/rag-refresh-notify"

NOTIFY=""
[ "${1:-}" = "--notify" ] && NOTIFY=1

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/$(date +%Y-%m-%dT%H-%M-%S).log"

# Tee everything (stdout + stderr) to the log file.
exec > >(tee -a "$LOG") 2>&1

# Lock so a manual --notify run can't collide with the cron-fired run.
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "another rag-refresh is already running; exiting"
  exit 0
fi

echo "=== rag-refresh @ $(date -Iseconds) ==="

pulled=0
up_to_date=0
failed=0
declare -a failures=()

# Self-discover repos: walk symlinks under projects/, resolve each to its
# git repo root, pull there. Skip anything that isn't a symlink or isn't
# inside a git checkout.
shopt -s nullglob
for link in "$PROJECTS_DIR"/*; do
  if [ ! -L "$link" ]; then
    continue
  fi
  target=$(readlink -f "$link") || {
    echo "skip $(basename "$link"): unreadable symlink"
    continue
  }
  if [ ! -d "$target" ]; then
    echo "skip $(basename "$link"): symlink target missing ($target)"
    continue
  fi
  repo_root=$(cd "$target" && git rev-parse --show-toplevel 2>/dev/null) || {
    echo "skip $(basename "$link"): target not in a git checkout ($target)"
    continue
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
    echo "PULL FAILED for $name:"
    echo "$out"
  fi
done
shopt -u nullglob

echo "--- running rag-ingest.sh projects ---"
if ! bash "$INGEST_SCRIPT" projects; then
  echo "ingest exited non-zero (continuing — partial ingest is still useful)"
fi

summary="pulled:$pulled up-to-date:$up_to_date failed:$failed"
if [ ${#failures[@]} -gt 0 ]; then
  summary="$summary failed_repos:[$(IFS=,; echo "${failures[*]}")]"
fi
echo "=== done — $summary ==="

if [ -n "$NOTIFY" ]; then
  if command -v jq &>/dev/null; then
    payload=$(jq -nc --arg s "$summary" --arg log "$LOG" \
      '{summary:$s, log_path:$log, ts:(now|todateiso8601)}')
  else
    # Minimal fallback if jq is missing — same shape, just less escaped.
    payload="{\"summary\":\"$summary\",\"log_path\":\"$LOG\",\"ts\":\"$(date -Iseconds)\"}"
  fi
  curl -s -X POST "$NOTIFY_URL" \
    -H 'content-type: application/json' \
    -d "$payload" \
    >/dev/null || echo "notify webhook failed (continuing — not fatal)"
fi
