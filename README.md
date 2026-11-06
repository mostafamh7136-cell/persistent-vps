# persistent-vps

> A persistent VPS blueprint that **saves its state** and **stays connected** — powered by [Tailscale](https://tailscale.com), built to be operated by humans *and* agents.

## What it does

- 🔗 **Always connected** — a systemd watchdog checks the tailnet every 5 minutes and repairs broken connections automatically
- 💾 **State that survives** — daily git snapshots of your persistent directory, restorable at any time
- 🤖 **Agent-first** — `AGENTS.md` is a complete operating manual, so an AI agent can provision, heal, and maintain the node
- 🔑 **Key discipline** — auth keys join nodes, API keys manage the tailnet; secrets live in `.env` and never in git

## Quickstart

On a fresh Ubuntu/Debian box (as root):

```bash
git clone https://github.com/mostafamh7136-cell/persistent-vps.git
cd persistent-vps
cp .env.example .env        # put your TAILSCALE_AUTH_KEY inside
nano .env
sudo -E ./install.sh
```

`install.sh` will:

1. Install Tailscale (official installer)
2. Join your tailnet with the auth key, with a stable hostname and Tailscale SSH
3. Install the keep-alive + state-snapshot scripts and systemd timers

When it finishes, the node is reachable from anywhere in your tailnet as `VPS_HOSTNAME` over Tailscale SSH.

## Layout

```
├── install.sh                    # one-shot bootstrap (Tailscale + systemd)
├── scripts/
│   ├── keep-alive.sh             # watchdog: keep the tailnet connection alive
│   ├── state-save.sh             # git-backed snapshots of PERSIST_DIR
│   └── ts-api.sh                 # Tailscale API wrapper (devices, auth keys)
├── systemd/
│   ├── persistent-keepalive.{service,timer}
│   └── state-snapshot.{service,timer}
├── docs/
│   └── tailscale.md              # auth key vs API key, and how to use each
├── AGENTS.md                     # operating manual for AI agents
├── .env.example                  # all configuration, copied to .env
│
└── workbuddy-ai-vps-guid/        # WorkBuddy-AI VPS GUID (see below)
    ├── scripts/                  # host-layer: boot, keepalive, VNC, watchdogs
    ├── chroot-scripts/           # Debian 13 chroot: desktop check, session save/restore
    ├── desktop-gateway/          # FastAPI gateway (noVNC + SSH-over-WS + MCP)
    ├── ssh-client/               # zero-dependency SSH connector
    ├── configs/                  # Docker mirror, XFCE session config
    └── README.md                 # full documentation
```

## Configuration

Everything is configured through environment variables (see `.env.example`):

| Variable | Required | Purpose |
|---|---|---|
| `TAILSCALE_AUTH_KEY` | ✅ | Auth key (`tskey-auth-…`) used to join this node to the tailnet |
| `VPS_HOSTNAME` | – | Stable hostname for the node (default `persistent-vps`) |
| `TAILSCALE_PEER` | – | Peer to ping in keep-alive checks (keeps NAT mappings warm) |
| `PERSIST_DIR` | – | Directory whose state is snapshotted (default `/srv/persistent`) |
| `STATE_GIT_REMOTE` | – | **Private** git remote for snapshots; empty = local-only |
| `TAILSCALE_API_KEY` | – | API key (`tskey-api-…`) for `scripts/ts-api.sh` |
| `TAILNET_NAME` | – | Your tailnet name, e.g. `example.ts.net` |

## How it works

**Keep-alive** — `persistent-keepalive.timer` runs `keep-alive.sh` every 5 minutes. It checks the Tailscale backend state, restarts `tailscaled` if the node fell off the tailnet, and optionally pings a peer so NAT mappings never go stale.

**State persistence** — `state-snapshot.timer` runs `state-save.sh` daily (04:00). It commits the contents of `PERSIST_DIR` into a bare git repo at `/var/lib/persistent-vps/state.git`, and pushes to `STATE_GIT_REMOTE` (branch `state`) if set. Restore anytime:

```bash
git clone /var/lib/persistent-vps/state.git restored-state
```

## For agents

This repo is designed to be operated by AI agents. If you are an agent (or scripting one), read [`AGENTS.md`](AGENTS.md) first — it covers provisioning, healing, snapshots, key rotation, and the safety rules that keep secrets out of this public repo.

## Security

- This repository is **public**: never commit `.env`, auth keys, or API keys.
- Prefer **single-use, pre-authorized, tagged** auth keys for joining nodes.
- Rotate the API key regularly (they expire after 90 days at most).
- Push state snapshots only to a **private** remote — they may contain data.

---

## WorkBuddy-AI VPS GUID

A complete **persistent cloud desktop** blueprint built and battle-tested inside a WorkBuddy AI sandbox. It provides a VNC desktop whose **open windows and apps never get lost**, a **three-layer self-healing watchdog chain**, Tailscale that **stays online in the background**, and Docker that **always works**.

→ **Full documentation**: [`workbuddy-ai-vps-guid/README.md`](workbuddy-ai-vps-guid/README.md)

### Highlights

| Feature | How |
|---|---|
| VNC desktop never loses session | Pure incremental recovery — never kills a running X server, only restores missing XFCE components |
| Open windows/apps persist | XFCE AutoSave + custom `.session-apps` dual mechanism (save every ~5 min, restore on restart) |
| Three-layer watchdog | `super-watchdog` (30s) → `keepalive` (8s) → `desktop-keepalive` (5s), all self-restart on exit |
| Tailscale stays online | Started first in boot; keepalive only starts (never kills) on network jitter |
| Docker always works | `dockerd` keepalive + `live-restore: true` + Tencent mirror |
| SSH from anywhere | SSH-over-WebSocket tunnel through the authenticated gateway |
| MCP endpoint | Sandboxed read-only tools for AI agents (system_health, list_dir, read_file, run_safe) |

## License

[MIT](LICENSE)
