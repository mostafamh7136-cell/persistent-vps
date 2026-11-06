# Tailscale keys: auth keys vs API keys

Two different key types do two different jobs. Mixing them up is the #1 mistake.

| | Auth key | API key |
|---|---|---|
| Prefix | `tskey-auth-…` | `tskey-api-…` |
| Purpose | **Register (join) a device** to the tailnet | **Manage the tailnet** via the HTTP API |
| Used by | `tailscale up --auth-key=…` | `scripts/ts-api.sh`, `curl api.tailscale.com` |
| Typical ops use | One per node provision (or one reusable for many) | List devices, delete devices, mint auth keys |
| Created in | Admin console → Settings → Keys, or via API | Admin console → Settings → Keys → API access tokens |

## Joining a node with an auth key

```bash
tailscale up \
  --auth-key="$TAILSCALE_AUTH_KEY" \
  --hostname="persistent-vps" \
  --accept-dns=false \
  --ssh
```

Notes:

- **Single-use vs reusable**: prefer single-use keys for one node; reusable keys for fleets/automation.
- **Pre-authorized** keys skip the device-approval click in the admin console.
- **Ephemeral** keys auto-remove the node when it goes offline — do *not* use them for a persistent VPS.
- **Tagged** keys (`tag:vps`) give the node a shared identity, useful for ACLs.

## Minting auth keys on demand

With an API key set (`TAILSCALE_API_KEY`, `TAILNET_NAME`):

```bash
scripts/ts-api.sh new-key 7        # pre-authorized + reusable, expires in 7 days
```

Raw API equivalent:

```bash
curl -fsS -u "api:$TAILSCALE_API_KEY" -X POST \
  -H "Content-Type: application/json" \
  -d '{"capabilities":{"devices":{"create":{"reusable":true,"ephemeral":false,"preAuthorized":true}}},"expirySeconds":604800}' \
  "https://api.tailscale.com/api/v2/tailnet/$TAILNET_NAME/keys"
```

The response contains the one-time `key` value (`tskey-auth-…`) — it is shown **only once**.

## Managing devices with the API

```bash
scripts/ts-api.sh devices              # list all nodes in the tailnet
scripts/ts-api.sh device <id>          # inspect one node
scripts/ts-api.sh delete-device <id>   # remove a node from the tailnet
```

## Keep-alive and the Tailscale connection

Tailscale connections are on-demand; idle periods are normal and healthy. The
watchdog in `scripts/keep-alive.sh` is there for the failure cases:

- `tailscaled` crashed or the backend left the `Running` state → restart the daemon
- NAT/firewall state dropped → an optional `TAILSCALE_PEER` ping warms the path

Useful diagnostics on the node:

```bash
tailscale status
tailscale ping <peer>
journalctl -u tailscaled -n 50
```

## Reference

- <https://tailscale.com/kb/1085/auth-keys>
- <https://tailscale.com/api>
