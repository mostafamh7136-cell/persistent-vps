#!/usr/bin/env bash
# persistent-vps state snapshot
#
# Runs via state-snapshot.timer (default: daily at 04:00) or on demand:
#   sudo systemctl start state-snapshot.service
#
# Commits the contents of PERSIST_DIR into a bare git repo and optionally
# pushes to STATE_GIT_REMOTE (branch: state).
#
# WARNING: only push to a PRIVATE remote — snapshots may contain secrets.
# Put a .gitignore inside PERSIST_DIR to exclude anything sensitive.
set -euo pipefail

PERSIST_DIR="${PERSIST_DIR:-/srv/persistent}"
STATE_REPO="${STATE_REPO:-/var/lib/persistent-vps/state.git}"
STATE_GIT_REMOTE="${STATE_GIT_REMOTE:-}"

log() { echo "[state-save] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

if [[ ! -d "${PERSIST_DIR}" ]]; then
  log "nothing to do: ${PERSIST_DIR} does not exist yet"
  exit 0
fi

# Bare repo keeps full history without touching the live directory
if [[ ! -d "${STATE_REPO}" ]]; then
  log "initialising state repo at ${STATE_REPO}"
  install -d "$(dirname "${STATE_REPO}")"
  git init --bare "${STATE_REPO}" >/dev/null
  git --git-dir="${STATE_REPO}" config user.name  "persistent-vps"
  git --git-dir="${STATE_REPO}" config user.email "persistent-vps@localhost"
fi

git --git-dir="${STATE_REPO}" --work-tree="${PERSIST_DIR}" add -A >/dev/null

if git --git-dir="${STATE_REPO}" --work-tree="${PERSIST_DIR}" diff --cached --quiet; then
  log "no changes since last snapshot"
  exit 0
fi

git --git-dir="${STATE_REPO}" --work-tree="${PERSIST_DIR}" \
  commit -m "snapshot $(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null
log "snapshot committed"

if [[ -n "${STATE_GIT_REMOTE}" ]]; then
  log "pushing snapshot to remote (branch: state)"
  git --git-dir="${STATE_REPO}" push --force "${STATE_GIT_REMOTE}" "HEAD:refs/heads/state"
fi

# Restore a snapshot anytime:
#   git clone /var/lib/persistent-vps/state.git restored-state
