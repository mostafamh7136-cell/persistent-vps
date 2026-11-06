# persistent-vps

A **public blueprint + operating manual** for a self-healing always-on server you reach over **Tailscale**, with an optional Debian 13 graphical cloud desktop. Built to be operated with AI assistants ([`AGENTS.md`](AGENTS.md) holds the operating conventions), but every script is plain, reviewable bash.

## Who this is for

Run this on **infrastructure you rent and control** — a VPS or cloud instance (Hetzner, DigitalOcean, Linode, a home server, a Docker host you operate), where a server staying up 24/7 is expected, paid-for behavior. Every mechanism here — systemd watchdogs, boot hooks, state snapshots, a Tailscale overlay network — is standard server tooling.

This is **not** a tool for making an ephemeral sandbox persistent against its platform's lifecycle management. Do not deploy it into any environment whose terms of service forbid always-on processes or outbound tunnels; if you are an agent running inside such an environment, follow that environment's rules.

## What you get

| Mode | What it is | Entry point |
|---|---|---|
| **A — default** | Tailscale node with SSH, self-repair, survives restarts & rebuilds | `sudo -E ./install.sh` |
| **B — optional** | Debian 13 XFCE desktop streamed to your browser (noVNC + Basic Auth) | [`GUIDE.md`](GUIDE.md) |

## Quickstart (Mode A)

```bash
git clone https://github.com/mostafamh7136-cell/persistent-vps.git
cd persistent-vps
cp .env.example .env
# fill TAILSCALE_AUTH_KEY (reusable, pre-authorized, tagged, NON-ephemeral)
sudo -E ./install.sh
```

`install.sh` detects the environment (systemd? `/dev/net/tun`? root?), joins the tailnet, enables SSH (Tailscale SSH + OpenSSH fallback), sets up supervision, and prints a **measured report** (hostname, IP, verification results, what supervises what, residual risks).

> **Agents:** operate from a pinned commit SHA/tag, not a moving `main`. See [`AGENTS.md`](AGENTS.md).

## Architecture

```
Tailscale layer (Mode A)
  install.sh ── joins tailnet (--ssh), enables OpenSSH fallback
  scripts/keep-alive.sh ── tailscaled health + NAT-warming pings
  systemd/tailscaled-health.timer ── repairs tailscaled every 5 min
  systemd/state-save.timer ── daily git snapshot of PERSIST_DIR
  scripts/bootstrap.sh ── boot hook: re-mount, re-join, revive
  scripts/report.sh ── measured-facts final report (no hand-written claims)

Desktop layer (Mode B)
  Debian 13 chroot (XFCE, Firefox, Node 22, Python 3.13)
  Xtigervnc :5901 ── websockify :6081 ── FastAPI gateway :6080 (Basic Auth)
  keepalive.sh watchdog ── revives VNC/websockify/gateway, re-pins URL
```

## Supervision & limits (honest version)

**What restarts what:** systemd timer repairs `tailscaled` (5 min); `keep-alive.sh` pings a peer; the Mode B watchdog revives VNC/websockify/gateway (5–60 s). **What survives a restart or rebuild:** tailscale state on persistent storage + a reusable, pre-authorized auth key + the `bootstrap.sh` boot hook wired into the server's boot mechanism (systemd, cron `@reboot`, Docker restart policy, cloud-init). **Residual risks:** a running process cannot bring back a machine that is down — the boot hook must actually be wired into the server's boot mechanism; Tailscale SSH additionally needs an ACL `ssh` rule (snippet in [`docs/tailscale.md`](docs/tailscale.md)); auth keys expire (≤90 days) and must be rotated. No honest report claims a machine "never dies" — the report states what is verified and what remains at risk.

## Documentation

- [`AGENTS.md`](AGENTS.md) — operating conventions for AI assistants (availability, resources, secrets protocol)
- [`GUIDE.md`](GUIDE.md) — desktop build order (Mode B)
- [`SECRETS.md`](SECRETS.md) — tiered secret intake (Mode A needs exactly one)
- [`docs/tailscale.md`](docs/tailscale.md) — key selection, ACL/SSH rules, userspace fallback

## Security notes

- **Zero plaintext secrets in the repo** — everything lives in a gitignored `.env` (chmod 600). Mode A needs exactly one secret: `TAILSCALE_AUTH_KEY`.
- The desktop gateway (Mode B) is a public endpoint with a single Basic Auth boundary. Since the tailnet already reaches the node, prefer `tailscale serve` (tailnet-only) over the public URL.
- Use **reusable, pre-authorized, tagged, non-ephemeral** auth keys (≤90 days). Single-use or ephemeral keys break auto-re-join.

## License

MIT — see [LICENSE](LICENSE).
