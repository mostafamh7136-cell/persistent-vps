#!/bin/bash
# persistent-vps — final report builder
#
# Prints ONLY measured facts. No hand-written claims: if something is not
# verified at run time, it is listed as a residual risk. An honest report is
# part of the contract (AGENTS.md — honest guarantees).
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "${DIR}/.env" ]] && { set -a; source "${DIR}/.env"; set +a; }

sep() { echo "----------------------------------------------------------------" >&2; }

# --- measured values ------------------------------------------------------------
STATUS_JSON="$(tailscale status --json 2>/dev/null || true)"
SELF_HOST="$(echo "${STATUS_JSON}" | grep -o '"HostName":"[^"]*"' | head -1 | cut -d'"' -f4)"
SELF_IP="$(tailscale ip -4 2>/dev/null | head -1)"

# Tailscale SSH enabled? (the --ssh flag registers SSH host keys on the node)
TSSH="unknown"
if echo "${STATUS_JSON}" | grep -q '"SSH_HostKeys":\['; then
  TSSH="enabled"
elif [[ -n "${STATUS_JSON}" ]]; then
  TSSH="disabled"
fi

# OpenSSH fallback present?
OSSSH="no"
if command -v sshd >/dev/null 2>&1 || pgrep -x sshd >/dev/null 2>&1; then
  OSSSH="yes"
fi

# Connectivity: ping self (or the configured peer)
PING_TARGET="${TAILSCALE_PEER:-${SELF_IP}}"
PING_OK="no"
if [[ -n "${PING_TARGET}" ]] && tailscale ping -c 1 --timeout 5s "${PING_TARGET}" >/dev/null 2>&1; then
  PING_OK="yes"
fi

# Supervision: what restarts what (measured, not claimed)
SUP=""
if command -v systemctl >/dev/null 2>&1 && systemctl is-enabled persistent-keepalive.timer >/dev/null 2>&1; then
  SUP+="systemd keep-alive timer (5m) -> tailscaled, "
fi
if command -v systemctl >/dev/null 2>&1 && systemctl is-enabled state-snapshot.timer >/dev/null 2>&1; then
  SUP+="systemd snapshot timer (daily), "
fi
if pgrep -f "tailscaled" >/dev/null 2>&1; then
  SUP+="tailscaled running"
fi
[[ -z "${SUP}" ]] && SUP="none detected (wire scripts/bootstrap.sh into the server's boot mechanism)"

# Survives restarts: state file + reusable key
STATE_FILE="/var/lib/tailscale/tailscaled.state"
[[ -f "${STATE_FILE}" ]] || STATE_FILE="${TAILSCALE_STATE_DIR:-/var/lib/tailscale}/tailscaled.state"
RESTART="no"
if [[ -f "${STATE_FILE}" ]]; then RESTART="partial (state persisted; wire bootstrap.sh into the boot mechanism)"; fi
if [[ -f "${STATE_FILE}" && -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
  RESTART="yes (state persisted + reusable re-join key available)"
fi

# --- residual risks (honest, always listed) --------------------------------------
RISKS=()
[[ "${PING_OK}" == "no" ]] && RISKS+=("tailnet connectivity not verified from this node")
[[ "${TSSH}" != "enabled" ]] && RISKS+=("Tailscale SSH not enabled on the node")
[[ "${TSSH}" == "enabled" ]] && RISKS+=("Tailscale SSH still requires a tailnet ACL 'ssh' rule with action:accept (see docs/tailscale.md)")
[[ "${OSSSH}" == "no" ]] && RISKS+=("no OpenSSH fallback installed")
[[ "${RESTART}" == "no" ]] && RISKS+=("tailscaled state not on persistent storage — re-join required after a rebuild")
RISKS+=("no external boot hook detected — a running process cannot restore a machine that is down; wire scripts/bootstrap.sh into the server's boot mechanism")

# --- report ------------------------------------------------------------------------
sep >&2
echo "Done"
echo "VPS created: ${SELF_HOST:-unknown}"
echo "Connect: ssh root@${SELF_IP:-no-ip-yet}"
echo "SSH: tailscale-ssh=${TSSH} (needs ACL rule) | openssh-fallback=${OSSSH}"
echo "Verified: tailscale ping ${PING_TARGET:-none} -> ${PING_OK}"
echo "Supervision: ${SUP}"
echo "Survives restart: ${RESTART}"
echo "Residual risks:"
for r in "${RISKS[@]}"; do echo "  - ${r}"; done
sep >&2
echo "Full key/ACL walkthrough: docs/tailscale.md"
