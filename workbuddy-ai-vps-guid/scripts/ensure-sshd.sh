#!/bin/bash
# ensure-sshd.sh — 启动/自愈 sshd（chroot 内 Debian 13，监听 22，仅密钥认证）
# 说明：SSH 必须落到 Debian 13 chroot 里，而不是 Ubuntu 宿主，因此固定走 chroot。
DIR=/workspace/debian13-server
LOG="$DIR/logs/sshd.log"
mkdir -p "$DIR/logs"

port_up() { chroot /srv/debian13 /bin/bash -c 'ss -tln 2>/dev/null | grep -q ":22 "' ; }

if port_up; then
  echo "[$(date '+%F %T')] sshd: listening" >> "$LOG"
  exit 0
fi

for attempt in 1 2 3; do
  chroot /srv/debian13 /bin/bash -c 'mkdir -p /run/sshd && chmod 0755 /run/sshd'
  chroot /srv/debian13 /bin/bash -c '/usr/sbin/sshd -e >>/tmp/sshd-start.log 2>&1' 2>>"$LOG"
  sleep 1
  if ! port_up; then
    chroot /srv/debian13 /bin/bash -c 'setsid nohup /usr/sbin/sshd -D -e >>/tmp/sshd-start.log 2>&1 </dev/null &' 2>>"$LOG"
    sleep 2
  fi
  if port_up; then
    echo "[$(date '+%F %T')] sshd: started (attempt $attempt)" >> "$LOG"
    exit 0
  fi
  sleep 2
done

echo "[$(date '+%F %T')] sshd: FAILED after 3 attempts" >> "$LOG"
tail -8 /srv/debian13/tmp/sshd-start.log 2>/dev/null >> "$LOG"
exit 1
