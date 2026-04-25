#!/usr/bin/env bash
# Daily backup for the agent stack. Runs from cron as the agent user.
# Dumps Postgres, snapshots Qdrant, exports n8n workflows,
# tars Open WebUI data, and pushes everything to GCS.

set -euo pipefail

DATE=$(date +%Y%m%d-%H%M)
AGENT_DIR="$HOME/agent"
BACKUP_DIR="$HOME/backups/$DATE"
mkdir -p "$BACKUP_DIR"

# Load .env so we have POSTGRES_USER in scope.
set -a
# shellcheck disable=SC1091
source "$AGENT_DIR/.env"
set +a

echo "[$(date -Iseconds)] backup start"

# ---- Postgres (all databases) ----
if docker ps --format '{{.Names}}' | grep -q '^agent-postgres$'; then
    docker exec agent-postgres pg_dumpall -U "$POSTGRES_USER" \
        | gzip > "$BACKUP_DIR/postgres.sql.gz"
    echo "  postgres dumped"
fi

# ---- Qdrant snapshot ----
if docker ps --format '{{.Names}}' | grep -q '^agent-qdrant$'; then
    docker exec agent-qdrant curl -s -X POST http://localhost:6333/snapshots \
        > "$BACKUP_DIR/qdrant-snapshot.json" || true
    echo "  qdrant snapshot metadata saved"
fi

# ---- n8n workflow export (portable JSON) ----
if docker ps --format '{{.Names}}' | grep -q '^agent-n8n$'; then
    docker exec agent-n8n n8n export:workflow --backup --output=/tmp/wf || true
    docker cp agent-n8n:/tmp/wf "$BACKUP_DIR/n8n-workflows" || true
    echo "  n8n workflows exported"
fi

# ---- Open WebUI volume ----
if docker volume ls --format '{{.Name}}' | grep -q '^agent_openwebui-data$'; then
    docker run --rm \
        -v agent_openwebui-data:/data \
        -v "$BACKUP_DIR":/backup \
        alpine tar czf /backup/openwebui-data.tar.gz -C /data .
    echo "  open-webui volume archived"
fi

# ---- Push to GCS ----
# Uses the VM's attached service account; `gsutil` is installed as part of
# google-cloud-cli which ships with the Ubuntu GCE image.
#
# Bucket name is derived from the project ID + suffix (see Terraform backup.tf).
BUCKET=$(gcloud config get-value project 2>/dev/null)-agent-backups-01

if command -v gsutil >/dev/null 2>&1 && [ -n "$BUCKET" ]; then
    gsutil -m rsync -r "$BACKUP_DIR" "gs://$BUCKET/$DATE/" || {
        echo "  gsutil push failed (not fatal)"
    }
fi

# ---- Local rotation (keep last 14 local copies) ----
find "$HOME/backups" -maxdepth 1 -mindepth 1 -type d -mtime +14 -exec rm -rf {} +

echo "[$(date -Iseconds)] backup done -> $BACKUP_DIR"
