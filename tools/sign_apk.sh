#!/usr/bin/env bash
# ==============================================================================
# MikuOS APK Signing Tool (Falcon Technix)
# ==============================================================================
# Signs APKs using the canonical MikuOS custom key set (4096-bit RSA / SHA-256).
# Supports all 5 AOSP 1:1 replacement roles + custom overlays and platform apps.
#
# Usage:
#   tools/sign_apk.sh [OPTIONS] <apk_file> [more_apks...]
#
# Options:
#   -r, --role <role>       Key role: platform (default), releasekey, media, shared, networkstack
#   -p, --platform          Shortcut for --role platform
#   --release               Shortcut for --role releasekey
#   -m, --media             Shortcut for --role media
#   -s, --shared            Shortcut for --role shared
#   -n, --networkstack      Shortcut for --role networkstack
#   -o, --output <path>     Output file path or directory (default: in-place / alongside)
#   --v1                    Enable v1 (JAR) signing (default: disabled to preserve 4K mmap alignment)
#   --no-align              Skip zipalign step
#   -v, --verify-only       Only verify signature and print certificate info without signing
#   -h, --help              Show this help message
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KEYS_DIR="$REPO_DIR/mikuos/signing"

# Auto-detect Android SDK build-tools
find_tool() {
    local tool="$1"
    local path=""
    if command -v "$tool" >/dev/null 2>&1; then
        path="$(command -v "$tool")"
    elif [ -n "${ANDROID_HOME:-}" ] && ls "$ANDROID_HOME/build-tools"/*/"$tool" 2>/dev/null | tail -1 >/dev/null; then
        path="$(ls -1 "$ANDROID_HOME/build-tools"/*/"$tool" 2>/dev/null | tail -1)"
    elif [ -n "${ANDROID_SDK_ROOT:-}" ] && ls "$ANDROID_SDK_ROOT/build-tools"/*/"$tool" 2>/dev/null | tail -1 >/dev/null; then
        path="$(ls -1 "$ANDROID_SDK_ROOT/build-tools"/*/"$tool" 2>/dev/null | tail -1)"
    elif ls "$HOME/Android/Sdk/build-tools"/*/"$tool" 2>/dev/null | tail -1 >/dev/null; then
        path="$(ls -1 "$HOME/Android/Sdk/build-tools"/*/"$tool" 2>/dev/null | tail -1)"
    fi
    echo "$path"
}

APKSIGNER="${APKSIGNER:-$(find_tool apksigner)}"
ZIPALIGN="${ZIPALIGN:-$(find_tool zipalign)}"

if [ -z "$APKSIGNER" ] || [ ! -x "$APKSIGNER" ]; then
    echo "ERROR: apksigner not found. Set APKSIGNER=/path/to/apksigner or install Android SDK build-tools." >&2
    exit 1
fi

ROLE="platform"
OUTPUT=""
ENABLE_V1=false
ENABLE_V2=true
ENABLE_V3=true
ENABLE_V4=false
DO_ALIGN=true
VERIFY_ONLY=false
APKS=()

usage() {
    cat << 'EOF'
Usage:
  sign_apk.sh [OPTIONS] <apk_file> [more_apks...]

Options:
  -r, --role <role>       Key role: platform (default), releasekey, media, shared, networkstack
  -p, --platform          Shortcut for --role platform
  --release               Shortcut for --role releasekey
  -m, --media             Shortcut for --role media
  -s, --shared            Shortcut for --role shared
  -n, --networkstack      Shortcut for --role networkstack
  -o, --output <path>     Output file path or destination directory
  --v1                    Enable v1 (JAR) signing (default: disabled for 4K page mmap safety)
  --no-align              Skip zipalign step
  -v, --verify-only       Only verify signature and print certificate info without signing
  -h, --help              Show this help message
EOF
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage ;;
        -r|--role) ROLE="$2"; shift 2 ;;
        -p|--platform) ROLE="platform"; shift ;;
        --release) ROLE="releasekey"; shift ;;
        -m|--media) ROLE="media"; shift ;;
        -s|--shared) ROLE="shared"; shift ;;
        -n|--networkstack) ROLE="networkstack"; shift ;;
        -o|--output) OUTPUT="$2"; shift 2 ;;
        --v1) ENABLE_V1=true; shift ;;
        --no-align) DO_ALIGN=false; shift ;;
        -v|--verify-only) VERIFY_ONLY=true; shift ;;
        -*) echo "Unknown option: $1" >&2; usage ;;
        *) APKS+=("$1"); shift ;;
    esac
done

if [ ${#APKS[@]} -eq 0 ]; then
    echo "ERROR: No APK files specified." >&2
    usage
fi

verify_apk() {
    local apk="$1"
    echo "=========================================================="
    echo " Verifying: $(basename "$apk")"
    echo " Path: $apk"
    echo "=========================================================="
    if "$APKSIGNER" verify --verbose --print-certs "$apk" 2>&1; then
        echo "--> Verification result: VALID"
    else
        echo "--> Verification result: INVALID or UNSIGNED"
    fi
    echo
}

if [ "$VERIFY_ONLY" = true ]; then
    for apk in "${APKS[@]}"; do
        [ -f "$apk" ] || { echo "ERROR: File not found: $apk" >&2; continue; }
        verify_apk "$apk"
    done
    exit 0
fi

# Ensure keys exist for the selected role
KEY_PK8="$KEYS_DIR/$ROLE.pk8"
KEY_PEM="$KEYS_DIR/$ROLE.x509.pem"

if [ ! -f "$KEY_PK8" ] || [ ! -f "$KEY_PEM" ]; then
    echo "ERROR: Keys for role '$ROLE' not found in $KEYS_DIR" >&2
    echo "Run $KEYS_DIR/generate_mikuos_keys.sh first." >&2
    exit 1
fi

echo "=========================================================="
echo "          MikuOS APK Signer (Falcon Technix)              "
echo "=========================================================="
echo "Role:         $ROLE"
echo "Certificate:  $KEY_PEM"
echo "Private Key:  $KEY_PK8"
echo "apksigner:    $APKSIGNER"
echo "zipalign:     ${ZIPALIGN:-'(not found - skipping alignment)'}"
echo "v1 (JAR):     $ENABLE_V1"
echo "v2:           $ENABLE_V2"
echo "v3:           $ENABLE_V3"
echo "=========================================================="

for apk in "${APKS[@]}"; do
    if [ ! -f "$apk" ]; then
        echo "ERROR: File not found: $apk" >&2
        continue
    fi

    target="$apk"
    if [ -n "$OUTPUT" ]; then
        if [ -d "$OUTPUT" ]; then
            target="$OUTPUT/$(basename "$apk")"
        else
            target="$OUTPUT"
        fi
    fi

    echo "--> Processing: $apk"

    # Capture SELinux label and file mode if on filesystem
    ctx=""
    mode="644"
    if command -v getfattr >/dev/null 2>&1; then
        ctx="$(getfattr -n security.selinux -e hex --only-values "$apk" 2>/dev/null || true)"
    fi
    mode="$(stat -c%a "$apk" 2>/dev/null || echo 644)"

    work_apk="$apk"
    temp_align=""
    if [ "$DO_ALIGN" = true ] && [ -n "$ZIPALIGN" ] && [ -x "$ZIPALIGN" ]; then
        temp_align="$(mktemp --suffix=.apk)"
        # Check alignment first (4-byte alignment, 4096-byte alignment for .so)
        if ! "$ZIPALIGN" -c -p 4 "$apk" >/dev/null 2>&1; then
            echo "    Aligning zip entries (4096-byte page aligned for .so)..."
            "$ZIPALIGN" -f -p 4 "$apk" "$temp_align"
            work_apk="$temp_align"
        fi
    fi

    # If target is different from work_apk, copy
    if [ "$work_apk" != "$target" ]; then
        mkdir -p "$(dirname "$target")"
        cp "$work_apk" "$target"
    fi

    # Clean temp align file if used
    [ -n "$temp_align" ] && rm -f "$temp_align"

    # Sign with apksigner
    echo "    Signing with [$ROLE] key..."
    "$APKSIGNER" sign \
        --key "$KEY_PK8" \
        --cert "$KEY_PEM" \
        --v1-signing-enabled "$ENABLE_V1" \
        --v2-signing-enabled "$ENABLE_V2" \
        --v3-signing-enabled "$ENABLE_V3" \
        --v4-signing-enabled "$ENABLE_V4" \
        "$target"

    # Restore SELinux xattrs and permissions
    if [ -n "$ctx" ] && command -v setfattr >/dev/null 2>&1; then
        setfattr -n security.selinux -v "$ctx" "$target" 2>/dev/null || true
    fi
    chmod "$mode" "$target" 2>/dev/null || true

    echo "    Successfully signed: $target"
    
    # Print quick verification summary
    fp="$("$APKSIGNER" verify --print-certs "$target" 2>/dev/null | grep -m1 "SHA-256 digest:" | sed 's/.*digest: //')"
    echo "    SHA-256 Fingerprint: $fp"
    echo
done

echo "Done."
