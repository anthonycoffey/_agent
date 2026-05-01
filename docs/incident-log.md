# Incident Log

Chronological record of issues hit during initial deployment. Kept for
future reference so we don't re-learn the same lessons.

## 2026-04-24 — Initial deploy session

### Incident #1: cloud-init silently no-op'd

**Symptom:** VM came up, but none of the expected tools (Docker, Tailscale)
were installed. `~/agent/` directory didn't exist. `sudo cloud-init status`
showed completion in 24 seconds (real runs take 3-5 minutes).

**Log signature:**
```
WARNING: Unhandled non-multipart (text/x-not-multipart) userdata: 'b'H4sIAAAAAAAA/6R765KjuLLu'...'
```

The `H4sIAAAA` prefix is the base64-encoded header of a gzipped blob.

**Root cause:** `cloudinit_config` data source in Terraform had
`gzip = true, base64_encode = true`. These flags are designed for AWS EC2,
not GCE. GCE's metadata server delivers user-data directly to cloud-init,
which expected plain text YAML and didn't know how to decode the
double-encoded blob.

**Fix:**
```hcl
data "cloudinit_config" "agent_vm" {
  gzip          = false
  base64_encode = false
  ...
}
```

**How we resolved:** Forced VM replacement via
`terraform apply "-replace=google_compute_instance.agent"`.

**Prevention:** Documented in `docs/reference/design-decisions.md`. Any
future Terraform module for GCE should set both flags to `false`.

---

### Incident #2: cloud-init user creation failed

**Symptom:** After the encoding fix, cloud-init got much further but
crashed in the `write_files` module:
```
('write_files', OSError('Unknown user or group: "getpwnam(): name not found: \'agent\'"'))
```

Packages installed (Docker, Tailscale visible), Tailscale joined the
tailnet, UFW configured, but `~/agent/` was empty.

**Root cause:** `enable-oslogin=TRUE` in VM metadata silently suppresses
cloud-init's top-level `users:` block. When `write_files` then tries to
create files owned by the (nonexistent) `agent` user, the module fails
entirely. Subsequent `runcmd` entries ran but were no-ops because their
target files weren't on disk.

**Fix (not yet applied to VM):**
1. Remove `users:` block from `cloud-init/agent-vm.yaml.tftpl`
2. Add `bootcmd:` section that creates the user before `write_files`:
   ```yaml
   bootcmd:
     - useradd --create-home --shell /bin/bash --groups sudo agent 2>/dev/null || true
     - echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-agent
     - chmod 0440 /etc/sudoers.d/90-agent
   ```

**Workaround (what we did):** Manually scp'd files to the VM and built
`.env` from Terraform state. See `docs/runbooks/secret-extraction.md`.

**Prevention:** The fix is documented but not yet in the TF source.
Applying it is the first task of the next work session.

---

### Incident #3: Tailscale SSH failures on Windows

Multiple related issues:

**3a — Strict host key check fails on first connection**
```
No ED25519 host key is known for agent-vm.tail9ed101.ts.net.
Host key verification failed.
```

Workaround: use plain `ssh` over the Tailnet instead of `tailscale ssh`.

**3b — `tailscale ssh` tries to resolve user locally on Windows**
```
tailscale: failed to look up local user "agent"
Connection closed by UNKNOWN port 65535
```

**Root cause:** `tailscale ssh` on Windows assumes Unix-style user
resolution — tries to match `agent` against a local Windows account
before connecting. Known papercut.

**Workaround:** `ssh agent@agent-vm` (plain ssh, lets the VM resolve the user).

**3c — Tailscale ACL didn't allow SSH to tagged machines**
```
Tailscale SSH enabled, but access controls don't allow anyone to access this device.
```

**Fix:** Added to Tailnet ACL (`https://login.tailscale.com/admin/acls`):
```json
"ssh": [
  {
    "action": "accept",
    "src":    ["autogroup:member"],
    "dst":    ["tag:agent"],
    "users":  ["autogroup:nonroot", "root"]
  }
]
```

---

### Incident #4: PowerShell arg parsing

**Symptom:**
```
terraform apply -replace=google_compute_instance.agent
→ Error: Invalid force-replace address "google_compute_instance"
```

**Root cause:** PowerShell parses the dot-separated resource address
and strips everything after the dot.

**Fix:** Quote the entire flag:
```powershell
terraform apply "-replace=google_compute_instance.agent"
```

**Prevention:** Noted in `docs/runbooks/initial-deploy.md` under "PowerShell
gotchas."

---

### Incident #5: Sensitive values masked in `terraform state show`

**Symptom:** Couldn't pull `random_password` values for manual `.env`
construction. `terraform state show` displayed `(sensitive value)`.

**Fix:** Used `terraform show -json` + PowerShell filtering:
```powershell
terraform show -json | ConvertFrom-Json |
  Select-Object -ExpandProperty values |
  Select-Object -ExpandProperty root_module |
  Select-Object -ExpandProperty resources |
  Where-Object { $_.type -eq "random_password" } |
  ForEach-Object { "$($_.name) = $($_.values.result)" }
```

**Note:** `(sensitive value)` is a display filter only; actual plaintext
is in the state file. Future version of TF module should expose secrets
through a dedicated `output "secrets" { sensitive = true }` for cleaner
extraction.

---

## 2026-04-25 — Repo restructure session

### Incident #6: `/home/agent` owned by root after first boot

**Symptom:** Trying to `mv ~/agent ~/agent.bak` from the agent user
failed with `Permission denied`, even though `~/agent` itself is owned
by `agent:agent`.

**Diagnosis:** `/home/agent` was owned `root:root 0755`. Renaming a
directory needs write permission on the *parent*, so agent couldn't
mutate anything at the top level of its own home.

**Root cause (suspected):** cloud-init's bootcmd runs
`useradd --create-home` and then `chown -R agent:agent /home/agent`,
which should produce an agent-owned home. But OS Login provisions home
directories on first SSH login, and likely re-created `/home/agent`
itself (root-owned) after cloud-init ran, leaving the contents
agent-owned but the parent dir not.

**Fix on the live VM:**
```bash
sudo chown agent:agent /home/agent
sudo chmod 0755 /home/agent
```

**Prevention (not yet applied to TF):** Add a runcmd at the very end of
`cloud-init/agent-vm.yaml.tftpl` that re-asserts ownership *after* OS
Login has had a chance to touch the directory:
```yaml
runcmd:
  - ...
  - chown agent:agent /home/agent && chmod 0755 /home/agent
```
A simpler alternative is a systemd one-shot service that runs on every
boot and idempotently fixes the ownership.

---

### Incident #7: LiteLLM crash-loop — `config.yaml` was a directory, not a file

**Symptom:** n8n's OpenAI credential test against `http://litellm:4000/v1`
returned "couldn't connect with these settings." Direct probe inside the
docker network confirmed nothing was listening:

```
$ docker exec agent-n8n wget http://litellm:4000/v1/models
wget: can't connect to remote host (172.18.0.6): Connection refused
```

`docker ps` showed `agent-litellm` as `Up`, masking the real state — the
container's main process had crashed and supervised restart was in
progress. Logs revealed:

```
File "/usr/lib/python3.13/site-packages/litellm/proxy/proxy_server.py",
  line 2334, in _get_config_from_file
    with open(f"{file_path}", "r") as config_file:
IsADirectoryError: [Errno 21] Is a directory: '/app/config.yaml'
```

On the host:

```
$ ls -la ~/agent/litellm/
drwxr-xr-x 2 root root 4096 Apr 25 00:36 config.yaml   ← a directory!
```

**Root cause:** When the bind-mount source path
`~/agent/litellm/config.yaml` did not exist at the moment the container
was first started, Docker's bind-mount logic created it. Docker has no
way to know whether the mount target inside the container is meant to
be a file or a directory, so it **defaults to creating a directory**
on the host side. LiteLLM then tried to read that "config file" and
crashed because it was a directory.

This is a long-standing Docker footgun: a missing bind-mount source is
silently created as a directory, owned by `root` (since the Docker
daemon runs as root), regardless of the parent directory's owner.

The condition arose because:

1. The compose file declares `./litellm/config.yaml:/app/config.yaml:ro`
2. We had created the *parent* directory `agent/litellm/` in the repo,
   tracked with a `.gitkeep`, but **no `config.yaml` file**
3. On the VM, after `docker compose up -d`, Docker found no file at
   `~/agent/litellm/config.yaml` → auto-created it as a root-owned
   directory → LiteLLM crashed → repeat forever

**Why a simple restart wasn't enough:** After we wrote a real
`config.yaml` and ran `docker compose up -d litellm`, the start failed
with:

```
Error response from daemon: failed to create task for container:
  ... mount src=/home/agent/agent/litellm/config.yaml,
      dst=/app/config.yaml ... not a directory
```

Even though the host file was now correct, the existing container's
mount spec had been negotiated and cached when the source was a
directory. Docker tried to bind-mount a *file* over the original
*directory* mountpoint — different mount semantics, refused.

**Fix on the live VM:**

1. Stop the misconfigured container so its mount handle releases:
   ```bash
   cd ~/agent && docker compose stop litellm
   ```
2. Remove the bogus auto-created directory:
   ```bash
   rm -rf ~/agent/litellm/config.yaml
   ```
3. Pull the real config from the repo (we'd added it in a prior commit):
   ```bash
   cd ~/bugsy && git pull
   ```
4. **Recreate** the container, not just restart — needed so Docker
   re-reads the mount source freshly:
   ```bash
   cd ~/agent && docker compose rm -sf litellm && docker compose up -d litellm
   ```
5. Verify after first-boot prisma migrations finish (~30s):
   ```bash
   docker logs --tail 20 agent-litellm
   curl -H "Authorization: Bearer $WEBUI_SECRET_KEY" http://litellm:4000/v1/models
   ```

**Prevention — three layers:**

1. **Never bind-mount a missing file.** Either commit the real file to
   the repo (now done — `agent/litellm/config.yaml` is tracked), or use
   a named volume + an init container to seed the file. The empty
   `.gitkeep`-only directory we had was actively dangerous because it
   *partially* satisfied the path while leaving the leaf node missing.

2. **For Terraform / fresh deploys:** the long-term fix is to stop
   relying on `cloud-init` to deliver runtime files via `filebase64`
   altogether. Per the [decisions log](../docs/decisions.md), `~/agent`
   is now a symlink into `~/bugsy/agent`, which is a `git clone` of the
   repo. A fresh deploy should:

   - Have cloud-init `git clone` the repo into `~/bugsy`
   - Symlink `~/agent` → `~/bugsy/agent`
   - Then run `docker compose up -d`

   That way every tracked file (including `litellm/config.yaml`) is
   present *before* Docker starts, and we never trigger the
   missing-source auto-create behavior. The current cloud-init still
   uses `filebase64` for a fixed list of files; it should be
   refactored to clone instead. **TODO** — open task for the next TF
   pass.

3. **Make Docker fail loudly on missing bind sources.** Compose v2.20+
   supports `bind: { create_host_path: false }` which makes the
   container fail to start instead of silently creating a directory:

   ```yaml
   volumes:
     - type: bind
       source: ./litellm/config.yaml
       target: /app/config.yaml
       read_only: true
       bind:
         create_host_path: false
   ```

   Worth adopting for every bind mount in
   [agent/docker-compose.yml](../agent/docker-compose.yml). Loud failure
   beats silent corruption every time.

**Diagnostic lesson:** `docker ps` showed `Up` because Docker's restart
policy was holding the container in a respawn loop — the *latest*
attempt was up for a few seconds before crashing again. Always pair
`docker ps` with `docker logs --tail N` when behavior doesn't match
status, and use `docker inspect <name> --format '{{.State.Status}} {{.RestartCount}}'`
to see the restart count, which is the real tell.

---

## 2026-05-01 — Job board fetcher session

### Incident #8: n8n Code node sandbox has no HTTP primitives

**Symptom:** The job board fetcher workflow was written to use a single
Code node that looped over job board URLs and fetched each one. Two
approaches were tried in sequence:

**Attempt 1 — `$helpers.httpRequest`:**
```
$helpers is not defined
```

**Attempt 2 — native `fetch`:**
```
fetch is not defined
```

Both failed at runtime inside the n8n Code node sandbox.

**Root cause:** n8n's Code node runs in a restricted Node.js VM context.
The `$helpers` object is documented in older n8n versions but is not
exposed in the current runner. The global `fetch` (available in Node 18+)
is also not injected into the sandbox. The sandbox provides plain
JavaScript plus n8n's own `$input`, `$json`, `$node`, etc. helpers — but
no outbound HTTP capability of its own.

**Workaround applied (before the real fix):** Replaced the Code node with
22 individual HTTP Request nodes chained sequentially, one per job board.
All responses were referenced by node name in a downstream "Normalize"
Code node using `.first().json`. This works but is brittle — adding a new
source means adding another node, rewiring the chain, and updating the
normalize node's name list.

**Real fix:** Add `NODE_FUNCTION_ALLOW_EXTERNAL=axios` to the n8n service
in `agent/docker-compose.yml`. This whitelists the `axios` npm module for
use inside Code nodes via `require('axios')`. Scoped to a named module
(not `*`) so the sandbox stays as locked down as possible.

```yaml
# agent/docker-compose.yml — n8n service environment
NODE_FUNCTION_ALLOW_EXTERNAL: axios
```

After `docker compose up -d n8n` on the VM, Code nodes can do:
```js
const axios = require('axios');
const { data } = await axios.get('https://example.com/jobs.json');
```

**Prevention:** When building any n8n workflow that needs outbound HTTP
inside a Code node, default to individual HTTP Request nodes (proven
pattern) OR ensure `NODE_FUNCTION_ALLOW_EXTERNAL=axios` is in the
compose env before writing Code-node-based fetchers. Document the sandbox
restriction clearly so future workflows don't rediscover it.

---

## Lessons distilled

1. **GCE cloud-init requires plain text user-data.** Not gzipped, not base64.
2. **OS Login conflicts with cloud-init's `users:` block.** Use `bootcmd`
   or `runcmd` to create users when OS Login is enabled.
3. **Tailscale SSH has Windows-specific rough edges.** Plain `ssh` is more
   reliable on Windows clients.
4. **PowerShell needs quotes around any flag containing dots or equals signs**
   that could confuse its parser.
5. **`random_password` values are in state, just display-masked.** Know how
   to extract them when you need to.
6. **Always check `sudo cloud-init status --long` after first boot.** A
   "done" status that completes in <30 seconds is suspect.
7. **Missing bind-mount sources get auto-created as root-owned
   directories.** Always commit the real file, or use
   `bind.create_host_path: false` so Docker fails loudly instead.
8. **`docker ps` showing `Up` does not mean healthy.** A container in a
   restart loop reports the *current* attempt as running. Cross-check
   with `docker logs` and `docker inspect ... .State.RestartCount`.
9. **Bind mounts are negotiated at container *create* time, not start
   time.** After fixing the host file/dir confusion, `docker compose
   restart` is not enough — you need `docker compose rm -sf <svc> && up
   -d` to force the mount spec to be re-read.
10. **n8n Code node sandbox has no HTTP primitives.** Neither `$helpers.httpRequest`
    nor global `fetch` are available. Use individual HTTP Request nodes (the proven
    pattern), or unlock `axios` via `NODE_FUNCTION_ALLOW_EXTERNAL=axios` in the n8n
    service environment.

## Open questions for future sessions

- Is there a way to make the TF cloud-init fix idempotent without forcing
  VM replacement? Probably not — cloud-init is intentionally a first-boot-only
  system. Document the replace workflow clearly instead.
- The `lifecycle { ignore_changes }` block we removed — should anything
  else in the stack use a similar pattern? Review if VM churn becomes an
  issue during iteration.
