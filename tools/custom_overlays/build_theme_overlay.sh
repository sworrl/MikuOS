#!/usr/bin/env bash
# Build + platform-sign the MikuThemeOverlay RRO (retints stock SystemUI modals).
set -euo pipefail
BT=/home/reaver/Android/Sdk/build-tools/35.0.0
ANDROID_JAR=/home/reaver/Android/Sdk/platforms/android-35/android.jar
KEYS=/home/reaver/Documents/GitHub/m500/m500-system-archive/keys
SRC="$(cd "$(dirname "$0")/MikuThemeOverlay" && pwd)"
OUT="$SRC/out"
rm -rf "$OUT"; mkdir -p "$OUT"

# 1. Compile resources
"$BT/aapt2" compile --dir "$SRC/res" -o "$OUT/res.zip"
# 2. Link into an unsigned APK (no dex; hasCode=false)
"$BT/aapt2" link \
    -o "$OUT/unsigned.apk" \
    --manifest "$SRC/AndroidManifest.xml" \
    -I "$ANDROID_JAR" \
    -R "$OUT/res.zip" \
    --min-sdk-version 26 \
    --target-sdk-version 35 \
    --auto-add-overlay
# 3. Align + sign with the platform key (RRO targeting a system pkg needs platform sig)
"$BT/zipalign" -f 4 "$OUT/unsigned.apk" "$OUT/aligned.apk"
"$BT/apksigner" sign \
    --key "$KEYS/platform.pk8" \
    --cert "$KEYS/platform.x509.pem" \
    --out "$SRC/MikuThemeOverlay.apk" \
    "$OUT/aligned.apk"
echo "Built + signed: $SRC/MikuThemeOverlay.apk"
"$BT/apksigner" verify --print-certs "$SRC/MikuThemeOverlay.apk" | head -2
