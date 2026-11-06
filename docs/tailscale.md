# docs/tailscale.md — Tailscale Layer Reference

## Key selection for an always-on node (read this first)

The default admin-console key choices are **wrong for this use case**. A node that must re-join unattended after a restart or rebuild (the availability convention in AGENTS.md) needs:

| Property | Required value | Why |
|---|---|---|
| Reusable | ✅ Yes | The node must be able to re-join after a restart or rebuild; a spent single-use key = dead node |
| Pre-authorized | ✅ Yes | Re-join must not wait for a human to click "approve device" |
| Tags | ✅ Yes, e.g. `tag:vps` | Stable ACL target, no user binding; lets you scope what the node may reach |
| Ephemeral | ❌ **No** | Ephemeral nodes are auto-removed — the opposite of an always-on server |
| Expiry | ≤ 90 days | Longest supported; calendar a rotation (agent checks `Expiry` and warns) |

Create in the admin console → **Settings → Keys**. The key is `tskey-auth-…` — see the joining vs managing distinction below.

## Joining vs managing

- `tskey-auth-…` — **auth key**: a node's invite. Used by `install.sh` and `scripts/bootstrap.sh` to join/re-join the tailnet.
- `tskey-api-…` — **API key**: for the Tailscale HTTP API (listing devices, minting keys). Used by `scripts/ts-api.sh`. Never passed to `tailscale up`.

Confusing them (or passing an API key to `tailscale up`) is the most common setup error.

## Environment detection & userspace fallback

`install.sh` probes the environment before choosing a path:

| Condition | Path |
|---|---|
| systemd **and** `/dev/net/tun` **and** root | Standard: systemd `tailscaled` + `tailscaled-health` timer |
| Missing systemd or tun (container host you operate) | **Userspace networking**: `tailscaled --tun=userspace-networking --state="$TAILSCALE_STATE_DIR"`, supervised by a `Restart=always`-equivalent loop, with `tailscale up --authkey=…` after tailscaled is healthy |

Userspace networking gives outbound connectivity and SSH over the tailnet without any kernel TUN device. Verify with `tailscale status` and `tailscale ping` — not just "the daemon started".

## SSH access — the part most setups get wrong

Enabling `--ssh` is **not** the same as "I can `ssh root@100.x.x.x`". Tailscale SSH authorizes via **tailnet ACL `ssh` rules**, not OS passwords or OS-level keys.

1. **Tagged nodes are not covered by `autogroup:self`.** The default rule won't reach a node joined with `tag:vps` — you need an explicit rule.
2. **Default action is often `check`**, which forces interactive browser re-authentication every few hours — useless for unattended/agent access. Use `action: accept` for a personal tailnet.

### ACL snippet (admin console → Access Controls)

```json
"ssh": [
  {
    "action": "accept",
    "src":    ["autogroup:member"],
    "dst":    ["tag:vps"],
    "users":  ["autogroup:nonroot", "root"]
  }
]
```

`autogroup:nonroot` includes a sudo-capable user; add `root` for direct root login. For stricter setups, drop `root` and use `sudo` after login.

### Fallback: OpenSSH over the tailnet

`install.sh` also enables OpenSSH bound to the tailscale interface with key-only auth, as an independent fallback. If the ACL rule above isn't in place, OpenSSH still works: the tailnet is the transport either way.

### Verification (before claiming SSH works)

- From the node: `tailscale status --json | jq -r '.Self.HostName, .Self.TailscaleIPs[0]'`
- From a second tailnet device: `ssh root@<ip>` (or `ssh <user>@<ip>`), and `tailscale ping <hostname>` to confirm WireGuard-level reachability. Only then may the report say `verified: yes`.

## State persistence across restarts & rebuilds

- Keep tailscaled state on persistent storage: `/var/lib/tailscale` (or `TAILSCALE_STATE_DIR` on the persistent volume).
- Wire `scripts/bootstrap.sh` into the server's boot mechanism — it re-mounts, restarts tailscaled, re-joins if needed (with the reusable key), and revives supervision. A running process cannot restart a machine that is down; the external boot hook is what restores the stack.
- `systemd/tailscaled-health.service` + `.timer` repair `tailscaled` every 5 minutes; `scripts/keep-alive.sh` additionally pings a peer to keep NAT mappings warm.

## Daily state snapshots

`systemd/state-save.service` + `.timer` commit `PERSIST_DIR` daily to a bare git repo at `/srv/persistent-state.git`, optionally pushed to `STATE_GIT_REMOTE` (must be **private**; encrypt snapshots if they may contain sensitive material — `age` or `restic`). Include `TAILSCALE_STATE_DIR` in what gets backed up so a restored node doesn't even need to re-join.

## Troubleshooting

- `failed to authenticate` on join ⇒ key expired/revoked — mint a new one (Settings → Keys), update `.env`, re-run.
- `tailscale up` succeeds but `tailscale ping` fails ⇒ likely an ACL `dst` missing for `tag:vps` in `acls`, or a network policy block.
- `dial tcp: missing CAP_NET_ADMIN` / no `/dev/net/tun` ⇒ re-run `install.sh`; it detects this and takes the userspace path.
- `Permission denied` on SSH ⇒ the ACL `ssh` rule (not the OS) authorized you — re-check the snippet above and confirm the node's tag matches `dst`.

## References

- <https://tailscale.com/kb/1117/custom-qa> (userspace networking)
- <https://tailscale.com/kb/1193/tailscale-ssh> (SSH rules)
- <https://tailscale.com/kb/1068/acl-tags> (tags)
- <https://tailscale.com/kb/1085/auth-keys> (auth keys)
