# Decisions log

Major architectural and workflow decisions. Newest first. Add a row when
a choice would be hard to reconstruct later from code or git history
alone — tech picks, tradeoffs taken, paths explicitly *not* taken.

| Date         | Decision                          | Why                                                                                          |
| ------------ | --------------------------------- | -------------------------------------------------------------------------------------------- |
| April 25, 2026 | Hoist runtime files from `tf/files/` to top-level `agent/` | So VM `~/agent` can mirror the repo layout via git clone + symlink; honest separation of infra vs app. |
| April 25, 2026 | Cloudflare Tunnel for public ingress (not Caddy) | Honors "no public IP" principle. Outbound-only tunnel keeps VM unreachable from internet; CF terminates TLS + WAF + optional Access SSO. |
| April 24, 2026 | ~~Caddy + public subdomain for n8n~~ — *superseded April 25* | Original idea conflicted with the "no public IP" infra principle. Replaced by Cloudflare Tunnel (above). |
| April 24, 2026 | VM `~/agent` is a git clone       | cloud-init only runs first boot; `scp` is forgettable; `tf -replace` wipes volumes.          |
| April 24, 2026 | Start a decisions log             | Preserve the *why* behind tradeoffs beyond what diffs can show.                              |

<!--
Row format: | Month DD, YYYY | short imperative title | one-sentence reason (optional) |
Keep entries to one line. If it needs more, write a doc and link it.
-->
