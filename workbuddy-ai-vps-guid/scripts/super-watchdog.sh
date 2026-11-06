#!/bin/bash
# super-watchdog.sh —— watchdog 的 watchdog
# 唯一职责：每 30 秒检查 keepalive.sh 是否活着，死了就拉起。
# 自身用 setsid 启动，父进程退出不会带走它。
# 如果自己意外退出，会 exec 重启自己。
DIR=/workspace/debian13-server
LOG=/tmp/super-watchdog.log

while true; do
  if ! pgrep -f "keepalive.sh" >/dev/null 2>&1; then
    echo "[$(date '+%F %T')] keepalive DEAD -> resurrecting" >> "$LOG"
    setsid nohup bash "$DIR/keepalive.sh" >>"$LOG" 2>&1 </dev/null &
    disown
    sleep 5
  fi
  # 同时确认 desktop-keepalive 子循环也在
  if ! pgrep -f "desktop-keepalive.sh" >/dev/null 2>&1; then
    echo "[$(date '+%F %T')] desktop-keepalive DEAD -> resurrecting" >> "$LOG"
    setsid nohup bash "$DIR/scripts/desktop-keepalive.sh" >>"$LOG" 2>&1 </dev/null &
    disown
  fi
  sleep 30
done

# 意外退出 -> 自重启
echo "[$(date '+%F %T')] super-watchdog exited unexpectedly -> self-restart" >> "$LOG"
exec bash "$0"
