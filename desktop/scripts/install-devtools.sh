#!/bin/bash
# persistent-vps — install dev tools inside the Debian 13 chroot:
# Node 22 LTS, pip config, OpenCode AI CLI, WorkBuddy shortcut.
# Idempotent: skips anything already installed.
set -e

# Node.js 22 LTS
NODE_VER=22.13.1
if [ ! -x /opt/node22/bin/node ]; then
  cd /tmp
  wget -q "https://nodejs.org/dist/v${NODE_VER}/node-v${NODE_VER}-linux-x64.tar.xz"
  tar -xJf "node-v${NODE_VER}-linux-x64.tar.xz"
  rm -rf /opt/node22
  mv "node-v${NODE_VER}-linux-x64" /opt/node22
  rm "node-v${NODE_VER}-linux-x64.tar.xz"
fi

# PATH hook
cat > /etc/profile.d/00-path.sh <<'EOF'
export PATH="/opt/node22/bin:/opt/oc-cli/bin:/usr/local/bin:/usr/bin:/bin"
export NODE_PATH="/opt/node22/lib/node_modules"
EOF
chmod +x /etc/profile.d/00-path.sh

# pip.conf override for Debian 13
cat > /etc/pip.conf <<'EOF'
[global]
break-system-packages = true
EOF

# OpenCode AI v2 CLI
OC_VER=2.0.29
if [ ! -x /opt/oc-cli/bin/opencode ]; then
  cd /tmp
  wget -q "https://github.com/sst/opencode/releases/download/v${OC_VER}/opencode-linux-x64.tar.gz" || true
  if [ -f opencode-linux-x64.tar.gz ]; then
    tar -xzf opencode-linux-x64.tar.gz
    rm -rf /opt/oc-cli
    mkdir -p /opt/oc-cli/bin
    mv opencode /opt/oc-cli/bin/
    chmod +x /opt/oc-cli/bin/opencode
    rm opencode-linux-x64.tar.gz
  else
    echo "NOTE: opencode tarball unavailable — substitute the closest "
    echo "equivalent (e.g. npm i -g opencode-ai) and record the substitution."
  fi
fi

# WorkBuddy shortcut
mkdir -p /home/debian/Desktop
cat > /home/debian/Desktop/workbuddy.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=WorkBuddy
Exec=firefox-esr --new-window https://workbuddy.cn
Icon=utilities-terminal
Terminal=false
EOF
chmod +x /home/debian/Desktop/workbuddy.desktop
chown -R debian:debian /home/debian/Desktop

echo "devtools installed."
