#!/bin/bash
export DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000
APP_LIST=/home/debian/.session-apps
: > "$APP_LIST"
for id in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | sed 's/.*#//' | tr ',' ' '); do
  pid=$(xprop -id "$id" _NET_WM_PID 2>/dev/null | awk '{print $3}')
  [ -z "$pid" ] && continue
  # 只跳过桌面/面板等壳层窗口，按窗口标题判断（避免误杀 xfce4-terminal 这类真实应用）
  name=$(xprop -id "$id" WM_NAME 2>/dev/null | sed 's/.*= *"//; s/"$//')
  case "$name" in
    xfce4-panel|Desktop|"") continue ;;
  esac
  cmd=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)
  [ -z "$cmd" ] && continue
  case "$cmd" in *autocutsel*|*Xvnc*|*sshd*|*xfwm4*|*xfdesktop*|*xfce4-session*) continue ;; esac
  echo "$cmd" >> "$APP_LIST"
done
sort -u "$APP_LIST" -o "$APP_LIST"
chown debian:debian "$APP_LIST" 2>/dev/null
echo "saved $(wc -l < "$APP_LIST") apps"
