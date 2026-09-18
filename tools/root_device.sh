#!/bin/bash
set -euo pipefail

# ==============================================================================
# MikuOS 1-Click Fast Root Tool
# ==============================================================================
# Flashes Magisk-patched init_boot without wiping userdata.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FW_DIR="$ROOT_DIR/m500-system-archive/firmware"
MAGISK_INIT_BOOT="$FW_DIR/magisk_patched_init_boot.img"

echo "=========================================================="
echo "          MikuOS 1-Click Fast Root Tool                   "
echo "=========================================================="

if [ ! -f "$MAGISK_INIT_BOOT" ]; then
    echo "[-] Error: Magisk patched init_boot not found at $MAGISK_INIT_BOOT"
    exit 1
fi

# Check if device is connected via ADB or Fastboot
DEV="$(fastboot devices 2>/dev/null | awk '{print $1}' | head -n1 || true)"
if [ -z "$DEV" ]; then
    echo "[*] Fastboot device not detected. Checking ADB..."
    ADB_DEV="$(adb devices 2>/dev/null | grep -w "device" | awk '{print $1}' | head -n1 || true)"
    if [ -n "$ADB_DEV" ]; then
        echo "[*] Found ADB device ($ADB_DEV). Rebooting to bootloader..."
        adb reboot bootloader
        echo "[*] Waiting for fastboot mode..."
        sleep 4
        DEV="$(fastboot devices 2>/dev/null | awk '{print $1}' | head -n1 || true)"
    fi
fi

if [ -z "$DEV" ]; then
    echo "[-] Error: No device found in Fastboot mode."
    echo "    Please reboot your M500 into FASTBOOT (Hold Power + Vol Down) and re-run."
    exit 1
fi

echo "[+] Target Device: $DEV"
echo "[+] Flashing Magisk patched init_boot to slot A & B..."
fastboot -s "$DEV" flash init_boot_a "$MAGISK_INIT_BOOT"
fastboot -s "$DEV" flash init_boot_b "$MAGISK_INIT_BOOT"

echo "[+] Root installation complete! Rebooting..."
fastboot -s "$DEV" reboot

echo "=========================================================="
echo "  Device successfully rooted! System is rebooting.        "
echo "=========================================================="
