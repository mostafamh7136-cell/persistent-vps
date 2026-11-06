#!/bin/bash
# session-save.sh — 记录当前桌面打开的 GUI 应用（供重启后恢复），仅记录，不影响会话
DIR=/workspace/debian13-server
STATE=/srv/debian13/home/debian/.session-apps
mkdir -p /srv/debian13/home/debian
: > "$STATE"

chroot /srv/debian13 /bin/su - debian -c '
export DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000
# 剪贴板桥接（PRIMARY <-> CLIPBOARD），保证与 noVNC 的复制粘贴互通
pgrep -x autocutsel >/dev/null 2>&1 || {
  nohup autocutsel -selection PRIMARY -fork >/dev/null 2>&1 &
  nohup autocutsel -selection CLIPBOARD -fork >/dev/null 2>&1 &
}
# 枚举顶层窗口 -> 取 PID -> 取 cmdline，写入待恢复清单
for id in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | sed "s/.*#//" | tr "," " "); do
  pid=$(xprop -id "$id" _NET_WM_PID 2>/dev/null | awk "{print \$3}")
  [ -z "$pid" ] && continue
  cmd=$(tr "\0" " " < /proc/$pid/cmdline 2>/dev/null)
  [ -z "$cmd" ] && continue
  case "$cmd" in
    */autocutsel*|*xfce4-panel*|*xfdesktop*|*xfwm4*|*xfc*|*Xvnc*|*sshd*) continue ;;
  esac
  echo "$cmd" >> /home/debian/.session-apps
done
' 2>/dev/null

chown 1000:1000 /srv/debian13/home/debian/.session-apps 2>/dev/null
sort -u "$STATE" -o "$STATE"
echo "[$(date '+%F %T')] session saved: $(wc -l < "$STATE") apps" >> "$DIR/logs/session.log"
