#!/usr/bin/env bash
# Run ON the VM (as the login user) after: gcloud compute scp ... openclaw-gateway:~/
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

log() { printf '%s\n' "$*"; }

if [[ $(id -u) -eq 0 ]]; then
  log "Run as your normal user (not root). Use: bash ~/vm-bootstrap.sh"
  exit 1
fi

log "[1/7] apt update + docker + git"
sudo apt-get update -qq
sudo apt-get install -y -qq git curl ca-certificates
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sudo sh
fi
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER" || true

log "[2/7] clone OpenClaw"
cd "$HOME"
if [[ ! -d openclaw ]]; then
  git clone --depth 1 https://github.com/openclaw/openclaw.git
fi
cd openclaw

log "[3/7] persistent dirs + .env"
mkdir -p "$HOME/.openclaw" "$HOME/.openclaw/workspace"
if [[ ! -f .env ]]; then
  GATEWAY_TOKEN="$(openssl rand -hex 32)"
  GOG_PW="$(openssl rand -hex 16)"
  cat > .env <<EOF
OPENCLAW_IMAGE=openclaw:local
OPENCLAW_GATEWAY_TOKEN=${GATEWAY_TOKEN}
OPENCLAW_GATEWAY_BIND=lan
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_CONFIG_DIR=${HOME}/.openclaw
OPENCLAW_WORKSPACE_DIR=${HOME}/.openclaw/workspace
GOG_KEYRING_PASSWORD=${GOG_PW}
XDG_CONFIG_HOME=/home/node/.openclaw
EOF
  chmod 600 .env
  log "Wrote ~/openclaw/.env (gateway token generated). Backup this file if you need the token."
fi

log "[4/7] loopback-only ports + Moltbook plugin mount (override compose)"
MOLT_DIR="${HOME}/molt-agent"
if [[ ! -f "${MOLT_DIR}/package.json" ]]; then
  if [[ -f "${HOME}/molt-agent-src.tgz" ]]; then
    log "Using ${HOME}/molt-agent-src.tgz (upload from your laptop; avoids private GitHub on the VM)"
    rm -rf "${MOLT_DIR}"
    tar xzf "${HOME}/molt-agent-src.tgz" -C "${HOME}"
  else
    git clone --depth 1 https://github.com/mikecohen/molt-agent.git "$MOLT_DIR" || {
      log "Git clone failed (private repo?). On your laptop: tar czf molt-agent-src.tgz --exclude=molt-agent/node_modules molt-agent"
      log "Then: gcloud compute scp molt-agent-src.tgz openclaw-gateway:~/ && re-run this script."
      exit 1
    }
  fi
fi
if ! command -v node >/dev/null 2>&1; then
  log "Installing Node.js 22 (needed for npm ci on the plugin)…"
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
  sudo apt-get install -y -qq nodejs
fi
(cd "$MOLT_DIR" && npm ci)

cat > docker-compose.override.yml <<EOF
services:
  openclaw-gateway:
    build: .
    env_file:
      - .env
      - .env.moltbook
    environment:
      MOLTBOOK_API_BASE: https://www.moltbook.com/api/v1
    ports:
      - "127.0.0.1:18789:18789"
      - "127.0.0.1:18790:18790"
    volumes:
      - ${MOLT_DIR}:/plugins/moltbook:ro

  openclaw-cli:
    build: .
    env_file:
      - .env
      - .env.moltbook
    environment:
      MOLTBOOK_API_BASE: https://www.moltbook.com/api/v1
    volumes:
      - ${MOLT_DIR}:/plugins/moltbook:ro
EOF

if [[ ! -f .env.moltbook ]]; then
  cat > .env.moltbook <<'EOF'
# Add your Moltbook agent API key (never commit this file)
MOLTBOOK_API_KEY=
EOF
  chmod 600 .env.moltbook
  log "Edit ~/openclaw/.env.moltbook and set MOLTBOOK_API_KEY, then: cd ~/openclaw && docker compose up -d --build"
fi

log "[5/7] OpenClaw config: load Moltbook plugin"
mkdir -p "$HOME/.openclaw"
if [[ ! -f "$HOME/.openclaw/openclaw.json" ]]; then
  cat > "$HOME/.openclaw/openclaw.json" <<'EOF'
{
  plugins: {
    load: {
      paths: ["/plugins/moltbook"],
    },
  },
}
EOF
elif ! grep -q '/plugins/moltbook' "$HOME/.openclaw/openclaw.json" 2>/dev/null; then
  log "WARNING: Add plugins.load.paths [\"/plugins/moltbook\"] to ~/.openclaw/openclaw.json"
fi

log "[6/7] docker compose build (may take 10–20+ minutes on e2-small)…"
sudo docker compose build

log "[7/7] start stack"
sudo docker compose up -d

log "Done. Gateway on VM loopback :18789 — from laptop (set zone/project as needed):"
log "  gcloud compute ssh openclaw-gateway --zone=us-central1-a -- -L 18789:127.0.0.1:18789"
log "Then open http://127.0.0.1:18789/ — use 'docker compose run --rm openclaw-cli dashboard --no-open' on the VM for a token URL."
