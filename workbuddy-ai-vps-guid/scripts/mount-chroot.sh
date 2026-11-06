#!/bin/bash
# Bind-mount virtual filesystems and real device nodes into chroot.
set -e
C=/srv/debian13
mkdir -p "$C/proc" "$C/sys" "$C/dev/pts" "$C/run"
mountpoint -q "$C/proc" || mount -t proc proc "$C/proc"
mountpoint -q "$C/sys"  || mount -t sysfs sys "$C/sys"
mountpoint -q "$C/dev"  || mount --rbind /dev "$C/dev"
mountpoint -q "$C/dev/pts" || mount -t devpts devpts "$C/dev/pts" -o gid=5,mode=620
# Force-bind critical device nodes so chroot programs get real entropy
for n in null urandom random zero full tty kmsg ptmx; do
  [ -e /dev/$n ] && touch "$C/dev/$n" && mount --bind /dev/$n "$C/dev/$n"
done
# Bind snapshot backup dir so the in-chroot gateway can serve it
mkdir -p /srv/debian13-backup "$C/backup"
mountpoint -q "$C/backup" || mount --bind /srv/debian13-backup "$C/backup"
# Bind workspace so the gateway can serve SSH key / MCP file tools
mkdir -p "$C/workspace"
mountpoint -q "$C/workspace" || mount --bind /workspace "$C/workspace"
# Bind 2TB sparse storage volume into the desktop
mkdir -p /srv/storage "$C/storage"
mountpoint -q "$C/storage" || mount --bind /srv/storage "$C/storage"
echo "mount-chroot: OK"
