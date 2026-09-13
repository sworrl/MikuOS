#!/usr/bin/env bash
# Flash MikuOS while PRESERVING /data (HeliBoard + its theme, liked songs, history).
# Identical to flash_mikuos.sh but WITHOUT `erase userdata`/`erase metadata`, so the
# encrypted userdata stays intact and decryptable (metadata holds the FBE keys). Use this
# for an update flash; use flash_mikuos_clean.sh only when you deliberately want a wipe.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIKUOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$MIKUOS_DIR/.." && pwd)"
FW_DIR="$REPO_DIR/m500-system-archive/firmware/extracted_1.00"
SUPER_IMG="$MIKUOS_DIR/out/mikuos_system_bundle.img"   # = OUTPUT_SUPER of build_mikuos_super.sh
VBMETA_DISABLED="$MIKUOS_DIR/out/vbmeta_disabled.img"
VBMETA_SYS_DISABLED="$MIKUOS_DIR/out/vbmeta_system_disabled.img"

if [ ! -f "$SUPER_IMG" ]; then
    echo "Error: $SUPER_IMG not found. Run build_mikuos_super.sh first."
    exit 1
fi

echo "=========================================================="
echo "     Flashing MikuOS to HiBy M500 (KEEPING /data)         "
echo "=========================================================="

DEV=$(fastboot devices | head -n1 | awk '{print $1}')
if [ -z "$DEV" ]; then
    echo "Error: No device detected in fastboot mode. Please boot into fastboot."
    exit 1
fi
echo "Target Device: $DEV"

echo "[1/4] Flashing official 1.00 Kernel & Boot partitions..."
# Kernel: STOCK 5.15.153. GKI 5.15.209 is DISQUALIFIED until its charging regression is fixed:
# A/B-tested 2026-09-10 at 94% battery on the same cable - stock charges immediately
# (mp2731 online=1/Charging), 5.15.209 never qualifies the input (online=0, current_max=0,
# device DRAINS on the cable; the input-qualify blips also strobed the screen via
# WAKE_REASON_PLUGGED_IN). Suspect: VBUS/charger-type notify path (dwc3-msm -> mp2731) on
# generic GKI. Audio/dlkms were fine on 5.15.209. Opt in only for testing: MIKU_KERNEL_209=1.
BOOT_IMG="$FW_DIR/boot.img"
[ "${MIKU_KERNEL_209:-0}" = "1" ] && [ -f "$FW_DIR/boot_gki_5.15.209.img" ] && BOOT_IMG="$FW_DIR/boot_gki_5.15.209.img"
echo "  boot image: $BOOT_IMG"
fastboot -s $DEV flash boot_a "$BOOT_IMG"
fastboot -s $DEV flash boot_b "$BOOT_IMG"
fastboot -s $DEV flash init_boot_a "$FW_DIR/init_boot.img"
fastboot -s $DEV flash init_boot_b "$FW_DIR/init_boot.img"
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
# 64M chunks: larger chunks wedge the M500's USB gadget mid-super (see memory
# m500-super-flash-chunk-fix); retry once if the gadget hiccups.
fastboot -s $DEV -S 64M flash super "$SUPER_IMG" || { sleep 3; fastboot -s $DEV -S 64M flash super "$SUPER_IMG"; }

echo "[4/4] Setting active slot to A (userdata + metadata PRESERVED)..."
fastboot -s $DEV set_active a

echo "=========================================================="
echo "  MikuOS Flash Complete (data kept)! Rebooting...          "
echo "=========================================================="
fastboot -s $DEV reboot

# The static /product/overlay RROs now come from the image. Remove the runtime ".live"
# copies that were adb-installed for no-reflash testing (they'd otherwise stack on top).
echo "[post] Waiting for boot to remove .live test overlays (Ctrl-C to skip)..."
if adb wait-for-device shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done' 2>/dev/null; then
    for p in com.miku.overlay.animations.live com.miku.theme.overlay.live com.miku.systemui.overlay.live; do
        adb shell pm uninstall "$p" >/dev/null 2>&1 && echo "  removed $p" || true
    done
    adb shell 'cmd overlay list | grep -i miku'
fi
