#!/usr/bin/env bash
# ==============================================================================
# 🚀 M500 Smart Multi-Transport Rsync Pipeline
# Automatically detects USB vs Wi-Fi connection and routes to the fastest available link:
#   - ⚡ USB High-Speed Link (~45 MB/s direct raw socket via adb port forward)
#   - 📶 5GHz Wi-Fi Direct Link (~18.5 MB/s raw socket via rsync://<SYNC_HOST>:<SYNC_PORT>)
#
# Host/IP/port are NOT hardcoded — they come from a gitignored env file
# (tools/m500-sync.env; copy tools/m500-sync.env.example) or environment variables.
#
# Usage:
#   tools/m500-sync.sh music /path/to/local/music
#   tools/m500-sync.sh movies /path/to/local/movies
#   tools/m500-sync.sh staging /path/to/local/staging
# ==============================================================================
set -euo pipefail

# Load user sync config (gitignored — never commit a real host/IP).
# Canonical location: tools/m500-sync.env (see tools/m500-sync.env.example).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ENV_FILE="${M500_SYNC_ENV:-}"
if [ -z "$ENV_FILE" ]; then
    for cand in "$SCRIPT_DIR/m500-sync.env" "$SCRIPT_DIR/../m500-sync.env"; do
        [ -f "$cand" ] && { ENV_FILE="$cand"; break; }
    done
fi
# shellcheck disable=SC1090
[ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ] && . "$ENV_FILE"

MODULE="${1:-music}"
SRC_DIR="${2:-}"
# Wi-Fi sync host: env M500_IP overrides SYNC_HOST from the env file; empty => USB-only.
WIFI_IP="${M500_IP:-${SYNC_HOST:-}}"
RSYNC_PORT="${SYNC_PORT:-8730}"

if [ -z "$SRC_DIR" ]; then
    echo "Usage: $0 <music|movies|staging> <local_source_directory>"
    exit 1
fi

if [ ! -d "$SRC_DIR" ]; then
    echo "❌ Error: Source directory '$SRC_DIR' does not exist."
    exit 1
fi

echo "========================================================"
echo "🎵 MIKU MEDIA MONITOR · M500 High-Speed Ingress Engine"
echo "========================================================"
echo "Module Target: $MODULE"
echo "Source:        $SRC_DIR"

# 1. Probe for USB connection via ADB
IS_USB=0
USB_SERIAL=""

if command -v adb >/dev/null 2>&1; then
    # Look for serial devices in adb (exclude the Wi-Fi endpoint, if one is configured)
    DEVICE_LIST=$(adb devices -l 2>/dev/null | grep "device " || true)
    if [ -n "$WIFI_IP" ]; then
        DEVICE_LIST=$(printf '%s\n' "$DEVICE_LIST" | grep -v "$WIFI_IP" || true)
    fi
    if [ -n "$DEVICE_LIST" ]; then
        USB_SERIAL=$(echo "$DEVICE_LIST" | head -n1 | awk '{print $1}')
        IS_USB=1
    fi
fi

if [ "$IS_USB" -eq 1 ]; then
    echo "⚡ High-Speed USB Connection Detected ($USB_SERIAL)!"
    echo "🔗 Forwarding TCP port $RSYNC_PORT via USB link..."
    adb -s "$USB_SERIAL" forward "tcp:$RSYNC_PORT" "tcp:$RSYNC_PORT" 2>/dev/null || true
    TARGET_URL="rsync://127.0.0.1:$RSYNC_PORT/$MODULE"
    ESTIMATED_SPEED="~35 - 45 MB/s (USB 2.0 High-Speed)"
elif [ -n "$WIFI_IP" ]; then
    echo "📶 Wireless Wi-Fi Link Selected ($WIFI_IP:$RSYNC_PORT)"
    TARGET_URL="rsync://$WIFI_IP:$RSYNC_PORT/$MODULE"
    ESTIMATED_SPEED="~15 - 18.5 MB/s (Wi-Fi 5GHz)"
else
    echo "❌ No USB device detected and no sync host configured."
    echo "   Set SYNC_HOST in ${ENV_FILE:-tools/m500-sync.env} (copy tools/m500-sync.env.example)"
    echo "   or export M500_IP=<host>."
    exit 1
fi

echo "🚀 Target: $TARGET_URL"
echo "⚡ Estimated Bandwidth: $ESTIMATED_SPEED"
echo "--------------------------------------------------------"

# Run high-performance rsync with zero-copy inplace streaming
START_TIME=$(date +%s)

rsync -avh \
    --inplace \
    --no-whole-file \
    --progress \
    --stats \
    --exclude=".*" \
    --exclude="Thumbs.db" \
    --exclude="desktop.ini" \
    "$SRC_DIR/" "$TARGET_URL/"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "--------------------------------------------------------"
echo "✨ Ingress completed in ${DURATION}s."
echo "🎵 Miku Media Monitor on M500 will auto-index incoming files into FastLibraryStore."
echo "========================================================"
