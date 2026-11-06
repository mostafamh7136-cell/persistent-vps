#!/usr/bin/env bash
# persistent-vps keep-alive watchdog
#
# Runs via persistent-keepalive.timer (default: every 5 minutes).
# - Verifies the Tailscale backend is in the Running state
# - Restarts tailscaled and retries if the node fell off the tailnet
# - Optionally pings TAILSCALE_PEER to keep NAT mappings warm
set -uo pipefail

TAILSCALE_PEER="${TAILSCALE_PEER:-}"
RESTART_WAIT_SECS="${RESTART_WAIT_SECS:-15}"

log() { echo "[keep-alive] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

if ! command -v tailscale >/dev/null 2>&1; then
  log "FATAL: tailscale is not installed"
  exit 1
fi

backend_state() {
  tailscale status --json 2>/dev/null \
    | grep -o '"BackendState":"[^"]*"' | cut -d'"' -f4
}

state="$(backend_state)"

if [[ "${state}" == "Running" ]]; then
  log "healthy: tailscale backend running"
else
  log "backend state is '${state:-unknown}' -> restarting tailscaled"
  systemctl restart tailscaled
  sleep "${RESTART_WAIT_SECS}"

  state="$(backend_state)"
  if [[ "${state}" == "Running" ]]; then
    log "recovered after restart"
  else
    log "still '${state:-unknown}' -> retrying 'tailscale up' with stored state"
    tailscale up >/dev/null 2>&1 || true
    exit 1
  fi
fi

# Warm the connection so NAT/firewall state never goes stale (optional)
if [[ -n "${TAILSCALE_PEER}" ]]; then
  if ping -c 1 -W 5 "${TAILSCALE_PEER}" >/dev/null 2>&1; then
    log "peer ${TAILSCALE_PEER} reachable"
  else
    log "WARNING: peer ${TAILSCALE_PEER} unreachable (may be offline)"
  fi
fi
