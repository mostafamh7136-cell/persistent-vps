# SECRETS.md — Tiered Secret Intake Manifest

This file lists **what** secrets exist and **which tier** needs them. **No values live here — ever.** The repository is public; a leaked secret here is a compromised server.

## Intake protocol (for agents)

1. Right after the user's first message, ask **only for the secrets your mode needs** — not everything on this page. Mode A needs exactly one secret.
2. Store answers **only** in `.env` on the machine (`chmod 600 .env`, gitignored).
3. Never echo a value back in full — confirm receipt by prefix only (`tskey-auth-abc…`).
4. Missing secret at runtime → stop and ask. Do not invent, do not hardcode.

## Tier 1 — Mode A (default: Tailscale node) — REQUIRED

| Secret | Where it's used | Notes |
|---|---|---|
| `TAILSCALE_AUTH_KEY` | `install.sh`, `scripts/bootstrap.sh` — joins / re-joins the tailnet | **Reusable, pre-authorized, tagged, NON-ephemeral, ≤90 days.** Single-use keys break unattended re-join after a restart or rebuild. Create in the admin console → Settings → Keys. |

## Tier 2 — optional enhancements (ask only if relevant)

| Secret | Where it's used | Notes |
|---|---|---|
| `TAILSCALE_API_KEY` | `scripts/ts-api.sh` — tailnet management, key minting | `tskey-api-…`; rotate regularly (≤90-day expiry) |
| `STATE_GIT_REMOTE` | `scripts/state-save.sh` — push remote for snapshots | **must be PRIVATE**; prefer encrypted snapshots (see below) |

## Tier 3 — Mode B only (graphical desktop)

| Secret | Where it's used | Notes |
|---|---|---|
| `GATEWAY_USER` | `desktop/server.py` — Basic Auth username | e.g. `admin` |
| `GATEWAY_PASS` | `desktop/server.py` — Basic Auth password | UTF-8; Arabic passwords fully supported |

## Non-secret configuration (store in `.env` alongside)

| Key | Purpose |
|---|---|
| `VPS_HOSTNAME` | Stable hostname (agent derives `<AgentName>-vps-<n>`; never ask the user) |
| `TAILNET_NAME` | Tailnet name, e.g. `example.ts.net` (needed by `scripts/ts-api.sh`) |
| `TAILSCALE_PEER` | Peer pinged by keep-alive to keep NAT mappings warm |
| `PERSIST_DIR` | Directory snapshotted daily (default `/srv/persistent`) |
| `TAILSCALE_STATE_DIR` | Persistent state path for userspace tailscaled (default `/var/lib/tailscale`) |
| `TAILSCALE_VERSION` | Optional version pin for the Tailscale installer |

## Hygiene

- `.gitignore` blocks `.env` and anything shaped like `tskey-auth-*` / `tskey-api-*` / `*.tskey` — the last line of defense, not the first.
- Rotate on any suspicion of leakage. If the user pastes a secret in plain text into chat, store it only in `.env` and recommend rotation after setup.
- State snapshots are plain git of arbitrary data. If they may contain sensitive material, encrypt before pushing (`age`, `restic`, or a `git-crypt`-style filter) — and include the tailscaled state dir in what is backed up.
