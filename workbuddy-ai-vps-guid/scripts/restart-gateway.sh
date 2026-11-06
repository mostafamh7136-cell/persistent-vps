#!/bin/bash
# 重启网关：模式写在文件里，避免匹配调用者 shell 命令行导致自杀
pkill -9 -f "desktop-gw/server.py" 2>/dev/null
sleep 2
setsid nohup bash /workspace/debian13-server/start-desktop.sh \
  > /workspace/debian13-server/logs/start-desktop.log 2>&1 < /dev/null &
sleep 6
curl -sf http://127.0.0.1:6080/healthz && echo
