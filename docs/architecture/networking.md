# Networking

## No public IP

The VM has no public IP address. It is unreachable from the internet directly. All public ingress goes through **Cloudflare Tunnel** (`cloudflared` container, outbound-only connection to Cloudflare's edge).

## Public hostnames

| Hostname | Routes to | Purpose |
|---|---|---|
| `n8n.coffey.codes` | `agent-n8n:5678` | n8n editor + webhooks |
| `docs.coffey.codes` | `agent-mkdocs:8000` | This documentation site |

Add a new hostname by editing the Cloudflare Tunnel configuration in the Cloudflare dashboard (Zero Trust → Networks → Tunnels → your tunnel → Public Hostnames).

## SSH access

SSH from Anthony's machines goes over **Tailscale**. The VM joins Tailscale on first boot via cloud-init. Connect as `agent@agent-vm`.

## Internal docker network

All containers join `agent_agent-net`. Container DNS uses container names (`postgres`, `qdrant`, `ollama`, `litellm`, `n8n`, etc.). Code inside one container reaches another via `http://<containername>:<port>`.

To poke at an internal service from the host shell, exec into a container that has `curl`, or spin up a throwaway:

```bash
docker run --rm --network agent_agent-net curlimages/curl:latest \
  -s http://agent-qdrant:6333/collections | jq
```

Most internal services do **not** publish ports to the host — that's intentional. The only host-published port is whatever cloudflared talks out on (no inbound).
