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

## Open questions for future sessions

- Is there a way to make the TF cloud-init fix idempotent without forcing
  VM replacement? Probably not — cloud-init is intentionally a first-boot-only
  system. Document the replace workflow clearly instead.
- The `lifecycle { ignore_changes }` block we removed — should anything
  else in the stack use a similar pattern? Review if VM churn becomes an
  issue during iteration.
