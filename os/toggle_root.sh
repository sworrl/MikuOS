#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
STOCK_INIT_BOOT="$REPO_DIR/m500-system-archive/firmware/extracted_1.00/init_boot.img"
MAGISK_INIT_BOOT="$REPO_DIR/m500-system-archive/firmware/magisk_patched_init_boot.img"

DEV=$(fastboot devices | head -n1 | awk '{print $1}')
if [ -z "$DEV" ]; then
    echo "Error: No device detected in fastboot mode. Put device in Fastboot Mode."
    exit 1
fi

ACTION="${1:-}"
if [ "$ACTION" == "--enable" ] || [ "$ACTION" == "root" ] || [ "$ACTION" == "enable" ]; then
    echo "⚡ Enabling Magisk Root (Zero data loss)..."
    fastboot -s $DEV flash init_boot_a "$MAGISK_INIT_BOOT"
    fastboot -s $DEV flash init_boot_b "$MAGISK_INIT_BOOT"
    fastboot -s $DEV set_active a
    echo "✅ Magisk Root Enabled! Rebooting..."
    fastboot -s $DEV reboot
elif [ "$ACTION" == "--disable" ] || [ "$ACTION" == "unroot" ] || [ "$ACTION" == "disable" ] || [ "$ACTION" == "stock" ]; then
    echo "🛡️ Returning to Clean Stock Non-Rooted Kernel (Zero data loss)..."
    fastboot -s $DEV flash init_boot_a "$STOCK_INIT_BOOT"
    fastboot -s $DEV flash init_boot_b "$STOCK_INIT_BOOT"
    fastboot -s $DEV set_active a
    echo "✅ Clean Stock Kernel Restored! Rebooting..."
    fastboot -s $DEV reboot
else
    echo "Usage: ./toggle_root.sh [--enable | --disable]"
    echo "  --enable  : Flash Magisk rooted init_boot (No wipe)"
    echo "  --disable : Flash stock non-rooted init_boot (No wipe)"
    exit 1
fi
