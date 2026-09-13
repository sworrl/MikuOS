#!/usr/bin/env bash
# MikuOS: revert to UNROOTED — flash the STOCK init_boot to both slots and reboot.
# Undoes enable_root.sh. No userdata wipe; the Magisk app stays installed but goes
# back to "not installed" (no su). This is the default onboarding state.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FW_DIR="$REPO_DIR/m500-system-archive/firmware/extracted_1.00"
STOCK_INIT_BOOT="$FW_DIR/init_boot.img"

[ -f "$STOCK_INIT_BOOT" ] || { echo "Error: stock init_boot not found: $STOCK_INIT_BOOT"; exit 1; }

DEV=$(fastboot devices | head -n1 | awk '{print $1}')
[ -n "$DEV" ] || { echo "Error: no device in fastboot mode. Reboot the M500 to fastboot first."; exit 1; }

echo "=========================================================="
echo "   MikuOS: DISABLING ROOT — back to stock init_boot        "
echo "   Device: $DEV"
echo "=========================================================="
fastboot -s "$DEV" flash init_boot_a "$STOCK_INIT_BOOT"
fastboot -s "$DEV" flash init_boot_b "$STOCK_INIT_BOOT"
fastboot -s "$DEV" --set-active=a
echo "   Root disabled (unrooted). Rebooting."
fastboot -s "$DEV" reboot
