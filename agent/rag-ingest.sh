#!/bin/bash
# rag-ingest.sh — embed markdown files from ~/agent/rag/ into Qdrant
#
# Usage:
#   bash ~/agent/rag-ingest.sh              # process all categories
#   bash ~/agent/rag-ingest.sh bio          # process one category only
#
# Cleanup behavior (runs automatically):
#   1. Shrink-orphans — after each successful ingest, any chunks for that filename
#      whose chunk_index >= the new total get purged. Handles docs that got shorter.
#   2. Rename/delete-orphans — at end of each category, any filename present in
#      Qdrant under that category but NOT in the local file set gets purged whole.
#      Handles renames + deletions in source repos.
#
#   Both cleanups are scoped per-category and skipped entirely if the category had
#   zero local files (guards against wiping a category when its dir is empty/missing).
#
# Prerequisites:
#   - Bugsy RAG Ingest workflow active in n8n
#   - nomic-embed-text pulled: docker exec agent-ollama ollama pull nomic-embed-text
#   - docker network `agent_agent-net` reachable from the host (for cleanup curl)

set -o pipefail

WEBHOOK="https://n8n.coffey.codes/webhook/rag-ingest"
RAG_DIR="$HOME/agent/rag"
QDRANT_URL="http://agent-qdrant:6333"
TARGET="${1:-}"

if ! command -v jq &>/dev/null; then
  echo "jq is required: sudo apt-get install -y jq"
  exit 1
fi

qdrant_curl() {
  docker run --rm --network agent_agent-net curlimages/curl:latest "$@"
}

# Delete chunks for a given filename whose chunk_index >= cutoff (shrink-orphans).
qdrant_shrink() {
  local fname="$1" cutoff="$2"
  local payload
  payload=$(jq -nc --arg f "$fname" --argjson c "$cutoff" \
    '{filter:{must:[{key:"filename",match:{value:$f}},{key:"chunk_index",range:{gte:$c}}]}}')
  qdrant_curl -s -o /dev/null -X POST \
    "$QDRANT_URL/collections/personal_knowledge/points/delete" \
    -H "Content-Type: application/json" \
    -d "$payload"
}

# Delete every chunk for a given filename (whole-file orphan).
qdrant_purge_filename() {
  local fname="$1"
  local payload
  payload=$(jq -nc --arg f "$fname" \
    '{filter:{must:[{key:"filename",match:{value:$f}}]}}')
  qdrant_curl -s -o /dev/null -X POST \
    "$QDRANT_URL/collections/personal_knowledge/points/delete" \
    -H "Content-Type: application/json" \
    -d "$payload"
}

# Print every distinct filename currently in Qdrant for a category (one per line).
qdrant_filenames_in_category() {
  local category="$1"
  local offset='null'
  while :; do
    local payload body
    payload=$(jq -nc --arg cat "$category" --argjson off "$offset" \
      '{limit:1000,with_payload:["filename"],with_vector:false,filter:{must:[{key:"category",match:{value:$cat}}]},offset:$off}')
    body=$(qdrant_curl -s -X POST \
      "$QDRANT_URL/collections/personal_knowledge/points/scroll" \
      -H "Content-Type: application/json" \
      -d "$payload")
    echo "$body" | jq -r '.result.points[].payload.filename // empty'
    local next
    next=$(echo "$body" | jq -c '.result.next_page_offset')
    [ "$next" = "null" ] && break
    offset="$next"
  done | sort -u
}

for category in bio articles case-studies projects; do
  [ -n "$TARGET" ] && [ "$TARGET" != "$category" ] && continue
  dir="$RAG_DIR/$category"
  [ -d "$dir" ] || continue

  declare -A seen=()

  while IFS= read -r -d '' f; do
    rel="${f#$dir/}"
    key="$category/$rel"
    seen[$key]=1
    echo -n "→ $key ... "
    response=$(curl -s -w "\n%{http_code}" -X POST "$WEBHOOK" \
      -H "Content-Type: application/json" \
      -d "{\"category\":\"$category\",\"filename\":\"$key\",\"content\":$(jq -Rs . < "$f")}")
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | head -1)
    if [ "$http_code" = "200" ]; then
      echo "$body"
      # Shrink threshold = total chunks the parser produced, NOT chunks actually
      # stored. count = successful upserts; failed = embed timeouts. total = both,
      # which is the upper bound on chunk_index for this file. Using `count` would
      # delete freshly-upserted chunks when any embed failed.
      count=$(echo "$body" | sed -n 's/^✓ \([0-9]\+\) chunks.*/\1/p')
      failed=$(echo "$body" | sed -n 's/.*(\([0-9]\+\) chunks dropped.*/\1/p')
      [ -z "$failed" ] && failed=0
      if [ -n "$count" ]; then
        total=$((count + failed))
        qdrant_shrink "$key" "$total"
      fi
    else
      echo "FAILED (HTTP $http_code): $body"
    fi
  done < <(find -L "$dir" -type f -name '*.md' -print0 | sort -z)

  if [ ${#seen[@]} -gt 0 ]; then
    echo "→ orphan check ($category): comparing ${#seen[@]} local files against Qdrant"
    orphans=0
    while IFS= read -r qf; do
      [ -z "$qf" ] && continue
      if [ -z "${seen[$qf]:-}" ]; then
        echo "  orphan: $qf → purging"
        qdrant_purge_filename "$qf"
        orphans=$((orphans + 1))
      fi
    done < <(qdrant_filenames_in_category "$category")
    echo "  $orphans orphan(s) purged"
  else
    echo "→ skipping orphan check ($category): no local files"
  fi

  unset seen
done

echo "Done."
