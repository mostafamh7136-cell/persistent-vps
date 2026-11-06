# WorkBuddy-AI VPS GUID

> A **persistent cloud desktop** blueprint built inside a WorkBuddy sandbox — the VNC desktop, open windows, and apps **never get lost**, Tailscale **stays online**, and Docker **always works**, all maintained by a three-layer self-healing watchdog chain.

This section documents the complete solution that was built and battle-tested inside a WorkBuddy AI sandbox environment. It is a real, working implementation — not a stub.

---

## What it solves

| Problem | Solution |
|---|---|
| VNC desktop goes black / session lost | Three-layer watchdog + **pure incremental recovery** — never kills a running X server, only restores missing components (xfwm4, xfdesktop, panel) |
| Open windows and apps disappear | XFCE AutoSave + custom `.session-apps` dual mechanism — saves the list of open GUI apps every ~5 min and restores them after any restart |
| Tailscale drops when you leave the VNC tab | `tailscaled` started at **the earliest point** in boot; keepalive only starts (never kills) the process on network jitter |
| Docker stops working | `dockerd` keepalive with `live-restore: true` + Tencent mirror for fast image pulls |
| 504 gateway errors | Gateway health check every 8s; re-pins public URL on runtime ID change without restarting any desktop process |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    WorkBuddy Sandbox (Ubuntu)                │
│                                                              │
│  boot.sh ──► Tailscale (first!) ──► keepalive.sh ──► desktop │
│                                         │                    │
│              ┌──────────────────────────┤                    │
│              ▼                          ▼                    │
│   super-watchdog.sh          desktop-keepalive.sh             │
│   (30s loop, ensures         (5s loop, chroot-internal,      │
│    keepalive stays alive)     incremental component repair)   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐     │
│  │         Debian 13 Chroot (/srv/debian13)             │     │
│  │                                                      │     │
│  │  Xtigervnc :1 (1600x900) ──► websockify :6081       │     │
│  │       │                                              │     │
│  │  XFCE4 (xfce4-session, xfwm4, xfdesktop, panel)     │     │
│  │       │                                              │     │
│  │  session-save-inner.sh ──► ~/.session-apps           │     │
│  │  session-restore-inner.sh ◄── ~/.session-apps        │     │
│  │                                                      │     │
│  │  sshd :22 (key-only) ──► WebSocket tunnel ──► :6080  │     │
│  └─────────────────────────────────────────────────────┘     │
│                                                              │
│  Gateway (FastAPI, :6080) ── Basic Auth ── noVNC web client  │
│       ├─ /desktop/vnc.html (resize=remote, autoconnect)      │
│       ├─ /ssh (WebSocket → TCP tunnel to :22)                │
│       ├─ /snapshot.tar.gz (authenticated download)           │
│       └─ /mcp (Model Context Protocol endpoint)              │
└─────────────────────────────────────────────────────────────┘
```

### Three-layer watchdog chain

| Layer | Script | Interval | Role |
|---|---|---|---|
| 1 | `super-watchdog.sh` | 30s | Ensures `keepalive.sh` and `desktop-keepalive.sh` stay alive; resurrects them if killed |
| 2 | `keepalive.sh` | 8s | Main watchdog: VNC X server, websockify, dockerd, sshd, tailscaled, gateway, public URL health |
| 3 | `desktop-keepalive.sh` | 5s | Chroot-internal: checks xfce4-session/xfwm4/xfdesktop/panel, restores missing ones without killing anything |

**Key principle**: All recovery is **pure incremental** — if a component is missing, it starts it. If it's running, it leaves it alone. This means open windows and apps are never destroyed.

---

## File inventory

### `scripts/` — Host-layer scripts (run on the sandbox host)

| File | Purpose |
|---|---|
| `boot.sh` | Bootstrap entry point. Starts Tailscale first, then keepalive, snapshot loop, super-watchdog, desktop-keepalive, finally launches the desktop gateway |
| `keepalive.sh` | Main 8s watchdog loop. Monitors Xtigervnc, websockify, dockerd, sshd, tailscaled, gateway, public URL. Self-restarts on unexpected exit |
| `start-desktop.sh` | Mounts chroot, copies gateway, starts VNC+sshd+websockify, launches FastAPI gateway on :6080 |
| `pin-link.js` | Pins the public URL to a stable subdomain using the platform's artifact-release API (survives container runtime ID changes) |
| `ensure-vnc.sh` | Pure incremental VNC/XFCE recovery. Starts X server only if absent; restores missing desktop components without killing running ones |
| `desktop-keepalive.sh` | 5s loop calling `desktop-check-inner.sh` inside the chroot. Decoupled from main keepalive for faster desktop recovery |
| `super-watchdog.sh` | 30s loop ensuring keepalive.sh and desktop-keepalive.sh stay alive (replaces unavailable cron) |
| `ensure-sshd.sh` | Starts/heals sshd inside the chroot (port 22, key-only auth). 3 retry attempts |
| `mount-chroot.sh` | Bind-mounts /proc, /sys, /dev, device nodes, workspace, storage into `/srv/debian13` |
| `tune-system.sh` | System tuning: swappiness=10, dirty ratios, file-max, process priority (nice -5 for VNC/XFCE/sshd) |
| `session-save.sh` | Saves open GUI app list to `.session-apps` (host-side wrapper) |
| `session-restore.sh` | Restores apps from `.session-apps` after desktop restart (host-side wrapper) |
| `install-desktop.sh` | Installs XFCE4, TigerVNC, websockify, noVNC, Firefox, LibreOffice, Blender, etc. inside chroot |
| `install-devtools.sh` | Installs Node.js 22 LTS, OpenCode AI CLI, WorkBuddy desktop shortcut |
| `restart-gateway.sh` | Restarts the FastAPI gateway without touching VNC/X session |
| `snapshot-loop.sh` | 60s loop running `snapshot.sh` |
| `snapshot.sh` | Creates validated tar.gz snapshot of scripts + system state, commits to local git repo, pushes if remote+token available |

### `chroot-scripts/` — Scripts that run inside `/srv/debian13` (Debian 13)

| File | Install path | Purpose |
|---|---|---|
| `desktop-check-inner.sh` | `/usr/local/bin/` | Called by desktop-keepalive every 5s. Checks X alive, then incrementally restores xfce4-session/xfwm4/xfdesktop/panel/autocutsel |
| `session-save-inner.sh` | `/usr/local/bin/` | Enumerates X11 windows via xprop, extracts PID→cmdline, filters out shell/desktop processes, writes to `~/.session-apps` |
| `session-restore-inner.sh` | `/usr/local/bin/` | Reads `~/.session-apps`, launches each app if not already running |

### `desktop-gateway/` — FastAPI gateway

| File | Purpose |
|---|---|
| `server.py` | Full gateway: Basic Auth (UTF-8 Arabic password support), noVNC web client, WebSocket proxy to websockify, SSH-over-WebSocket tunnel, snapshot download, MCP endpoint with sandboxed tools |

**Gateway routes:**
- `GET /` → redirects to noVNC (`resize=remote`, autoconnect, reconnect)
- `GET /scale` → noVNC with `resize=scale` (fallback)
- `GET /healthz` → unauthenticated health check
- `WS /websockify` → VNC WebSocket proxy
- `WS /ssh` → SSH-over-WebSocket tunnel (Basic Auth required)
- `GET /ssh/id_ed25519` → SSH private key download (Basic Auth required)
- `GET /snapshot.tar.gz` → system snapshot download (Basic Auth required)
- `POST /mcp` → MCP Streamable HTTP endpoint (sandboxed tools: system_health, snapshot_latest, list_dir, read_file, run_safe)

### `ssh-client/` — Client-side SSH connector

| File | Purpose |
|---|---|
| `ssh-connect.py` | Zero-dependency Python SSH client. Downloads key via Basic Auth, starts local TCP↔WSS bridge on :2222, calls system `ssh` |
| `id_ed25519.pub` | SSH public key (safe to share) |

> **Private key is NOT in this repo** — it lives on the server only and is downloaded authenticated via the gateway.

### `configs/` — Configuration files

| File | Install path | Purpose |
|---|---|---|
| `registries.conf` | `/etc/containers/registries.conf` | Docker/Podman mirror config (Tencent Cloud `mirror.ccs.tencentyun.com`) |
| `xfce4-session.xml` | `~/.config/xfce4/xfconf/xfce-perchannel-xml/` | XFCE session config with `AutoSave=true`, `SaveOnQuit=true`, `PromptOnLogout=false` |

---

## Setup guide

### Prerequisites

- A WorkBuddy sandbox (or similar environment) with root access
- Internet access (GitHub, Cloudflare reachable)
- Tailscale auth key (`tskey-auth-...`) for joining the tailnet
- ~10GB free disk for the Debian 13 chroot + desktop packages

### Step 1: Create the Debian 13 chroot

```bash
# Install debootstrap on the host
apt-get update && apt-get install -y debootstrap

# Create Debian 13 (trixie) chroot
debootstrap --variant=minbase trixie /srv/debian13 http://deb.debian.org/debian

# Bind-mount virtual filesystems
bash scripts/mount-chroot.sh
```

### Step 2: Install desktop + dev tools inside chroot

```bash
bash scripts/install-desktop.sh
bash scripts/install-devtools.sh
```

### Step 3: Install chroot-internal scripts

```bash
cp chroot-scripts/desktop-check-inner.sh   /srv/debian13/usr/local/bin/
cp chroot-scripts/session-save-inner.sh    /srv/debian13/usr/local/bin/
cp chroot-scripts/session-restore-inner.sh /srv/debian13/usr/local/bin/
chmod +x /srv/debian13/usr/local/bin/*.sh
```

### Step 4: Apply configurations

```bash
# Docker/Podman mirror
mkdir -p /etc/containers
cp configs/registries.conf /etc/containers/registries.conf

# XFCE session auto-save
CHROOT_HOME=/srv/debian13/home/debian
mkdir -p "$CHROOT_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
cp configs/xfce4-session.xml "$CHROOT_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/"
chown -R 1000:1000 "$CHROOT_HOME/.config"
```

### Step 5: Install Tailscale (userspace networking)

```bash
curl -fsSL https://pkgs.tailscale.com/stable/tailscale_latest_amd64.tgz | tar xz -C /tmp
mv /tmp/tailscale_*/tailscaled /usr/sbin/
mv /tmp/tailscale_*/tailscale /usr/local/bin/

# Start with userspace networking (no /dev/net/tun needed)
mkdir -p /var/lib/tailscale /run/tailscale
setsid nohup /usr/sbin/tailscaled --tun=userspace-networking \
  --state=/var/lib/tailscale/tailscaled.state \
  --socket=/run/tailscale/tailscaled.sock >>/tmp/tailscaled.log 2>&1 &

# Join tailnet
tailscale up --auth-key=tskey-auth-YOURKEY --hostname=debian-vps
```

### Step 6: Install Docker (with live-restore)

```bash
# Configure live-restore so containers survive daemon restarts
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{"live-restore": true}
EOF

# Start dockerd
setsid nohup dockerd --host=unix:///var/run/docker.sock >>/tmp/dockerd.log 2>&1 &
```

### Step 7: Generate SSH keys

```bash
ssh-keygen -t ed25519 -f ssh-client/id_ed25519 -C "debian13-cloud-desktop" -N ""
# Install public key into chroot
mkdir -p /srv/debian13/home/debian/.ssh
cp ssh-client/id_ed25519.pub /srv/debian13/home/debian/.ssh/authorized_keys
chown -R 1000:1000 /srv/debian13/home/debian/.ssh
chmod 700 /srv/debian13/home/debian/.ssh
chmod 600 /srv/debian13/home/debian/.ssh/authorized_keys
```

### Step 8: Copy gateway into chroot and launch

```bash
mkdir -p /srv/debian13/opt/desktop-gw/novnc
cp desktop-gateway/server.py /srv/debian13/opt/desktop-gw/server.py
# Copy noVNC web client
cp -r /usr/share/novnc/* /srv/debian13/opt/desktop-gw/novnc/ 2>/dev/null || true

# Launch everything
bash scripts/boot.sh
```

---

## Connecting to the desktop

### VNC (browser)

```
https://admin:PASSWORD@YOUR_SUBDOMAIN.sg.agentos-app.run/desktop/vnc.html?autoconnect=1&resize=scale&path=websockify
```

- `resize=remote` — desktop resolution follows browser window (no black borders)
- `resize=scale` — proportional scaling (fallback)
- `reconnect=1` — auto-reconnect on disconnect without rebuilding session

### SSH (from any machine)

```bash
python3 ssh-client/ssh-connect.py              # interactive shell
python3 ssh-client/ssh-connect.py "blender -v" # run a command
```

The script auto-downloads the SSH key (authenticated), starts a local TCP↔WSS bridge on port 2222, and connects via `ssh`.

---

## How session persistence works

1. **XFCE AutoSave** (`xfce4-session.xml`): XFCE natively saves session state on logout and restores on next login.
2. **Custom `.session-apps`** (dual mechanism): Every ~5 minutes, `session-save-inner.sh` enumerates all X11 windows via `xprop -root _NET_CLIENT_LIST`, extracts each window's PID and command line, filters out shell/desktop infrastructure processes, and writes the list to `~/.session-apps`.
3. **On restore**: After XFCE starts, `session-restore-inner.sh` reads the list and re-launches each app if it's not already running.
4. **Incremental desktop repair**: `desktop-check-inner.sh` runs every 5 seconds. If `xfwm4` crashes, it starts a new one — but your windows stay because the X server (`Xtigervnc`) is never killed. If `xfdesktop` crashes, icons/wallpaper come back. If the panel dies, it reappears.

---

## Tailscale persistence notes

The keepalive logic for Tailscale is deliberately conservative:

- `tailscaled` is started at the **earliest point** in `boot.sh`, before anything else.
- The keepalive loop **only starts** tailscaled if the process is truly absent — it **never kills** tailscaled on a `status --json` timeout (network jitter is normal; killing the process would force a re-login and drop the device).
- The Tailscale socket is bind-mounted into the Debian chroot so `tailscale` CLI works from inside the desktop too.

> **Sandbox limitation**: Some sandbox firewalls block Tailscale's control plane IPs (`192.200.0.x`). If Tailscale can't reach `controlplane.tailscale.com`, it will stay in a relay-only mode via DERP servers. This is an infrastructure constraint, not a script bug. On a normal VPS without such firewall rules, Tailscale works fully.

---

## Docker persistence

- `dockerd` is monitored by `keepalive.sh` every 8s — if the process is absent, it's started with `setsid nohup`.
- `live-restore: true` in `/etc/docker/daemon.json` ensures running containers survive daemon restarts.
- Image pulls are accelerated via Tencent Cloud mirror (`mirror.ccs.tencentyun.com`).

---

## Snapshot system

`snapshot.sh` runs every 60 seconds and:

1. Stages all scripts + a lightweight system state manifest (dpkg list, pip list, node version, status.yaml)
2. Creates a validated `tar.gz` (gzip CRC + tar structure + content spot-check)
3. Commits to a local git repo at `/srv/debian13-backup/repo` only if content changed
4. Pushes to a remote if configured and a token is available
5. Serves the snapshot via `GET /snapshot.tar.gz` (Basic Auth protected)

---

## MCP endpoint

The gateway exposes a sandboxed MCP (Model Context Protocol) endpoint at `POST /mcp`:

| Tool | Description |
|---|---|
| `system_health` | VNC/XFCE/websockify/sshd/gateway status + uptime + disk |
| `snapshot_latest` | sha256, size, mtime, recent git commits of latest snapshot |
| `list_dir` | List whitelisted directories (`/workspace/debian13-server`, `/backup/repo`) |
| `read_file` | Read whitelisted text files (max 64KB) |
| `run_safe` | Run whitelisted read-only commands (`uptime`, `df -h`, `free -h`, `date`, `hostname`, `ss -tln`) |

All tools are path-sandboxed (symlink-resolved) and command-whitelisted (`shell=False`, exact match).

---

## Security notes

- The gateway password in `server.py` and `start-desktop.sh` is a **default placeholder** — change `GATEWAY_PASS` before production use.
- **Never commit the SSH private key** (`id_ed25519`) to a public repo. Only the public key is included here.
- The `.session-apps` file may contain command lines with arguments — if those contain secrets, ensure your snapshot remote is private.
- MCP tools are strictly read-only and sandboxed — no write/exec beyond the allowlist.
