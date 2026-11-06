#!/bin/bash
# ensure-vnc.sh —— 纯增量式保活：只补缺失的进程，绝不杀、绝不重启已运行的 X/桌面
# 这样已打开的窗口和应用永远不会丢失。
set +e   # 任何单步失败都不退出，继续保活

# 以 root 预创建运行时目录
chroot /srv/debian13 /bin/bash -c '
mkdir -p /run/user/1000 /tmp/.X11-unix
chown 1000:1000 /run/user/1000 /tmp/.X11-unix 2>/dev/null
chmod 700 /run/user/1000
chmod 1777 /tmp/.X11-unix
' 2>/dev/null

# 全部在 chroot 内执行，DISPLAY=:1
chroot /srv/debian13 /bin/su - debian -c '
export DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 XDG_SESSION_TYPE=x11 LANG=en_US.UTF-8
export XDG_CONFIG_HOME=/home/debian/.config XDG_CACHE_HOME=/home/debian/.cache
export XAUTHORITY=/home/debian/.Xauthority

# ---- 1) X server：只在完全没有时才启动（绝不重启）----
if ! pgrep -x Xtigervnc >/dev/null 2>&1; then
  echo "[ensure-vnc] Xtigervnc not running -> starting fresh (windows on a dead X are already gone)"
  /usr/bin/Xtigervnc :1 \
    -localhost=1 \
    -desktop "Debian 13 Desktop" \
    -geometry 1600x900 \
    -depth 24 \
    -rfbport 5901 \
    -SecurityTypes None \
    -AlwaysShared \
    >/tmp/xvnc.log 2>&1 &
  disown
  # 等 X 起来
  for i in $(seq 1 10); do xdpyinfo >/dev/null 2>&1 && break; sleep 1; done
else
  # X 还在 —— 确保能连上，连不上说明 X 卡死（罕见），只能重启 X
  if ! DISPLAY=:1 xdpyinfo >/dev/null 2>&1; then
    echo "[ensure-vnc] Xtigervnc process exists but X unresponsive -> must restart X (last resort)"
    # 这种情况下窗口本来就保不住了，重启 X
    pkill -x Xtigervnc 2>/dev/null; sleep 2
    /usr/bin/Xtigervnc :1 -localhost=1 -desktop "Debian 13 Desktop" \
      -geometry 1600x900 -depth 24 -rfbport 5901 -SecurityTypes None -AlwaysShared \
      >/tmp/xvnc.log 2>&1 &
    disown
    for i in $(seq 1 10); do xdpyinfo >/dev/null 2>&1 && break; sleep 1; done
  fi
fi

# ---- 2) 桌面组件：缺什么补什么，绝不杀已运行的 ----
# xfce4-session 是顶层，它不在就整个拉起（会自动带起 wm/panel/desktop）
if ! pgrep -x xfce4-session >/dev/null 2>&1; then
  echo "[ensure-vnc] xfce4-session missing -> launching full session"
  nohup dbus-launch startxfce4 >/tmp/xfce4.log 2>&1 </dev/null &
  disown
  sleep 6
else
  # session 在，但子组件可能掉了 —— 单独补
  if ! pgrep -x xfwm4 >/dev/null 2>&1; then
    echo "[ensure-vnc] xfwm4 missing -> starting (windows stay)"
    nohup xfwm4 --replace >/tmp/xfwm4.log 2>&1 </dev/null & disown
    sleep 2
  fi
  if ! pgrep -x xfdesktop >/dev/null 2>&1; then
    echo "[ensure-vnc] xfdesktop missing -> starting (icons/wallpaper back)"
    nohup xfdesktop >/tmp/xfdesktop.log 2>&1 </dev/null & disown
    sleep 2
  fi
  if ! pgrep -x xfce4-panel >/dev/null 2>&1; then
    echo "[ensure-vnc] panel missing -> starting"
    nohup xfce4-panel >/tmp/xfce4-panel.log 2>&1 </dev/null & disown
    sleep 2
  fi
fi

# ---- 3) 剪贴板桥接 ----
pgrep -x autocutsel >/dev/null 2>&1 || {
  nohup autocutsel -selection PRIMARY -fork >/dev/null 2>&1 </dev/null & disown
  nohup autocutsel -selection CLIPBOARD -fork >/dev/null 2>&1 </dev/null & disown
}

# ---- 4) 会话恢复（只在刚拉起完整 session 后补一次窗口）----
if [ ! -f /tmp/.desktop-restored ]; then
  setsid nohup /usr/local/bin/session-restore-inner.sh >/tmp/session-restore.log 2>&1 </dev/null &
  disown
  touch /tmp/.desktop-restored
fi

echo "ensure-vnc: OK (xfce=$(pgrep -x xfce4-session|head -1) wm=$(pgrep -x xfwm4|head -1) desk=$(pgrep -x xfdesktop|head -1) panel=$(pgrep -x xfce4-panel|head -1))"
'
