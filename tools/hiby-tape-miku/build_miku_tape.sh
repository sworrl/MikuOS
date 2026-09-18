#!/usr/bin/env bash
# ==============================================================================
# Miku Tape builder -- rebrand HiBy Tape (com.hiby.tape) into a MikuOS suite app
# ==============================================================================
# decode (apktool) -> patch resources/artwork/icon -> rebuild -> zipalign+sign
# with the Falcon Technix *platform* key via tools/sign_apk.sh.
#
# Package name stays com.hiby.tape (coexists with stock, HiBy intents intact).
# Stock APK is platform-signed (AOSP test key c8a2e9bc...), so the platform
# role is the correct re-sign target on a re-keyed MikuOS image.
#
# Usage:
#   tools/hiby-tape-miku/build_miku_tape.sh [--stock <HiByTape.apk>] [--keep-work]
#
# Env overrides: APKTOOL_JAR, APKSIGNER, ZIPALIGN, STOCK_APK, OUT_DIR
# Output: tools/hiby-tape-miku/out/MikuTape.apk (+ .sha256, badging.txt)
# ==============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
STOCK_APK="${STOCK_APK:-$REPO/m500-system-archive/vendor_software/HiByTape.apk}"
OUT_DIR="${OUT_DIR:-$HERE/out}"
WORK="$HERE/work"
KEEP_WORK=false

while [ $# -gt 0 ]; do
  case "$1" in
    --stock) STOCK_APK="$2"; shift 2 ;;
    --keep-work) KEEP_WORK=true; shift ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- tool discovery -----------------------------------------------------------
find_bt() { ls -1 "$HOME/Android/Sdk/build-tools"/*/"$1" 2>/dev/null | sort -V | tail -1; }
APKTOOL_JAR="${APKTOOL_JAR:-$REPO/tools/apktool.jar}"
if [ -f "$APKTOOL_JAR" ]; then
  APKTOOL=(java -jar "$APKTOOL_JAR")
elif command -v apktool >/dev/null 2>&1; then
  APKTOOL=(apktool)
else
  echo "ERROR: apktool not found (need $REPO/tools/apktool.jar or 'apktool' on PATH)" >&2; exit 1
fi
export APKSIGNER="${APKSIGNER:-$(command -v apksigner || find_bt apksigner)}"
export ZIPALIGN="${ZIPALIGN:-$(command -v zipalign || find_bt zipalign)}"
[ -n "$APKSIGNER" ] && [ -x "$APKSIGNER" ] || { echo "ERROR: apksigner not found (install Android build-tools or set APKSIGNER=)" >&2; exit 1; }
[ -n "$ZIPALIGN" ]  && [ -x "$ZIPALIGN" ]  || { echo "ERROR: zipalign not found (install Android build-tools or set ZIPALIGN=)" >&2; exit 1; }
python3 -c 'import PIL' 2>/dev/null || { echo "ERROR: python3 Pillow (PIL) required" >&2; exit 1; }
[ -f "$STOCK_APK" ] || { echo "ERROR: stock APK not found: $STOCK_APK" >&2; exit 1; }
[ -f "$REPO/mikuos/signing/platform.pk8" ] || { echo "ERROR: Falcon platform key missing at mikuos/signing/platform.pk8" >&2; exit 1; }

echo "== Miku Tape build =="
echo "stock:     $STOCK_APK"
echo "apktool:   ${APKTOOL[*]} ($("${APKTOOL[@]}" --version 2>/dev/null | head -1))"
echo "apksigner: $APKSIGNER"
echo "zipalign:  $ZIPALIGN"
echo "out:       $OUT_DIR"

rm -rf "$WORK"; mkdir -p "$WORK" "$OUT_DIR"
DEC="$WORK/decoded"

# --- 1. decode: full resources (we edit values/layouts/drawables), -s keeps the
#        original classes.dex byte-for-byte (no code is patched, no smali round-trip)
echo "[1/5] apktool decode"
"${APKTOOL[@]}" d -s -f -o "$DEC" "$STOCK_APK" > "$WORK/decode.log" 2>&1 || { tail -20 "$WORK/decode.log"; exit 1; }

# --- 2. patch -------------------------------------------------------------------
echo "[2/5] patch resources + artwork"
python3 "$HERE/patches/patch_resources.py" "$DEC"
echo "[2/5] generate Miku icon set"
python3 "$HERE/patches/gen_icon.py" "$DEC" "$OUT_DIR/icon_preview.png"

# --- 3. rebuild -----------------------------------------------------------------
echo "[3/5] apktool build"
UNSIGNED="$WORK/MikuTape-unsigned.apk"
if ! "${APKTOOL[@]}" b -o "$UNSIGNED" "$DEC" > "$WORK/build.log" 2>&1; then
  echo "apktool build FAILED; last errors:" >&2
  grep -n 'error' "$WORK/build.log" | head -30 >&2
  exit 1
fi

# --- 4. zipalign + sign (Falcon Technix platform key) ---------------------------
echo "[4/5] zipalign + sign (platform role) via tools/sign_apk.sh"
ALIGNED="$WORK/MikuTape-aligned.apk"
"$ZIPALIGN" -f -p 4 "$UNSIGNED" "$ALIGNED"
FINAL="$OUT_DIR/MikuTape.apk"
"$REPO/tools/sign_apk.sh" --platform -o "$FINAL" "$ALIGNED" | sed 's/^/    /'

# --- 5. verify -------------------------------------------------------------------
echo "[5/5] verify"
"$APKSIGNER" verify --print-certs "$FINAL" > "$OUT_DIR/signature.txt" 2>&1 || { cat "$OUT_DIR/signature.txt"; exit 1; }
"$ZIPALIGN" -c -p 4 "$FINAL" >/dev/null && echo "    zipalign: OK (4-byte, 4K .so pages)"
want="$(openssl x509 -in "$REPO/mikuos/signing/platform.x509.pem" -noout -fingerprint -sha256 | sed 's/.*=//' | tr -d ':' | tr 'A-F' 'a-f')"
got="$(grep -m1 'SHA-256 digest' "$OUT_DIR/signature.txt" | sed 's/.*: //' | tr -d ': ' | tr 'A-F' 'a-f')"
if [ "$want" = "$got" ]; then echo "    signer == mikuos/signing/platform.x509.pem: OK"; else echo "    signer MISMATCH ($got != $want)" >&2; exit 1; fi
if command -v aapt >/dev/null 2>&1; then
  aapt dump badging "$FINAL" > "$OUT_DIR/badging.txt" 2>/dev/null || true
  grep -E "^package:|^application-label:|^launchable-activity" "$OUT_DIR/badging.txt" | sed 's/^/    /'
  grep -q "application-label:'Miku Tape'" "$OUT_DIR/badging.txt" || { echo "    label check FAILED" >&2; exit 1; }
fi
sha256sum "$FINAL" | tee "$OUT_DIR/MikuTape.apk.sha256" | sed 's/^/    /'
ls -la "$FINAL" | sed 's/^/    /'

$KEEP_WORK || rm -rf "$WORK"
echo "DONE -> $FINAL"
