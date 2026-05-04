# Webhooks

All webhooks are exposed via Cloudflare Tunnel at `https://n8n.coffey.codes/webhook/<path>`.

| Path | Method | Workflow | Caller | Notes |
|---|---|---|---|---|
| `/slack-bugsy` | POST | `bugsy.json` | Slack Event API | DMs + @mentions. Handles URL verification challenge. |
| `/ask` | POST | `bugsy.json` | Slack slash command `/ask` | ACKs immediately, replies async via `response_url`. |
| `/rag-query` | POST | `bugsy-rag-query.json` | Scripts, testing | JSON-API. No memory. See [RAG query](../workflows/rag-query.md). |
| `/rag-ingest` | POST | `bugsy-rag-ingest.json` | `rag-ingest.sh` | Pushes a markdown doc into Qdrant. |
| `/job-board` | GET | `bugsy-job-board-ui.json` | Browser | HTML view of the job listings table. |
| `/bugsy-research` | POST | `bugsy-research.json` | Slack slash command (TBD) | Research/SearXNG flow. |
| `/bugsy-wa` | POST | `bugsy-whatsapp.json` | Evolution API webhooks | WhatsApp message events. |

## Payload examples

### `/ask` (Slack slash command)
```
POST /webhook/ask
Content-Type: application/x-www-form-urlencoded

text=tell me about my expertise&user_id=U0AUSKT2VRD&user_name=anthony&channel_id=C...&response_url=https://hooks.slack.com/commands/...
```

### `/slack-bugsy` (Slack Event API)
```json
POST /webhook/slack-bugsy
{
  "type": "event_callback",
  "event": {
    "type": "message",
    "channel": "C...",
    "user": "U...",
    "text": "<@U_BUGSY> tell me about my expertise",
    "ts": "1716580000.123456",
    "channel_type": "im"
  }
}
```

### `/rag-query`
```json
POST /webhook/rag-query
{
  "question": "what are my strongest skills?",
  "top_k": 5
}
```

### `/rag-ingest`
```json
POST /webhook/rag-ingest
{
  "category": "bio",
  "content": "---\ntitle: My Resume\ntags: [resume, react]\n---\n\nResume body here..."
}
```
