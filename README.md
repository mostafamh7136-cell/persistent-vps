# persistent-vps

> A persistent VPS blueprint that **always stays alive**, **maxes out every resource it can find**, and **never stores a secret in plaintext** — a Debian 13 XFCE cloud desktop + Tailscale persistent networking, built to be operated by humans *and* agents.

## What it does

**Subsystem 1 — Debian 13 Cloud Desktop** ([`GUIDE.md`](GUIDE.md), `desktop/`)

- 🖥️ **Graphical cloud desktop** — Debian 13 (trixie) XFCE in a chroot, streamed to any browser via noVNC + websockify
- 🔐 **Basic Auth on every entry point** — UTF-8 credentials (Arabic passwords supported), sourced from `.env` via the secrets intake; `/healthz` stays open for the watchdog
- 📌 **Permanent pinned URL** — unique 16-hex subdomain per deployment, persisted in `.pinned_id`, re-pinned automatically when the container recycles
- 🩹 **Self-healing** — a watchdog supervises VNC, XFCE, websockify, the gateway, and the public URL; anything that dies gets restarted within 60s
- 🚀 **Max resources** — a mandatory boot probe discovers CPU, RAM, GPU, disk, and permission limits; zram swap, GPU passthrough, raised limits — claim everything the environment grants

**Subsystem 2 — Tailscale Persistent Networking** (`install.sh`, `scripts/`, `systemd/`)

- 🔗 **Always connected** — systemd watchdog keeps the node on your tailnet
- 💾 **State that survives** — daily git snapshots of your persistent directory

## The three directives (`AGENTS.md`)

Agents operating this repo are bound by, in priority order:

1. **ALWAYS ALIVE** — the VPS stays live, no matter what happens. Everything supervised, everything self-healing.
2. **MAXIMUM RESOURCES** — discover every capability, permission, and limit; use the maximum of everything (CPU, RAM, GPU, disk, network). Find it → claim it → use it.
3. **SECRETS PROTOCOL** — zero plaintext secrets in this public repo. The agent asks the user for every needed secret right after their first message ([`SECRETS.md`](SECRETS.md)) and stores them only in `.env` on the machine.

## Quickstart (cloud desktop)

Follow [`GUIDE.md`](GUIDE.md) steps 0 → 12 on the sandbox:

```bash
# 1. Secrets intake: the agent asks you for GATEWAY_USER / GATEWAY_PASS first
# 2. Build
bash desktop/scripts/mount-chroot.sh
bash desktop/scripts/install-desktop.sh
bash desktop/scripts/install-devtools.sh
bash desktop/scripts/probe-resources.sh
bash desktop/start-desktop.sh &
node desktop/pin-link.js > LINK.txt
nohup bash desktop/keepalive.sh >/dev/null 2>&1 & disown
```

## Quickstart (Tailscale, on a VM/bare metal)

```bash
git clone https://github.com/mostafamh7136-cell/persistent-vps.git
cd persistent-vps
cp .env.example .env        # agent collects secrets from you -> .env
sudo -E ./install.sh
```

## Layout

```
├── GUIDE.md                        # Debian 13 cloud desktop build order (steps 0-12)
├── AGENTS.md                       # binding directives + operating manual
├── SECRETS.md                      # secret intake manifest (names only, never values)
├── desktop/
│   ├── server.py                   # FastAPI gateway — Basic Auth on every entry point
│   ├── start-desktop.sh            # boots: mounts -> VNC -> websockify -> gateway
│   ├── boot.sh                     # autostart hook (mounts, watchdog, stack)
│   ├── keepalive.sh                # ALWAYS ALIVE watchdog loop
│   ├── pin-link.js                 # unique pinned subdomain, survives restarts
│   └── scripts/                    # mount-chroot, install-desktop, install-devtools,
│                                   # ensure-vnc, probe-resources
├── install.sh                      # Tailscale bootstrap
├── scripts/                        # keep-alive, state-save, ts-api (Tailscale)
├── systemd/                        # timers for keep-alive + state snapshots
├── docs/tailscale.md               # auth key vs API key guide
└── .env.example                    # all configuration — no values, ever
```

## Configuration

Everything is env vars in `.env` (see `.env.example`; the agent fills it during secrets intake):

| Variable | Subsystem | Purpose |
|---|---|---|
| `GATEWAY_USER` | desktop | HTTP Basic Auth username (every entry point) |
| `GATEWAY_PASS` | desktop | HTTP Basic Auth password — UTF-8, Arabic supported |
| `TAILSCALE_AUTH_KEY` | tailscale | Auth key (`tskey-auth-…`) to join the tailnet |
| `TAILSCALE_API_KEY` | tailscale | API key (`tskey-api-…`) for tailnet management |
| `TAILNET_NAME` | tailscale | Tailnet name, e.g. `example.ts.net` |
| `VPS_HOSTNAME` | tailscale | Stable hostname in the tailnet |
| `TAILSCALE_PEER` | tailscale | Peer pinged to keep NAT mappings warm |
| `PERSIST_DIR` | tailscale | Snapshotted directory (default `/srv/persistent`) |
| `STATE_GIT_REMOTE` | tailscale | **Private** git remote for snapshots |

## Security

- This repository is **public**: never commit `.env`, keys, or passwords. The gateway has **no hardcoded credentials** — it refuses to start without them.
- Prefer single-use, pre-authorized, tagged Tailscale auth keys.
- Push state snapshots only to a **private** remote.
- See [`SECRETS.md`](SECRETS.md) for the full intake protocol.

## License

[MIT](LICENSE)
