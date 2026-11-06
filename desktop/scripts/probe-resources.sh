#!/bin/bash
# persistent-vps — MAX RESOURCES probe.
#
# Standing priority (AGENTS.md Directive 2): discover every capability,
# permission, and limit in the environment, then USE the maximum of
# everything found (CPU, RAM, GPU, disk, network). Run at boot, after every
# recycle, and whenever anything feels slower than it should be.
#
# Usage: probe-resources.sh [logfile]
set -uo pipefail
LOG="${1:-/tmp/resources.log}"

{
echo "=== probe $(date -u +%FT%TZ) ==="

echo "-- CPU --"
nproc 2>/dev/null
grep -m1 "model name" /proc/cpuinfo 2>/dev/null

echo "-- RAM --"
free -h 2>/dev/null
grep -E "MemTotal|SwapTotal" /proc/meminfo 2>/dev/null

echo "-- SWAP --"
if swapon --show 2>/dev/null | grep -q .; then
  swapon --show
else
  echo "NO SWAP -> create zram swap (see install-desktop.sh)"
fi

echo "-- DISK --"
df -h / /workspace /srv 2>/dev/null
lsblk -o NAME,SIZE,ROTA,TYPE 2>/dev/null

echo "-- GPU --"
if lspci 2>/dev/null | grep -iEq "vga|3d controller|nvidia"; then
  lspci | grep -iE "vga|3d|nvidia"
else
  echo "no GPU on PCI bus"
fi
nvidia-smi 2>/dev/null | head -6 || true
if [ -d /dev/dri ]; then ls -la /dev/dri; else echo "no /dev/dri"; fi

echo "-- CGROUP LIMITS --"
cat /sys/fs/cgroup/cpu.max 2>/dev/null || echo "cgroup v2 cpu.max not readable"
cat /sys/fs/cgroup/memory.max 2>/dev/null || echo "cgroup v2 memory.max not readable"

echo "-- ULIMITS --"
ulimit -a

echo "-- PERMISSIONS / ACCELERATION --"
for c in docker podman kvm qemu qemu-system-x86_64; do
  command -v "$c" >/dev/null 2>&1 && echo "$c: available"
done
[ -e /dev/kvm ] && echo "KVM: available" || echo "no /dev/kvm"
[ -c /dev/net/tun ] && echo "TUN: available" || echo "no /dev/net/tun"

echo "-- NETWORK --"
ip -brief addr 2>/dev/null || true
sysctl net.core.somaxconn 2>/dev/null || true

echo "=== end probe ==="
} >> "$LOG" 2>&1

echo "probe written to $LOG"
echo "NEXT (Directive 2): act on every finding — claim cores, add zram, bind"
echo "GPUs into the chroot, raise limits where permitted. Record what you"
echo "cannot lift in the final report."
