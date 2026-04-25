# Decisions log

Record of major architectural and workflow decisions for the Bugsy AI
project. Newest first. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/) — each entry is dated and
notes the *why* when it isn't obvious.

Add an entry whenever a decision would be hard to reconstruct later from
code or git history alone (tech choices, tradeoffs taken, paths
explicitly *not* taken).

---

## [2026-04-24]

### Added
- **Decisions log** (`docs/decisions.md`). Captures the *why* behind
  choices so future-us doesn't have to re-derive them from diffs.

### Changed
- **VM deploy workflow → git pull on the VM.** `~/agent` becomes a clone
  of this repo; deploys are `git pull && docker compose up -d`.
  *Why:* cloud-init only runs on first boot, so edited template files
  never reach the live VM. The alternatives were `scp` (easy to forget)
  or `terraform apply -replace` (wipes data volumes).

### Decided
- **HTTPS for n8n → Caddy + public subdomain** (e.g. `n8n.coffey.codes`),
  not Tailscale Serve.
  *Why:* keeps the door open for future services that benefit from
  public reachability (Slack slash commands, webhooks from third-party
  SaaS, sharing a UI with collaborators). Tailscale Serve was simpler
  but tailnet-only. We accept a narrow public ingress (Caddy → n8n)
  managed by Cloudflare DNS + Let's Encrypt.

---

## Template

```
## [YYYY-MM-DD]

### Added | Changed | Removed | Decided | Deprecated
- **Short title.** What changed in one sentence.
  *Why:* (optional) the reason, constraint, or incident driving it.
```
