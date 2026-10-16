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

Docker services on the VM (full table with images and roles:
[architecture overview](docs/architecture/overview.md)):

- `agent-postgres` (pgvector/pg16) — app data, n8n's internal DB, chat memory
- `agent-qdrant` — vector store (`personal_knowledge` collection)
- `agent-redis` — cache / queue
- `agent-ollama` — local model runtime (`qwen3:8b`, `nomic-embed-text`)
- `agent-litellm` — OpenAI-compatible proxy for local + hosted models
- `agent-openwebui` — chat UI on `:3000`
- `agent-n8n` — workflow automation + AI Agent runtime; the orchestration layer
- `agent-cloudflared` — Cloudflare Tunnel; the only public ingress
- `agent-searxng` — self-hosted metasearch behind the research + lead-gen workflows
- `agent-mcp-atlassian` / `agent-mcp-github` / `agent-mcp-notion` — MCP servers giving the
  agent live Jira, GitHub, and Notion tools instead of stale RAG snapshots
- `agent-aider` — AI coding-agent runner (half-built; nothing drives it yet)
- `agent-evolution-api` — parked WhatsApp bridge from a retired experiment

Slack is the interface; n8n holds the workflows. Those are documented per-workflow under
[docs/workflows/](docs/workflows/).

---

## Repo layout

```
_agent/
├── README.md
├── CLAUDE.md                      project context for AI assistants; current-state source of truth
├── agent/                         runtime files; mirrors ~/agent on the VM
│   ├── docker-compose.yml         the stack
│   ├── env.template               .env reference
│   ├── backup.sh                  nightly backup with GCS upload
│   ├── rag-ingest.sh              POST markdown files → RAG ingest webhook
│   ├── motd                       SSH welcome banner
│   ├── aider/                     AI coding-agent runner scripts
│   ├── litellm/                   model list + proxy settings
│   ├── n8n/workflows/             workflow JSON (source of truth) + reference generator
│   ├── postgres/                  init SQL + schema migrations
│   ├── rag/                       personal-knowledge documents (markdown gitignored)
│   ├── scripts/                   rag-refresh cron job
│   └── searxng/                   metasearch config
├── docs/                          MkDocs Material site — architecture, workflows, operations,
│                                  reference, and the DDD spec home under docs/specs/
├── logs/
│   ├── decisions-log.md           major architectural decisions
│   ├── incident-log.md            deploy-time issues and lessons
│   └── plans/                     working plans for in-flight initiatives
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

## Constraints

- No Secret Manager yet — state-based secrets are acceptable for now.
- No meeting bots that join calls — post-meeting transcript APIs only.
- No LinkedIn scraping.
- No automated cold email sending — research and draft only.

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
parsing, secret extraction), see [`logs/incident-log.md`](logs/incident-log.md).

---

## Deciding what to build next

When tempted to add something:

1. Can you describe the workflow in one sentence?
2. Will you actually use it in two weeks, or is it shiny?
3. Can you imagine reviewing the output daily or weekly?
4. Does it need an integration you don't already have working?

Yes / yes / yes / no → build it. Otherwise → "someday" list, finish the
current phase.
