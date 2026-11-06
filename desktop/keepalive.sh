#!/bin/bash
# persistent-vps — cloud desktop watchdog (ALWAYS ALIVE directive, as code)
#
# Infinite loop, every 60s:
#   1. Xtigervnc dead           -> restart VNC + XFCE
#   2. websockify dead          -> restart websockify
#   3. gateway (6080) dead      -> restart the whole stack
#   4. AGENTOS_RUNTIME_ID moved -> re-pin the public URL
#   5. public URL failing       -> re-pin after 3 consecutive failures
#
# No secrets here: it only touches the open /healthz route.
set -uo pipefail

DIR=/workspace/debian13-server
PINNED_ID=$(cat "$DIR/.pinned_id" 2>/dev/null || echo "default-node")
LINK="https://${PINNED_ID}.sg.agentos-app.run"
LOG=/tmp/desktop-keepalive.log
FAIL=0
LAST_RID="${AGENTOS_RUNTIME_ID:-}"

log() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }
log "keepalive started for ID: $PINNED_ID (pid $$)"

while true; do
  # 1) VNC
  pgrep -f "Xtigervnc :1" >/dev/null || {
    log "Xtigervnc down -> restarting"
    bash "$DIR/scripts/ensure-vnc.sh" >>"$LOG" 2>&1
  }

  # 2) websockify
  pgrep -f "websockify.*6081" >/dev/null || {
    log "websockify down -> restarting"
    pkill -9 -f websockify >/dev/null 2>&1 || true
    sleep 1
    nohup websockify --heartbeat=30 127.0.0.1:6081 127.0.0.1:5901 >>"$LOG" 2>&1 &
    disown
    sleep 2
  }

  # 3) Gateway
  if ! curl -sf --max-time 5 http://127.0.0.1:6080/healthz >/dev/null; then
    log "gateway (6080) down -> restarting"
    pkill -9 -f "desktop-gw/server.py" >/dev/null 2>&1 || true
    sleep 2
    setsid nohup bash "$DIR/start-desktop.sh" >>/tmp/desktop-gw.log 2>&1 </dev/null &
    disown
    sleep 6
  fi

  # 4) URL re-pin if runtimeId changed
  CUR_RID="${AGENTOS_RUNTIME_ID:-}"
  if [ -n "$CUR_RID" ] && [ "$CUR_RID" != "$LAST_RID" ]; then
    log "runtimeId changed ($LAST_RID -> $CUR_RID): re-pin"
    node "$DIR/pin-link.js" >>"$LOG" 2>&1
    LAST_RID="$CUR_RID"
  fi

  # 5) Public link health
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$LINK/healthz" 2>/dev/null || echo "000")
  case "$CODE" in
    200) FAIL=0 ;;
    *)
      FAIL=$((FAIL+1))
      log "public check code=$CODE fail=$FAIL"
      if [ "$FAIL" -ge 3 ]; then
        node "$DIR/pin-link.js" >>"$LOG" 2>&1
        FAIL=0
        sleep 5
      fi
      ;;
  esac

  sleep 60
done
