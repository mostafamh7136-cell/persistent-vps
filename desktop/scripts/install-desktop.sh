#!/bin/bash
# persistent-vps — install XFCE desktop + system tools inside the Debian 13
# chroot. Idempotent.
set -e
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8 LANG=C.UTF-8

chroot /srv/debian13 /bin/bash -c '
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  xfce4 xfce4-terminal xfce4-goodies thunar-archive-plugin \
  xorg dbus-x11 \
  tigervnc-standalone-server tigervnc-viewer websockify novnc \
  sudo locales keyboard-configuration console-setup \
  firefox-esr libreoffice thunderbird vlc gimp \
  fonts-noto fonts-noto-cjk fonts-noto-color-emoji \
  ca-certificates curl wget git unzip nano vim less \
  build-essential python3 python3-pip python3-venv

# XFCE extras (best effort)
apt-get install -y -qq --no-install-recommends \
  xfce4-whiskermenu-plugin xfce4-indicator-plugin xfce4-pulseaudio-plugin \
  xfce4-battery-plugin xfce4-datetime-plugin xfce4-weather-plugin || true

# Locales (English and Arabic)
sed -i "s/# en_US.UTF-8/en_US.UTF-8/; s/# ar_SA.UTF-8/ar_SA.UTF-8/" /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

# Desktop user with passwordless sudo
id debian 2>/dev/null || useradd -m -s /bin/bash debian
echo "debian ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/debian
chmod 440 /etc/sudoers.d/debian

# VNC dir
mkdir -p /home/debian/.vnc
chown -R debian:debian /home/debian
'

# MAX RESOURCES: create zram swap inside the chroot if there is no swap yet
# (uses host RAM as compressed swap — big win on desktop workloads).
if ! chroot /srv/debian13 /bin/bash -c 'swapon --show | grep -q .' 2>/dev/null; then
  chroot /srv/debian13 /bin/bash -c '
    modprobe zram 2>/dev/null || true
    if [ -e /dev/zram0 ]; then
      echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null || true
      echo $(( $(nproc) * 1024 * 512 )) > /sys/block/zram0/disksize 2>/dev/null || true
      mkswap /dev/zram0 >/dev/null 2>&1 && swapon -p 100 /dev/zram0 || true
      echo "zram swap enabled"
    fi
  ' || true
fi

echo "desktop installed."
