#!/usr/bin/env bash
# persistent-vps bootstrap
#
# Idempotent: safe to re-run. Installs Tailscale, joins the tailnet with the
# auth key, installs the keep-alive + state scripts, and enables the timers.
#
# Usage:
#   sudo -E ./install.sh
#
# Required environment (or .env next to this script):
#   TAILSCALE_AUTH_KEY   tskey-auth-... auth key for joining the tailnet
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="/usr/local/lib/persistent-vps"
VPS_HOSTNAME="${VPS_HOSTNAME:-persistent-vps}"
AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"

log() { echo "[install] $*"; }

# --- checks ------------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
  log "ERROR: run as root: sudo -E ./install.sh"
  exit 1
fi

# Load .env if the key was not exported into the environment
if [[ -z "${AUTH_KEY}" && -f "${REPO_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a; source "${REPO_DIR}/.env"; set +a
fi
if [[ -z "${AUTH_KEY}" ]]; then
  log "ERROR: TAILSCALE_AUTH_KEY not set (env or .env). See .env.example"
  exit 1
fi

# --- 1. Tailscale ------------------------------------------------------------
if ! command -v tailscale >/dev/null 2>&1; then
  log "installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
else
  log "Tailscale already installed: $(tailscale version | head -n1)"
fi

# --- 2. Join the tailnet -----------------------------------------------------
log "bringing node online as ${VPS_HOSTNAME}..."
tailscale up \
  --auth-key="${AUTH_KEY}" \
  --hostname="${VPS_HOSTNAME}" \
  --accept-dns=false \
  --ssh

# --- 3. Install scripts + systemd units --------------------------------------
log "installing scripts to ${LIB_DIR}..."
install -d "${LIB_DIR}"
install -m 0750 "${REPO_DIR}/scripts/keep-alive.sh"  "${LIB_DIR}/keep-alive.sh"
install -m 0750 "${REPO_DIR}/scripts/state-save.sh"   "${LIB_DIR}/state-save.sh"

for unit in persistent-keepalive.service persistent-keepalive.timer \
            state-snapshot.service state-snapshot.timer; do
  install -m 0644 "${REPO_DIR}/systemd/${unit}" "/etc/systemd/system/${unit}"
done

systemctl daemon-reload
systemctl enable --now persistent-keepalive.timer state-snapshot.timer

# --- 4. Prepare the persistent directory -------------------------------------
PERSIST_DIR="${PERSIST_DIR:-/srv/persistent}"
if [[ ! -d "${PERSIST_DIR}" ]]; then
  log "creating ${PERSIST_DIR}..."
  install -d -m 0755 "${PERSIST_DIR}"
fi

# --- done --------------------------------------------------------------------
log "✅ done."
log "   tailscale IPv4: $(tailscale ip -4)"
log "   timers: $(systemctl list-timers --no-pager | grep -c persistent) persistent-* timers active"
log "   logs:   journalctl -u persistent-keepalive.service -u state-snapshot.service"
