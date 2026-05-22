#!/bin/sh
# run-agent.sh — Invoked by n8n's SSH node via `docker exec -d agent-aider`.
# Creates a branch, runs Aider, pushes, opens a draft PR, posts a comment.
#
# Usage:
#   docker exec -d agent-aider /agent/run-agent.sh \
#     --repo-name=coffey.codes \
#     --issue-number=42 \
#     --issue-title="Fix the nav bug" \
#     --issue-body="Steps to reproduce..."
#
# Optional:
#   --repo-owner=anthonycoffey   (default: anthonycoffey)
#   --base-branch=main           (default: main)
#
# Logs written to /tmp/aider-issue-<N>.log inside the container.
# Inspect with: docker exec agent-aider cat /tmp/aider-issue-42.log

set -e

# ── Parse args ────────────────────────────────────────────────────────────
REPO_OWNER="anthonycoffey"
BASE_BRANCH="main"

for arg in "$@"; do
  case "$arg" in
    --repo-name=*)    REPO_NAME="${arg#*=}" ;;
    --repo-owner=*)   REPO_OWNER="${arg#*=}" ;;
    --base-branch=*)  BASE_BRANCH="${arg#*=}" ;;
    --issue-number=*) ISSUE_NUMBER="${arg#*=}" ;;
    --issue-title=*)  ISSUE_TITLE="${arg#*=}" ;;
    --issue-body=*)   ISSUE_BODY="${arg#*=}" ;;
  esac
done

# ── Validate required args ────────────────────────────────────────────────
if [ -z "$REPO_NAME" ] || [ -z "$ISSUE_NUMBER" ] || [ -z "$ISSUE_TITLE" ]; then
  echo "[run-agent] ERROR: --repo-name, --issue-number, and --issue-title are required."
  exit 1
fi

BRANCH="agent/issue-${ISSUE_NUMBER}-$(date +%s)"
LOG="/tmp/aider-issue-${ISSUE_NUMBER}.log"
WORKSPACE="/workspace/${REPO_NAME}"

# Redirect everything to log from here
exec >> "$LOG" 2>&1

echo ""
echo "========================================="
echo "[run-agent] $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "[run-agent] ${REPO_OWNER}/${REPO_NAME} — Issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}"
echo "[run-agent] Branch: ${BRANCH}"
echo "========================================="

# ── Sanity check workspace ────────────────────────────────────────────────
if [ ! -d "${WORKSPACE}/.git" ]; then
  echo "[run-agent] ERROR: ${WORKSPACE} is missing or not a git repo."
  echo "[run-agent] Clone it first:"
  echo "[run-agent]   docker exec -it agent-aider sh -c 'cd /workspace && git clone https://github.com/${REPO_OWNER}/${REPO_NAME}.git'"
  exit 1
fi

cd "$WORKSPACE"

# ── Branch setup ─────────────────────────────────────────────────────────
git fetch origin
git checkout -b "$BRANCH" "origin/${BASE_BRANCH}"

# ── Run Aider ────────────────────────────────────────────────────────────
# OPENAI_API_BASE and OPENAI_API_KEY are set by docker-compose (→ LiteLLM).
# --yes skips all interactive prompts. --auto-commits is set via .aider.conf.yml.
PROMPT="GitHub Issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}

${ISSUE_BODY}"

echo "[run-agent] Starting Aider..."
aider \
  --model openai/claude-sonnet-4-6 \
  --message "$PROMPT" \
  --yes

echo "[run-agent] Aider finished."

# ── Push branch ───────────────────────────────────────────────────────────
git push origin "$BRANCH"
echo "[run-agent] Branch pushed: ${BRANCH}"

# ── Create draft PR ───────────────────────────────────────────────────────
PR_BODY="Automated PR for issue #${ISSUE_NUMBER}.\n\nCloses #${ISSUE_NUMBER}"

PR_RESPONSE=$(curl -sf -X POST \
  -H "Authorization: Bearer ${GITHUB_TOKEN_AIDER}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/pulls" \
  -d "{
    \"title\": \"[Agent] ${ISSUE_TITLE}\",
    \"body\": \"${PR_BODY}\",
    \"head\": \"${BRANCH}\",
    \"base\": \"${BASE_BRANCH}\",
    \"draft\": true
  }")

PR_URL=$(printf '%s' "$PR_RESPONSE" | grep -o '"html_url":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "[run-agent] Draft PR created: ${PR_URL}"

# ── Comment on the issue ──────────────────────────────────────────────────
curl -sf -X POST \
  -H "Authorization: Bearer ${GITHUB_TOKEN_AIDER}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/issues/${ISSUE_NUMBER}/comments" \
  -d "{\"body\": \"🤖 Agent finished. Draft PR ready for review: ${PR_URL}\"}"

echo "[run-agent] Issue comment posted."
echo "[run-agent] Done."
