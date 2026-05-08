# Decisions log

Major architectural and workflow decisions. Newest first. Add a row when
a choice would be hard to reconstruct later from code or git history
alone — tech picks, tradeoffs taken, paths explicitly *not* taken.

| Date         | Decision                          | Why                                                                                          |
| ------------ | --------------------------------- | -------------------------------------------------------------------------------------------- |
| May 7, 2026 | LLM-score every new job before storing; only insert ≥75 fit. Threshold lives in `Aggregate Scored` Code node, scoring criteria in `Build Score Request` system prompt | Job board was burying real fits under Java/Spring, .NET, financial-analyst noise. Filtering at fetch (haiku-4-5, ~1s per job) is cheap and keeps the table signal-dense. Existing rows aren't backfilled — re-scoring is a manual one-shot if the rubric shifts. |
| May 2, 2026 | Self-hosted Evolution API (Baileys) for Bugsy on WhatsApp, not Twilio / Meta Cloud API | FOSS-first; no per-message billing, no Business number / template approval / 24h reply window. Tradeoff accepted: unofficial WhatsApp Web protocol carries small ban risk on the paired number — mitigated by using a burner number, not personal. |
| May 1, 2026 | Enable axios in n8n Code node sandbox via `NODE_FUNCTION_ALLOW_EXTERNAL=axios` | Neither `$helpers.httpRequest` nor `fetch` are available in the n8n Code node sandbox; axios is the cleanest escape hatch and is scoped to a named module (safer than `*`). |
| April 25, 2026 | Hoist runtime files from `tf/files/` to top-level `agent/` | So VM `~/agent` can mirror the repo layout via git clone + symlink; honest separation of infra vs app. |
| April 25, 2026 | Cloudflare Tunnel for public ingress (not Caddy) | Honors "no public IP" principle. Outbound-only tunnel keeps VM unreachable from internet; CF terminates TLS + WAF + optional Access SSO. |
| April 24, 2026 | ~~Caddy + public subdomain for n8n~~ — *superseded April 25* | Original idea conflicted with the "no public IP" infra principle. Replaced by Cloudflare Tunnel (above). |
| April 24, 2026 | VM `~/agent` is a git clone       | cloud-init only runs first boot; `scp` is forgettable; `tf -replace` wipes volumes.          |
| April 24, 2026 | Start a decisions log             | Preserve the *why* behind tradeoffs beyond what diffs can show.                              |

<!--
Row format: | Month DD, YYYY | short imperative title | one-sentence reason (optional) |
Keep entries to one line. If it needs more, write a doc and link it.
-->
