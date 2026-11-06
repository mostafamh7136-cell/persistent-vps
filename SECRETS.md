# SECRETS.md — Secret Intake Manifest

This file lists **what** secrets the deployment needs. **No values live here — ever.** The repository is public; a leaked secret here is a compromised VPS.

## Intake protocol (for agents)

1. **Right after the user's first message**, ask the user for every item below that applies to the deployment (see `GUIDE.md` scope). Ask even if the user will type them in plain text.
2. Store answers **only** in `.env` on the machine (`chmod 600 .env`, gitignored).
3. Never echo a value back in full — confirm receipt by prefix only (`tskey-auth-abc…`).
4. If a needed secret is missing at runtime, **stop and ask the user**. Do not invent, do not hardcode, do not proceed with a fake value.

## Required secrets

| # | Secret | Where it's used | Notes |
|---|---|---|---|
| 1 | `GATEWAY_USER` | `desktop/server.py` — HTTP Basic Auth **username** for every entry point of the cloud desktop | e.g. `admin` |
| 2 | `GATEWAY_PASS` | `desktop/server.py` — HTTP Basic Auth **password** | UTF-8; Arabic passwords fully supported |
| 3 | `TAILSCALE_AUTH_KEY` | `install.sh` — joins the machine to the tailnet | `tskey-auth-…`; prefer single-use, pre-authorized |
| 4 | `TAILSCALE_API_KEY` | `scripts/ts-api.sh` — tailnet management (devices, key minting) | `tskey-api-…` |
| 5 | `STATE_GIT_REMOTE` | `scripts/state-save.sh` — push remote for state snapshots | **must be a PRIVATE remote**; include token only if the remote requires one in its URL — prefer a credential helper |

## Non-secret configuration (ask alongside, store in `.env` too)

| Key | Purpose |
|---|---|
| `TAILNET_NAME` | Tailnet name, e.g. `example.ts.net` (needed by `scripts/ts-api.sh`) |
| `VPS_HOSTNAME` | Stable hostname for the tailnet node |
| `TAILSCALE_PEER` | Peer pinged by keep-alive to keep NAT mappings warm |
| `PERSIST_DIR` | Directory snapshotted daily (default `/srv/persistent`) |

## Hygiene

- `.gitignore` blocks `.env` and anything shaped like `tskey-auth-*` / `tskey-api-*` / `*.tskey`. That is the last line of defense, not the first.
- Rotate on any suspicion of leakage: mint new keys, update `.env`, revoke old keys.
- If the user pastes a secret in plain text into chat, still store it only in `.env` — and warn them the value now exists in chat history, so rotation after setup is good practice.
