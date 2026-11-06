#!/bin/bash
# desktop-check-inner.sh —— 在 chroot 内执行，检查并补齐桌面组件
# 这个脚本被 desktop-keepalive.sh 通过 chroot 调用
export DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 XDG_SESSION_TYPE=x11 LANG=en_US.UTF-8
export XDG_CONFIG_HOME=/home/debian/.config XDG_CACHE_HOME=/home/debian/.cache
export XAUTHORITY=/home/debian/.Xauthority

# X 还活着吗？
if ! xdpyinfo >/dev/null 2>&1; then
  exit 0
fi

# 桌面组件缺失就补 —— 从不杀
if ! pgrep -x xfce4-session >/dev/null 2>&1; then
  echo "[desktop-ka] xfce4-session gone -> relaunch full session"
  nohup dbus-launch startxfce4 >/tmp/xfce4.log 2>&1 </dev/null & disown
  sleep 4
else
  if ! pgrep -x xfwm4 >/dev/null 2>&1; then
    echo "[desktop-ka] xfwm4 missing -> starting"
    nohup xfwm4 --replace >/tmp/xfwm4.log 2>&1 </dev/null & disown
  fi
  if ! pgrep -x xfdesktop >/dev/null 2>&1; then
    echo "[desktop-ka] xfdesktop missing -> starting"
    nohup xfdesktop >/tmp/xfdesktop.log 2>&1 </dev/null & disown
  fi
  if ! pgrep -x xfce4-panel >/dev/null 2>&1; then
    echo "[desktop-ka] panel missing -> starting"
    nohup xfce4-panel >/tmp/xfce4-panel.log 2>&1 </dev/null & disown
  fi
fi

# 剪贴板桥接
if ! pgrep -x autocutsel >/dev/null 2>&1; then
  nohup autocutsel -selection PRIMARY -fork   >/dev/null 2>&1 </dev/null & disown
  nohup autocutsel -selection CLIPBOARD -fork >/dev/null 2>&1 </dev/null & disown
fi
