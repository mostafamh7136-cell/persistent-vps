#!/bin/bash
# persistent-vps — cloud desktop startup
#
# Boots the full desktop stack: chroot mounts -> VNC -> websockify -> gateway.
# Credentials are sourced from .env (secrets intake, SECRETS.md) — NEVER
# hardcoded: this repository is public.
set -euo pipefail

DIR=/workspace/debian13-server

# --- secrets intake: load .env ------------------------------------------------
if [[ -f "${DIR}/.env" ]]; then
  set -a; source "${DIR}/.env"; set +a
fi
if [[ -z "${GATEWAY_USER:-}" || -z "${GATEWAY_PASS:-}" ]]; then
  echo "FATAL: GATEWAY_USER/GATEWAY_PASS missing." >&2
  echo "       Ask the user for the gateway credentials (SECRETS.md), write them to ${DIR}/.env, and re-run." >&2
  exit 1
fi

# --- chroot mounts (must precede everything inside the chroot) ---------------
bash "${DIR}/scripts/mount-chroot.sh" >/dev/null 2>&1

# --- sync gateway files --------------------------------------------------------
mkdir -p /srv/debian13/opt/desktop-gw/novnc
cp -f "${DIR}/desktop/server.py" /srv/debian13/opt/desktop-gw/server.py

# --- VNC + XFCE -----------------------------------------------------------------
bash "${DIR}/scripts/ensure-vnc.sh" >/tmp/boot-vnc.log 2>&1

# --- websockify on 6081 ----------------------------------------------------------
if ! pgrep -f "websockify.*6081" >/dev/null; then
  pkill -9 -f websockify >/dev/null 2>&1 || true
  sleep 1
  nohup websockify --heartbeat=30 127.0.0.1:6081 127.0.0.1:5901 \
    >/tmp/websockify.log 2>&1 &
  disown
  sleep 2
fi

# --- gateway on 6080 (env carries GATEWAY_USER/GATEWAY_PASS into the chroot) ----
exec chroot /srv/debian13 /bin/bash -c '
export PATH=/usr/local/bin:/usr/bin:/bin
export PORT=6080
exec /usr/bin/python3 /opt/desktop-gw/server.py
'
