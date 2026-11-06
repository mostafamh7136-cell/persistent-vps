#!/bin/bash
# persistent-vps — cloud desktop boot hook
#
# Wire this into whatever boot mechanism the platform provides. The node must
# come back by itself after any recycle (ALWAYS ALIVE directive).
set -euo pipefail

DIR=/workspace/debian13-server

# Re-probe resources after every recycle (MAX RESOURCES directive)
bash "${DIR}/scripts/probe-resources.sh" /tmp/resources.log >/dev/null 2>&1 || true

bash "${DIR}/scripts/mount-chroot.sh" >/dev/null 2>&1

# Watchdog must always be running
pgrep -f keepalive.sh >/dev/null || {
  nohup bash "${DIR}/keepalive.sh" >/dev/null 2>&1 & disown
}

exec bash "${DIR}/start-desktop.sh"
