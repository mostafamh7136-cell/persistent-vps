#!/bin/bash
# session-restore.sh — VNC/XFCE 重启后自动恢复上次打开的应用（不重建用户文件）
sleep 8  # 等 XFCE 起来
chroot /srv/debian13 /bin/su - debian -c '
export DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 XDG_CONFIG_HOME=/home/debian/.config
APP_LIST=/home/debian/.session-apps
[ -f "$APP_LIST" ] || exit 0
# 剪贴板桥接（PRIMARY <-> CLIPBOARD）
pgrep -x autocutsel >/dev/null 2>&1 || {
  nohup autocutsel -selection PRIMARY -fork >/dev/null 2>&1 &
  nohup autocutsel -selection CLIPBOARD -fork >/dev/null 2>&1 &
}
while IFS= read -r cmdline; do
  [ -z "$cmdline" ] && continue
  bin=$(echo "$cmdline" | awk "{print \$1}")
  command -v "$bin" >/dev/null 2>&1 || continue
  pgrep -x "$(basename "$bin")" >/dev/null 2>&1 && continue
  nohup $cmdline >/dev/null 2>&1 &
  sleep 1
done < "$APP_LIST"
' 2>/dev/null
echo "[$(date '+%F %T')] session restored" >> /workspace/debian13-server/logs/session.log
