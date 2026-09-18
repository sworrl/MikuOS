#!/usr/bin/env bash
# Generic MikuOS RRO builder: compile res/ + AndroidManifest.xml of an overlay dir into a
# zipaligned APK signed with the Falcon Technix PLATFORM key (the same key the re-keyed
# framework/SystemUI use), so every overlay we bake into /product/overlay is trusted.
#   build_overlay.sh <overlay-src-dir> <output.apk>
# The src dir must contain AndroidManifest.xml and res/.
set -euo pipefail
BT=/home/reaver/Android/Sdk/build-tools/35.0.0
ANDROID_JAR=/home/reaver/Android/Sdk/platforms/android-35/android.jar
KEYS=/home/reaver/Documents/GitHub/m500/m500-system-archive/keys
SRC="$(cd "$1" && pwd)"
OUT_APK="$2"
WORK="$SRC/out"
rm -rf "$WORK"; mkdir -p "$WORK"
"$BT/aapt2" compile --dir "$SRC/res" -o "$WORK/res.zip"
"$BT/aapt2" link \
    -o "$WORK/unsigned.apk" \
    --manifest "$SRC/AndroidManifest.xml" \
    -I "$ANDROID_JAR" \
    -R "$WORK/res.zip" \
    --min-sdk-version 26 \
    --target-sdk-version 35 \
    --auto-add-overlay
"$BT/zipalign" -f 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"
# Sign with the SAME platform key the target image trusts:
#   default (REKEY=0 images, what the device runs today) = miku-player-kotlin/platform.jks
#   (AOSP platform test key, matches framework/SystemUI/our apps on-device, hash b4addb29);
#   OVERLAY_KEY=falcon = m500-system-archive/keys/platform.pk8 for REKEY=1 images.
if [ "${OVERLAY_KEY:-jks}" = "falcon" ]; then
    "$BT/apksigner" sign \
        --key "$KEYS/platform.pk8" \
        --cert "$KEYS/platform.x509.pem" \
        --out "$OUT_APK" \
        "$WORK/aligned.apk"
else
    PROPS=/home/reaver/Documents/GitHub/m500/keystore.properties
    _ks="$(grep '^platform.storeFile=' "$PROPS" | cut -d= -f2-)"
    [ -f "$_ks" ] || _ks="/home/reaver/Documents/GitHub/m500/$_ks"
    "$BT/apksigner" sign \
        --ks "$_ks" \
        --ks-key-alias "$(grep '^platform.keyAlias=' "$PROPS" | cut -d= -f2-)" \
        --ks-pass "pass:$(grep '^platform.storePassword=' "$PROPS" | cut -d= -f2-)" \
        --key-pass "pass:$(grep '^platform.keyPassword=' "$PROPS" | cut -d= -f2-)" \
        --out "$OUT_APK" \
        "$WORK/aligned.apk"
fi
echo "Built + platform-signed: $OUT_APK"
"$BT/apksigner" verify --print-certs "$OUT_APK" | grep -E "SHA-256" | head -1
