#!/bin/bash
# rag-ingest.sh — embed markdown files from ~/agent/rag/ into Qdrant
#
# Usage:
#   bash ~/agent/rag-ingest.sh              # process all categories
#   bash ~/agent/rag-ingest.sh bio          # process one category only
#
# Prerequisites:
#   - Bugsy RAG Ingest workflow active in n8n
#   - nomic-embed-text pulled: docker exec agent-ollama ollama pull nomic-embed-text

WEBHOOK="https://n8n.coffey.codes/webhook/rag-ingest"
RAG_DIR="$HOME/agent/rag"
TARGET="${1:-}"

if ! command -v jq &>/dev/null; then
  echo "jq is required: sudo apt-get install -y jq"
  exit 1
fi

for category in bio articles case-studies projects; do
  [ -n "$TARGET" ] && [ "$TARGET" != "$category" ] && continue
  dir="$RAG_DIR/$category"
  [ -d "$dir" ] || continue

  while IFS= read -r -d '' f; do
    rel="${f#$dir/}"
    echo -n "→ $category/$rel ... "
    response=$(curl -s -w "\n%{http_code}" -X POST "$WEBHOOK" \
      -H "Content-Type: application/json" \
      -d "{\"category\":\"$category\",\"filename\":\"$category/$rel\",\"content\":$(jq -Rs . < "$f")}")
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | head -1)
    if [ "$http_code" = "200" ]; then
      echo "$body"
    else
      echo "FAILED (HTTP $http_code): $body"
    fi
  done < <(find -L "$dir" -type f -name '*.md' -print0 | sort -z)
done

echo "Done."
