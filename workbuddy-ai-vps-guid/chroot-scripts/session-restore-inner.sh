#!/bin/bash
export DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 XDG_CONFIG_HOME=/home/debian/.config
APP_LIST=/home/debian/.session-apps
sleep 6
pgrep -x autocutsel >/dev/null 2>&1 || {
  nohup autocutsel -selection PRIMARY -fork >/dev/null 2>&1 &
  nohup autocutsel -selection CLIPBOARD -fork >/dev/null 2>&1 &
}
[ -f "$APP_LIST" ] || exit 0
while IFS= read -r cmdline; do
  [ -z "$cmdline" ] && continue
  bin=$(echo "$cmdline" | awk '{print $1}')
  command -v "$bin" >/dev/null 2>&1 || continue
  pgrep -x "$(basename "$bin")" >/dev/null 2>&1 && continue
  nohup $cmdline >/dev/null 2>&1 &
  sleep 1
done < "$APP_LIST"
