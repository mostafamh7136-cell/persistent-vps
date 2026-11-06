#!/bin/bash
DIR=/workspace/debian13-server
bash "$DIR/scripts/mount-chroot.sh" >/dev/null 2>&1
bash "$DIR/scripts/tune-system.sh" >/dev/null 2>&1

# ---- Tailscale：最先启动，确保即使没连 VNC 也保持在线 ----
mkdir -p /var/lib/tailscale /run/tailscale
if ! pgrep -x tailscaled >/dev/null; then
  setsid nohup /usr/sbin/tailscaled --tun=userspace-networking \
    --state=/var/lib/tailscale/tailscaled.state \
    --socket=/run/tailscale/tailscaled.sock >>/tmp/tailscaled.log 2>&1 </dev/null &
  disown
  sleep 3
  timeout 10 tailscale up --accept-routes=false --hostname=debian-vps 2>/dev/null || true
fi

# keepalive 用 setsid 完全脱离终端 + 新会话，任何父进程退出都不会带走它
pgrep -f "keepalive.sh" >/dev/null || {
  setsid nohup bash "$DIR/keepalive.sh" >/dev/null 2>&1 </dev/null & disown
}
pgrep -f "snapshot-loop.sh" >/dev/null || {
  setsid nohup bash "$DIR/scripts/snapshot-loop.sh" >/dev/null 2>&1 </dev/null & disown
}
# 超级 watchdog：确保 keepalive 自身永不被杀（替代不可用的 cron）
pgrep -f "super-watchdog.sh" >/dev/null || {
  setsid nohup bash "$DIR/scripts/super-watchdog.sh" >/dev/null 2>&1 </dev/null & disown
}
# 立即触发一次桌面保活，确保开机就有桌面
pgrep -f "desktop-keepalive.sh" >/dev/null || {
  setsid nohup bash "$DIR/scripts/desktop-keepalive.sh" >/dev/null 2>&1 </dev/null & disown
}
exec bash "$DIR/start-desktop.sh"
