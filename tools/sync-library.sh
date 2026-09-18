#!/usr/bin/env bash
# M500 music-library sync — INCREMENTAL and change-gated.
#
#   Cost model:
#     - nothing changed        -> exits in ~1s (one MediaStore query, a diff), no scan, no push
#     - N files added/replaced -> header-scans only those N files on-device, reuses the rest
#     - deletions              -> rebuild drops them, no scan needed
#
#   The library rarely changes, so run this event-driven: have the import/trickle
#   pipeline call it after each import. It's cheap enough to also call on a slow
#   timer as a safety net. The widget itself never scans — it just reads the
#   pushed JSON and reloads only when its mtime changes.
#
#   Usage:  tools/sync-library.sh            # incremental
#           tools/sync-library.sh --force    # full re-scan of every file
set -euo pipefail
export PATH="$PATH:$HOME/Android/Sdk/platform-tools"
# Sync host is not hardcoded: source the gitignored env (tools/m500-sync.env; see
# tools/m500-sync.env.example), then derive the adb-over-Wi-Fi serial from SYNC_HOST.
# An explicit ANDROID_SERIAL still wins; it stays empty when nothing is configured, and
# the reachability check below then skips gracefully instead of targeting a personal IP.
ENV_FILE="${M500_SYNC_ENV:-$(cd "$(dirname "$0")" && pwd)/m500-sync.env}"
# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && . "$ENV_FILE"
ADB_TCP_PORT="${ADB_TCP_PORT:-5555}"
: "${ANDROID_SERIAL:=${SYNC_HOST:+${SYNC_HOST}:${ADB_TCP_PORT}}}"; export ANDROID_SERIAL
REPO="$(cd "$(dirname "$0")/.." && pwd)"; LIB="$REPO/library"; TOOLS="$REPO/tools"
DEV=/sdcard/MikuLibrary
# Feed both widget packages: the in-place mod (com.hiby.widget) and the
# standalone Miku Music Widget (com.miku.widget). Each reads library.json from
# its own scoped external dir.
WDIRS="/sdcard/Android/data/com.hiby.widget/files /sdcard/Android/data/com.miku.widget/files"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FORCE="${1:-}"; mkdir -p "$LIB"

# Unattended-safe: if the M500 isn't reachable (asleep / off the bench), skip
# quietly so a timer run doesn't error. Route is pinned; just (re)connect.
adb connect "$ANDROID_SERIAL" >/dev/null 2>&1 || true
if [ "$(adb -s "$ANDROID_SERIAL" get-state 2>/dev/null)" != "device" ]; then
  echo "M500 not reachable ($ANDROID_SERIAL) — skipping."; exit 0
fi

echo "[1/5] MediaStore snapshot…"
adb shell "content query --uri content://media/external/audio/media --projection _data:title:artist:album:duration:mime_type:track:_size" > "$TMP/meta.txt"

echo "[2/5] diff vs current DB…"
SUMMARY=$(python3 - "$TMP/meta.txt" "$LIB/library.json" "$TMP/changed.txt" "$FORCE" <<'PY'
import re,sys,json,os
meta,prevj,out,force = sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]=='--force'
cur={}
for l in open(meta,encoding='utf-8',errors='ignore'):
    m=re.search(r'_data=(.*?), title=.*, _size=(\d+)\s*$', l)
    if m: cur[m.group(1)]=int(m.group(2))
prev={}
if os.path.exists(prevj):
    try:
        for t in json.load(open(prevj,encoding='utf-8'))['tracks']:
            prev[t['path']]=t.get('size',0)
    except Exception: pass
changed=[p for p,sz in cur.items() if force or p not in prev or prev.get(p)!=sz]
deleted=[p for p in prev if p not in cur]
open(out,'w',encoding='utf-8').write('\n'.join(changed)+('\n' if changed else ''))
print(f"{len(changed)} {len(deleted)}")
PY
)
CHANGED=$(echo "$SUMMARY" | awk '{print $1}'); DELETED=$(echo "$SUMMARY" | awk '{print $2}')
echo "  changed=$CHANGED deleted=$DELETED"

if [ "$CHANGED" -eq 0 ] && [ "$DELETED" -eq 0 ] && [ "$FORCE" != "--force" ]; then
  echo "  up to date — no scan, no push."
  exit 0
fi

: > "$TMP/headers.txt"
if [ "$CHANGED" -gt 0 ]; then
  echo "[3/5] header-scan $CHANGED changed file(s) on device…"
  adb shell "mkdir -p $DEV" >/dev/null
  adb push "$TMP/changed.txt" "$DEV/paths.txt" >/dev/null
  adb push "$TOOLS/scan_headers.sh" "$DEV/scan.sh" >/dev/null
  adb shell "nohup sh $DEV/scan.sh >/dev/null 2>&1 &"
  while :; do
    adb shell "tail -1 $DEV/headers.txt 2>/dev/null" | grep -q '###DONE' && break
    sleep 2
  done
  adb pull "$DEV/headers.txt" "$TMP/headers.txt" >/dev/null
else
  echo "[3/5] deletions only — no scan needed."
fi

echo "[4/5] rebuild master DB (fresh for changed, reuse unchanged, drop deleted)…"
python3 "$TOOLS/build_library_db.py" "$TMP/meta.txt" "$TMP/headers.txt" "$LIB"

echo "[5/5] push to device + widget dir…"
for f in library.db library.csv library.json library.js library.html; do
  [ -f "$LIB/$f" ] && adb push "$LIB/$f" "$DEV/$f" >/dev/null
done
for wd in $WDIRS; do
  adb shell "mkdir -p $wd" >/dev/null 2>&1
  adb push "$LIB/library.json" "$wd/library.json" >/dev/null 2>&1 || true
done
echo "done — widget pill will refresh on its next tick."
