---
title: Bugsy Troubleshooting
tags: [bugsy, troubleshooting, incidents, n8n, docker, debugging]
---

# Troubleshooting

Living list of "this happened, here's the fix." Mostly cribbed from `logs/incident-log.md`.

## n8n: Code node fails with "task runner disconnected"

Generic error appears whenever the runner subprocess dies for any reason. Most common causes:

- **Looping `axios` calls inside one Code node** — the runner subprocess can be killed by n8n's broker when a Code node holds a long sequential await chain. Refactor to native HTTP Request nodes; n8n iterates per item natively, no loop needed.
- **`require('axios')` followed by env access** — the require itself isn't usually the killer; the env access is (`process.env` and `$env` are both blocked in the runner sandbox; trying either throws unrecoverably). Move the secret-using call to a native HTTP Request node with a credential.

## n8n: webhook returns 200 with empty body

The Code node threw before reaching `Respond to Webhook`. Same root cause as above. Open the latest execution → click the red node → read the actual error.

## n8n: `process is not defined` / `access to env vars denied`

The Code node tried to read an env var. n8n's runner sandbox blocks both `process.env` and `$env`. Refactor to a native HTTP Request node that uses `$env.X` in a header expression — that runs on the main process where env access works.

If even that's blocked (some installs), use a stored credential (`Header Auth`, `OpenAI API`, etc.) and reference it via the node's authentication dropdown. Credentials never need env vars at the workflow level.

## n8n: expression appears literally in LLM output (e.g. `{{ $json.context }}`)

The langchain `AI Agent` and its memory sub-node have a restricted expression evaluator. `$('NodeName')` doesn't resolve there. `$json.X` may or may not resolve depending on the field — `systemMessage` is unreliable.

**Fix:** put dynamic content into the `chatInput` field (the user message) inside an upstream Code node. The agent always sees that. Keep `systemMessage` purely static.

## n8n: webhook path conflict on activation

Two workflows have the same webhook path. Deactivate the one you don't want, then activate the new one. Verify with:

```bash
docker exec agent-postgres psql -U $POSTGRES_USER -d n8n -c \
  "select name, active, jsonb_path_query(nodes::jsonb, '\$[*].parameters.path') as path from workflow_entity where active=true;"
```

## Qdrant: `wget` / `curl` not in container

Neither image ships an HTTP client. Spin up a throwaway on the same docker network:

```bash
docker run --rm --network agent_agent-net curlimages/curl:latest \
  -s http://agent-qdrant:6333/collections | jq
```

## Tailscale SSH fails with 502 Bad Gateway / "socket forbidden" — local VPN is on

Symptom (from a Windows machine running NordVPN, ExpressVPN, ProtonVPN, or similar):

```
> tailscale ssh agent@agent-vm
Dial("agent-vm.tailXXXXXX.ts.net.", 22): unexpected HTTP response: 502 Bad Gateway,
dial failure: dial tcp 100.x.x.x:22: connectex: An attempt was made to access a socket
in a way forbidden by its access permissions.

> ssh agent@agent-vm
ssh: connect to host agent-vm port 22: Permission denied
```

`tailscale status` may also show the peer with a bare `-` (no recent contact) instead of `idle`.

**Cause:** consumer VPN clients install a virtual network adapter and an aggressive split-tunnel /
kill-switch policy that captures **all** outbound traffic, including the local Tailscale process.
Tailscale's WireGuard packets get blackholed, the control plane sees the peer as unreachable, and
Windows reports `WSAEACCES (10013)` on the raw socket attempt. **Enabling a VPN while a Tailscale
SSH session is open will terminate the active session too** — not just block new ones.

**Fix:** disconnect the VPN. SSH works immediately, no Tailscale restart needed.

**Workarounds if you need both at once:**

- Configure the VPN client's split-tunnel exclusions to bypass the Tailscale process / the
  `100.64.0.0/10` CGNAT range (NordVPN: Settings → Split Tunneling → Add `tailscaled.exe`).
- Use the GCP IAP tunnel instead, which doesn't depend on Tailscale at all:
  ```powershell
  gcloud compute ssh agent-vm --zone=us-central1-a --tunnel-through-iap --project=bugsy-ai
  ```

Before chasing this as a VM-side problem (expired Tailscale node key, dead `tailscaled`, VM crash),
**first toggle the local VPN off** and retry. It's the single most common cause of "Tailscale was
working yesterday and now it isn't."

## Cloud-init didn't apply my latest change

Cloud-init only runs on the **first boot**. After that, changes to `tf/` cloud-init data are inert until you replace the VM:

```powershell
terraform apply "-replace=google_compute_instance.agent"
```

Most of the time you don't want that — `git pull` + `docker compose up -d` is the deploy path for everything except VM-level setup.

## n8n logs `N8N_RUNNERS_ENABLED -> Remove this environment variable`

Benign. Newer n8n versions made runners default-on; the env var is deprecated but still works. Worth removing on the next docker-compose tidy pass.

## n8n shows "Up" but webhooks 502

Cloudflare can't reach the upstream — usually n8n is still booting after a recreate. Wait ~10s, check `docker logs agent-n8n --tail 5` for "Editor is now accessible", then retry.
