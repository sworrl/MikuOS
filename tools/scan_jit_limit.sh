#!/usr/bin/env bash
# Find methods ART will REFUSE to JIT-compile.
#
# ART gives up on any method over 16384 dex instructions and logs
#   "Method exceeds compiler instruction limit: <n> in <method>"
# The method still runs — interpreted, every call. For a @Composable that
# recomposes, that silently pins the main thread with no crash and no stack to
# blame. This is how the MikuOS lockscreen (18785 insns) and the network
# observatory (46419) came to burn CPU for months unnoticed.
#
# Checking on-device logcat is NOT reliable: ART only attempts compilation of a
# method that actually RUNS, so a screen you did not open reports nothing. This
# script reads the built APK instead, so it sees everything you shipped.
#
# Usage: tools/scan_jit_limit.sh <apk> [warn_threshold]
set -euo pipefail

APK="${1:?usage: scan_jit_limit.sh <apk> [warn_threshold]}"
WARN="${2:-12000}"
LIMIT=16384

DEXDUMP="$(ls "$HOME"/Android/Sdk/build-tools/*/dexdump 2>/dev/null | sort -V | tail -1 || true)"
[ -n "$DEXDUMP" ] || { echo "dexdump not found under \$HOME/Android/Sdk/build-tools/*/" >&2; exit 2; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
unzip -q -o "$APK" 'classes*.dex' -d "$WORK"
for d in "$WORK"/classes*.dex; do "$DEXDUMP" -d "$d" 2>/dev/null; done > "$WORK/all.txt"

LIMIT="$LIMIT" WARN="$WARN" APK="$APK" python3 - "$WORK/all.txt" <<'PY'
import os, re, sys
limit, warn = int(os.environ["LIMIT"]), int(os.environ["WARN"])
cur, best = None, {}
for line in open(sys.argv[1], errors="ignore"):
    m = re.match(r"\s*name\s*:\s*'([^']+)'", line)
    if m:
        cur = m.group(1); continue
    m = re.search(r"insns size\s*:\s*(\d+)", line)
    if m and cur:
        n = int(m.group(1))
        if n > best.get(cur, -1): best[cur] = n
        cur = None
rows = sorted(((n, k) for k, n in best.items() if n >= warn), reverse=True)
over = [r for r in rows if r[0] > limit]
print(f"{os.path.basename(os.environ['APK'])}: methods >= {warn} insns (ART JIT limit {limit})")
if not rows:
    print("  none")
for n, name in rows:
    print(f"  {n:6}  {name}" + ("   <-- OVER LIMIT: never compiled, runs interpreted" if n > limit else ""))
print()
if over:
    print(f"FAIL: {len(over)} method(s) over the limit. Split them into smaller composables/functions.")
    sys.exit(1)
print("OK: nothing over the limit.")
PY
