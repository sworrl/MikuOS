#!/usr/bin/env bash
# Re-sign a mainline (compressed .capex or plain .apex) APEX module to the Falcon key set so no
# AOSP-test-key code remains inside APEX payloads. See memory m500-apex-resign-pipeline.
# Usage: resign_apex.sh <in.capex|in.apex> <out.apex>
set -uo pipefail
IN="${1:?in apex}"; OUT="${2:?out apex}"
DIR="$(cd "$(dirname "$0")" && pwd)"; KEYS="$DIR/../signing"
TOOLS="${APEX_TOOLS:-/mnt/aosp-out/out/host/linux-x86/bin}"
APKSIGNER="${APKSIGNER:-$(ls ~/Android/Sdk/build-tools/*/apksigner | tail -1)}"
AJAR="${ANDROID_JAR:-$(ls ~/Android/Sdk/platforms/android-34/android.jar ~/Android/Sdk/platforms/android-35/android.jar 2>/dev/null | head -1)}"
export PATH="$TOOLS:$PATH"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
declare -A MAP=( [c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8]=platform
  [a40da80a59d170caa950cf15c18c454d47a39b26989d8b640ecd745ba71bf5dc]=releasekey
  [465983f7791f2abeb43ea2cbdc7f21a8260b72bc08a55c839fc1a43bc741a81e]=media
  [28bbfe4a7b97e74681dc55c2fbb6ccb8d6c74963733f6af6ae74d8c3a6e879fd]=shared
  [e1dbadce60dc080d15b58a014b0dcf9400e24de23fa00b287a5a982bfebda2ee]=networkstack )
fp(){ "$APKSIGNER" verify --print-certs "$1" 2>/dev/null | grep -m1 "SHA-256 digest:" | sed 's/.*digest: //' | tr -d ':\r\n ' | tr 'A-F' 'a-f'; }

# 1. decompress if capex
APEX="$WORK/in.apex"
if unzip -l "$IN" 2>/dev/null | grep -q original_apex; then
  deapexer decompress --input "$IN" --output "$APEX" >/dev/null 2>&1 || { echo "decompress failed"; exit 1; }
else cp "$IN" "$APEX"; fi
# 2. extract payload
PL="$WORK/payload"
deapexer --debugfs_path "$TOOLS/debugfs_static" --fsckerofs_path "$TOOLS/fsck.erofs" extract "$APEX" "$PL" >/dev/null 2>&1 || { echo "extract failed"; exit 1; }
# 3. re-sign AOSP-test-key inner apks
changed=0
while IFS= read -r apk; do
  role="${MAP[$(fp "$apk")]:-}"; [ -z "$role" ] && continue
  "$APKSIGNER" sign --key "$KEYS/$role.pk8" --cert "$KEYS/$role.x509.pem" --v1-signing-enabled false --v2-signing-enabled true --v3-signing-enabled true "$apk" >/dev/null 2>&1 \
    && { echo "  re-signed inner [$role]: $(basename "$apk")"; changed=1; }
done < <(find "$PL" -name "*.apk")
if [ "$changed" = 0 ]; then echo "  (no AOSP-test-key inner apks; skip $(basename "$IN"))"; exit 2; fi
# 4. keys
[ -f "$KEYS/apex.pem" ] || openssl genrsa -out "$KEYS/apex.pem" 4096 2>/dev/null
python3 "$DIR/../../tools/avbtool.py" extract_public_key --key "$KEYS/apex.pem" --output "$WORK/apex_pubkey" 2>/dev/null
[ -f "$KEYS/apex.pk8" ] || openssl pkcs8 -topk8 -inform PEM -outform DER -in "$KEYS/apex.pem" -out "$KEYS/apex.pk8" -nocrypt 2>/dev/null
[ -f "$KEYS/apex.x509.pem" ] || openssl req -new -x509 -key "$KEYS/apex.pem" -outform PEM -out "$KEYS/apex.x509.pem" -days 10000 -subj "/CN=Falcon Technix APEX/O=Falcon Technix" -sha256 2>/dev/null
# 5. manifest + fs metadata
cp "$PL/apex_manifest.pb" "$WORK/apex_manifest.pb"; rm -f "$PL/apex_manifest.pb"
{ echo " 0 2000 0755"; ( cd "$PL" && find . -mindepth 1 -type d | sed 's|^\./||' | sed 's|$| 0 2000 0755|'; find . -type f | sed 's|^\./||' | while read f; do m=644; case "$f" in bin/*) m=755;; esac; echo "$f 0 2000 0$m"; done ); echo "apex_manifest.pb 0 2000 0644"; } > "$WORK/canned_fs_config"
printf '(/.*)?  u:object_r:system_file:s0\n' > "$WORK/file_contexts"
# 6. rebuild
apexer -f --manifest "$WORK/apex_manifest.pb" --file_contexts "$WORK/file_contexts" --canned_fs_config "$WORK/canned_fs_config" \
  --key "$KEYS/apex.pem" --pubkey "$WORK/apex_pubkey" --apexer_tool_path "$TOOLS" --android_jar_path "$AJAR" \
  --payload_type image --payload_fs_type erofs --min_sdk_version 34 --target_sdk_version 34 "$PL" "$OUT" >/dev/null 2>&1 || { echo "apexer failed"; exit 1; }
# 7. sign container (uncompressed apex first)
UNC="$WORK/out.apex"
apexer >/dev/null 2>&1 || true
mv "$OUT" "$UNC" 2>/dev/null || cp "$OUT" "$UNC"
"$APKSIGNER" sign --key "$KEYS/apex.pk8" --cert "$KEYS/apex.x509.pem" --min-sdk-version 29 --v2-signing-enabled true --v3-signing-enabled true "$UNC" >/dev/null 2>&1 || { echo "container sign failed"; exit 1; }
# 8. if OUT is .capex, recompress + re-sign the compressed container; else ship the uncompressed apex
case "$OUT" in
  *.capex)
    apex_compression_tool compress --apex_compression_tool_path "$TOOLS" --input "$UNC" --output "$OUT" >/dev/null 2>&1 || { echo "compress failed"; exit 1; }
    "$APKSIGNER" sign --key "$KEYS/apex.pk8" --cert "$KEYS/apex.x509.pem" --min-sdk-version 29 --v2-signing-enabled true --v3-signing-enabled true "$OUT" >/dev/null 2>&1 || { echo "capex sign failed"; exit 1; }
    ;;
  *) mv "$UNC" "$OUT" ;;
esac
echo "  OK: $(basename "$OUT") container=$(fp "$OUT" | cut -c1-8)"
