---
title: Bugsy Deployment
tags: [bugsy, deploy, ops, git, docker-compose, n8n-import, terraform]
---

# Deploying changes

Three kinds of changes, three deploy paths.

## Code / config / docker-compose changes

```bash
# On the VM
cd ~/bugsy && git pull
cd ~/agent && docker compose up -d <service>
```

`docker compose up -d` will detect changed env vars / image tags and recreate. If you need to be sure:

```bash
docker compose up -d --force-recreate <service>
```

## n8n workflow changes

n8n stores workflows in its Postgres DB; file changes don't auto-apply. Re-import via the n8n UI:

1. Open the workflow editor for the workflow you want to update
2. Top-right **⋮** → **Import from URL**
3. Paste the raw GitHub URL: `https://raw.githubusercontent.com/anthonycoffey/_agent/main/agent/n8n/workflows/<file>.json`
4. Click **Import**
5. **Save** (Ctrl+S) — easy to miss, import alone doesn't persist
6. Toggle **Active** if it deactivated itself

After editing any workflow JSON, refresh the auto-generated node-reference docs from the local dev machine so they stay in sync:

```bash
node agent/n8n/scripts/generate-workflow-reference.mjs
git add docs/workflows && git commit -m "docs: refresh node reference"
```

See [n8n import workflow](n8n-import.md) for tips on avoiding common pitfalls (path collisions, duplicate workflows, credential references).

## Terraform / infrastructure changes

```powershell
# From the Windows dev machine in tf/
terraform plan
terraform apply

# Force VM replacement if needed:
terraform apply "-replace=google_compute_instance.agent"
```

Replacing the VM means cloud-init re-runs and `~/agent/` is rebuilt from scratch. n8n credentials and workflow JSON in the n8n DB **survive** because they live in the persistent Postgres volume. Job board data, vector store contents, and chat memory survive too — same reason.

## Verifying a deploy worked

```bash
# All containers healthy?
docker compose ps

# Recent logs?
docker logs agent-n8n --tail 30
docker logs agent-postgres --tail 30

# n8n executions
# (open https://n8n.coffey.codes → Executions tab)
```
