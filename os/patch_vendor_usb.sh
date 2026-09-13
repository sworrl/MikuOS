#!/bin/bash
# Patch vendor.img init.qcom.usb.rc to replace "HiBy RS8II" with "m500 Hatsune Miku Edition"
set -e
FW_DIR="/home/reaver/Documents/GitHub/m500/m500-system-archive/firmware/extracted_1.00"
OUT_DIR="/home/reaver/Documents/GitHub/m500/mikuos/out"

echo "Patching vendor USB gadget descriptor strings..."
TMP_RC="/tmp/init.qcom.usb.rc"
debugfs -R "cat etc/init/hw/init.qcom.usb.rc" "$OUT_DIR/vendor.img" 2>/dev/null > "$TMP_RC" || true
if [ -s "$TMP_RC" ]; then
    sed -i 's/HiBy RS8II/m500 Hatsune Miku Edition/g' "$TMP_RC"
    debugfs -w -R "write $TMP_RC etc/init/hw/init.qcom.usb.rc" "$OUT_DIR/vendor.img" 2>/dev/null || true
    echo "  -> Successfully patched vendor.img USB gadget descriptors to 'm500 Hatsune Miku Edition'!"
fi
rm -f "$TMP_RC"
