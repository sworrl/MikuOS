#!/usr/bin/env bash
# ==============================================================================
# HiBy M500 — MikuOS Pure AOSP 14 GSI Flashing Tool
# ==============================================================================
# Flashes the unified Pure AOSP 14 GSI dynamic super image with Qualcomm BSP
# hardware bindings and MikuOS application suite.
#
# Usage:
#   mikuos/build/flash_mikuos_gsi.sh [--rooted]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIKUOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$MIKUOS_DIR/.." && pwd)"
FW_DIR="$REPO_DIR/m500-system-archive/firmware/extracted_1.00"
MAGISK_INIT_BOOT="$REPO_DIR/m500-system-archive/firmware/magisk_patched_init_boot.img"
GSI_SUPER="$MIKUOS_DIR/out/mikuos_gsi_super.img"
VBMETA_DISABLED="$MIKUOS_DIR/out/vbmeta_disabled.img"
VBMETA_SYS_DISABLED="$MIKUOS_DIR/out/vbmeta_system_disabled.img"

USE_ROOT="${1:-}"

if [ ! -f "$GSI_SUPER" ]; then
    echo "Error: $GSI_SUPER not found. Run build_mikuos_gsi.sh first." >&2
    exit 1
fi

echo "=========================================================="
echo "      Flashing MikuOS Pure AOSP 14 to HiBy M500           "
echo "=========================================================="

DEV=$(fastboot devices | head -n1 | awk '{print $1}')
if [ -z "$DEV" ]; then
    echo "Error: No device detected in fastboot mode. Please boot into fastboot." >&2
    exit 1
fi

echo "Target Device: $DEV"

echo "[1/4] Flashing Qualcomm Kernel & Boot partitions..."
fastboot -s $DEV flash boot_a "$FW_DIR/boot.img"
fastboot -s $DEV flash boot_b "$FW_DIR/boot.img"

if [ -f "$MAGISK_INIT_BOOT" ]; then
    echo "  -> Using Magisk-patched init_boot for root access & adb authorization"
    fastboot -s $DEV flash init_boot_a "$MAGISK_INIT_BOOT"
    fastboot -s $DEV flash init_boot_b "$MAGISK_INIT_BOOT"
else
    echo "  -> Flashing stock init_boot"
    fastboot -s $DEV flash init_boot_a "$FW_DIR/init_boot.img"
    fastboot -s $DEV flash init_boot_b "$FW_DIR/init_boot.img"
fi

fastboot -s $DEV flash dtbo_a "$FW_DIR/dtbo.img"
fastboot -s $DEV flash dtbo_b "$FW_DIR/dtbo.img"
fastboot -s $DEV flash vendor_boot_a "$FW_DIR/vendor_boot.img"
fastboot -s $DEV flash vendor_boot_b "$FW_DIR/vendor_boot.img"

echo "[2/4] Flashing Verified Boot Disabler vbmeta (flags=0x03)..."
fastboot -s $DEV flash vbmeta_a "$VBMETA_DISABLED"
fastboot -s $DEV flash vbmeta_b "$VBMETA_DISABLED"
fastboot -s $DEV flash vbmeta_system_a "$VBMETA_SYS_DISABLED"
fastboot -s $DEV flash vbmeta_system_b "$VBMETA_SYS_DISABLED"

echo "[3/4] Flashing MikuOS Pure AOSP 14 super.img..."
fastboot -s $DEV -S 400M flash super "$GSI_SUPER"

echo "[4/4] Setting active slot A & performing clean filesystem wipe..."
fastboot -s $DEV set_active a
fastboot -s $DEV erase misc
fastboot -s $DEV erase metadata
fastboot -s $DEV erase userdata

echo "=========================================================="
echo "  MikuOS AOSP 14 Flash Complete! Rebooting device...     "
echo "=========================================================="
fastboot -s $DEV reboot
