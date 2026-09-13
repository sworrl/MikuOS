#!/usr/bin/env bash
# MikuOS opt-in root: flash the Magisk-patched init_boot to BOTH slots and reboot.
# Root lives entirely in init_boot's ramdisk, so this needs NO userdata wipe — the
# user keeps everything (liked songs, history) and just gains root. The Magisk app
# is already installed (baked into system/app/Magisk); after this it shows "installed"
# and can grant su. Revert any time with disable_root.sh.
#
# This is the "point Magisk at the device to enable root" path from onboarding:
# default is UNROOTED (stock init_boot via flash_mikuos.sh); run this to turn root on.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MAGISK_INIT_BOOT="$REPO_DIR/m500-system-archive/firmware/magisk_patched_init_boot.img"

[ -f "$MAGISK_INIT_BOOT" ] || { echo "Error: patched init_boot not found: $MAGISK_INIT_BOOT"; exit 1; }

DEV=$(fastboot devices | head -n1 | awk '{print $1}')
[ -n "$DEV" ] || { echo "Error: no device in fastboot mode. Reboot the M500 to fastboot first."; exit 1; }

echo "=========================================================="
echo "   MikuOS: ENABLING ROOT (Magisk) — no data wipe          "
echo "   Device: $DEV"
echo "=========================================================="
fastboot -s "$DEV" flash init_boot_a "$MAGISK_INIT_BOOT"
fastboot -s "$DEV" flash init_boot_b "$MAGISK_INIT_BOOT"
fastboot -s "$DEV" --set-active=a
echo "   Root enabled. Rebooting — open Magisk to grant su."
fastboot -s "$DEV" reboot
