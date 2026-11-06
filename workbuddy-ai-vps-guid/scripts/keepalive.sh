#!/bin/bash
DIR=/workspace/debian13-server
PINNED_ID=$(cat "$DIR/.pinned_id" 2>/dev/null || echo "default-node")
LINK="https://${PINNED_ID}.sg.agentos-app.run"
LOG=/tmp/desktop-keepalive.log
FAIL=0
SAVE_TICK=0
LAST_RID="${AGENTOS_RUNTIME_ID:-}"

log() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }
log "keepalive started for ID: $PINNED_ID (pid $$)"

# 独立的、更快的桌面保活循环（每 5 秒检查，纯增量补齐，绝不杀进程）
# 与主 keepalive 解耦，桌面恢复更快，且互不影响
pgrep -f "desktop-keepalive.sh" >/dev/null || {
  log "starting desktop-keepalive (sub-loop)"
  setsid nohup bash "$DIR/scripts/desktop-keepalive.sh" >/dev/null 2>&1 </dev/null &
  disown
}

while true; do
  # 1) VNC X server（pgrep -x 精确匹配进程名）
  #    只在 X 完全没了或卡死时才交给 ensure-vnc —— ensure-vnc 是纯增量式，绝不杀活的 X
  pgrep -x Xtigervnc >/dev/null || {
    log "Xtigervnc down -> ensure-vnc (fresh start)"; bash "$DIR/scripts/ensure-vnc.sh" >>"$LOG" 2>&1;
  }
  # 2) websockify
  pgrep -x websockify >/dev/null || {
    log "websockify down -> restarting"
    pkill -9 -f websockify >/dev/null 2>&1 || true; sleep 1
    nohup websockify --heartbeat=30 127.0.0.1:6081 127.0.0.1:5901 >>"$LOG" 2>&1 &
    disown; sleep 2
  }
  # 2.5) 快照循环（keepalive 自身从文件运行，命令行不含此模式，-f 匹配安全）
  pgrep -f "snapshot-loop.sh" >/dev/null || {
    log "snapshot-loop down -> restarting"
    setsid nohup bash "$DIR/scripts/snapshot-loop.sh" >/dev/null 2>&1 </dev/null &
    disown
  }
  # 2.5b) Docker daemon（只在没了时启动，绝不杀已有的；live-restore 已开）
  if ! pgrep -x dockerd >/dev/null 2>&1; then
    log "dockerd down -> starting"
    mkdir -p /var/run
    setsid nohup dockerd --host=unix:///var/run/docker.sock \
      --tlsverify --tlscacert /certs/server/ca.pem \
      --tlskey /certs/server/key.pem \
      --tlscert /certs/server/cert.pem \
      >>/tmp/dockerd.log 2>&1 </dev/null &
    disown
    sleep 3
  fi
  # 2.6) sshd
  pgrep -x sshd >/dev/null || {
    log "sshd down -> restarting"; bash "$DIR/scripts/ensure-sshd.sh" >>"$LOG" 2>&1;
  }
  # 2.6.5) share the host Tailscale socket with the Debian chroot
  mkdir -p /srv/debian13/run/tailscale
  if [ -d /run/tailscale ] && ! mountpoint -q /srv/debian13/run/tailscale; then
    mount --bind /run/tailscale /srv/debian13/run/tailscale >>"$LOG" 2>&1 \
      && log "Tailscale socket shared with Debian chroot" \
      || log "WARNING: failed to expose Tailscale socket to Debian chroot"
  fi
  # 2.7) tailscaled：只在进程不存在时才启动，绝不因为 status 超时就杀进程
  #      （杀进程会导致重新登录、设备离线；沙箱网络抖动时 status 超时是正常的）
  if ! pgrep -x tailscaled >/dev/null; then
    log "tailscaled process down -> starting"
    rm -f /run/tailscale/tailscaled.sock
    setsid nohup /usr/sbin/tailscaled --tun=userspace-networking \
      --state=/var/lib/tailscale/tailscaled.state \
      --socket=/run/tailscale/tailscaled.sock >>/tmp/tailscaled.log 2>&1 </dev/null &
    disown
    sleep 3
    # 确保 tailscale up（用已保存的 state，不需要重新登录）
    timeout 10 tailscale up --accept-routes=false --hostname=debian-vps 2>/dev/null || true
  fi
  # 2.8) 每 5 轮（约 5 分钟）保存一次桌面会话，供重启后恢复
  SAVE_TICK=$((SAVE_TICK+1))
  if [ $((SAVE_TICK % 5)) -eq 0 ]; then
    chroot /srv/debian13 /bin/su - debian -c '/usr/local/bin/session-save-inner.sh' >>"$DIR/logs/session.log" 2>&1
  fi
  # 3) Gateway
  if ! curl -sf --max-time 5 http://127.0.0.1:6080/healthz >/dev/null; then
    log "gateway (6080) down -> restarting"
    pkill -9 -f "desktop-gw/server.py" >/dev/null 2>&1 || true; sleep 2
    setsid nohup bash "$DIR/start-desktop.sh" >>/tmp/desktop-gw.log 2>&1 </dev/null &
    disown; sleep 6
  fi
  # 4) URL re-pin if runtimeId changed
  CUR_RID="${AGENTOS_RUNTIME_ID:-}"
  if [ -n "$CUR_RID" ] && [ "$CUR_RID" != "$LAST_RID" ]; then
    log "runtimeId changed ($LAST_RID -> $CUR_RID): re-pin"
    node "$DIR/pin-link.js" >>"$LOG" 2>&1
    LAST_RID="$CUR_RID"
  fi
  # 5) Public link health
  #    重要：链接失败时只做无害的 re-pin，绝不重启任何桌面/容器/X 进程
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$LINK/healthz" 2>/dev/null || echo "000")
  case "$CODE" in
    200) FAIL=0 ;;
    *)   FAIL=$((FAIL+1)); log "public check code=$CODE fail=$FAIL"
         if [ "$FAIL" -ge 3 ]; then
           node "$DIR/pin-link.js" >>"$LOG" 2>&1
           FAIL=0
         fi ;;
  esac
  sleep 8   # 从 60s 降到 8s：桌面/网关出问题能更快发现
done

# ===== watchdog 自保活：万一上面 while 循环意外退出，立刻重启自己 =====
log "keepalive loop exited unexpectedly -> self-restart"
exec bash "$0"
