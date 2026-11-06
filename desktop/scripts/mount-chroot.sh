#!/bin/bash
# persistent-vps — bind-mount virtual filesystems and real device nodes into
# the Debian 13 chroot.
#
# CRITICAL: /dev/urandom MUST be the host's real device, not an empty file.
# Go programs (OpenCode, npm) hang without real entropy.
set -e

C=/srv/debian13
mkdir -p "$C/proc" "$C/sys" "$C/dev/pts" "$C/run"

mountpoint -q "$C/proc" || mount -t proc proc "$C/proc"
mountpoint -q "$C/sys"  || mount -t sysfs sys "$C/sys"
mountpoint -q "$C/dev"  || mount --rbind /dev "$C/dev"
mountpoint -q "$C/dev/pts" || mount -t devpts devpts "$C/dev/pts" -o gid=5,mode=620

# Force-bind critical device nodes so chroot programs get real entropy
for n in null urandom random zero full tty kmsg ptmx; do
  if [ -e /dev/$n ]; then
    touch "$C/dev/$n"
    mount --bind /dev/$n "$C/dev/$n"
  fi
done

# MAX RESOURCES: if a GPU is present on the host, claim it for the desktop.
if [ -d /dev/dri ]; then
  mkdir -p "$C/dev/dri"
  for card in /dev/dri/*; do
    touch "$C/dev/dri/$(basename "$card")" 2>/dev/null || true
    mount --bind "$card" "$C/dev/dri/$(basename "$card")" 2>/dev/null || true
  done
  echo "GPU (/dev/dri) bound into chroot"
fi
