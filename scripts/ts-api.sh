#!/usr/bin/env bash
# persistent-vps Tailscale API wrapper
#
# Thin wrapper around the Tailscale HTTP API (https://tailscale.com/api).
# Requires: TAILSCALE_API_KEY (tskey-api-...) and TAILNET_NAME (e.g. example.ts.net)
#
# Usage:
#   ts-api.sh devices                    list all devices in the tailnet
#   ts-api.sh device <id|nodeId>         inspect one device
#   ts-api.sh delete-device <id>         remove a device from the tailnet
#   ts-api.sh new-key [ttl-days]         mint a pre-authorized reusable auth key
#   ts-api.sh help                       this help
set -euo pipefail

API_BASE="${TAILSCALE_API_URL:-https://api.tailscale.com}/api/v2"
KEY="${TAILSCALE_API_KEY:?TAILSCALE_API_KEY not set (tskey-api-...)}"
TAILNET="${TAILNET_NAME:?TAILNET_NAME not set (e.g. example.ts.net)}"

req() { curl -fsS -u "api:${KEY}" "$@"; }

case "${1:-help}" in
  devices)
    req "${API_BASE}/tailnet/${TAILNET}/devices"
    echo
    ;;

  device)
    req "${API_BASE}/device/${2:?device id required}"
    echo
    ;;

  delete-device)
    req -X DELETE "${API_BASE}/device/${2:?device id required}"
    echo "[ts-api] device deleted (if it existed)"
    ;;

  new-key)
    ttl_days="${2:-7}"
    if ! [[ "${ttl_days}" =~ ^[0-9]+$ ]]; then
      echo "ERROR: ttl-days must be a number" >&2
      exit 1
    fi
    expiry_seconds=$(( ttl_days * 86400 ))
    body=$(cat <<EOF
{"capabilities":{"devices":{"create":{"reusable":true,"ephemeral":false,"preAuthorized":true}}},"expirySeconds":${expiry_seconds}}
EOF
)
    req -X POST -H "Content-Type: application/json" -d "${body}" \
      "${API_BASE}/tailnet/${TAILNET}/keys"
    echo
    echo "NOTE: the key value is shown only once. Store it safely." >&2
    ;;

  *)
    grep '^#' "$0" | cut -c 3-
    ;;
esac
