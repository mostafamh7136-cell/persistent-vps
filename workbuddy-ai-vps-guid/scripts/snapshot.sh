#!/bin/bash
# snapshot.sh — 生成系统快照 tar.gz，校验完整性，提交到私有 git 仓库并在有 Token 时推送
# 快照内容：/workspace/debian13-server（全部脚本/配置/固定ID/链接）+ chroot 系统状态清单
set -u
DIR=/workspace/debian13-server
REPO=/srv/debian13-backup/repo
CHROOT=/srv/debian13
LOG="$DIR/logs/snapshot.log"
STAMP=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$STAMP] $*" >> "$LOG"; }

mkdir -p "$REPO" "$DIR/logs"
cd "$REPO"
[ -d .git ] || { git init -q -b main; git config user.email "snapshot@debian13.local"; git config user.name "Debian13 Snapshot Bot"; }

# --- 1. 组装快照材料（staging）---
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -a "$DIR" "$STAGE/debian13-server"
# 去掉大体积/运行时产物
rm -rf "$STAGE/debian13-server/logs"/*.log 2>/dev/null
rm -f  "$STAGE/debian13-server/"*.png 2>/dev/null

# chroot 系统状态清单（轻量，不打 5.8G 整个系统）
mkdir -p "$STAGE/system-state"
chroot "$CHROOT" dpkg -l            > "$STAGE/system-state/dpkg-packages.txt" 2>/dev/null
chroot "$CHROOT" pip list 2>/dev/null > "$STAGE/system-state/pip-packages.txt"
/opt/node22/bin/node --version      > "$STAGE/system-state/node-version.txt" 2>/dev/null
chroot "$CHROOT" /opt/oc-cli/bin/opencode --version > "$STAGE/system-state/opencode-version.txt" 2>/dev/null
chroot "$CHROOT" blender --version 2>/dev/null | head -1 > "$STAGE/system-state/blender-version.txt"
ls -la "$CHROOT/home/debian/Desktop" > "$STAGE/system-state/desktop-icons.txt" 2>/dev/null
{ echo "timestamp: $STAMP"; echo "pinned_id: $(cat $DIR/.pinned_id)"; echo "link: $(cat $DIR/LINK.txt 2>/dev/null)";
  echo "runtime_id: ${AGENTOS_RUNTIME_ID:-unknown}";
  echo "vnc: $(pgrep -x Xtigervnc >/dev/null && echo running || echo DOWN)";
  echo "websockify: $(pgrep -x websockify >/dev/null && echo running || echo DOWN)";
  echo "gateway: $(curl -sf --max-time 3 http://127.0.0.1:6080/healthz >/dev/null && echo running || echo DOWN)";
} > "$STAGE/system-state/status.yaml"

# --- 2. 生成 tar.gz ---
OUT="$REPO/snapshot.tar.gz"
TMP_OUT="$REPO/.snapshot.tmp.tar.gz"
tar -czf "$TMP_OUT" -C "$STAGE" . 2>/dev/null

# --- 3. 完整性校验（gzip CRC + tar 结构 + 内容抽查）---
VALID=0
if gzip -t "$TMP_OUT" 2>/dev/null && tar -tzf "$TMP_OUT" >/dev/null 2>&1; then
  # 抽查关键文件确实在包内
  if tar -tzf "$TMP_OUT" | grep -q "debian13-server/.pinned_id" \
     && tar -tzf "$TMP_OUT" | grep -q "system-state/status.yaml"; then
    VALID=1
  fi
fi

if [ "$VALID" != "1" ]; then
  log "ERROR: snapshot validation FAILED, retrying once"
  rm -f "$TMP_OUT"
  tar -czf "$TMP_OUT" -C "$STAGE" . 2>/dev/null
  if gzip -t "$TMP_OUT" 2>/dev/null && tar -tzf "$TMP_OUT" >/dev/null 2>&1; then VALID=1; fi
fi

if [ "$VALID" != "1" ]; then
  log "ERROR: snapshot still invalid after retry — keeping previous snapshot untouched"
  rm -f "$TMP_OUT"
  exit 1
fi

mv -f "$TMP_OUT" "$OUT"
SHA=$(sha256sum "$OUT" | cut -d' ' -f1)
echo "$SHA  snapshot.tar.gz" > "$REPO/snapshot.sha256"
SIZE=$(du -h "$OUT" | cut -f1)

# --- 4. 仅在内容变化时提交 ---
git add -A snapshot.tar.gz snapshot.sha256
if git diff --cached --quiet; then
  log "OK: snapshot valid ($SIZE, sha256 ${SHA:0:12}...) — no change, skip commit"
else
  git commit -q -m "snapshot $STAMP (valid, sha256 ${SHA:0:12})"
  log "OK: snapshot valid ($SIZE) — committed"
  # --- 5. 推送到私有 remote（本地 file:// 始终推；GitHub 等 https remote 需 Token）---
  if git remote get-url origin >/dev/null 2>&1; then
    REMOTE_URL=$(git remote get-url origin)
    if [[ "$REMOTE_URL" != http* ]] || [ -n "${GITHUB_TOKEN:-}" ]; then
      if git push -q origin main 2>>"$LOG"; then
        log "OK: pushed to remote ($REMOTE_URL)"
      else
        log "WARN: push failed (will retry next cycle)"
      fi
    fi
  fi
fi
