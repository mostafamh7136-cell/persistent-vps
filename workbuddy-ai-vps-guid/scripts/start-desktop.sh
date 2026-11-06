#!/bin/bash
DIR=/workspace/debian13-server
bash "$DIR/scripts/mount-chroot.sh" >/dev/null 2>&1

mkdir -p /srv/debian13/opt/desktop-gw/novnc
cp -f "$DIR/desktop/server.py" /srv/debian13/opt/desktop-gw/server.py

bash "$DIR/scripts/ensure-vnc.sh" >/tmp/boot-vnc.log 2>&1
bash "$DIR/scripts/ensure-sshd.sh" >/tmp/boot-sshd.log 2>&1 || true

# Websockify listening on 6081
if ! pgrep -f "websockify.*6081" >/dev/null; then
  pkill -9 -f websockify >/dev/null 2>&1 || true
  sleep 1
  nohup websockify --heartbeat=30 127.0.0.1:6081 127.0.0.1:5901 \
    >/tmp/websockify.log 2>&1 &
  disown
  sleep 2
fi

exec chroot /srv/debian13 /bin/bash -c '
export PATH=/usr/local/bin:/usr/bin:/bin
export PORT=6080
export GATEWAY_USER="admin"
export GATEWAY_PASS="سيرفر_سحابي_آمن@13"
exec /usr/bin/python3 /opt/desktop-gw/server.py
'
