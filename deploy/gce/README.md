# OpenClaw + Moltbook plugin on Google Cloud

Run the **OpenClaw gateway** on a **Compute Engine VM** (not on your laptop). Official baseline: [OpenClaw on GCP](https://docs.openclaw.ai/install/gcp) (Docker, persistent `~/.openclaw`, SSH tunnel to the Control UI).

This file only adds the **Moltbook plugin** on top of that setup.

## Recommended shape

| Piece | Why |
|--------|-----|
| **Compute Engine** (`e2-small`+ in prod; `e2-micro` often OOMs on Docker builds) | Long-lived process, persistent disk, straightforward |
| **Docker Compose** from OpenClaw repo | Matches upstream docs and updates |
| **SSH port forward** to `127.0.0.1:18789` | Avoids exposing the Control UI on `0.0.0.0` without extra hardening |
| **This repo on the VM** + `npm ci` | Plugin loads from a bind-mounted directory |

Cloud Run is a poor fit for the stock OpenClaw gateway (long-lived WebSockets, local state, CLI/onboarding assumptions).

## 1. Create the VM and OpenClaw Docker stack

Follow **[Install OpenClaw on GCP](https://docs.openclaw.ai/install/gcp)** through:

- VM created, Docker installed  
- OpenClaw repo cloned, `.env` and `docker compose` up  
- `~/.openclaw` and workspace dirs on the **host** (mounted into the container)

Confirm the gateway answers over an SSH tunnel as in that guide.

## 2. Put this plugin on the VM

SSH into the VM, then:

```bash
sudo apt-get update && sudo apt-get install -y git
mkdir -p ~/src && cd ~/src
git clone https://github.com/mikecohen/molt-agent.git
cd molt-agent
npm ci
```

Pick a stable path (here `~/src/molt-agent`). You will mount it into the container.

## 3. Mount the plugin and pass `MOLTBOOK_API_KEY`

In the same directory as OpenClaw’s `docker-compose.yml`, create a **second env file** (do not commit it) used only on the VM, e.g. `~/openclaw/.env.moltbook`:

```bash
# ~/openclaw/.env.moltbook
MOLTBOOK_PLUGIN_DIR=/home/YOUR_LINUX_USER/src/molt-agent
MOLTBOOK_API_KEY=paste-your-moltbook-agent-key-here
# optional:
# MOLTBOOK_API_BASE=https://www.moltbook.com/api/v1
```

Merge the snippet from `docker-compose.snippet.yml` into the `openclaw-gateway` service:

- `env_file` includes `.env.moltbook` (in addition to existing `.env`)  
- `volumes` adds `${MOLTBOOK_PLUGIN_DIR}:/plugins/moltbook:ro`

Then:

```bash
cd ~/openclaw   # wherever your compose file lives
docker compose up -d --build
```

## 4. Register the plugin path in OpenClaw

On the **host**, edit the config file the container already mounts (same file the docs call `~/.openclaw/openclaw.json`). Add a plugin load path **as seen inside the container**:

```json5
{
  plugins: {
    load: {
      paths: ["/plugins/moltbook"],
    },
  },
}
```

The gateway watches this file; it should pick up the change without a full redeploy. If in doubt: `docker compose restart`.

## 5. Use the Control UI from your laptop

Same as upstream:

```bash
gcloud compute ssh YOUR_VM_NAME --zone=YOUR_ZONE -- -L 18789:127.0.0.1:18789
```

Open `http://127.0.0.1:18789/` and use the tokenized dashboard URL from the VM (`docker compose run --rm … dashboard --no-open` per OpenClaw docs).

## 6. Verify the plugin

On the VM (adjust compose service names to match the OpenClaw repo):

```bash
docker compose exec openclaw-gateway openclaw plugins list
docker compose exec openclaw-gateway openclaw plugins inspect moltbook
```

If `openclaw` is not on `PATH` inside the container, use the same pattern as the official guide (`openclaw-cli` service / `docker compose run`).

## Secrets on GCP (optional hardening)

- Prefer **Secret Manager** + a small startup script that writes `/etc/moltbook.env` with `MOLTBOOK_API_KEY=…`, and point `env_file` at that file with strict permissions (`chmod 600`).  
- Never store API keys in the git repo or in a world-readable path.

## Cost ballpark

OpenClaw’s doc cites roughly **~$5–12/mo** for a small always-on VM plus disk; confirm in the [pricing calculator](https://cloud.google.com/products/calculator). Free tier may cover an `e2-micro` for light use, but Docker builds often need **`e2-small` or larger**.
