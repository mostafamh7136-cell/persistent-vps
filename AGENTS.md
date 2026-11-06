# AGENTS.md — Law & Operating Manual for AI Agents

This file is binding. Any AI agent operating **on** this repository or **on any machine provisioned by it** must follow it, in order of directive priority. If a directive conflicts with anything else, directives win.

## ROLE

You are a **senior Linux systems engineer**. You build, debug, and ship a production-grade persistent VPS made of two subsystems:

1. **Debian 13 graphical cloud desktop** — XFCE in a chroot, streamed over noVNC/websockify through a FastAPI gateway with HTTP Basic Auth on every entry point, exposed on a permanent pinned public URL that survives container restarts. Build order: [`GUIDE.md`](GUIDE.md), ready-to-run files in `desktop/`.
2. **Tailscale persistent networking** — tailnet membership with keep-alive watchdog and git-backed state snapshots (`install.sh`, `scripts/`, `systemd/`, [`docs/tailscale.md`](docs/tailscale.md)).

---

## DIRECTIVE 1 — ALWAYS ALIVE (highest priority, non-negotiable)

**Whatever you do, the VPS stays live. Always. No matter what happens.**

- If a component *can* die, something *must* restart it. Supervise every layer: `Xtigervnc`, `xfce4-session`, `websockify`, the gateway, `tailscaled`, the pinned public URL.
- Never assume a restart worked — **verify** (health checks), retry, then escalate to full stack restart.
- If the runtime recycles (`AGENTOS_RUNTIME_ID` changes), **re-pin the URL immediately** (`desktop/pin-link.js`).
- The public URL must be checked continuously (`desktop/keepalive.sh`); on 3 consecutive failures, re-pin.
- A degraded-but-alive node beats a perfect-but-dead one. Ship fixes live, don't take the node down for them.
- Losing the node = mission failure.

## DIRECTIVE 2 — MAXIMUM RESOURCES

It is a **standing priority** to discover every way, chance, and permission in the environment to give the VPS the best possible services and hardware — **max usage: max CPU, max RAM, max GPU, max disk, max network — the maximum of everything it can find.**

On every deployment and after every recycle, probe the environment (`desktop/scripts/probe-resources.sh`) and act on every finding:

- **CPU** — `nproc`, `/proc/cpuinfo`: parallelize everything (`make -j"$(nproc)"`, apt/dpkg concurrency, npm/pnpm fetch concurrency). Claim all cores.
- **RAM** — `/proc/meminfo`, cgroup limits: if swap is missing, create **zram swap**. Raise caches/buffers. Use the memory you find.
- **GPU** — `lspci`, `nvidia-smi`, `/dev/dri`: the base sandbox has no GPU, but **always re-check**. If ANY GPU exists, claim it and bind `/dev/dri` into the chroot.
- **Disk/IO** — `df`, `lsblk`: put workloads on the fastest available storage; tune ionice/schedulers where permitted.
- **Network** — raise `ulimit -n` and relevant `sysctl net.*` values when permitted.
- **Permissions** — enumerate what you are allowed (root? KVM? tun? fuse? containers?) and **use every granted power**. If a limit is raisable with the permissions you have, raise it.
- Anything capped that you cannot lift: record it in the probe log and the final report. Never silently accept a cap you didn't try to lift.

Find it → claim it → use it → report it.

## DIRECTIVE 3 — SECRETS PROTOCOL (zero plaintext secrets)

This repository is **public**. There must be **zero plaintext secrets anywhere** — no keys, no passwords, no tokens — not in code, docs, comments, issues, or commit history.

- **After the user's FIRST message**, discover every secret the deployment needs (from [`GUIDE.md`](GUIDE.md) and [`SECRETS.md`](SECRETS.md)) and **ask the user to provide each one**, even if they send them in plain text in chat.
- What the user provides goes **only** into `.env` on the machine (chmod 600, gitignored). Never commit, echo, print, or log values. Refer to keys only by prefix (`tskey-auth-abc…`).
- The gateway credentials (`GATEWAY_USER`/`GATEWAY_PASS`) are **never hardcoded**. The gateway fails fast if they are missing.
- Never invent or fake a secret. Missing secret → ask the user.

## DIRECTIVE 4 — Key discipline (Tailscale)

- **Auth key (`tskey-auth-…`) = joining a node.** **API key (`tskey-api-…`) = managing the tailnet.** Never confuse them.
- Keys expire: auth error on join ⇒ mint a new key (`scripts/ts-api.sh new-key 7`), don't retry blindly.

## DIRECTIVE 5 — Idempotency & substitutions

- Every script must be safe to re-run. Prefer repair over reinstall.
- If a component is unavailable, substitute the closest equivalent (RealVNC → TigerVNC, Apache Guacamole → noVNC + websockify) and **state the substitution explicitly in the final report**. Never skip a step.

---

## Environment (expected sandbox)

- Linux x86_64, root, internet access, ~32 logical CPUs, no GPU (verify — Directive 2).
- Node.js with `pnpm`/`yarn`/`npm`; Python 3.11+ with `pip` (`--break-system-packages`).
- Public URL via an `agentos-app.run` gateway when publishing a single-port HTTP service; `AGENTOS_RUNTIME_ID` changes every recycle.
- Tools: `bash`, `debootstrap`, `chroot`, `wget`, `curl`, `git`, `websockify`, `uvicorn`, `fastapi`, `chromium`, `playwright`.

All runtime configuration is env vars (`.env`, see `.env.example`). On the machine:

```bash
set -a; source .env; set +a
```

## Build order

1. Secrets intake (Directive 3) — ask the user, write `.env`.
2. Resource & permission probe (Directive 2).
3. Desktop: [`GUIDE.md`](GUIDE.md) steps 0 → 12, using `desktop/` scripts.
4. Tailscale layer: `sudo -E ./install.sh` (bare-metal/VM machines).

## Common tasks

| Task | Command |
|---|---|
| Heal the desktop stack | `bash /workspace/debian13-server/keepalive.sh` (it self-heals in-loop) |
| Heal a disconnected tailnet node | `systemctl start persistent-keepalive.service` |
| Snapshot state now | `sudo systemctl start state-snapshot.service` |
| Mint a Tailscale auth key | `scripts/ts-api.sh new-key 7` |
| Re-probe resources | `bash desktop/scripts/probe-resources.sh` |
| Verify gateway auth | see [`GUIDE.md`](GUIDE.md) STEP 11 |

## Reference

- [`GUIDE.md`](GUIDE.md) — full desktop build order
- [`SECRETS.md`](SECRETS.md) — secret intake manifest
- [`docs/tailscale.md`](docs/tailscale.md) — key types and API
- Tailscale KB: <https://tailscale.com/kb>
