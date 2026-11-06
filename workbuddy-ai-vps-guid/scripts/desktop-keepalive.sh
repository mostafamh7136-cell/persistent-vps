#!/bin/bash
# desktop-keepalive.sh —— 纯增量桌面保活循环
# 每 5 秒调用一次 desktop-check-inner.sh（在 chroot 内执行）
# 缺什么补什么，绝不杀进程，绝不重启 X -> 窗口和应用永远不丢
DIR=/workspace/debian13-server
LOG=/tmp/desktop-ka-loop.log
echo "[$(date '+%F %T')] desktop-keepalive started (pid $$)" >> "$LOG"

while true; do
  # 调用 chroot 内的检查脚本，任何错误都不会杀死外层循环
  chroot /srv/debian13 /bin/su - debian -c /usr/local/bin/desktop-check-inner.sh >> "$LOG" 2>&1 || true
  sleep 5
done

# 意外退出 -> 自重启
echo "[$(date '+%F %T')] desktop-keepalive exited unexpectedly -> self-restart" >> "$LOG"
exec bash "$0"
