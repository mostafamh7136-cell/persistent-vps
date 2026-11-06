# AGENTS.md

Operating manual for AI agents working **on** this repository and **on any VPS provisioned by it**.

## What this repo is

A blueprint for a **persistent VPS**: a machine that

1. **stays connected** to a Tailscale tailnet (watchdog + keep-alive), and
2. **saves its state** (daily git snapshots of `PERSIST_DIR`, restorable anytime).

The repo is **public**, so secrets never live here — they live in `.env` on the node.

## Golden rules

1. **Secrets stay in `.env` on the machine.** Never commit, print, echo, or paste `tskey-auth-…` or `tskey-api-…` values — in commits, issues, PRs, logs, or chat. If you must refer to a key, show a prefix (`tskey-auth-abc…`).
2. **Auth key = joining. API key = managing.** `TAILSCALE_AUTH_KEY` (auth key) registers a node with `tailscale up --auth-key=…`. `TAILSCALE_API_KEY` (API key) manages the tailnet via `scripts/ts-api.sh`. Never confuse the two.
3. **This repo is public.** State snapshots that may contain secrets go to a private `STATE_GIT_REMOTE` or stay local.
4. **Everything is idempotent.** All scripts must be safe to re-run. Prefer repairing over reinstalling.
5. **Keys expire.** Auth keys can be single-use; API keys expire after ≤90 days. If a join fails with an auth error, the key is probably expired — mint a new one instead of retrying blindly.

## Environment

All configuration is env vars (see `.env.example`). On the node, load them with:

```bash
set -a; source .env; set +a
```

## Common tasks

### Provision a new node

```bash
cp .env.example .env && edit .env      # set TAILSCALE_AUTH_KEY, VPS_HOSTNAME
sudo -E ./install.sh
tailscale status                        # verify: node appears in the tailnet
```

### Heal a disconnected node

```bash
systemctl status tailscaled
systemctl start persistent-keepalive.service     # runs the watchdog immediately
journalctl -u persistent-keepalive.service -n 50
```

The watchdog restarts `tailscaled` if the backend is not `Running`.

### Snapshot state now / restore

```bash
sudo systemctl start state-snapshot.service       # snapshot immediately
sudo PERSIST_DIR=/srv/persistent scripts/state-save.sh
git clone /var/lib/persistent-vps/state.git /tmp/restore   # restore a snapshot
```

### Mint a new auth key (API key required)

```bash
scripts/ts-api.sh new-key 7            # pre-auth, reusable, 7-day expiry
```

### Rotate keys

1. Mint a new key: `scripts/ts-api.sh new-key 7`
2. Update `.env` on the node.
3. Revoke the old key in the admin console or via the API.

## Toolbox

| Tool | Purpose |
|---|---|
| `install.sh` | Bootstrap: install Tailscale, join tailnet, enable timers |
| `scripts/keep-alive.sh` | Connection watchdog (runs via `persistent-keepalive.timer`) |
| `scripts/state-save.sh` | Git snapshot of `PERSIST_DIR` (runs via `state-snapshot.timer`) |
| `scripts/ts-api.sh` | Tailscale API wrapper: `devices`, `device <id>`, `delete-device <id>`, `new-key [ttl-days]` |

## Reference

- Tailscale keys: [`docs/tailscale.md`](docs/tailscale.md)
- Tailscale KB: <https://tailscale.com/kb>
- Tailscale API: <https://tailscale.com/api>
