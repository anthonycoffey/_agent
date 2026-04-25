# Decisions log

Major architectural and workflow decisions. Newest first. Add a row when
a choice would be hard to reconstruct later from code or git history
alone — tech picks, tradeoffs taken, paths explicitly *not* taken.

| Date         | Decision                          | Why                                                                                          |
| ------------ | --------------------------------- | -------------------------------------------------------------------------------------------- |
| April 24, 2026 | Caddy + public subdomain for n8n  | Keeps door open for Slack slash commands, third-party webhooks, shared UIs. Tailnet-only too limiting. |
| April 24, 2026 | VM `~/agent` is a git clone       | cloud-init only runs first boot; `scp` is forgettable; `tf -replace` wipes volumes.          |
| April 24, 2026 | Start a decisions log             | Preserve the *why* behind tradeoffs beyond what diffs can show.                              |

<!--
Row format: | Month DD, YYYY | short imperative title | one-sentence reason (optional) |
Keep entries to one line. If it needs more, write a doc and link it.
-->
