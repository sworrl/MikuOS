#!/usr/bin/env bash
# Re-sign every AOSP-public-test-key-signed APK in a rootfs with the MikuOS
# custom key set (Falcon Technix). This is what removes the world-known AOSP
# test keys from the platform so 3rd parties can't self-grant system perms.
#
# The five AOSP test keys map 1:1 to our five custom keys. The mapping is a
# bijection, so every sharedUserId group (incl. android.uid.system) and the
# framework-res platform anchor stay internally consistent. Real Google/Qualcomm/
# HiBy signatures are never touched.
#
# Usage:
#   resign_system.sh <rootfs_dir>            # DRY RUN — report only
#   APPLY=1 resign_system.sh <rootfs_dir>    # actually re-sign in place
#
# Also re-signs explicit APKs (our Miku apps) with the platform key:
#   APPLY=1 resign_system.sh --platform-apk path/to/App.apk [more.apk ...]
# Not `set -e`: a per-APK scan must survive an unreadable APK and still finish
# the pass + print the summary. Failures in APPLY mode are tracked explicitly.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
KEYS="$(cd "$DIR/../signing" && pwd)"
# Honor an APKSIGNER override so this runs under sudo (where ~ is /root).
APKSIGNER="${APKSIGNER:-$(ls ~/Android/Sdk/build-tools/*/apksigner 2>/dev/null | tail -1)}"
[ -n "$APKSIGNER" ] || { echo "ERROR: apksigner not found (set APKSIGNER=...)"; exit 1; }

# AOSP public test-key SHA-256 fingerprint (colonless, lowercase) -> our role.
# Also includes legacy intermediate test keys so any dirty tree is migrated cleanly.
# Roles actually re-keyed. DEFAULT EXCLUDES networkstack: on this firmware the
# android.uid.networkstack shared UID also contains APEX-embedded APKs
# (/apex/com.android.tethering TetheringNext, /apex/com.android.cellbroadcast
# CellBroadcastServiceModule) that stay on the AOSP networkstack cert e1dbadce
# because APEX payloads can't be re-signed here. Re-keying NetworkStack.apk then
# splits that shared UID between two certs, and Android 14's
# ReconcilePackageUtils treats a cert mismatch inside a system shared UID as
# FATAL (IllegalStateException in the PackageManager constructor -> system_server
# dies -> stuck on the boot animation with no USB). Root cause of every REKEY=1
# boot hang to date. Override with REKEY_ROLES="platform releasekey media shared networkstack".
REKEY_ROLES="${REKEY_ROLES:-platform releasekey shared}"
role_enabled() { case " $REKEY_ROLES " in *" $1 "*) return 0;; *) return 1;; esac; }

declare -A MAP=(
  # AOSP standard public test keys
  [c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8]=platform
  [a40da80a59d170caa950cf15c18c454d47a39b26989d8b640ecd745ba71bf5dc]=releasekey
  [465983f7791f2abeb43ea2cbdc7f21a8260b72bc08a55c839fc1a43bc741a81e]=media
  [28bbfe4a7b97e74681dc55c2fbb6ccb8d6c74963733f6af6ae74d8c3a6e879fd]=shared
  [e1dbadce60dc080d15b58a014b0dcf9400e24de23fa00b287a5a982bfebda2ee]=networkstack
  # Legacy / previous custom test keys
  [467aa492c2993fefd4ea09ef3e0487e6f309143fc10c7637f2600f1fdfb02066]=platform
  [417bcef029a64f0f8ea80b8564822a5efe295222429f83f46e52ab49d51903d8]=releasekey
  [20ac32d0ab9a281c75bb485818972a72ae499c39323566e51acef42f095e5cd5]=media
  [a246defa3446d2938cc250460d77816f247d96ea00b5528633cc7b6d3b661894]=shared
  [73bbe2e3ac6585831acb4e297ab4f060116851fc93d9e5dc8a6ab3ea65230497]=networkstack
  [dfe220d2c2e64f8f50d1d4ba1eb5d6b699750eaa20b0d14adce24660cbff7c61]=platform
)

FAILED=0
resign() {  # <apk> <role>
    local apk="$1" role="$2"
    local pk8="$KEYS/$role.pk8" cert="$KEYS/$role.x509.pem"
    [ -f "$pk8" ] && [ -f "$cert" ] || { echo "  !! missing key for role '$role'"; FAILED=$((FAILED+1)); return 1; }
    if [ "${APPLY:-0}" = "1" ]; then
        local ctx mode
        ctx="$(getfattr -n security.selinux -e hex --only-values "$apk" 2>/dev/null | tr -cd '0-9a-fA-Fx' || true)"
        mode="$(stat -c%a "$apk" 2>/dev/null || echo 644)"
        # Strip stale vendor signature files so Android 14 PackageManager doesn't fail with signature mismatch
        zip -d "$apk" "META-INF/*.SF" "META-INF/*.RSA" "META-INF/*.DSA" "META-INF/*.EC" "META-INF/*.MF" 2>/dev/null || true
        local zipalign="${ZIPALIGN:-$(ls ~/Android/Sdk/build-tools/*/zipalign 2>/dev/null | tail -1)}"
        if [ -n "$zipalign" ]; then
            local tmp_aligned
            tmp_aligned="$(mktemp --suffix=.apk)"
            "$zipalign" -f -p 4 "$apk" "$tmp_aligned" && mv "$tmp_aligned" "$apk"
            rm -f "$tmp_aligned"
        fi
        if "$APKSIGNER" sign --key "$pk8" --cert "$cert" \
                --v1-signing-enabled true --v2-signing-enabled true \
                --v3-signing-enabled true --v4-signing-enabled false "$apk"; then
            [ -n "$ctx" ] && setfattr -n security.selinux -v "$ctx" "$apk" 2>/dev/null || true
            chmod "$mode" "$apk" 2>/dev/null || true
            echo "  re-signed [$role]: $apk"
        else
            echo "  !! FAILED to re-sign [$role]: $apk"; FAILED=$((FAILED+1))
        fi
    else
        echo "  would re-sign [$role]: $apk"
    fi
}

fingerprint() {  # <apk> -> colonless lowercase sha256, or empty
    local out
    out="$("$APKSIGNER" verify --print-certs "$1" 2>/dev/null | grep -m1 "SHA-256 digest:" | sed 's/.*digest: //' | tr -d ':\r\n ' | tr 'A-F' 'a-f' || true)"
    echo "$out"
}

if [ "${1:-}" = "--platform-apk" ]; then
    shift
    for apk in "$@"; do resign "$apk" platform; done
    [ "$FAILED" -eq 0 ] || { echo "[resign] $FAILED failure(s)"; exit 1; }
    exit 0
fi

ROOT="${1:?usage: resign_system.sh <rootfs_dir>}"
echo "[resign] scanning $ROOT  (APPLY=${APPLY:-0})"
declare -A COUNT=() ; skipped=0
while IFS= read -r apk; do
    fp="$(fingerprint "$apk")"
    role=""
    if [ -n "$fp" ] && [[ "$fp" =~ ^[0-9a-f]{64}$ ]]; then
        role="${MAP[$fp]:-}"
        if [ -n "$role" ] && ! role_enabled "$role"; then
            echo "  keep [$role, role disabled]: $apk"; role=""
        fi
    fi
    if [ -n "$role" ]; then
        resign "$apk" "$role"
        COUNT[$role]=$(( ${COUNT[$role]:-0} + 1 ))
    else
        skipped=$((skipped+1))   # Google / Qualcomm / HiBy / already-ours — leave alone
    fi
done < <(find "$ROOT" -name "*.apk" 2>/dev/null)

echo "[resign] summary:"
for r in platform releasekey media shared networkstack; do
    echo "  $r: ${COUNT[$r]:-0}"
done
echo "  left untouched (vendor/Google/other): $skipped"
[ "$FAILED" -eq 0 ] || { echo "[resign] ERROR: $FAILED APK(s) failed to re-sign"; exit 1; }
