#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIKUOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$MIKUOS_DIR/.." && pwd)"
FW_DIR="$REPO_DIR/m500-system-archive/firmware/extracted_1.00"
MAGISK_INIT_BOOT="$REPO_DIR/m500-system-archive/firmware/magisk_patched_init_boot.img"
SUPER_IMG="$MIKUOS_DIR/out/mikuos_system_bundle.img"   # = OUTPUT_SUPER of build_mikuos_super.sh
VBMETA_DISABLED="$MIKUOS_DIR/out/vbmeta_disabled.img"
VBMETA_SYS_DISABLED="$MIKUOS_DIR/out/vbmeta_system_disabled.img"

if [ ! -f "$SUPER_IMG" ]; then
    echo "Error: $SUPER_IMG not found. Run build_mikuos_super.sh first."
    exit 1
fi

echo "=========================================================="
echo "      Flashing Rooted (Magisk) MikuOS v0.1.0 to M500      "
echo "=========================================================="

DEV=$(fastboot devices | head -n1 | awk '{print $1}')
if [ -z "$DEV" ]; then
    echo "Error: No device detected in fastboot mode. Please boot into fastboot."
    exit 1
fi

echo "Target Device: $DEV"

echo "[1/4] Flashing official 1.00 Kernel & Magisk Patched init_boot..."
fastboot -s $DEV flash boot_a "$FW_DIR/boot.img"
fastboot -s $DEV flash boot_b "$FW_DIR/boot.img"
fastboot -s $DEV flash init_boot_a "$MAGISK_INIT_BOOT"
fastboot -s $DEV flash init_boot_b "$MAGISK_INIT_BOOT"
fastboot -s $DEV flash dtbo_a "$FW_DIR/dtbo.img"
fastboot -s $DEV flash dtbo_b "$FW_DIR/dtbo.img"
fastboot -s $DEV flash vendor_boot_a "$FW_DIR/vendor_boot.img"
fastboot -s $DEV flash vendor_boot_b "$FW_DIR/vendor_boot.img"

echo "[2/4] Flashing AVB Disabler vbmeta (flags=3 for Custom ROMs)..."
fastboot -s $DEV flash vbmeta_a "$VBMETA_DISABLED"
fastboot -s $DEV flash vbmeta_b "$VBMETA_DISABLED"
fastboot -s $DEV flash vbmeta_system_a "$VBMETA_SYS_DISABLED"
fastboot -s $DEV flash vbmeta_system_b "$VBMETA_SYS_DISABLED"

echo "[3/4] Flashing MikuOS Dynamic super.img (System, Vendor, Product, System_Ext, ODM)..."
fastboot -s $DEV -S 400M flash super "$SUPER_IMG"

echo "[4/4] Setting active slot to A and clearing userdata cache..."
fastboot -s $DEV set_active a
# Clear the boot-control block (misc/BCB)
fastboot -s $DEV erase misc
# Erase metadata and userdata; first_stage_mount will format f2fs metadata and FBE ext4 userdata automatically
fastboot -s $DEV erase metadata
fastboot -s $DEV erase userdata

echo "=========================================================="
echo "  Rooted MikuOS Flash Complete! Rebooting device...       "
echo "=========================================================="
fastboot -s $DEV reboot
