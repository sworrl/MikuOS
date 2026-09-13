#!/usr/bin/env bash
# ==============================================================================
# MikuOS Pure AOSP 14 GSI Dynamic Super Builder
# ==============================================================================
# Integrates Pure AOSP 14 ARM64 Treble GSI with HiBy M500 Qualcomm hardware BSP
# and injects the MikuOS core application suite.
#
# Usage:
#   mikuos/build/build_mikuos_gsi.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIKUOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$MIKUOS_DIR/.." && pwd)"
FW_DIR="$REPO_DIR/m500-system-archive/firmware/extracted_1.00"
GSI_DIR="$MIKUOS_DIR/gsi"
OUT_DIR="$MIKUOS_DIR/out"
PARTITION_TOOLS="$REPO_DIR/m500-system-archive/tools/partition_tools"
LPMAKE="$PARTITION_TOOLS/lpmake"
SIMG2IMG="$PARTITION_TOOLS/simg2img"

mkdir -p "$OUT_DIR"

GSI_SRC="$GSI_DIR/aosp-14-vanilla.img"
if [ ! -f "$GSI_SRC" ]; then
    echo "ERROR: GSI source image not found at $GSI_SRC" >&2
    exit 1
fi

echo "=========================================================="
echo "    Building MikuOS Pure AOSP 14 System (HiBy M500)       "
echo "=========================================================="

echo "[1/5] Compiling MikuOS Core Applications..."
cd "$REPO_DIR/miku-player-kotlin"
./gradlew assembleRelease

latest_apk() { ls -1t $1 2>/dev/null | head -n1; }
LAUNCHER_APK="$(latest_apk "$REPO_DIR/miku-player-kotlin/mikuos-launcher/build/outputs/apk/release/*.apk")"
MUSIC_APK="$(latest_apk "$REPO_DIR/miku-player-kotlin/app/build/outputs/apk/release/*.apk")"
SETTINGS_APK="$(latest_apk "$REPO_DIR/miku-player-kotlin/mikuos-settings/build/outputs/apk/release/*.apk")"
SYSTEMUI_APK="$(latest_apk "$REPO_DIR/miku-player-kotlin/mikuos-systemui/build/outputs/apk/release/*.apk")"
HW_SETTINGS_APK="$(latest_apk "$REPO_DIR/miku-player-kotlin/hardware-settings/build/outputs/apk/release/*.apk")"

echo "[2/5] Preparing GSI system.img..."
WORK_SYS="$OUT_DIR/gsi_system.img"
cp "$GSI_SRC" "$WORK_SYS"

# Convert sparse to raw if necessary
if file "$WORK_SYS" | grep -q "Android sparse image"; then
    echo "  -> Converting sparse GSI image to raw ext4..."
    "$SIMG2IMG" "$WORK_SYS" "$WORK_SYS.raw"
    mv "$WORK_SYS.raw" "$WORK_SYS"
fi

# Expand system partition by 256MB to provide headroom for MikuOS suite
e2fsck -fy "$WORK_SYS" >/dev/null 2>&1 || true
resize2fs "$WORK_SYS" 2500M
e2fsck -fy "$WORK_SYS" >/dev/null 2>&1 || true

label() { debugfs -w -R "ea_set $2 security.selinux $3\\000" "$1" >/dev/null 2>&1; }

echo "[3/5] Injecting MikuOS Suite into AOSP GSI system.img..."

inject_app() {
    local apk="$1" name="$2"
    [ -f "$apk" ] || { echo "ERROR: Missing APK $apk" >&2; exit 1; }
    echo "  -> Injecting $name into system/app/$name/"
    debugfs -w -R "mkdir system/app/$name" "$WORK_SYS" 2>/dev/null || true
    debugfs -w -R "set_inode_field system/app/$name mode 040755" "$WORK_SYS" 2>/dev/null || true
    debugfs -w -R "write $apk system/app/$name/$name.apk" "$WORK_SYS" 2>/dev/null || true
    debugfs -w -R "set_inode_field system/app/$name/$name.apk mode 0100644" "$WORK_SYS" 2>/dev/null || true
    label "$WORK_SYS" "system/app/$name" "u:object_r:system_file:s0"
    label "$WORK_SYS" "system/app/$name/$name.apk" "u:object_r:system_file:s0"
}

inject_app "$LAUNCHER_APK" "MikuLauncher"
inject_app "$MUSIC_APK" "MikuMusic"
inject_app "$SETTINGS_APK" "MikuSettings"
inject_app "$SYSTEMUI_APK" "MikuSystemUI"
inject_app "$HW_SETTINGS_APK" "M500HardwareSettings"

# Inject Privapp & Default Permissions
PERMS_XML="$MIKUOS_DIR/build/permissions/privapp-permissions-mikuos.xml"
DEF_PERMS_XML="$MIKUOS_DIR/build/permissions/default-permissions-mikuos.xml"
if [ -f "$PERMS_XML" ]; then
    debugfs -w -R "write $PERMS_XML system/etc/permissions/privapp-permissions-mikuos.xml" "$WORK_SYS" 2>/dev/null || true
    debugfs -w -R "set_inode_field system/etc/permissions/privapp-permissions-mikuos.xml mode 0100644" "$WORK_SYS" 2>/dev/null || true
    label "$WORK_SYS" "system/etc/permissions/privapp-permissions-mikuos.xml" "u:object_r:system_file:s0"
fi
if [ -f "$DEF_PERMS_XML" ]; then
    debugfs -w -R "mkdir system/etc/default-permissions" "$WORK_SYS" 2>/dev/null || true
    debugfs -w -R "set_inode_field system/etc/default-permissions mode 040755" "$WORK_SYS" 2>/dev/null || true
    debugfs -w -R "write $DEF_PERMS_XML system/etc/default-permissions/default-permissions-mikuos.xml" "$WORK_SYS" 2>/dev/null || true
    debugfs -w -R "set_inode_field system/etc/default-permissions/default-permissions-mikuos.xml mode 0100644" "$WORK_SYS" 2>/dev/null || true
    label "$WORK_SYS" "system/etc/default-permissions" "u:object_r:system_file:s0"
    label "$WORK_SYS" "system/etc/default-permissions/default-permissions-mikuos.xml" "u:object_r:system_file:s0"
fi

# Pre-authorize host ADB key so adb is immediately authorized on first boot
HOST_ADB_KEY="$HOME/.android/adbkey.pub"
if [ -f "$HOST_ADB_KEY" ]; then
    echo "  -> Pre-authorizing host ADB key ($HOST_ADB_KEY)..."
    debugfs -w -R "mkdir system/etc/security" "$WORK_SYS" 2>/dev/null || true
    debugfs -w -R "set_inode_field system/etc/security mode 040755" "$WORK_SYS" 2>/dev/null || true
    debugfs -w -R "write $HOST_ADB_KEY system/etc/security/adb_keys" "$WORK_SYS" 2>/dev/null || true
    debugfs -w -R "set_inode_field system/etc/security/adb_keys mode 0100644" "$WORK_SYS" 2>/dev/null || true
    label "$WORK_SYS" "system/etc/security" "u:object_r:system_file:s0"
    label "$WORK_SYS" "system/etc/security/adb_keys" "u:object_r:adb_keys_file:s0"
fi

MIKUOS_VERSION="${MIKUOS_VERSION:-0.1.0-gsi}"
DEVICE_IDENTITY="m500_mikuOS-v${MIKUOS_VERSION}"

TMP_PROP="$(mktemp)"
debugfs -R "cat system/build.prop" "$WORK_SYS" > "$TMP_PROP" 2>/dev/null || true

sed -i "s/^ro.product.model=.*/ro.product.model=${DEVICE_IDENTITY}/" "$TMP_PROP"
sed -i "s/^ro.product.system.model=.*/ro.product.system.model=${DEVICE_IDENTITY}/" "$TMP_PROP"
sed -i "s/^ro.product.name=.*/ro.product.name=m500_mikuOS/" "$TMP_PROP"
sed -i "s/^ro.product.system.name=.*/ro.product.system.name=m500_mikuOS/" "$TMP_PROP"
sed -i "s/^ro.product.device=.*/ro.product.device=m500_mikuOS/" "$TMP_PROP"
sed -i "s/^ro.product.system.device=.*/ro.product.system.device=m500_mikuOS/" "$TMP_PROP"
sed -i "s/^ro.build.display.id=.*/ro.build.display.id=${DEVICE_IDENTITY}/" "$TMP_PROP"
sed -i "s/^ro.build.version.incremental=.*/ro.build.version.incremental=${DEVICE_IDENTITY}/" "$TMP_PROP"

cat << EOF >> "$TMP_PROP"

# ========================================================
# MikuOS AOSP 14 Identity & Telemetry Configuration
# ========================================================
ro.product.model=${DEVICE_IDENTITY}
ro.product.system.model=${DEVICE_IDENTITY}
ro.product.name=m500_mikuOS
ro.product.system.name=m500_mikuOS
ro.product.device=m500_mikuOS
ro.product.system.device=m500_mikuOS
ro.build.product=m500_mikuOS
ro.build.display.id=${DEVICE_IDENTITY}
ro.build.version.incremental=${DEVICE_IDENTITY}
ro.build.id=m500_mikuOS
ro.mikuos.version=${MIKUOS_VERSION}
ro.mikuos.edition=Hatsune Miku Cyberpunk DAP
bluetooth.device.default_name=${DEVICE_IDENTITY}
ro.bluetooth.name=${DEVICE_IDENTITY}
persist.sys.device_name=${DEVICE_IDENTITY}
persist.vendor.usb.product_string=${DEVICE_IDENTITY}
vendor.usb.product_string=${DEVICE_IDENTITY}
ro.usb.product_string=${DEVICE_IDENTITY}

# System & Permission Stability Fallbacks
ro.control_privapp_permissions=log
persist.service.adb.enable=1
persist.service.debuggable=1
ro.debuggable=1
ro.adb.secure=0

# Audio & DAC Direct Bypass routing
persist.audio.offload.pbuffer.size=256
audio.offload.buffer.size.kb=64
audio.offload.gapless.enabled=true
persist.sys.locale=en-US
EOF

debugfs -w -R "rm system/build.prop" "$WORK_SYS" 2>/dev/null || true
debugfs -w -R "write $TMP_PROP system/build.prop" "$WORK_SYS" 2>/dev/null || true
debugfs -w -R "set_inode_field system/build.prop mode 0100644" "$WORK_SYS" 2>/dev/null || true
label "$WORK_SYS" "system/build.prop" "u:object_r:system_file:s0"
rm -f "$TMP_PROP"

# Shrink system.img to minimal ext4 size to conserve super partition space
e2fsck -fy "$WORK_SYS" >/dev/null 2>&1 || true
resize2fs -M "$WORK_SYS"
e2fsck -fy "$WORK_SYS" >/dev/null 2>&1 || true

echo "[4/5] Preparing Qualcomm Hardware BSP & Clean Treble Partitions..."
WORK_VEN="$OUT_DIR/gsi_vendor.img"
WORK_PROD="$OUT_DIR/gsi_product.img"
WORK_EXT="$OUT_DIR/gsi_system_ext.img"

cp "$FW_DIR/vendor.img" "$WORK_VEN"

# Create clean, minimal ext4 partitions for product and system_ext so OEM framework
# classes never clash with the pure AOSP GSI bootclasspath
create_clean_partition() {
    local img="$1" mount_point="$2"
    rm -f "$img"
    truncate -s 4M "$img"
    mke2fs -t ext4 -b 4096 -I 256 -M "$mount_point" -O ^has_journal "$img" >/dev/null 2>&1
    e2fsck -fy "$img" >/dev/null 2>&1 || true
}

create_clean_partition "$WORK_PROD" "/product"
create_clean_partition "$WORK_EXT" "/system_ext"

e2fsck -fy "$WORK_VEN" >/dev/null 2>&1 || true
resize2fs -M "$WORK_VEN" 2>/dev/null || true
e2fsck -fy "$WORK_VEN" >/dev/null 2>&1 || true

echo "[5/5] Synthesizing Dynamic super.img Container..."
GSI_SUPER="$OUT_DIR/mikuos_gsi_super.img"

SYS_SZ="$(stat -c%s "$WORK_SYS")"
VEN_SZ="$(stat -c%s "$WORK_VEN")"
PROD_SZ="$(stat -c%s "$WORK_PROD")"
EXT_SZ="$(stat -c%s "$WORK_EXT")"
ODM_SZ="$(stat -c%s "$FW_DIR/odm.img")"
SYS_DLKM_SZ="$(stat -c%s "$FW_DIR/system_dlkm.img")"
VEN_DLKM_SZ="$(stat -c%s "$FW_DIR/vendor_dlkm.img")"

"$LPMAKE" \
  --metadata-size 65536 \
  --super-name super \
  --metadata-slots 2 \
  --device super:4831838208 \
  --group qti_dynamic_partitions_a:4831838208 \
  --group qti_dynamic_partitions_b:4831838208 \
  --partition system_a:readonly:${SYS_SZ}:qti_dynamic_partitions_a \
  --image system_a="$WORK_SYS" \
  --partition system_b:readonly:0:qti_dynamic_partitions_b \
  --partition vendor_a:readonly:${VEN_SZ}:qti_dynamic_partitions_a \
  --image vendor_a="$WORK_VEN" \
  --partition vendor_b:readonly:0:qti_dynamic_partitions_b \
  --partition product_a:readonly:${PROD_SZ}:qti_dynamic_partitions_a \
  --image product_a="$WORK_PROD" \
  --partition product_b:readonly:0:qti_dynamic_partitions_b \
  --partition system_ext_a:readonly:${EXT_SZ}:qti_dynamic_partitions_a \
  --image system_ext_a="$WORK_EXT" \
  --partition system_ext_b:readonly:0:qti_dynamic_partitions_b \
  --partition odm_a:readonly:${ODM_SZ}:qti_dynamic_partitions_a \
  --image odm_a="$FW_DIR/odm.img" \
  --partition odm_b:readonly:0:qti_dynamic_partitions_b \
  --partition system_dlkm_a:readonly:${SYS_DLKM_SZ}:qti_dynamic_partitions_a \
  --image system_dlkm_a="$FW_DIR/system_dlkm.img" \
  --partition system_dlkm_b:readonly:0:qti_dynamic_partitions_b \
  --partition vendor_dlkm_a:readonly:${VEN_DLKM_SZ}:qti_dynamic_partitions_a \
  --image vendor_dlkm_a="$FW_DIR/vendor_dlkm.img" \
  --partition vendor_dlkm_b:readonly:0:qti_dynamic_partitions_b \
  --sparse \
  --output "$GSI_SUPER"

echo "=========================================================="
echo "  MikuOS GSI super.img built: $GSI_SUPER"
echo "=========================================================="
