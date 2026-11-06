#!/bin/bash
# tune-system.sh — 把现有硬件资源用满（注意：CPU/RAM/GPU 由平台分配，本脚本只做软件层最大化利用）
DIR=/workspace/debian13-server
LOG="$DIR/logs/tune.log"
log() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }

# 1) 内存：降低换出倾向、提高脏页回写阈值，优先保证 VNC/Blender 常驻内存
sysctl -w vm.swappiness=10            >>"$LOG" 2>&1 || log "warn: swappiness"
sysctl -w vm.dirty_ratio=15           >>"$LOG" 2>&1 || log "warn: dirty_ratio"
sysctl -w vm.dirty_background_ratio=5 >>"$LOG" 2>&1 || log "warn: dirty_background"
sysctl -w vm.max_map_count=1048576    >>"$LOG" 2>&1 || log "warn: max_map_count"

# 2) 文件/进程上限
ulimit -n 1048576 2>/dev/null || true
sysctl -w fs.file-max=2097152 >>"$LOG" 2>&1 || log "warn: file-max"

# 3) 桌面进程优先级：VNC/XFCE/sshd 提升调度优先级，避免被批处理任务抢占
for p in Xtigervnc xfce4-session sshd websockify; do
  for pid in $(pgrep -x "$p"); do
    renice -n -5 -p "$pid" >/dev/null 2>&1 || true
  done
done

# 4) Blender 全核渲染（Cycles 默认 auto；显式写死 32 线程）
CORE=$(nproc)
if [ -x /opt/blender-threads ]; then :; fi
log "tune done: cores=$CORE mem=$(free -g | awk '/^Mem:/{print $2"G"}') swappiness=$(cat /proc/sys/vm/swappiness)"
