#!/bin/bash
# snapshot-loop.sh — 每 60 秒执行一次快照
DIR=/workspace/debian13-server
echo "[$(date '+%F %T')] snapshot-loop started (pid $$)" >> "$DIR/logs/snapshot.log"
while true; do
  bash "$DIR/scripts/snapshot.sh"
  sleep 60
done
