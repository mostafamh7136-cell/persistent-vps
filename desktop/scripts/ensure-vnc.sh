#!/bin/bash
# persistent-vps — ensure VNC + XFCE are running inside the chroot.
# Idempotent: skips components that are already up. Used by the watchdog.
set -e

chroot /srv/debian13 /bin/su - debian -c '
export DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 XDG_SESSION_TYPE=x11 LANG=en_US.UTF-8
mkdir -p /run/user/1000 && chmod 700 /run/user/1000
export XDG_CONFIG_HOME=/home/debian/.config
export XDG_CACHE_HOME=/home/debian/.cache

if ! pgrep -f "Xtigervnc :1" >/dev/null; then
  /usr/bin/Xtigervnc :1 \
    -localhost=1 \
    -desktop "Debian 13 Desktop" \
    -geometry 1600x900 \
    -depth 24 \
    -rfbport 5901 \
    -SecurityTypes None \
    -AlwaysShared \
    >/tmp/xvnc.log 2>&1 &
  disown
  sleep 3
fi

if ! pgrep -f "xfce4-session" >/dev/null; then
  nohup dbus-launch startxfce4 >/tmp/xfce4.log 2>&1 &
  disown
  sleep 5
fi
'
