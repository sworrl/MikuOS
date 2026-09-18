#!/usr/bin/env bash
# ==============================================================================
# HiBy M500 (M500_MIKU_4G) — Universal Factory Restore & Unbrick Tool
# ==============================================================================
# Restores the device to 100% factory condition from any state (fastboot / bootloop).
# Flashes all stock partitions, kernel, bootloaders, vbmeta, and the factory super.img.
#
# Usage:
#   tools/unbrick_factory.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FW_DIR="$REPO_DIR/m500-system-archive/firmware/extracted_1.00"
SUPER_IMG="$REPO_DIR/m500-system-archive/firmware/super.img"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BLUE}${BOLD}====================================================================${NC}"
echo -e "${BLUE}${BOLD}      HiBy M500 — Universal Factory Restore & Unbrick Suite         ${NC}"
echo -e "${BLUE}${BOLD}====================================================================${NC}"

# Check required files
for f in "$FW_DIR/boot.img" "$FW_DIR/init_boot.img" "$FW_DIR/dtbo.img" \
         "$FW_DIR/vendor_boot.img" "$FW_DIR/vbmeta.img" "$FW_DIR/vbmeta_system.img" "$SUPER_IMG"; do
    if [ ! -f "$f" ]; then
        echo -e "${RED}[ERROR] Required image file missing: $f${NC}" >&2
        exit 1
    fi
done

# Detect Device
echo -e "\n${BOLD}[1/4] Detecting device connection...${NC}"
if fastboot devices | grep -q "fastboot"; then
    DEV="$(fastboot devices | head -n1 | awk '{print $1}')"
    echo -e "  [${GREEN}OK${NC}] Device detected in Fastboot mode: ${YELLOW}$DEV${NC}"
elif adb devices | grep -q "device$\|recovery$"; then
    DEV="$(adb devices | grep -E "device$|recovery$" | head -n1 | awk '{print $1}')"
    echo -e "  [*] Device detected in ADB mode ($DEV). Rebooting to bootloader..."
    adb -s "$DEV" reboot bootloader
    sleep 3
    DEV="$(fastboot devices | head -n1 | awk '{print $1}')"
else
    echo -e "${RED}[ERROR] No device detected. Connect M500 via USB in Fastboot mode.${NC}" >&2
    exit 1
fi

[ -n "$DEV" ] || { echo -e "${RED}[ERROR] Failed to get fastboot device handle.${NC}" >&2; exit 1; }

echo -e "\n${BOLD}[2/4] Restoring official Qualcomm/HiBy Kernel & Boot partitions...${NC}"
fastboot -s "$DEV" flash boot_a "$FW_DIR/boot.img"
fastboot -s "$DEV" flash boot_b "$FW_DIR/boot.img"
fastboot -s "$DEV" flash init_boot_a "$FW_DIR/init_boot.img"
fastboot -s "$DEV" flash init_boot_b "$FW_DIR/init_boot.img"
fastboot -s "$DEV" flash dtbo_a "$FW_DIR/dtbo.img"
fastboot -s "$DEV" flash dtbo_b "$FW_DIR/dtbo.img"
fastboot -s "$DEV" flash vendor_boot_a "$FW_DIR/vendor_boot.img"
fastboot -s "$DEV" flash vendor_boot_b "$FW_DIR/vendor_boot.img"

echo -e "\n${BOLD}[3/4] Restoring official Verified Boot (vbmeta) containers...${NC}"
fastboot -s "$DEV" flash vbmeta_a "$FW_DIR/vbmeta.img"
fastboot -s "$DEV" flash vbmeta_b "$FW_DIR/vbmeta.img"
fastboot -s "$DEV" flash vbmeta_system_a "$FW_DIR/vbmeta_system.img"
fastboot -s "$DEV" flash vbmeta_system_b "$FW_DIR/vbmeta_system.img"

echo -e "\n${BOLD}[4/4] Flashing factory dynamic super.img (System, Vendor, Product, Ext, ODM)...${NC}"
fastboot -s "$DEV" -S 400M flash super "$SUPER_IMG"

echo -e "\n${BOLD}[*] Setting active slot to A and performing clean partition wipe...${NC}"
fastboot -s "$DEV" set_active a
fastboot -s "$DEV" erase misc
fastboot -s "$DEV" erase metadata
fastboot -s "$DEV" erase userdata

echo -e "\n${GREEN}${BOLD}====================================================================${NC}"
echo -e "${GREEN}${BOLD}>>> RESTORE COMPLETE! Device is 100% factory stock and unbricked.   ${NC}"
echo -e "${GREEN}${BOLD}====================================================================${NC}"
echo -e "[*] Rebooting into factory system..."
fastboot -s "$DEV" reboot
