# GUIDE.md — Debian 13 Cloud Desktop: Build Order

The canonical, step-by-step build for the graphical cloud desktop subsystem of **persistent-vps**. The ready-to-run scripts live in `desktop/` — this guide is the build order and the contract they implement.

> **Read `AGENTS.md` first.** Three standing directives apply to every step:
> **1. ALWAYS ALIVE** (the VPS stays live, no matter what) · **2. MAXIMUM RESOURCES** (discover every capability/permission and use the maximum of everything: CPU, RAM, GPU, disk, network) · **3. SECRETS INTAKE** (no plaintext secrets anywhere in this public repo — collect `GATEWAY_USER`/`GATEWAY_PASS` and Tailscale keys from the user right after their first message; see `SECRETS.md`).

## ROLE

You are a senior Linux systems engineer. Build, debug, and ship a production-grade Debian 13 graphical cloud desktop that **survives container restarts**, exposes a **permanent public URL**, requires **HTTP Basic Auth on every entry point**, and **self-heals when any component dies**.

## Sandbox properties (expected)

- Linux x86_64, root, internet access, ~32 logical CPUs, no GPU (verify anyway — MAX RESOURCES directive).
- Node.js runtime with `pnpm`, `yarn`, `npm`. Python 3.11+ with `pip` (`--break-system-packages` if needed).
- The platform exposes a public URL via an `agentos-app.run` gateway when you publish a single-port HTTP service. The URL is derived from `appName`; `AGENTOS_RUNTIME_ID` changes on every container recycle. Your job is to pin the URL per instance dynamically and persistently.
- Tools available: `bash`, `debootstrap`, `chroot`, `wget`, `curl`, `git`, `websockify`, `uvicorn`, `fastapi`, `chromium`, `playwright`.

## Substitution policy

If a component is unavailable on the platform, substitute the closest equivalent and **state the substitution explicitly in the final report**. Do not skip steps. Substitutions used by this blueprint:

- RealVNC → **TigerVNC**
- Apache Guacamole → **noVNC + websockify**
- debootstrap unavailable → static tarball extraction or Docker-in-Docker (note in final report)

## FINAL DELIVERABLE

A single public URL:

```
https://<unique-pinned-id>.sg.agentos-app.run/desktop/vnc.html?autoconnect=1&resize=scale&path=websockify
```

that:

1. Asks for HTTP Basic Auth — credentials come from the user via secrets intake → `.env` (`GATEWAY_USER` / `GATEWAY_PASS`; UTF-8, Arabic passwords supported). Never hardcoded.
2. Loads a noVNC client that auto-connects.
3. Shows the Debian 13 XFCE desktop with full keyboard/mouse control.
4. Generates a completely unique, non-colliding subdomain per user/deployment, and preserves that same URL across container restarts (`.pinned_id` + re-pinning on `AGENTOS_RUNTIME_ID` change).

## ARCHITECTURE

```
┌─────────────────────────────────────────────────────────────────┐
│ Browser (any device)                                            │
│   ↓ HTTPS Basic Auth (UTF-8 supported)                          │
│ CloudStudio Gateway (TLS) — uniquely pinned subdomain            │
│   ↓ HTTP                                                        │
│ FastAPI Secure Desktop Gateway :6080                            │
│   ├─ /                → 302 → /desktop/vnc.html                  │
│   ├─ /desktop/        → static noVNC files                       │
│   ├─ /websockify      → WebSocket proxy (binary frames)          │
│   │     ↓                                                         │
│   │   websockify :6081 → Xtigervnc :5901                          │
│   └─ /healthz         → JSON 200 (open, for watchdog)            │
└─────────────────────────────────────────────────────────────────┘
```

A chroot at `/srv/debian13` runs Debian trixie with XFCE, Firefox, OpenCode AI, WorkBuddy shortcut, Node 22, Python 3.13. The chroot's `/proc`, `/sys`, `/dev` (with real `urandom`, `null`, `zero`, `random`, `full`, `tty`, `ptmx`, `kmsg`) are bind-mounted at every boot — programs inside the chroot require entropy and real devices.

All file paths below are relative to `/workspace/debian13-server` unless absolute. The scripts referenced live in this repository under `desktop/` and must be copied/synced to the workspace before use.

---

## STEP 0 — Workspace & Unique ID Generation

```bash
mkdir -p /workspace/debian13-server/{scripts,logs}
cd /workspace/debian13-server

# Generate a unique 16-hex-character ID if it does not already exist
if [ ! -f .pinned_id ]; then
  head -c 8 /dev/urandom | xxd -p > .pinned_id
fi
echo "Instance Unique ID: $(cat .pinned_id)"
```

## STEP 0.5 — Resource & Permission Discovery (MANDATORY — MAX RESOURCES directive)

Run the probe before building and after every recycle; act on every finding:

```bash
bash desktop/scripts/probe-resources.sh /tmp/resources.log
```

Act on what it reports: create zram swap if RAM is plentiful and swap is missing; parallelize builds with all cores; claim any GPU found (`/dev/dri` → bind-mount into the chroot); raise `ulimit -n` and tune `sysctl net.*` where permitted; use the fastest block device for `/workspace`. Anything you cannot lift — record it in the probe log and the final report. Never silently accept a cap you didn't try to lift.

## STEP 1 — Install Debian 13 chroot

```bash
apt-get update -qq && apt-get install -y -qq debootstrap
debootstrap --arch=amd64 trixie /srv/debian13 http://deb.debian.org/debian
```

If `debootstrap` is unavailable, use a static tarball extraction or pivot to Docker-in-Docker — note the substitution in the final report.

## STEP 2 — Bind mounts (`desktop/scripts/mount-chroot.sh`)

`/dev/urandom` MUST be the host's real device, not an empty file — Go programs (OpenCode, npm) hang without it.

```bash
bash desktop/scripts/mount-chroot.sh
```

The script bind-mounts `proc`, `sysfs`, `/dev` (rbind), `devpts`, and force-binds the critical device nodes (`null urandom random zero full tty kmsg ptmx`) so chroot programs get real entropy. It also bind-mounts `/dev/dri` into the chroot **if a GPU is present** (MAX RESOURCES). Safe to re-run (uses `mountpoint -q` guards).

## STEP 3 — Desktop + dev tools inside the chroot

```bash
bash desktop/scripts/install-desktop.sh    # XFCE4 + TigerVNC + noVNC + apps + locales (en, ar) + user 'debian'
bash desktop/scripts/install-devtools.sh   # Node 22 LTS, pip.conf, OpenCode AI CLI, WorkBuddy shortcut
```

Highlights:

- `--no-install-recommends` everywhere for a lean image; XFCE extras installed best-effort.
- Locales: `en_US.UTF-8` and `ar_SA.UTF-8` (Arabic support), Noto fonts (incl. CJK + emoji).
- User `debian` with passwordless sudo; VNC dir at `/home/debian/.vnc`.
- Node 22 LTS to `/opt/node22` with a PATH hook in `/etc/profile.d/00-path.sh`.
- `pip.conf` sets `break-system-packages = true` (Debian 13).
- OpenCode AI CLI v2 to `/opt/oc-cli/bin/opencode`; WorkBuddy desktop shortcut (`workbuddy.desktop`).
- **zram swap** is created automatically if none exists (MAX RESOURCES).

## STEP 4 — VNC setup (`desktop/scripts/ensure-vnc.sh`)

```bash
bash desktop/scripts/ensure-vnc.sh
```

Starts `Xtigervnc :1` (localhost-only, `1600x900`, depth 24, port 5901, no VNC-layer auth — the gateway is the security boundary) and `startxfce4` via `dbus-launch`. Idempotent: skips components already running. Always run after mounts; re-run by the watchdog whenever VNC dies.

## STEP 5 — Gateway dependencies (inside the chroot)

```bash
chroot /srv/debian13 /bin/bash -c "
apt-get install -y -qq --no-install-recommends python3-pip 2>&1 | tail -3
pip install --break-system-packages --quiet --ignore-installed fastapi 'uvicorn[standard]' websockets
python3 -c 'import fastapi, uvicorn, websockets; print(\"Dependencies OK\")'
"
```

## STEP 6 — Secure Desktop Gateway (`desktop/server.py`)

The gateway enforces HTTP Basic Auth on **every** entry point except the two open routes (`/healthz`, `/favicon.ico`). Credentials are read from the environment (`GATEWAY_USER` / `GATEWAY_PASS`) with **no defaults and no hardcoded values** — the secrets intake (`SECRETS.md`) fills `.env`. The password is compared as standard UTF-8 bytes, so Arabic (and any UTF-8) passwords validate correctly.

```bash
mkdir -p /workspace/debian13-server/desktop
cp desktop/server.py /srv/debian13/opt/desktop-gw/server.py   # after .env intake

# Copy noVNC assets into the chroot
mkdir -p /srv/debian13/opt/desktop-gw/novnc
cp -rf /usr/share/novnc/. /srv/debian13/opt/desktop-gw/novnc/ 2>/dev/null \
  || cp -rf /usr/share/webapps/novnc/. /srv/debian13/opt/desktop-gw/novnc/ 2>/dev/null \
  || { echo "Downloading noVNC 1.6.0 ..."; \
       wget -qO- https://github.com/novnc/noVNC/archive/refs/tags/v1.6.0.tar.gz \
       | tar -xz -C /tmp && cp -rf /tmp/noVNC-1.6.0/. /srv/debian13/opt/desktop-gw/novnc/; }
```

## STEP 7 — Startup (`desktop/start-desktop.sh`)

```bash
bash desktop/start-desktop.sh &
sleep 6
```

The script sources `.env` (secrets intake) — it **fails fast if `GATEWAY_USER`/`GATEWAY_PASS` are missing** — then: mounts the chroot, ensures VNC, starts websockify on `127.0.0.1:6081 → 127.0.0.1:5901`, and execs the gateway on `:6080` inside the chroot.

## STEP 8 — Pin the unique link (`desktop/pin-link.js`)

```bash
node desktop/pin-link.js > LINK.txt
cat LINK.txt
```

Reads or generates a completely unique 16-hex-char ID per user deployment, persists it in `.pinned_id` so the same user keeps the same URL after restarts while every different deployment gets a distinct URL, then pins `appName` to port 6080 with the platform and prints the public URL.

## STEP 9 — Dynamic watchdog (`desktop/keepalive.sh`)

```bash
nohup bash desktop/keepalive.sh >/dev/null 2>&1 & disown
```

Infinite loop, every 60s: restart `Xtigervnc` if dead → restart websockify if dead → restart the whole stack if `/healthz` fails → re-pin the URL when `AGENTOS_RUNTIME_ID` changes → probe the public URL and re-pin after 3 consecutive failures. This is the ALWAYS ALIVE directive as code.

## STEP 10 — Autostart hook (`desktop/boot.sh`)

```bash
bash desktop/boot.sh
```

Mounts the chroot, re-probes resources, spawns the watchdog if it isn't running, then execs `start-desktop.sh`. Wire this into whatever boot mechanism the platform gives you — the node must come back by itself after any recycle.

## STEP 11 — End-to-end verification

```bash
# 0. Local health (open route for the watchdog)
curl -sf http://127.0.0.1:6080/healthz
# Expected: {"ok":true,"service":"secure-desktop-gateway","auth":"basic"}

# 1. No credentials -> 401
curl -sI http://127.0.0.1:6080/ | head -n1
# Expected: HTTP/1.1 401 Unauthorized

# 2. With credentials from .env (UTF-8) -> 302
set -a; source .env; set +a
AUTH_HEADER=$(python3 - <<'EOF'
import base64, os
pair = f"{os.environ['GATEWAY_USER']}:{os.environ['GATEWAY_PASS']}".encode("utf-8")
print("Basic " + base64.b64encode(pair).decode("ascii"))
EOF
)
curl -sI -H "Authorization: $AUTH_HEADER" http://127.0.0.1:6080/ | head -n1
# Expected: HTTP/1.1 302 Found

# 3. Pinned public URL answers with the same auth behavior
curl -s -o /dev/null -w "%{http_code}\n" --max-time 15 "$(cat LINK.txt)/healthz"
# Expected: 200
```

## STEP 12 — Delivery to the user

Provide the user with their dynamic instance link:

- **Bare URL (recommended, works in all browsers):**
  `https://<unique-pinned-id>.sg.agentos-app.run`
  When the browser prompts, the user enters the credentials **they provided during secrets intake** (`GATEWAY_USER` / `GATEWAY_PASS`). The agent never prints the password back in full.

- **Direct noVNC link (URL-encoded credentials):** build it from `.env` values only if the user explicitly asks for an embedded-credentials link, and warn them it stores the password in browser history:

  ```bash
  python3 - <<'EOF'
  import os, urllib.parse, pathlib
  u = urllib.parse.quote(os.environ["GATEWAY_USER"], safe="")
  p = urllib.parse.quote(os.environ["GATEWAY_PASS"], safe="")
  host = pathlib.Path("LINK.txt").read_text().strip().removeprefix("https://")
  print(f"https://{u}:{p}@{host}/desktop/vnc.html?autoconnect=1&resize=scale&path=websockify")
  EOF
  ```

The final report must state: pinned URL, probe findings and resource actions taken (MAX RESOURCES), substitutions made, verification results, and remaining limitations.
