#!/usr/bin/env bash
# persistent-vps bootstrap (Tailscale layer)
#
# Idempotent: safe to re-run. Installs Tailscale, joins the tailnet with the
# auth key, sets up SSH access (Tailscale SSH + OpenSSH fallback), installs
# the keep-alive + state scripts, enables timers, and prints a MEASURED
# final report via scripts/report.sh.
#
# Usage:
#   sudo -E ./install.sh
#
# Required (env or .env): TAILSCALE_AUTH_KEY.
# For a persistent node use a REUSABLE, pre-authorized, tagged, NON-ephemeral
# key (max 90 days) so the node can re-join by itself after a container
# recycle. Single-use keys break the ALWAYS ALIVE directive (AGENTS.md).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="/usr/local/lib/persistent-vps"
STATE_DIR="${TAILSCALE_STATE_DIR:-/var/lib/tailscale}"

log() { echo "[install] $*"; }

if [[ "${EUID}" -ne 0 ]]; then
  log "ERROR: run as root: sudo -E ./install.sh"
  exit 1
fi

# --- 1. Source .env FIRST, then read variables (order matters!) ---------------
# All .env-derived values must be resolved AFTER sourcing, or they silently
# fall back to defaults even when the user set them.
if [[ -f "${REPO_DIR}/.env" ]]; then
  set -a; source "${REPO_DIR}/.env"; set +a
fi

AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
VPS_HOSTNAME="${VPS_HOSTNAME:-persistent-vps}"

if [[ -z "${AUTH_KEY}" ]]; then
  log "ERROR: TAILSCALE_AUTH_KEY not set (env or .env). See .env.example"
  exit 1
fi

# --- 2. Environment detection -------------------------------------------------
HAVE_SYSTEMD=0
if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  HAVE_SYSTEMD=1
fi
HAVE_TUN=0
[[ -c /dev/net/tun ]] && HAVE_TUN=1
log "environment: systemd=${HAVE_SYSTEMD} tun=${HAVE_TUN}"

# --- 3. Tailscale --------------------------------------------------------------
if ! command -v tailscale >/dev/null 2>&1; then
  log "installing Tailscale..."
  # Optional version pin (recommended): TAILSCALE_VERSION=1.82.0 sudo -E ./install.sh
  curl -fsSL https://tailscale.com/install.sh \
    | sh -s -- ${TAILSCALE_VERSION:+--version="${TAILSCALE_VERSION}"}
else
  log "Tailscale already installed: $(tailscale version | head -n1)"
fi

# --- 4. Bring the node online ---------------------------------------------------
if [[ "${HAVE_SYSTEMD}" -eq 1 ]]; then
  # Keep tailscaled state on a persistent path if possible; with systemd the
  # daemon owns /var/lib/tailscale — ensure that volume is persistent so the
  # node re-authenticates silently after a recycle.
  mkdir -p /var/lib/tailscale
  tailscale up \
    --auth-key="${AUTH_KEY}" \
    --hostname="${VPS_HOSTNAME}" \
    --accept-dns=false \
    --ssh
else
  # No systemd (container/sandbox): userspace networking with state on disk.
  # The node re-authenticates silently after a recycle (reusable auth key).
  log "no systemd -> userspace-networking tailscaled, state at ${STATE_DIR}"
  mkdir -p "${STATE_DIR}" /var/run/tailscale
  if ! pgrep -f tailscaled >/dev/null; then
    setsid nohup tailscaled \
      --tun=userspace-networking \
      --state="${STATE_DIR}/tailscaled.state" \
      --socket=/var/run/tailscale/tailscaled.sock \
      >/tmp/tailscaled.log 2>&1 &
    sleep 3
  fi
  tailscale --socket=/var/run/tailscale/tailscaled.sock up \
    --auth-key="${AUTH_KEY}" \
    --hostname="${VPS_HOSTNAME}" \
    --accept-dns=false \
    --ssh
fi

# --- 5. SSH: OpenSSH fallback + ACL guidance ------------------------------------
# Tailscale SSH authorizes via tailnet ACL "ssh" rules, NOT OS passwords/keys.
# A tagged node is NOT covered by autogroup:self — you need an explicit rule.
# Add this to your tailnet ACL file (admin console -> Access Controls):
#
#   "tagOwners": { "tag:vps": ["autogroup:admin"] },
#   "acls": [
#     {"action": "accept", "src": ["autogroup:admin"], "dst": ["tag:vps:*"]},
#     {"action": "accept", "src": ["tag:vps"], "dst": ["tag:vps:*"]}
#   ],
#   "ssh": [
#     {"action": "accept", "src": ["autogroup:admin"],
#      "dst": ["root@tag:vps"], "user": ["root"]}
#   ]
#
# NOTE: use "action": "accept", not "check" — "check" forces browser
# re-authentication and breaks non-interactive use.
# Full walkthrough: docs/tailscale.md
if command -v apt-get >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    --no-install-recommends openssh-server >/dev/null 2>&1 || true
  if [[ "${HAVE_SYSTEMD}" -eq 1 ]]; then
    systemctl enable --now ssh >/dev/null 2>&1 || true
  fi
fi

# --- 6. Scripts + systemd units (systemd path) -----------------------------------
if [[ "${HAVE_SYSTEMD}" -eq 1 ]]; then
  log "installing scripts to ${LIB_DIR}..."
  install -d "${LIB_DIR}"
  install -m 0750 "${REPO_DIR}/scripts/keep-alive.sh" "${LIB_DIR}/keep-alive.sh"
  install -m 0750 "${REPO_DIR}/scripts/state-save.sh"  "${LIB_DIR}/state-save.sh"

  for unit in persistent-keepalive.service persistent-keepalive.timer \
              state-snapshot.service state-snapshot.timer; do
    install -m 0644 "${REPO_DIR}/systemd/${unit}" "/etc/systemd/system/${unit}"
  done

  systemctl daemon-reload
  systemctl enable --now persistent-keepalive.timer state-snapshot.timer
fi

# --- 7. Prepare the persistent directory -----------------------------------------
PERSIST_DIR="${PERSIST_DIR:-/srv/persistent}"
if [[ ! -d "${PERSIST_DIR}" ]]; then
  log "creating ${PERSIST_DIR}..."
  install -d -m 0755 "${PERSIST_DIR}"
fi

# --- 8. Boot hook ------------------------------------------------------------------
# Wire scripts/bootstrap.sh into whatever restart mechanism the platform
# provides. It re-ensures tailscaled, re-joins with the reusable key if state
# was lost, and re-enables timers — after every recycle.

# --- 9. Verify + report --------------------------------------------------------------
log "verifying..."
bash "${REPO_DIR}/scripts/report.sh"
