# Bugsy AI

A self-hosted personal AI assistant running on a GCE VM. FOSS-first and
educational — built to learn every layer while growing into an assistant that
handles email, meetings, code, sales outreach, and content work through a
Slack-driven interface.

---

## Goals

- **Email** — read inboxes, summarize, draft replies, send digests
- **Meetings** — capture Zoom/Meet/Teams transcripts into Notion
- **Code** — issues, PRs, and articles for `coffey.codes`
- **Interface** — Slack as primary control panel
- **Sales** — research and drafting; humans send
- **Content** — aggregate AI news, job postings, interesting reads
- **Career** — maintain resumes, tailor applications
- **Creative** — Adobe Firefly for marketing visuals
- **Stretch** — personal CRM, time tracking, commitment tracking

---

## Design principles

- **Slack is the control panel.** Digests, approvals, questions; reactions gate irreversible actions.
- **Human in the loop for anything that sends.** Email, social posts, code merges.
- **Memory is the moat.** An assistant that knows *you* beats one with 50 integrations and no context.
- **FOSS over proprietary** wherever reasonable.
- **CPU-only.** No GPU. Local models for non-time-critical work; hosted models (Claude primarily) for interactive use.

---

## Infrastructure

- **No public IP.** Egress via Cloud NAT; ingress only via Tailscale or IAP SSH.
- **Dedicated VPC** with deny-all firewall + IAP fallback rule.
- **Shielded VM + OS Login** enabled.
- **Narrow service account** — `logging.logWriter`, `monitoring.metricWriter`, `secretmanager.secretAccessor`, and `storage.objectUser` on its own backup bucket.
- **Secrets via `random_password`** written to `.env` on first boot. State lives in GCS with encryption, versioning, and public-access prevention. Upgrade paths: Secret Manager with ephemeral resources, or CMEK.
- **Boot disk is a separate resource** so the snapshot schedule can attach as a `resource_policy`.
- **Stack does not auto-start.** cloud-init lays down files and installs Docker; the operator fills API keys in `.env` and runs `docker compose up -d`.

---

## Stack

Docker services on the VM:

- `agent-postgres` (pgvector/pg16) — `agent`, `n8n`, `langfuse`, `memory` databases
- `agent-qdrant` — vector store
- `agent-redis` — cache
- `agent-ollama` — local model runtime (`qwen3:8b`, `nomic-embed-text`)
- `agent-litellm` — OpenAI-compatible proxy for local + hosted models
- `agent-openwebui` — chat UI on `:3000`

---

## Repo layout

```
_agent/
├── README.md
├── agent/                         runtime files; mirrors ~/agent on the VM
│   ├── docker-compose.yml         the stack
│   ├── env.template               .env reference
│   ├── backup.sh                  nightly backup with GCS upload
│   └── motd                       SSH welcome banner
├── docs/
│   ├── decisions.md               major architectural decisions
│   └── incident-log.md            deploy-time issues and lessons
└── tf/
    ├── versions.tf                TF 1.9+, google ~> 6.0, random, cloudinit
    ├── backend.tf                 GCS remote state
    ├── providers.tf               provider config + default_labels
    ├── variables.tf               inputs with validation + defaults
    ├── iam.tf                     API enablement + service account + IAM
    ├── network.tf                 VPC, subnet, firewall
    ├── vm.tf                      disk, VM, NAT, secrets, cloud-init
    ├── backup.tf                  GCS backup bucket + lifecycle rules
    ├── outputs.tf                 SSH commands, URLs
    ├── terraform.tfvars.example
    ├── bootstrap/
    │   └── 00-create-state-bucket.sh
    └── cloud-init/
        └── agent-vm.yaml.tftpl    first-boot bootstrap
```

---

## Getting started

```bash
cd tf/

# 1. one-time GCS state bucket
./bootstrap/00-create-state-bucket.sh MY-PROJECT MY-PROJECT-tfstate-agent

# 2. point backend.tf at that bucket
# 3. fill variables
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars        # project_id, tailscale_auth_key, etc.

# 4. apply
terraform init
terraform plan
terraform apply
```

After apply, wait 3–5 minutes for cloud-init, then:

```bash
ssh agent@agent-vm
cd ~/agent
$EDITOR .env                    # add OPENAI_API_KEY etc.
docker compose up -d
```

---

## Roadmap

Six-phase ramp from "chat UI" to working assistant.

<div align="center">

<table>
  <colgroup>
    <col width="60">
    <col width="280">
    <col>
  </colgroup>
  <thead>
    <tr>
      <th align="center">Phase</th>
      <th align="left">Theme</th>
      <th align="left">Deliverables</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td align="center">1</td>
      <td>Foundation</td>
      <td>n8n + Caddy + Slack app · morning Gmail digest → Slack DM</td>
    </tr>
    <tr>
      <td align="center">2</td>
      <td>Memory + Slack-native chat</td>
      <td>Memory MCP (<code>remember</code> / <code>recall</code> / <code>forget</code>) · Drive + articles indexed into Qdrant · Slack DM → AI Agent w/ retrieval</td>
    </tr>
    <tr>
      <td align="center">3</td>
      <td>Meetings + content feed</td>
      <td>Zoom / Meet / Teams transcripts → Notion · RSS aggregation → daily <code>#bugsy-feed</code></td>
    </tr>
    <tr>
      <td align="center">4</td>
      <td>Email writing + GitHub</td>
      <td>Slack DM → draft → 👍 sends via Gmail · daily issue / PR triage for <code>coffey.codes</code></td>
    </tr>
    <tr>
      <td align="center">5</td>
      <td>Sales research + follow-up</td>
      <td>Prospect URL → brief + ICP score + draft · Postgres CRM + stale-prospect reminders</td>
    </tr>
    <tr>
      <td align="center">6</td>
      <td>Content + career</td>
      <td>Voice-matched articles for <code>coffey.codes</code> · resume + cover letter per posting</td>
    </tr>
  </tbody>
</table>

</div>

### Beyond

Personal CRM expansion, commitment tracking from outgoing messages, time
tracking + invoicing, Adobe Firefly MCP, voice interface (Whisper + Piper),
low-risk autonomous code changes (deps, docs, typos), reading-list curator,
learning tracker, weekly retrospective.

---

## Constraints

- No Secret Manager yet — state-based secrets are acceptable for now.
- No meeting bots that join calls — post-meeting transcript APIs only.
- No LinkedIn scraping.
- No automated cold email sending — research and draft only.
- No multi-agent orchestration before a single agent works well.

---

## Troubleshooting

**Force a VM rebuild when the cloud-init template changes.** cloud-init only
runs on first boot; the live VM ignores subsequent template edits. To pick up
changes:

```powershell
terraform apply "-replace=google_compute_instance.agent"
```

For the full record of issues hit during initial deployment (cloud-init
encoding, OS Login user creation, Tailscale SSH on Windows, PowerShell arg
parsing, secret extraction), see [`docs/incident-log.md`](docs/incident-log.md).

---

## Deciding what to build next

When tempted to add something:

1. Can you describe the workflow in one sentence?
2. Will you actually use it in two weeks, or is it shiny?
3. Can you imagine reviewing the output daily or weekly?
4. Does it need an integration you don't already have working?

Yes / yes / yes / no → build it. Otherwise → "someday" list, finish the
current phase.
