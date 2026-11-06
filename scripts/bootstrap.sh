#!/bin/bash
# persistent-vps — Tailscale-layer boot hook (AGENTS.md: Availability)
#
# Idempotent: safe to run on every boot. Wire this into the restart mechanism
# of the infrastructure you operate (systemd unit, cron @reboot, Docker
# restart policy, cloud-init boot hook). A running process cannot bring back
# a machine that is down — this external boot hook is what restores the stack.
#
# What it does:
#   systemd path:  restart tailscaled, re-join if state lost, re-enable timers
#   no systemd:    userspace-networking tailscaled with persistent state,
#                  re-join with the reusable auth key if state was lost
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${TAILSCALE_STATE_DIR:-/var/lib/tailscale}"
LOG="/tmp/tailscale-bootstrap.log"

log() { echo "[$(date '+%F %T')] $*" >> "${LOG}"; }

# Secrets only from .env on disk — never from the repo (it is public).
[[ -f "${DIR}/.env" ]] && { set -a; source "${DIR}/.env"; set +a; }
AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
VPS_HOSTNAME="${VPS_HOSTNAME:-persistent-vps}"

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  # --- systemd path ------------------------------------------------------------
  log "systemd path: ensuring tailscaled + timers"
  systemctl restart tailscaled || true
  sleep 2
  if ! tailscale status >/dev/null 2>&1; then
    log "node offline -> re-joining with reusable auth key"
    tailscale up \
      --auth-key="${AUTH_KEY}" \
      --hostname="${VPS_HOSTNAME}" \
      --accept-dns=false \
      --ssh || log "ERROR: re-join failed (auth key expired?)"
  fi
  systemctl restart persistent-keepalive.timer state-snapshot.timer 2>/dev/null || true
  log "done (systemd)"
else
  # --- userspace path (container hosts without systemd, maybe no /dev/net/tun) --
  log "userspace path: ensuring tailscaled"
  if ! pgrep -f tailscaled >/dev/null; then
    mkdir -p "${STATE_DIR}" /var/run/tailscale
    setsid nohup tailscaled \
      --tun=userspace-networking \
      --state="${STATE_DIR}/tailscaled.state" \
      --socket=/var/run/tailscale/tailscaled.sock \
      >> "${LOG}" 2>&1 &
    sleep 3
    log "tailscaled started (userspace-networking)"
  fi
  if ! tailscale --socket=/var/run/tailscale/tailscaled.sock status >/dev/null 2>&1; then
    log "node offline -> re-joining with reusable auth key"
    tailscale --socket=/var/run/tailscale/tailscaled.sock up \
      --auth-key="${AUTH_KEY}" \
      --hostname="${VPS_HOSTNAME}" \
      --accept-dns=false \
      --ssh || log "ERROR: re-join failed (auth key expired?)"
  fi
  # Keep-alive + state snapshot in supervisor loops (systemd timers unavailable)
  if ! pgrep -f "keep-alive.sh" >/dev/null; then
    setsid nohup bash "${DIR}/scripts/keep-alive.sh" >> "${LOG}" 2>&1 &
    log "keep-alive loop started"
  fi
  log "done (userspace)"
fi
