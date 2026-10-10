#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIKUOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$MIKUOS_DIR/.." && pwd)"
FW_DIR="$REPO_DIR/m500-system-archive/firmware/extracted_1.00"
PARTITION_TOOLS="$REPO_DIR/m500-system-archive/tools/partition_tools"
LPMAKE="$PARTITION_TOOLS/lpmake"
OUTPUT_DIR="$MIKUOS_DIR/out"
OUTPUT_SUPER="$OUTPUT_DIR/mikuos_system_bundle.img"

# Platform re-key: replace the public AOSP test keys with the MikuOS custom key
# set (see resign_system.sh). REKEY=0 builds the legacy AOSP-test-signed image.
# REKEY_NOOP=1 (with REKEY=1) is a boot-hang bisection build: runs the full
# rekey mount mechanics (unshare_blocks, rw loop mount, sync/umount) but
# re-signs NOTHING and leaves mac_permissions untouched, so the content is
# identical to REKEY=0. Boots -> hang is re-sign content; hangs -> the mount
# mechanics corrupt the image.
REKEY="${REKEY:-1}"
REKEY_NOOP="${REKEY_NOOP:-0}"
# BUMP THIS ON ANY CHANGE TO A SYSTEM APP IN THE IMAGE.
#
# DEVICE_IDENTITY below becomes ro.build.version.incremental, which is part of
# ro.build.fingerprint. PackageManager only invalidates its parsed-package cache
# (/data/system/package_cache) and fully re-scans the system partitions when that
# fingerprint CHANGES. Rebuild the image with the same version and keep /data, and PMS
# trusts the cache: the new APK's CODE runs (it is loaded from the file at runtime) while
# everything derived from its MANIFEST stays as it was parsed months ago.
#
# That cost 2026-10-09. The FM tuner's new ACCESS_WIFI_STATE was present in the APK on the
# device, byte-identical to the build output, and `dumpsys package com.caf.fmradio` still
# listed the OLD five permissions and never granted it, through two reboots. The permission
# the vendor jar needs was simply not there as far as PMS was concerned.
MIKUOS_VERSION="${MIKUOS_VERSION:-0.3.0}"
DEVICE_IDENTITY="m500_mikuOS-v${MIKUOS_VERSION}"
# MIKUOS_RELEASE=1 builds the image users get: adb needs on-device approval and is not forced on,
# no adb over Wi-Fi, no pre-authorized host key, no root seed, no dev Wi-Fi, ro.debuggable=0, and
# ro.miku.release=1 so the apps (sysbridge) apply their release defaults. 0 (default) is the dev
# build, unchanged. See mikuos/docs/security-plan.md.
MIKUOS_RELEASE="${MIKUOS_RELEASE:-0}"
[ "$MIKUOS_RELEASE" = "1" ] && echo "  (MIKUOS_RELEASE=1: release hardening on)"
RESIGN_SH="$SCRIPT_DIR/resign_system.sh"
APKSIGNER="${APKSIGNER:-$(ls ~/Android/Sdk/build-tools/*/apksigner 2>/dev/null | tail -1)}"

# debugfs 'write' creates files UNLABELED. Under enforcing SELinux an unlabeled
# /system app can't be read by its own process (resources NPE / crash loop) and
# init won't process an unlabeled .rc — so every injected file must be given its
# SELinux context. label <img> <path-in-img> <context>
label() { debugfs -w -R "ea_set $2 security.selinux $3\\000" "$1" >/dev/null 2>&1; }
# debugfs exits 0 even when a path is missing, so presence is read from its output.
img_has() { ! debugfs -R "stat $2" "$1" 2>&1 | grep -q "not found"; }
# rm_tree removes a directory recursively with debugfs, which has no rm -r.
rm_tree() {
    local img="$1" dir="$2" line name mode
    debugfs -R "ls -p $dir" "$img" 2>/dev/null | while IFS=/ read -r _ _ mode _ _ name _; do
        [ -z "$name" ] || [ "$name" = "." ] || [ "$name" = ".." ] && continue
        if [ "${mode:0:2}" = "04" ]; then rm_tree "$img" "$dir/$name"
        else debugfs -w -R "rm $dir/$name" "$img" >/dev/null 2>&1 || true; fi
    done
    debugfs -w -R "rmdir $dir" "$img" >/dev/null 2>&1 || true
}

# CRITICAL: debugfs 'write' REFUSES to overwrite an existing file ("Ext2 file
# already exists") and the callers pipe that error to /dev/null, so replacing a
# stock file (build.prop, SystemUI.apk, bootanimation) SILENTLY no-ops — the
# stock file survives untouched. For any path that already exists in the image,
# rm first, then write. dfput <img> <src> <path-in-img>  (label separately).
dfput() {
    debugfs -w -R "rm $3" "$1" >/dev/null 2>&1
    debugfs -w -R "write $2 $3" "$1" 2>&1 | grep -qi "already exists" \
        && { echo "  !! dfput still failed to overwrite: $3 in $1" >&2; return 1; }
    debugfs -w -R "set_inode_field $3 mode 0100644" "$1" >/dev/null 2>&1
    return 0
}

mkdir -p "$OUTPUT_DIR"

echo "=========================================================="
echo "          Building MikuOS Production super.img            "
echo "=========================================================="

echo "[1/6] Compiling MikuOS Core System APKs..."
cd "$REPO_DIR/miku-player-kotlin"
# SKIP_GRADLE=1 reuses the APKs already in build/outputs (e.g. while agents are mid-edit on a
# module, or for an image-only rebuild). :fmradio is part of the set — Miku FM only works when
# BUNDLED in the image (its JNI needs the shared linker namespace), so it must be fresh here.
if [ "${SKIP_GRADLE:-0}" = "1" ]; then
    echo "  (SKIP_GRADLE=1: using existing build/outputs APKs)"
else
    ./gradlew :mikuos-launcher:assembleRelease :app:assembleRelease :mikuos-settings:assembleRelease :mikuos-systemui:assembleRelease :fmradio:assembleRelease :hardware-settings:assembleRelease :miku-sysbridge:assembleRelease
    # The MikuOS replacements for stock apps. Built separately and allowed to fail: each one's
    # stock counterpart is only removed further down when its replacement made it into the image.
    ./gradlew :mikuos-tools:assembleRelease || echo "  !! mikuos-tools did not build; stock Clock/Calculator/Calendar stay"
    ./gradlew :mikuos-media:assembleRelease || echo "  !! mikuos-media did not build; stock Camera/Gallery/Recorder stay"
    ./gradlew :mikuos-update:assembleRelease || echo "  !! mikuos-update did not build; no OTA app updates in this image"
    ./gradlew :mikuos-riot:assembleRelease || echo "  !! mikuos-riot did not build; no Riot mode in this image"
    ./gradlew :mikuos-wheel:assembleRelease || echo "  !! mikuos-wheel did not build; no MikuPod in this image"
fi

# Resolve versioned APK names (e.g. MikuOS_Launcher-v0.1.0.apk); newest wins.
latest_apk() { ls -1t $1 2>/dev/null | head -n1; }
SETTINGS_APK="$(latest_apk "$REPO_DIR/miku-player-kotlin/mikuos-settings/build/outputs/apk/release/MikuOS_Settings-v*.apk")"
LAUNCHER_APK="$(latest_apk "$REPO_DIR/miku-player-kotlin/mikuos-launcher/build/outputs/apk/release/MikuOS_Launcher-v*.apk")"
MUSIC_APK="$(latest_apk "$REPO_DIR/miku-player-kotlin/app/build/outputs/apk/release/MikuMusic-v*.apk")"
SYSTEMUI_APK="$(latest_apk "$REPO_DIR/miku-player-kotlin/mikuos-systemui/build/outputs/apk/release/MikuOS_SystemUI-v*.apk")"
# Miku FM tuner — MUST keep applicationId com.caf.fmradio + platform sig to get the
# SELinux vendor_fm_app domain (only path to /dev/radio0). Replaces stock FM2.
FMRADIO_APK="$(latest_apk "$REPO_DIR/miku-player-kotlin/fmradio/build/outputs/apk/release/FMRadio-com.caf.fmradio-v*.apk")"
HARDWARE_APK="$(latest_apk "$REPO_DIR/miku-player-kotlin/hardware-settings/build/outputs/apk/release/M500HardwareSettings.apk")"
SYSBRIDGE_APK="$(latest_apk "$REPO_DIR/miku-player-kotlin/miku-sysbridge/build/outputs/apk/release/MikuSysBridge.apk")"
TOOLS_APK="$(latest_apk "$REPO_DIR/miku-player-kotlin/mikuos-tools/build/outputs/apk/release/MikuTools*.apk")"
MEDIA_APK="$(latest_apk "$REPO_DIR/miku-player-kotlin/mikuos-media/build/outputs/apk/release/MikuMedia*.apk")"
UPDATE_APK="$(latest_apk "$REPO_DIR/miku-player-kotlin/mikuos-update/build/outputs/apk/release/MikuUpdate.apk")"
RIOT_APK="$(latest_apk "$REPO_DIR/miku-player-kotlin/mikuos-riot/build/outputs/apk/release/MikuRiot.apk")"
WHEEL_APK="$(latest_apk "$REPO_DIR/miku-player-kotlin/mikuos-wheel/build/outputs/apk/release/MikuWheel.apk")"
if [ -z "$SYSTEMUI_APK" ]; then
    SYSTEMUI_APK="$(latest_apk "$REPO_DIR/miku-player-kotlin/mikuos-systemui/build/outputs/apk/release/*.apk")"
fi
# Interim builds: <NAME>_APK_OVERRIDE=<path> uses that APK instead of the build output (e.g. the
# copy pulled off the device, to ship one module fresh while the others are mid-edit), and
# MIKU_NO_REPLACEMENTS=1 leaves MikuTools/MikuMedia out, which also keeps the stock apps they
# replace.
for _v in SETTINGS_APK LAUNCHER_APK MUSIC_APK SYSTEMUI_APK FMRADIO_APK HARDWARE_APK SYSBRIDGE_APK UPDATE_APK RIOT_APK WHEEL_APK; do
    _o="${_v}_OVERRIDE"
    if [ -n "${!_o:-}" ]; then
        [ -f "${!_o}" ] || { echo "!! $_o=${!_o} does not exist"; exit 1; }
        printf -v "$_v" '%s' "${!_o}"
        echo "  (override: $_v = ${!_o})"
    fi
done
if [ "${MIKU_NO_REPLACEMENTS:-0}" = "1" ]; then TOOLS_APK=""; MEDIA_APK=""; fi
PERMISSIONS_XML="$MIKUOS_DIR/build/permissions/privapp-permissions-mikuos.xml"
DEFAULT_PERMS_XML="$MIKUOS_DIR/build/permissions/default-permissions-mikuos.xml"

# Platform-sign the injected MikuOS apps with the custom key (on copies, so the
# dev build outputs stay on their legacy keys for piecemeal adb install).
if [ "$REKEY" = "1" ] && [ "$REKEY_NOOP" != "1" ]; then
    echo "[1b] Platform-signing MikuOS apps with the custom MikuOS key..."
    SIGN_TMP="$(mktemp -d)"
    for _v in SETTINGS_APK LAUNCHER_APK MUSIC_APK SYSTEMUI_APK; do
        _src="${!_v}"
        [ -f "$_src" ] || { echo "  !! missing $_v ($_src)"; exit 1; }
        _dst="$SIGN_TMP/$(basename "$_src")"
        cp "$_src" "$_dst"
        APKSIGNER="$APKSIGNER" APPLY=1 "$RESIGN_SH" --platform-apk "$_dst" >/dev/null
        printf -v "$_v" '%s' "$_dst"
    done
fi

echo "[2/6] Preparing working partition images..."
cp "$FW_DIR/system_ext.img" "$OUTPUT_DIR/system_ext.img"
cp "$FW_DIR/system.img" "$OUTPUT_DIR/system.img"
cp "$FW_DIR/product.img" "$OUTPUT_DIR/product.img"
cp "$FW_DIR/vendor.img" "$OUTPUT_DIR/vendor.img"

# ============================================================================
# CRITICAL SEQUENCE: stock images use ext4 shared_blocks (block dedup).
# Writing into a shared-blocks fs with debugfs CORRUPTS every file that shares
# physical blocks. Root cause of boot crashes (garbage ClassStatus in
# NQNfcNci.odex / IntentResolver.odex).
#
# CORRECT ORDER (unshare needs free space to clone blocks):
# 1. Resize filesystems to provide working space (~3500M / 1000M / 500M)
# 2. Un-share all blocks so each file owns private copies
# 3. Then do debugfs injections
# ============================================================================
echo "  [1] Expanding filesystems for unshare_blocks working space..."
e2fsck -fy "$OUTPUT_DIR/system.img" || true
resize2fs "$OUTPUT_DIR/system.img" 3500M

e2fsck -fy "$OUTPUT_DIR/system_ext.img" || true
resize2fs "$OUTPUT_DIR/system_ext.img" 1000M

e2fsck -fy "$OUTPUT_DIR/product.img" || true
resize2fs "$OUTPUT_DIR/product.img" 500M

truncate -s +160M "$OUTPUT_DIR/vendor.img"
e2fsck -fy "$OUTPUT_DIR/vendor.img" || true
resize2fs "$OUTPUT_DIR/vendor.img" || true

echo "  [2] Un-sharing ext4 shared_blocks from stock images..."
for _img in system system_ext product vendor; do
    echo "    -> un-sharing $_img.img"
    e2fsck -fy -E unshare_blocks "$OUTPUT_DIR/$_img.img" || { echo "  !! unshare_blocks failed: $_img"; exit 1; }
done

# Notification sounds: HiBy's 1.20 services.jar stubs NotificationManagerService.playSound() to
# return false, so no notification ever makes a sound. patch_services_notif_sound.py puts back the
# AOSP body HiBy restored in 1.30 (only that method; the 1.30 jar itself is not usable). The
# prebuilt services.odex/vdex/art were compiled from the stock dex and would be rejected, so they
# are removed and odrefresh compiles services.jar into /data on first boot.
SVC_TMP="$(mktemp -d)"
debugfs -R "dump system/framework/services.jar $SVC_TMP/stock.jar" "$OUTPUT_DIR/system.img" 2>/dev/null
python3 -I "$SCRIPT_DIR/patch_services_notif_sound.py" "$SVC_TMP/stock.jar" "$SVC_TMP/services.jar" \
    || { echo "  !! services.jar notification sound patch refused"; exit 1; }
dfput "$OUTPUT_DIR/system.img" "$SVC_TMP/services.jar" system/framework/services.jar \
    || { echo "  !! could not write the patched services.jar"; exit 1; }
label "$OUTPUT_DIR/system.img" system/framework/services.jar u:object_r:system_file:s0
for _f in services.odex services.vdex services.art; do
    debugfs -w -R "rm system/framework/oat/arm64/$_f" "$OUTPUT_DIR/system.img" >/dev/null 2>&1 || true
done
debugfs -R "dump system/framework/services.jar $SVC_TMP/check.jar" "$OUTPUT_DIR/system.img" 2>/dev/null
cmp -s "$SVC_TMP/check.jar" "$SVC_TMP/services.jar" \
    || { echo "  !! patched services.jar did not land in system.img"; exit 1; }
img_has "$OUTPUT_DIR/system.img" system/framework/oat/arm64/services.odex \
    && { echo "  !! stale services.odex still in system.img"; exit 1; }
rm -rf "$SVC_TMP"

echo "  [3] vendor_dlkm: the Si4705 driver hands userspace whole RDS groups and the stereo pilot..."
# HiBy's radio-si4705-common.ko reads all four RDS blocks from the chip and copies only the
# first two to the reader, so the station name and RadioText (blocks C/D) never leave the
# kernel; and it reads the chip's stereo pilot/blend and throws it away. patch_si4705_rds.py
# fixes both (5 instructions, hash-checked against stock); see its docstring. Same shared_blocks rule as above: unshare before debugfs writes.
cp "$FW_DIR/vendor_dlkm.img" "$OUTPUT_DIR/vendor_dlkm.img"
truncate -s +16M "$OUTPUT_DIR/vendor_dlkm.img"
e2fsck -fy "$OUTPUT_DIR/vendor_dlkm.img" >/dev/null || true
resize2fs "$OUTPUT_DIR/vendor_dlkm.img" >/dev/null 2>&1 || true
e2fsck -fy -E unshare_blocks "$OUTPUT_DIR/vendor_dlkm.img" >/dev/null || { echo "  !! unshare_blocks failed: vendor_dlkm"; exit 1; }
SI4705_TMP="$(mktemp -d)"
debugfs -R "dump /lib/modules/radio-si4705-common.ko $SI4705_TMP/stock.ko" "$OUTPUT_DIR/vendor_dlkm.img" 2>/dev/null
# MIKU_FM_UNLOCK=1 (default) also widens the driver's band table to 50-250 MHz so the chip, not
# the driver, decides what it can tune; MIKU_FM_STEREO=1 (default) lowers the chip's stereo blend
# mono thresholds. Either =0 leaves that part stock.
MIKU_FM_UNLOCK="${MIKU_FM_UNLOCK:-1}" MIKU_FM_STEREO="${MIKU_FM_STEREO:-1}" python3 -I "$SCRIPT_DIR/patch_si4705_rds.py" "$SI4705_TMP/stock.ko" "$SI4705_TMP/radio-si4705-common.ko" \
    || { echo "  !! si4705 RDS patch refused"; exit 1; }
dfput "$OUTPUT_DIR/vendor_dlkm.img" "$SI4705_TMP/radio-si4705-common.ko" /lib/modules/radio-si4705-common.ko \
    || { echo "  !! could not write the patched si4705 module"; exit 1; }
label "$OUTPUT_DIR/vendor_dlkm.img" /lib/modules/radio-si4705-common.ko u:object_r:vendor_file:s0
debugfs -R "dump /lib/modules/radio-si4705-common.ko $SI4705_TMP/check.ko" "$OUTPUT_DIR/vendor_dlkm.img" 2>/dev/null
cmp -s "$SI4705_TMP/check.ko" "$SI4705_TMP/radio-si4705-common.ko" \
    || { echo "  !! patched si4705 module did not land in vendor_dlkm"; exit 1; }
rm -rf "$SI4705_TMP"
# HiBy 1.30 parts: files the 1.20 to 1.30 OTA fixed that drop into the 1.20 image unchanged.
# adopt_hiby130.py refuses anything but the exact 1.20 file and HiBy's exact 1.30 file, and for
# kernel modules re-checks vermagic and every symbol CRC against the 1.20 module it replaces.
# The parts are local, like the stock images: m500-system-archive/firmware/hiby_1.30_parts/
# (sha256 list in SHA256SUMS.txt there). See mikuos/docs/hiby-firmware-history.md.
#   cs43198_dlkm.ko: NOS mask fixed (supersedes patch_cs43198_nos.py) and the balanced DAC is
#     written whatever the output is, so filter/DRE/rate changes made on 3.5 mm reach 4.4 mm.
#   cw2015_battery.ko: the fuel gauge sees charging from mp2731-charger (1.20 hard-wires it off),
#     smooths the percentage and stops logging every 2 s.
HIBY130_DIR="${HIBY130_DIR:-$REPO_DIR/m500-system-archive/firmware/hiby_1.30_parts}"
# Without the 1.30 parts (anyone who only has the stock 1.20 images), fall back to patching the
# 1.20 codec driver for NOS and leave the gauge and health HAL stock.
if [ -d "$HIBY130_DIR" ]; then
for _ko in cs43198_dlkm.ko cw2015_battery.ko; do
    _T="$(mktemp -d)"
    debugfs -R "dump /lib/modules/$_ko $_T/cur.ko" "$OUTPUT_DIR/vendor_dlkm.img" 2>/dev/null
    python3 -I "$SCRIPT_DIR/adopt_hiby130.py" "$_ko" "$_T/cur.ko" "$HIBY130_DIR/$_ko" "$_T/$_ko" \
        || { echo "  !! $_ko: HiBy 1.30 module refused"; exit 1; }
    dfput "$OUTPUT_DIR/vendor_dlkm.img" "$_T/$_ko" "/lib/modules/$_ko" \
        || { echo "  !! could not write $_ko"; exit 1; }
    label "$OUTPUT_DIR/vendor_dlkm.img" "/lib/modules/$_ko" u:object_r:vendor_file:s0
    debugfs -R "dump /lib/modules/$_ko $_T/check.ko" "$OUTPUT_DIR/vendor_dlkm.img" 2>/dev/null
    cmp -s "$_T/check.ko" "$_T/$_ko" || { echo "  !! $_ko did not land in vendor_dlkm"; exit 1; }
    rm -rf "$_T"
done
else
    echo "  -> no HiBy 1.30 parts at $HIBY130_DIR: patching the 1.20 codec driver for NOS only"
    _T="$(mktemp -d)"
    debugfs -R "dump /lib/modules/cs43198_dlkm.ko $_T/stock.ko" "$OUTPUT_DIR/vendor_dlkm.img" 2>/dev/null
    python3 -I "$SCRIPT_DIR/patch_cs43198_nos.py" "$_T/stock.ko" "$_T/cs43198_dlkm.ko" \
        || { echo "  !! cs43198 NOS patch refused"; exit 1; }
    dfput "$OUTPUT_DIR/vendor_dlkm.img" "$_T/cs43198_dlkm.ko" /lib/modules/cs43198_dlkm.ko \
        || { echo "  !! could not write the patched cs43198 module"; exit 1; }
    label "$OUTPUT_DIR/vendor_dlkm.img" /lib/modules/cs43198_dlkm.ko u:object_r:vendor_file:s0
    rm -rf "$_T"
fi
e2fsck -fy "$OUTPUT_DIR/vendor_dlkm.img" >/dev/null || { echo "  !! vendor_dlkm fsck failed"; exit 1; }

# Health HAL from 1.30: 1.20 looks for mp2731-charger once at start and, if the charger driver has
# not registered yet, falls back to sw7203-charger paths that do not exist on the M500 until the
# HAL restarts. 1.30 waits up to 2 s for it. Same libraries and imports as 1.20.
if [ -d "$HIBY130_DIR" ]; then
_T="$(mktemp -d)"
_HAL=bin/hw/android.hardware.health-service.qti
debugfs -R "dump $_HAL $_T/cur" "$OUTPUT_DIR/vendor.img" 2>/dev/null
python3 -I "$SCRIPT_DIR/adopt_hiby130.py" android.hardware.health-service.qti "$_T/cur" \
    "$HIBY130_DIR/android.hardware.health-service.qti" "$_T/hal" \
    || { echo "  !! health HAL: HiBy 1.30 build refused"; exit 1; }
dfput "$OUTPUT_DIR/vendor.img" "$_T/hal" "$_HAL" || { echo "  !! could not write the health HAL"; exit 1; }
debugfs -w -R "set_inode_field $_HAL mode 0100755" "$OUTPUT_DIR/vendor.img" >/dev/null 2>&1
debugfs -w -R "set_inode_field $_HAL gid 2000" "$OUTPUT_DIR/vendor.img" >/dev/null 2>&1
label "$OUTPUT_DIR/vendor.img" "$_HAL" u:object_r:hal_health_default_exec:s0
debugfs -R "dump $_HAL $_T/check" "$OUTPUT_DIR/vendor.img" 2>/dev/null
cmp -s "$_T/check" "$_T/hal" || { echo "  !! health HAL did not land in vendor.img"; exit 1; }
rm -rf "$_T"
fi

echo "[2b] Setting boot 'welcome' voice (trimmed to play immediately, not at ~9s)..."
# The stock bootanimation_<locale>.mp4 has the "Welcome to HiBy Music, the show
# starts now" voice buried ~8.3s into a 12.5s clip (long silent lead-in). We keep
# the voice (user-approved) but replace the audio track with the pre-trimmed
# voice-only clip at t=0, so it speaks right away. Per-locale voice mapping:
#   base .mp4 = Chinese, _en = English, _jp = Japanese, _cn = Chinese variant.
# (Gated by persist.sys.customanim.boot.sounds=1, set in build.prop.)
VOICE_DIR="$SCRIPT_DIR/boot_voice"
TMP_ANIM_DIR="$(mktemp -d)"
# MikuOS boot video (mikuos/art/splash/make_boot.py). Stock's shows HiBy's and the official Miku
# logos. Same format as stock: 720x1280, 30 fps, 12.5 s, H.264 Main.
BOOT_VIDEO="$MIKUOS_DIR/art/splash/bootanimation.mp4"
for pair in "bootanimation.mp4:welcome_voice.ogg" \
            "bootanimation_en.mp4:welcome_voice_en.ogg" \
            "bootanimation_jp.mp4:welcome_voice_jp.ogg" \
            "bootanimation_cn.mp4:welcome_voice_cn.ogg"; do
    anim="${pair%%:*}"; voice="${pair##*:}"
    if [ -s "$BOOT_VIDEO" ]; then
        cp "$BOOT_VIDEO" "$TMP_ANIM_DIR/$anim"
    else
        debugfs -R "dump media/$anim $TMP_ANIM_DIR/$anim" "$OUTPUT_DIR/vendor.img" 2>/dev/null || true
    fi
    [ -s "$TMP_ANIM_DIR/$anim" ] || continue
    if [ -f "$VOICE_DIR/$voice" ]; then
        # keep the original video, swap in the trimmed voice as the audio at t=0.
        # No -shortest: output keeps the full video length; voice plays up front,
        # silence for the remainder.
        ffmpeg -y -i "$TMP_ANIM_DIR/$anim" -i "$VOICE_DIR/$voice" \
            -map 0:v -map 1:a -c:v copy -c:a aac "$TMP_ANIM_DIR/new_$anim" 2>/dev/null || true
    elif [ -s "$BOOT_VIDEO" ]; then
        cp "$TMP_ANIM_DIR/$anim" "$TMP_ANIM_DIR/new_$anim"
    fi
    if [ -s "$TMP_ANIM_DIR/new_$anim" ]; then
        debugfs -w -R "rm media/$anim" "$OUTPUT_DIR/vendor.img" 2>/dev/null || true
        debugfs -w -R "write $TMP_ANIM_DIR/new_$anim media/$anim" "$OUTPUT_DIR/vendor.img" 2>/dev/null || true
        debugfs -w -R "set_inode_field media/$anim mode 0100644" "$OUTPUT_DIR/vendor.img" 2>/dev/null || true
        label "$OUTPUT_DIR/vendor.img" "media/$anim" "u:object_r:vendor_file:s0"
    fi
done
rm -rf "$TMP_ANIM_DIR"

echo "[3/6] Configuring system_ext.img..."

# Miku FM: replace the stock FM2.apk (com.caf.fmradio) with our cool Miku-styled FM
# tuner. Same package name + platform signature = same SELinux vendor_fm_app domain,
# so it keeps /dev/radio0 tuner access (which our com.miku.player build could never
# get). Drop the stale oat so ART recompiles our APK; keep app/FM2/lib (vendor FM JNI).
# Broadcast station catalogue: 47,826 US/CA/MX stations with transmitter coordinates, ERP,
# HAAT and call-sign dates, built by tools/radiodb from FCC public-record data. Injected as a
# data file rather than an APK asset so it can be refreshed without rebuilding the app, and so
# the launcher can read it too. Logos are deliberately NOT in here: they are trademarks and
# this image is published, so the device fetches and caches them per-device at runtime.
STATIONS_DB="$REPO_DIR/mikuos/data/stations.sqlite"
if [ -f "$STATIONS_DB" ]; then
    echo "  -> injecting station catalogue ($(( $(stat -c%s "$STATIONS_DB") / 1048576 )) MB)"
    debugfs -w -R "mkdir etc/miku" "$OUTPUT_DIR/system_ext.img" >/dev/null 2>&1 || true
    label "$OUTPUT_DIR/system_ext.img" "etc/miku" "u:object_r:system_file:s0"
    dfput "$OUTPUT_DIR/system_ext.img" "$STATIONS_DB" "etc/miku/stations.sqlite" \
        && label "$OUTPUT_DIR/system_ext.img" "etc/miku/stations.sqlite" "u:object_r:system_file:s0" \
        || echo "  !! station catalogue injection failed"
else
    echo "  -> no station catalogue at $STATIONS_DB (run tools/radiodb/fetch_sources.sh)"
fi

# ---------------------------------------------------------------------------------------------
# Android Auto (com.google.android.projection.gearhead), as a PRIVILEGED system app.
#
# It is not in AOSP and HiBy's media-player GMS set does not carry it, so "this is Android 14"
# does not get you Android Auto. Sideloading does not work either: since Android 10 the app
# refuses to run unless it is a privileged system app, which is the "must have been bundled with
# your OS" error. Hence here.
#
# SPLITS, NOT A MERGED APK. This ships as base + config.arm64_v8a + config.en + config.xxxhdpi,
# all signed by Google (SHA-1 a60bd681..., CN=Android, O=Google Inc., with a Play source stamp).
# Merging them into one universal APK would re-sign it, and GMS checks this package's signature,
# so the splits go in as a cluster directory exactly as Google signed them. PackageManager reads
# the `split` attribute inside each APK, not the filenames.
#
# The allowlist is GENERATED, never hand-written: tools/androidauto/prepare_android_auto.py
# intersects the APK's 82 requested permissions with the 313 this build's framework marks
# privileged, giving 22. check_privapp.py below then fails the BUILD if that is ever stale,
# because ro.control_privapp_permissions=enforce turns a missing entry into a device that does
# not boot rather than a warning.
AA_DIR="$REPO_DIR/mikuos/build/gapps_dl/x_androidauto/split"
AA_BASE="$AA_DIR/com.google.android.projection.gearhead.apk"
AA_PERMS="$MIKUOS_DIR/build/permissions/privapp-permissions-androidauto.xml"
if [ "${MIKUOS_ANDROID_AUTO:-1}" = "1" ] && [ -f "$AA_BASE" ] && [ -f "$AA_PERMS" ]; then
    echo "  -> injecting Android Auto ($(( $(stat -c%s "$AA_BASE") / 1048576 )) MB base + splits)"
    AA_FW="$(mktemp -d)"
    debugfs -R "dump system/framework/framework-res.apk $AA_FW/framework-res.apk" "$OUTPUT_DIR/system.img" 2>/dev/null
    python3 -I "$SCRIPT_DIR/check_privapp.py" /home/reaver/Android/Sdk/build-tools/35.0.0/aapt2 \
        "$AA_BASE" "$AA_FW/framework-res.apk" "$AA_PERMS" \
        || { echo "!! FATAL: Android Auto privapp allowlist incomplete. Regenerate it with"; \
             echo "   tools/androidauto/prepare_android_auto.py --apk \"$AA_BASE\" --system-img $OUTPUT_DIR/system.img"; \
             rm -rf "$AA_FW"; exit 1; }
    rm -rf "$AA_FW"
    rm_tree "$OUTPUT_DIR/system_ext.img" priv-app/AndroidAuto
    debugfs -w -R "mkdir priv-app/AndroidAuto" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true
    debugfs -w -R "set_inode_field priv-app/AndroidAuto mode 040755" "$OUTPUT_DIR/system_ext.img"
    label "$OUTPUT_DIR/system_ext.img" priv-app/AndroidAuto u:object_r:system_file:s0
    for aa_src in "$AA_DIR"/*.apk; do
        case "$(basename "$aa_src")" in
            com.google.android.projection.gearhead.apk) aa_dst="AndroidAuto.apk" ;;
            *) aa_dst="split_$(basename "$aa_src")" ;;
        esac
        dfput "$OUTPUT_DIR/system_ext.img" "$aa_src" "priv-app/AndroidAuto/$aa_dst" \
            || { echo "  !! could not write $aa_dst"; exit 1; }
        label "$OUTPUT_DIR/system_ext.img" "priv-app/AndroidAuto/$aa_dst" u:object_r:system_file:s0
    done
    debugfs -w -R "mkdir etc/permissions" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true
    debugfs -w -R "set_inode_field etc/permissions mode 040755" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true
    label "$OUTPUT_DIR/system_ext.img" etc/permissions u:object_r:system_file:s0
    dfput "$OUTPUT_DIR/system_ext.img" "$AA_PERMS" "etc/permissions/privapp-permissions-androidauto.xml" \
        && label "$OUTPUT_DIR/system_ext.img" "etc/permissions/privapp-permissions-androidauto.xml" u:object_r:system_file:s0 \
        || { echo "  !! Android Auto allowlist injection failed; refusing to ship the APK without it"; exit 1; }
else
    [ "${MIKUOS_ANDROID_AUTO:-1}" = "1" ] && echo "  -> no Android Auto bundle at $AA_DIR (skipping)"
fi

if [ -n "$FMRADIO_APK" ] && [ -f "$FMRADIO_APK" ]; then
    echo "  -> injecting Miku FM ($FMRADIO_APK) over stock FM2"
    debugfs -w -R "rm app/FM2/oat/arm64/FM2.odex" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true
    debugfs -w -R "rm app/FM2/oat/arm64/FM2.vdex" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true
    debugfs -w -R "rm app/FM2/oat/arm/FM2.odex" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true
    debugfs -w -R "rm app/FM2/oat/arm/FM2.vdex" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true
    dfput "$OUTPUT_DIR/system_ext.img" "$FMRADIO_APK" "app/FM2/FM2.apk" \
        && label "$OUTPUT_DIR/system_ext.img" "app/FM2/FM2.apk" "u:object_r:system_file:s0" \
        || echo "  !! FM2 (system_ext) replace failed (kept stock)"
    # There is ALSO a stock FM2 in system.img (system/app/FM2) — Android picked THAT
    # one because its versionCode (14) beat ours. Replace it too (our module is now
    # versionCode 100), and drop its oat, so our Miku FM wins on a clean flash.
    debugfs -w -R "rm system/app/FM2/oat/arm64/FM2.odex" "$OUTPUT_DIR/system.img" 2>/dev/null || true
    debugfs -w -R "rm system/app/FM2/oat/arm64/FM2.vdex" "$OUTPUT_DIR/system.img" 2>/dev/null || true
    debugfs -w -R "rm system/app/FM2/oat/arm/FM2.odex" "$OUTPUT_DIR/system.img" 2>/dev/null || true
    debugfs -w -R "rm system/app/FM2/oat/arm/FM2.vdex" "$OUTPUT_DIR/system.img" 2>/dev/null || true
    dfput "$OUTPUT_DIR/system.img" "$FMRADIO_APK" "system/app/FM2/FM2.apk" \
        && label "$OUTPUT_DIR/system.img" "system/app/FM2/FM2.apk" "u:object_r:system_file:s0" \
        || echo "  !! FM2 (system) replace failed"
else
    echo "  -> Miku FM APK not found; leaving stock FM2 (build fmradio module first)"
fi

# Remove stock Launcher3QuickStep (competing HOME intent with MikuLauncher)
debugfs -w -R "rm priv-app/Launcher3QuickStep/oat/arm64/Launcher3QuickStep.odex" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true
debugfs -w -R "rm priv-app/Launcher3QuickStep/oat/arm64/Launcher3QuickStep.vdex" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true
debugfs -w -R "rm priv-app/Launcher3QuickStep/Launcher3QuickStep.apk" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true

# Neutralize SystemUI OEM voice prompts (Headphones connected, Charging, Shutdown)
echo "  -> Neutralizing OEM SystemUI voice announcements (Headphones connected, Charging, Shutdown)..."
TMP_SYSUI_DIR="$(mktemp -d)"
debugfs -R "dump priv-app/SystemUI/SystemUI.apk $TMP_SYSUI_DIR/SystemUI.apk" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true
if [ -s "$TMP_SYSUI_DIR/SystemUI.apk" ]; then
    mkdir -p "$TMP_SYSUI_DIR/res/raw"
    ffmpeg -y -f lavfi -i anullsrc=r=44100:cl=mono -t 0.05 -c:a libvorbis "$TMP_SYSUI_DIR/silent.ogg" 2>/dev/null || true
    for sound in headset_plugged_in headset_plugged_in_en headset_plugged_in_jp headset_plugged_out headset_plugged_out_en headset_plugged_out_jp shutdown shutdown_en shutdown_jp charging charging_en charging_jp battery_low battery_low_en battery_low_jp volume_high volume_high_en volume_high_jp; do
        cp -f "$TMP_SYSUI_DIR/silent.ogg" "$TMP_SYSUI_DIR/res/raw/$sound.ogg"
    done
    (cd "$TMP_SYSUI_DIR" && zip -0 -u SystemUI.apk res/raw/*.ogg >/dev/null 2>&1 && /home/reaver/Android/Sdk/build-tools/35.0.0/zipalign -f 4 SystemUI.apk SystemUI_aligned.apk && mv SystemUI_aligned.apk SystemUI.apk)
    debugfs -w -R "rm priv-app/SystemUI/SystemUI.apk" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true
    debugfs -w -R "write $TMP_SYSUI_DIR/SystemUI.apk priv-app/SystemUI/SystemUI.apk" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true
    debugfs -w -R "set_inode_field priv-app/SystemUI/SystemUI.apk mode 0100644" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true
    label "$OUTPUT_DIR/system_ext.img" "priv-app/SystemUI/SystemUI.apk" "u:object_r:system_file:s0"
fi
rm -rf "$TMP_SYSUI_DIR"

# Remove stock Provision (stock AOSP wizard that stalls boot and lacks Apps provisioning step)
debugfs -w -R "rm priv-app/Provision/oat/arm64/Provision.odex" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true
debugfs -w -R "rm priv-app/Provision/oat/arm64/Provision.vdex" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true
debugfs -w -R "rm priv-app/Provision/Provision.apk" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true

# Inject permissions XML
debugfs -w -R "write $PERMISSIONS_XML etc/permissions/privapp-permissions-mikuos.xml" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true
debugfs -w -R "set_inode_field etc/permissions/privapp-permissions-mikuos.xml mode 0100644" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true
label "$OUTPUT_DIR/system_ext.img" etc/permissions/privapp-permissions-mikuos.xml u:object_r:system_file:s0

# Patch system_ext build.prop identity
TMP_EXT_PROP="/tmp/miku_system_ext_build.prop"
debugfs -R "cat etc/build.prop" "$OUTPUT_DIR/system_ext.img" > "$TMP_EXT_PROP" 2>/dev/null || true
if [ -s "$TMP_EXT_PROP" ]; then
    sed -i "s/^ro.product.system_ext.model=.*/ro.product.system_ext.model=${DEVICE_IDENTITY}/" "$TMP_EXT_PROP"
    sed -i "s/^ro.product.system_ext.name=.*/ro.product.system_ext.name=m500_mikuOS/" "$TMP_EXT_PROP"
    sed -i "s/^ro.product.system_ext.device=.*/ro.product.system_ext.device=m500_mikuOS/" "$TMP_EXT_PROP"
    dfput "$OUTPUT_DIR/system_ext.img" "$TMP_EXT_PROP" "etc/build.prop" \
        && label "$OUTPUT_DIR/system_ext.img" "etc/build.prop" "u:object_r:system_file:s0" || true
fi
rm -f "$TMP_EXT_PROP"

echo "[4/6] Debloating product.img..."

# Google Fi APN: bake the Fi h2g2 APNs (GID1 4276 / IMSI 31026097 match) into product/etc/apns-conf.xml so a Fi SIM gets
# mobile data on a clean flash (stock file has no Fi entry -> generic wrong APN -> data denied).
# See memory m500-google-fi-4g-data. dfput = rm+write (debugfs won't overwrite an existing file).
APNS_MIKU="$SCRIPT_DIR/apns-conf-mikuos.xml"
if [ -f "$APNS_MIKU" ]; then
    dfput "$OUTPUT_DIR/product.img" "$APNS_MIKU" "etc/apns-conf.xml" \
        && label "$OUTPUT_DIR/product.img" "etc/apns-conf.xml" "u:object_r:system_file:s0" \
        && echo "  -> injected Google Fi APN into product/etc/apns-conf.xml" \
        || echo "  !! APN inject failed (non-fatal)"
else
    echo "  !! $APNS_MIKU missing; skipping Fi APN injection"
fi

# Remove stock HiByMusic from product partition
debugfs -w -R "rm app/HiByMusic/oat/arm/HiByMusic.odex" "$OUTPUT_DIR/product.img" 2>/dev/null || true
debugfs -w -R "rm app/HiByMusic/oat/arm/HiByMusic.vdex" "$OUTPUT_DIR/product.img" 2>/dev/null || true
debugfs -w -R "rm app/HiByMusic/HiByMusic.apk" "$OUTPUT_DIR/product.img" 2>/dev/null || true

# HiByMusic ALSO ships in vendor/app/HiByMusic (com.hiby.music) — the product-only
# removal above missed it, so the app kept reappearing installed. Strip the vendor
# copy too (rm the apk + its oat), so the package is truly absent, not just disabled.
for _f in app/HiByMusic/oat/arm/HiByMusic.odex app/HiByMusic/oat/arm/HiByMusic.vdex \
          app/HiByMusic/oat/arm64/HiByMusic.odex app/HiByMusic/oat/arm64/HiByMusic.vdex \
          app/HiByMusic/HiByMusic.apk; do
    debugfs -w -R "rm $_f" "$OUTPUT_DIR/vendor.img" 2>/dev/null || true
done

# Vendor MUSIC volume curves: bake the MikuOS-corrected audio_policy_volumes.xml over the
# stock /vendor/etc/audio_policy_volumes.xml (the file XIncluded — by absolute path — from
# /vendor/etc/audio/audio_policy_configuration.xml, the config the APM actually loads).
# It fixes the smart-quote example in the stock doc comment and replaces the MUSIC
# HEADSET/EXT_MEDIA refs with explicit full-range curves ending at 0 dB @ index 100, so the
# vendor file — not an AOSP default table — is authoritative for MUSIC on the DAC outputs.
# (The on-device 35/100 cap itself is HiBy's volume lock; disarmed in miku_ime.rc below.)
VOLUMES_XML="$SCRIPT_DIR/audio/audio_policy_volumes.xml"
if [ -f "$VOLUMES_XML" ]; then
    dfput "$OUTPUT_DIR/vendor.img" "$VOLUMES_XML" "etc/audio_policy_volumes.xml" \
        && label "$OUTPUT_DIR/vendor.img" "etc/audio_policy_volumes.xml" "u:object_r:vendor_configs_file:s0" \
        && echo "  -> Baked corrected vendor audio_policy_volumes.xml (full-range MUSIC curves)" \
        || echo "  !! audio_policy_volumes.xml replace failed (stock curves kept)"
else
    echo "  !! $VOLUMES_XML missing — stock volume curves kept"
fi

# Re-sign the (voice-neutralized, from the [196] block) STOCK SystemUI so its signature is valid
# and matches framework-res for this REKEY mode. We deliberately DO NOT inject the committed
# $SCRIPT_DIR/SystemUI.apk "patched" build: it is a foreign/newer com.android.systemui declaring
# ~177 privileged permissions vs this device's 71-entry stock allowlist, so under
# ro.control_privapp_permissions=enforce it is denied MANAGE_ACTIVITY_TASKS (and more) and
# crash-loops ~600x/boot -> black screen (see memory m500-systemui-signature-crashloop). The stock
# SystemUI matches the device's allowlist and boots clean; the only reason it needs a re-sign is the
# earlier voice-neutralization's `zip -u` invalidated its original signature.
SYSUI_TMP="$(mktemp -d)"
debugfs -R "dump priv-app/SystemUI/SystemUI.apk $SYSUI_TMP/SystemUI.apk" "$OUTPUT_DIR/system_ext.img" 2>/dev/null || true
if [ -s "$SYSUI_TMP/SystemUI.apk" ]; then
    ZIPALIGN="${ZIPALIGN:-$(ls ~/Android/Sdk/build-tools/*/zipalign 2>/dev/null | tail -1)}"
    [ -n "$ZIPALIGN" ] && "$ZIPALIGN" -f -p 4 "$SYSUI_TMP/SystemUI.apk" "$SYSUI_TMP/aligned.apk" && mv "$SYSUI_TMP/aligned.apk" "$SYSUI_TMP/SystemUI.apk"
    # Re-sign for BOTH modes so the voice-edit's broken signature is always fixed with a key that
    # matches the framework: REKEY=1 -> the NEW custom platform key (the [5b] re-key then leaves it,
    # since it is no longer an AOSP-test source key); REKEY=0 -> the AOSP-test platform key.
    # (The re-key CANNOT fix a broken-sig apk — apksigner cannot read its cert to map it — so
    # skipping this for REKEY=1 left SystemUI invalidly signed and the gate rightly rejected it.)
    if [ "$REKEY" = "1" ]; then
        "$APKSIGNER" sign --key "$REPO_DIR/mikuos/signing/platform.pk8" --cert "$REPO_DIR/mikuos/signing/platform.x509.pem" \
            --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true \
            "$SYSUI_TMP/SystemUI.apk" \
            && echo "  -> re-signed STOCK SystemUI with NEW custom platform key (matches re-keyed framework)" \
            || { echo "  !! SystemUI re-sign FAILED — aborting"; exit 1; }
    else
        PLATFORM_JKS="$REPO_DIR/miku-player-kotlin/platform.jks"
        "$APKSIGNER" sign --ks "$PLATFORM_JKS" --ks-key-alias platform --ks-pass pass:android \
            --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true \
            "$SYSUI_TMP/SystemUI.apk" \
            && echo "  -> re-signed STOCK SystemUI with platform key (c8a2e9bc, matches framework-res + 71-perm allowlist)" \
            || { echo "  !! SystemUI re-sign FAILED — aborting"; exit 1; }
    fi
    dfput "$OUTPUT_DIR/system_ext.img" "$SYSUI_TMP/SystemUI.apk" "priv-app/SystemUI/SystemUI.apk" \
        && label "$OUTPUT_DIR/system_ext.img" "priv-app/SystemUI/SystemUI.apk" "u:object_r:system_file:s0" \
        && echo "  -> Injected voice-neutralized + re-signed STOCK SystemUI into system_ext" \
        || echo "  !! SystemUI inject failed"
    rm -rf "$SYSUI_TMP"
fi

# Inject permissions XML
debugfs -w -R "write $PERMISSIONS_XML etc/permissions/privapp-permissions-mikuos.xml" "$OUTPUT_DIR/product.img" 2>/dev/null || true
debugfs -w -R "set_inode_field etc/permissions/privapp-permissions-mikuos.xml mode 0100644" "$OUTPUT_DIR/product.img" 2>/dev/null || true

# Patch product build.prop identity
TMP_PROD_PROP="/tmp/miku_product_build.prop"
debugfs -R "cat etc/build.prop" "$OUTPUT_DIR/product.img" > "$TMP_PROD_PROP" 2>/dev/null || true
if [ -s "$TMP_PROD_PROP" ]; then
    sed -i "s/^ro.product.product.model=.*/ro.product.product.model=${DEVICE_IDENTITY}/" "$TMP_PROD_PROP"
    sed -i "s/^ro.product.product.name=.*/ro.product.product.name=m500_mikuOS/" "$TMP_PROD_PROP"
    sed -i "s/^ro.product.product.device=.*/ro.product.product.device=m500_mikuOS/" "$TMP_PROD_PROP"
    dfput "$OUTPUT_DIR/product.img" "$TMP_PROD_PROP" "etc/build.prop" \
        && label "$OUTPUT_DIR/product.img" "etc/build.prop" "u:object_r:system_file:s0" || true
fi
rm -f "$TMP_PROD_PROP"

# Inject the MikuSystemUI RRO overlay into /product/overlay — the overlay dir this ROM actually
# SCANS (verified: stock CarrierConfigResCommon_Sys.apk etc. live here and are enabled;
# /system_ext/overlay exists but is NOT scanned here, which is why the first attempt failed).
# Placed top-level with context system_file:s0 (same as the stock overlays). Static RRO
# (targetPackage=com.android.systemui) forcing enable_volume_ui=false → SystemUI's VolumeUI never
# registers the stock AOSP volume dialog, so only the MikuOS launcher volume modal shows. Volume
# keys still work (PhoneWindowManager, independent). Signature need not match SystemUI (verified:
# a working stock overlay is signed with a different key than SystemUI).
# All four MikuOS RROs are static overlays baked into /product/overlay (trusted by location,
# platform-signed by tools/custom_overlays/build_overlay.sh). dfput (rm+write) is used so a
# re-run never silently no-ops on an existing file (see m500-debugfs-overwrite-noop-bug).
#   MikuSystemUIOverlay  → com.android.systemui: enable_volume_ui=false (stock volume dialog off),
#                          HiBy headset/Fn strings.  (Its manifest MUST carry <application/>, or
#                          PackageManager rejects it — that bug hid it on the 08-21 image.)
#   MikuFrameworkOverlay → android: config_navBarInteractionMode=2 (gestural).
#   MikuThemeOverlay     → com.android.systemui: Miku teal retint of the stock power menu /
#                          global actions, fallback volume dialog, notification guts, QS accents.
#   MikuAnimOverlay      → android: KDE fly-in / fall-apart / fly-away window animations for
#                          activity_*, task_* AND wallpaper_* (home<->app) transitions, system-wide.
debugfs -w -R "mkdir overlay" "$OUTPUT_DIR/product.img" 2>/dev/null || true
inject_overlay() {   # <src apk> <dest name> <description>
    if [ -f "$1" ]; then
        dfput "$OUTPUT_DIR/product.img" "$1" "overlay/$2" \
            && label "$OUTPUT_DIR/product.img" "overlay/$2" u:object_r:system_file:s0 \
            && echo "  -> Injected $2 ($3) into /product/overlay" \
            || echo "  !! $2 inject FAILED"
    else
        echo "  !! $2 missing ($1) — $3 will NOT be applied"
    fi
}
inject_overlay "$REPO_DIR/tools/custom_overlays/MikuSystemUIOverlay/com.miku.systemui.overlay.apk" MikuSystemUIOverlay.apk "stock volume dialog off, AOSP nav handle transparent, HiBy strings"
inject_overlay "$REPO_DIR/tools/custom_overlays/MikuFrameworkOverlay/MikuFrameworkOverlay.apk" MikuFrameworkOverlay.apk "gestural nav config"
inject_overlay "$REPO_DIR/tools/custom_overlays/MikuThemeOverlay/MikuThemeOverlay.apk" MikuThemeOverlay.apk "power menu + dialog retint"
inject_overlay "$MIKUOS_DIR/build/MikuAnimOverlay.apk" MikuAnimOverlay.apk "KDE window animations"
# The overlay APK is gitignored; build it from the committed res/ (no Gemini key needed).
SPLASH_OVL="$REPO_DIR/tools/custom_overlays/MikuSplashOverlay"
if [ ! -f "$SPLASH_OVL/MikuSplashOverlay.apk" ] && ls "$SPLASH_OVL"/res/drawable-*/*.png >/dev/null 2>&1; then
    "$REPO_DIR/tools/custom_overlays/build_overlay.sh" "$SPLASH_OVL" "$SPLASH_OVL/MikuSplashOverlay.apk" >/dev/null \
        || echo "  !! MikuSplashOverlay build failed"
fi
inject_overlay "$REPO_DIR/tools/custom_overlays/MikuSplashOverlay/MikuSplashOverlay.apk" MikuSplashOverlay.apk "Miku splash art (headphones, charging, low battery, shutdown, volume warning)"

echo "[5/6] Injecting MikuOS Suite into system.img..."
# Remove stock bloat
debugfs -w -R "rm system/app/Abupdate/oat/arm64/Abupdate.odex" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "rm system/app/Abupdate/oat/arm64/Abupdate.vdex" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "rm system/app/Abupdate/Abupdate.apk" "$OUTPUT_DIR/system.img" 2>/dev/null || true

debugfs -w -R "rm system/priv-app/MusicFX/oat/arm64/MusicFX.odex" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "rm system/priv-app/MusicFX/oat/arm64/MusicFX.vdex" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "rm system/priv-app/MusicFX/MusicFX.apk" "$OUTPUT_DIR/system.img" 2>/dev/null || true

# Inject MikuLauncher into system/app/
debugfs -w -R "mkdir system/app/MikuLauncher" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "set_inode_field system/app/MikuLauncher mode 040755" "$OUTPUT_DIR/system.img"
debugfs -w -R "write $LAUNCHER_APK system/app/MikuLauncher/MikuLauncher.apk" "$OUTPUT_DIR/system.img"
debugfs -w -R "set_inode_field system/app/MikuLauncher/MikuLauncher.apk mode 0100644" "$OUTPUT_DIR/system.img"
label "$OUTPUT_DIR/system.img" system/app/MikuLauncher u:object_r:system_file:s0
label "$OUTPUT_DIR/system.img" system/app/MikuLauncher/MikuLauncher.apk u:object_r:system_file:s0

# Inject MikuMusic into system/app/
debugfs -w -R "mkdir system/app/MikuMusic" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "set_inode_field system/app/MikuMusic mode 040755" "$OUTPUT_DIR/system.img"
debugfs -w -R "write $MUSIC_APK system/app/MikuMusic/MikuMusic.apk" "$OUTPUT_DIR/system.img"
debugfs -w -R "set_inode_field system/app/MikuMusic/MikuMusic.apk mode 0100644" "$OUTPUT_DIR/system.img"
label "$OUTPUT_DIR/system.img" system/app/MikuMusic u:object_r:system_file:s0
label "$OUTPUT_DIR/system.img" system/app/MikuMusic/MikuMusic.apk u:object_r:system_file:s0

# Inject MikuSettings into system/priv-app/. Privileged, because Android resets intent-filter
# priority to 0 for anything outside priv-app, and then stock Settings wins or ties every
# android.settings.* action (the dual Settings UI). This device enforces the privapp allowlist
# with no exemption for platform-signed apps, so check_privapp.py fails the BUILD if any
# privileged permission the APK requests is not allowlisted; otherwise that would be a bootloop.
FWRES_TMP="$(mktemp -d)"
debugfs -R "dump system/framework/framework-res.apk $FWRES_TMP/framework-res.apk" "$OUTPUT_DIR/system.img" 2>/dev/null
python3 -I "$SCRIPT_DIR/check_privapp.py" /home/reaver/Android/Sdk/build-tools/35.0.0/aapt2 \
    "$SETTINGS_APK" "$FWRES_TMP/framework-res.apk" "$PERMISSIONS_XML" \
    || { echo "!! FATAL: MikuSettings privapp allowlist incomplete; refusing to build an image that would not boot"; exit 1; }
rm -rf "$FWRES_TMP"
rm_tree "$OUTPUT_DIR/system.img" system/app/MikuSettings   # an older image layout put it here
debugfs -w -R "mkdir system/priv-app/MikuSettings" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "set_inode_field system/priv-app/MikuSettings mode 040755" "$OUTPUT_DIR/system.img"
debugfs -w -R "write $SETTINGS_APK system/priv-app/MikuSettings/MikuSettings.apk" "$OUTPUT_DIR/system.img"
debugfs -w -R "set_inode_field system/priv-app/MikuSettings/MikuSettings.apk mode 0100644" "$OUTPUT_DIR/system.img"
label "$OUTPUT_DIR/system.img" system/priv-app/MikuSettings u:object_r:system_file:s0
label "$OUTPUT_DIR/system.img" system/priv-app/MikuSettings/MikuSettings.apk u:object_r:system_file:s0

# M500 Hardware Settings (holds the camera-EV100 ambient-light auto-brightness service + DAC controls).
if [ -n "$HARDWARE_APK" ] && [ -f "$HARDWARE_APK" ]; then
    debugfs -w -R "mkdir system/app/M500Hardware" "$OUTPUT_DIR/system.img" 2>/dev/null || true
    debugfs -w -R "set_inode_field system/app/M500Hardware mode 040755" "$OUTPUT_DIR/system.img"
    debugfs -w -R "write $HARDWARE_APK system/app/M500Hardware/M500Hardware.apk" "$OUTPUT_DIR/system.img"
    debugfs -w -R "set_inode_field system/app/M500Hardware/M500Hardware.apk mode 0100644" "$OUTPUT_DIR/system.img"
    label "$OUTPUT_DIR/system.img" system/app/M500Hardware u:object_r:system_file:s0
    label "$OUTPUT_DIR/system.img" system/app/M500Hardware/M500Hardware.apk u:object_r:system_file:s0
    echo "  -> injected M500HardwareSettings (ambient-light sensor)"
else
    echo "  !! M500HardwareSettings.apk not found — ambient-light sensor will be missing" >&2
fi

# MikuOS system bridge: the one Miku package with sharedUserId=android.uid.system, so it runs in
# the system_app domain, which HiBy's policy lets set vendor.usb.* and sys.usb.config. USB DAC mode
# (the M500 as a USB sound card) goes through it; every other Miku app is platform_app and cannot.
if [ -n "$SYSBRIDGE_APK" ] && [ -f "$SYSBRIDGE_APK" ]; then
    debugfs -w -R "mkdir system/app/MikuSysBridge" "$OUTPUT_DIR/system.img" 2>/dev/null || true
    debugfs -w -R "set_inode_field system/app/MikuSysBridge mode 040755" "$OUTPUT_DIR/system.img"
    debugfs -w -R "write $SYSBRIDGE_APK system/app/MikuSysBridge/MikuSysBridge.apk" "$OUTPUT_DIR/system.img"
    debugfs -w -R "set_inode_field system/app/MikuSysBridge/MikuSysBridge.apk mode 0100644" "$OUTPUT_DIR/system.img"
    label "$OUTPUT_DIR/system.img" system/app/MikuSysBridge u:object_r:system_file:s0
    label "$OUTPUT_DIR/system.img" system/app/MikuSysBridge/MikuSysBridge.apk u:object_r:system_file:s0
    echo "  -> injected MikuSysBridge (USB DAC mode)"
else
    echo "  !! MikuSysBridge.apk not found — USB DAC mode will not switch" >&2
fi

# MikuOS replacements for the stock Clock, Calculator, Calendar (MikuTools) and Camera, Gallery,
# Recorder (MikuMedia). Each stock app is the only handler of an intent other apps rely on (set
# an alarm, open a photo, take a picture), so it is removed in the debloat step ONLY when its
# replacement was injected here: TOOLS_INJECTED / MEDIA_INJECTED gate that.
inject_system_app() {   # <apk> <dir name> <label>
    local apk="$1" dir="$2"
    [ -n "$apk" ] && [ -f "$apk" ] || return 1
    debugfs -w -R "mkdir system/app/$dir" "$OUTPUT_DIR/system.img" 2>/dev/null || true
    debugfs -w -R "set_inode_field system/app/$dir mode 040755" "$OUTPUT_DIR/system.img"
    debugfs -w -R "rm system/app/$dir/$dir.apk" "$OUTPUT_DIR/system.img" 2>/dev/null || true
    debugfs -w -R "write $apk system/app/$dir/$dir.apk" "$OUTPUT_DIR/system.img" || return 1
    debugfs -w -R "set_inode_field system/app/$dir/$dir.apk mode 0100644" "$OUTPUT_DIR/system.img"
    label "$OUTPUT_DIR/system.img" "system/app/$dir" u:object_r:system_file:s0
    label "$OUTPUT_DIR/system.img" "system/app/$dir/$dir.apk" u:object_r:system_file:s0
    img_has "$OUTPUT_DIR/system.img" "system/app/$dir/$dir.apk" || return 1
    echo "  -> injected $dir ($3)"
}
TOOLS_INJECTED=0; MEDIA_INJECTED=0
inject_system_app "$TOOLS_APK" MikuTools "Clock, Calculator, Calendar" && TOOLS_INJECTED=1 \
    || echo "  !! MikuTools not injected; stock Clock/Calculator/Calendar kept"
inject_system_app "$MEDIA_APK" MikuMedia "Camera, Gallery, Recorder" && MEDIA_INJECTED=1 \
    || echo "  !! MikuMedia not injected; stock Camera/Gallery/Recorder kept"
# Miku Update: over-the-air updates of the com.miku.* apps (never the FM app, which has to come
# from the image). System UID + platform signature already hold INSTALL_PACKAGES.
inject_system_app "$UPDATE_APK" MikuUpdate "over-the-air app updates" \
    || echo "  !! MikuUpdate not injected; no over-the-air app updates in this image"
# Easter eggs, unlocked from the BPM game (MikuSecrets.kt). Nothing is debloated for them.
inject_system_app "$RIOT_APK" MikuRiot "Riot mode easter egg" \
    || echo "  !! MikuRiot not injected; the Riot mode secret has nothing to open"
inject_system_app "$WHEEL_APK" MikuWheel "MikuPod easter egg" \
    || echo "  !! MikuWheel not injected; the MikuPod secrets have nothing to open"

# Inject MikuSystemUI into system/app/
debugfs -w -R "mkdir system/app/MikuSystemUI" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "set_inode_field system/app/MikuSystemUI mode 040755" "$OUTPUT_DIR/system.img"
debugfs -w -R "write $SYSTEMUI_APK system/app/MikuSystemUI/MikuSystemUI.apk" "$OUTPUT_DIR/system.img"
debugfs -w -R "set_inode_field system/app/MikuSystemUI/MikuSystemUI.apk mode 0100644" "$OUTPUT_DIR/system.img"
label "$OUTPUT_DIR/system.img" system/app/MikuSystemUI u:object_r:system_file:s0
label "$OUTPUT_DIR/system.img" system/app/MikuSystemUI/MikuSystemUI.apk u:object_r:system_file:s0

# Inject permissions XML into system/etc/permissions/
debugfs -w -R "write $PERMISSIONS_XML system/etc/permissions/privapp-permissions-mikuos.xml" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "set_inode_field system/etc/permissions/privapp-permissions-mikuos.xml mode 0100644" "$OUTPUT_DIR/system.img" 2>/dev/null || true
label "$OUTPUT_DIR/system.img" system/etc/permissions/privapp-permissions-mikuos.xml u:object_r:system_file:s0

# Default runtime-permission grants (auto-grant location etc. so system apps
# don't prompt; Wi-Fi scanner needs location or it returns nothing).
debugfs -w -R "mkdir system/etc/default-permissions" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "set_inode_field system/etc/default-permissions mode 040755" "$OUTPUT_DIR/system.img" 2>/dev/null || true
label "$OUTPUT_DIR/system.img" system/etc/default-permissions u:object_r:system_file:s0
debugfs -w -R "write $DEFAULT_PERMS_XML system/etc/default-permissions/default-permissions-mikuos.xml" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "set_inode_field system/etc/default-permissions/default-permissions-mikuos.xml mode 0100644" "$OUTPUT_DIR/system.img" 2>/dev/null || true
label "$OUTPUT_DIR/system.img" system/etc/default-permissions/default-permissions-mikuos.xml u:object_r:system_file:s0

# Inject any preloaded APKs from mikuos/build/preloaded_apks/
PRELOAD_DIR="$SCRIPT_DIR/preloaded_apks"
mkdir -p "$PRELOAD_DIR"
for apk_file in "$PRELOAD_DIR"/*.apk; do
    if [ -f "$apk_file" ]; then
        apk_base=$(basename "$apk_file" .apk)
        echo "  -> Preloading APK into system/app/$apk_base/$apk_base.apk"
        debugfs -w -R "mkdir system/app/$apk_base" "$OUTPUT_DIR/system.img" 2>/dev/null || true
        debugfs -w -R "set_inode_field system/app/$apk_base mode 040755" "$OUTPUT_DIR/system.img"
        # dfput (rm+write): a plain debugfs write silently no-ops on an existing file.
        # NOTE: never put FM2.apk here — Miku FM already replaced system/app/FM2 in [3/6].
        dfput "$OUTPUT_DIR/system.img" "$apk_file" "system/app/$apk_base/$apk_base.apk" \
            || echo "  !! preload $apk_base failed"
        label "$OUTPUT_DIR/system.img" system/app/$apk_base u:object_r:system_file:s0
        label "$OUTPUT_DIR/system.img" system/app/$apk_base/$apk_base.apk u:object_r:system_file:s0
    fi
done

# Bundle OPTIONAL apps (not system apps) into /system/etc/mikuos-optional-apks/ for the
# first-boot provisioner below. Two layouts are supported:
#   optional_apks/<file>.apk            single universal APK
#   optional_apks/<package>/<split>.apk split-APK set (base + config.<abi>/<dpi>/<lang>) staged
#                                       by mikuos-optional-apks/stage_optional_apks.sh; the
#                                       developers' signatures are untouched so Play Store can
#                                       update these apps later.
OPTIONAL_DIR="$SCRIPT_DIR/optional_apks"
OPT_ROOT="system/etc/mikuos-optional-apks"
if ls "$OPTIONAL_DIR"/*.apk "$OPTIONAL_DIR"/*/*.apk >/dev/null 2>&1; then
    echo "  -> Bundling optional apps into $OPT_ROOT/ ($(du -sh "$OPTIONAL_DIR" | cut -f1))"
    debugfs -w -R "mkdir $OPT_ROOT" "$OUTPUT_DIR/system.img" 2>/dev/null || true
    debugfs -w -R "set_inode_field $OPT_ROOT mode 040755" "$OUTPUT_DIR/system.img" 2>/dev/null || true
    label "$OUTPUT_DIR/system.img" "$OPT_ROOT" u:object_r:system_file:s0
    for apk_file in "$OPTIONAL_DIR"/*.apk; do
        [ -f "$apk_file" ] || continue
        base="$(basename "$apk_file")"
        dfput "$OUTPUT_DIR/system.img" "$apk_file" "$OPT_ROOT/$base" \
            && label "$OUTPUT_DIR/system.img" "$OPT_ROOT/$base" u:object_r:system_file:s0 \
            || echo "  !! optional apk inject failed: $base"
    done
    for pkg_dir in "$OPTIONAL_DIR"/*/; do
        [ -d "$pkg_dir" ] || continue
        pkg="$(basename "$pkg_dir")"
        ls "$pkg_dir"/*.apk >/dev/null 2>&1 || continue
        debugfs -w -R "mkdir $OPT_ROOT/$pkg" "$OUTPUT_DIR/system.img" 2>/dev/null || true
        debugfs -w -R "set_inode_field $OPT_ROOT/$pkg mode 040755" "$OUTPUT_DIR/system.img" 2>/dev/null || true
        label "$OUTPUT_DIR/system.img" "$OPT_ROOT/$pkg" u:object_r:system_file:s0
        for split in "$pkg_dir"/*.apk; do
            sbase="$(basename "$split")"
            dfput "$OUTPUT_DIR/system.img" "$split" "$OPT_ROOT/$pkg/$sbase" \
                && label "$OUTPUT_DIR/system.img" "$OPT_ROOT/$pkg/$sbase" u:object_r:system_file:s0 \
                || echo "  !! optional split inject failed: $pkg/$sbase"
        done
        echo "  -> optional app $pkg: $(ls "$pkg_dir" | grep -c '\.apk$') split(s)"
    done
fi

# Shared-library STUBS required by bundled optional apps. Amazon Music declares
# <uses-library android:name="com.google.android.wearable" android:required="true"/>; this
# HiBy image has no Wear OS library, so `pm install` fails with INSTALL_FAILED_MISSING_SHARED_LIBRARY.
# An empty jar registered under that name satisfies the package manager (the app only touches
# the Wear classes when a watch is paired). Skipped if the image already provides the library.
if ! debugfs -R "stat system/etc/permissions/com.google.android.wearable.xml" "$OUTPUT_DIR/system.img" >/dev/null 2>&1; then
    TMP_WEAR_DIR="$(mktemp -d)"
    ( cd "$TMP_WEAR_DIR" && mkdir -p META-INF && printf 'Manifest-Version: 1.0\n' > META-INF/MANIFEST.MF \
        && zip -q -X com.google.android.wearable.jar META-INF/MANIFEST.MF )
    cat > "$TMP_WEAR_DIR/com.google.android.wearable.xml" <<'WEAREOF'
<?xml version="1.0" encoding="utf-8"?>
<!-- MikuOS: stub Wear OS shared library so apps that hard-require it (Amazon Music) install. -->
<permissions>
    <library name="com.google.android.wearable" file="/system/framework/com.google.android.wearable.jar" />
</permissions>
WEAREOF
    dfput "$OUTPUT_DIR/system.img" "$TMP_WEAR_DIR/com.google.android.wearable.jar" system/framework/com.google.android.wearable.jar \
        && label "$OUTPUT_DIR/system.img" system/framework/com.google.android.wearable.jar u:object_r:system_file:s0 \
        && dfput "$OUTPUT_DIR/system.img" "$TMP_WEAR_DIR/com.google.android.wearable.xml" system/etc/permissions/com.google.android.wearable.xml \
        && label "$OUTPUT_DIR/system.img" system/etc/permissions/com.google.android.wearable.xml u:object_r:system_file:s0 \
        && echo "  -> Injected com.google.android.wearable stub shared library (for Amazon Music)" \
        || echo "  !! wearable stub inject failed"
    rm -rf "$TMP_WEAR_DIR"
fi

# First-boot offline APK provisioner (CyanogenMod-style addon.d/pm-install script).
# Installs the bundled apps directly via the package manager on first boot — NO Play
# Store / Aurora / network needed. Runs once, guarded by a flag file, then stops
# its own service. Split-APK sets are installed through a pm install session so the
# developers' signatures are preserved and Play Store can update them afterwards.
echo "[4c] Injecting first-boot offline APK provisioner (pm install sessions)..."
TMP_PRELOAD_SH="/tmp/miku_preload_apks.sh"
cat << 'PRELOADEOF' > "$TMP_PRELOAD_SH"
#!/system/bin/sh
# MikuOS first-boot offline app installer. No network, no Google account.
# NOTE: must live somewhere the shell domain can WRITE — /data/misc is root:misc,
# so mkdir there silently fails and the whole run leaves no log (bug found 2026-08-27
# on the first REKEY=1 boot: zero optional apps installed, no log, no flag).
FLAG=/data/local/tmp/mikuos/.preload_done
LOG=/data/local/tmp/mikuos/preload.log
ROOT=/system/etc/mikuos-optional-apks
mkdir -p /data/local/tmp/mikuos
[ -f "$FLAG" ] && exit 0
echo "MikuOS preload start $(date)" >> "$LOG"

install_set() { # <label> <apk>... — one pm session per app (single APK or base+splits)
    label="$1"; shift
    sid=$(pm install-create -r -g 2>>"$LOG" | sed 's/.*\[\([0-9]*\)\].*/\1/')
    if [ -z "$sid" ]; then echo "  FAILED $label (no session)" >> "$LOG"; return 1; fi
    ok=1
    for f in "$@"; do
        [ -f "$f" ] || continue
        sz=$(stat -c %s "$f")
        pm install-write -S "$sz" "$sid" "$(basename "$f")" "$f" >> "$LOG" 2>&1 || ok=0
    done
    if [ "$ok" = "1" ] && pm install-commit "$sid" >> "$LOG" 2>&1; then
        echo "  installed $label" >> "$LOG"
    else
        pm install-abandon "$sid" >> "$LOG" 2>&1
        echo "  FAILED $label" >> "$LOG"
    fi
}

# Single universal APKs
for apk in "$ROOT"/*.apk; do
    [ -f "$apk" ] || continue
    install_set "$(basename "$apk")" "$apk"
done
# Split-APK sets (one folder per package)
for dir in "$ROOT"/*/; do
    [ -d "$dir" ] || continue
    set -- "$dir"*.apk
    [ -f "$1" ] || continue
    install_set "$(basename "$dir")" "$@"
done

# Kick our platform apps out of the never-launched "stopped" state so their
# BOOT_COMPLETED receivers work from the NEXT boot on (a fresh /data leaves every
# app force-stopped until first launch -> no Miku QS/SystemUI at first boot).
# Sane clock defaults on a fresh /data: NTP time + telephony/geo TZ detection ON.
settings put global auto_time 1 >> "$LOG" 2>&1
settings put global auto_time_zone 1 >> "$LOG" 2>&1
# NTP source (stock has none -> auto_time can't sync -> wrong clock on every boot) + location TZ detect.
settings put global ntp_server time.google.com >> "$LOG" 2>&1
settings put global ntp_server_2 time.android.com >> "$LOG" 2>&1
settings put global auto_time_zone_explicit 1 >> "$LOG" 2>&1
settings put secure location_time_zone_detection_enabled 1 >> "$LOG" 2>&1

for pkg in com.miku.systemui com.miku.settings; do
    monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >> "$LOG" 2>&1
    sleep 1
done
input keyevent KEYCODE_HOME >> "$LOG" 2>&1

touch "$FLAG"
echo "MikuOS preload done $(date)" >> "$LOG"
# stop this one-shot service so it never re-runs
setprop mikuos.preload.done 1
exit 0
PRELOADEOF
debugfs -w -R "rm system/etc/miku_preload_apks.sh" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "write $TMP_PRELOAD_SH system/etc/miku_preload_apks.sh" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "set_inode_field system/etc/miku_preload_apks.sh mode 0100755" "$OUTPUT_DIR/system.img" 2>/dev/null || true
label "$OUTPUT_DIR/system.img" system/etc/miku_preload_apks.sh u:object_r:system_file:s0
rm -f "$TMP_PRELOAD_SH"

TMP_PRELOAD_RC="/tmp/miku_preload.rc"
cat << 'PRELOADRCEOF' > "$TMP_PRELOAD_RC"
# MikuOS first-boot offline APK installer. Runs once after the framework is up
# (needs pm), as a one-shot service so init doesn't block. No Play Store.
service miku_preload /system/bin/sh /system/etc/miku_preload_apks.sh
    class late_start
    user system
    group system shell
    disabled
    oneshot
    seclabel u:r:shell:s0

on property:sys.boot_completed=1
    start miku_preload
PRELOADRCEOF
debugfs -w -R "rm system/etc/init/miku_preload.rc" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "write $TMP_PRELOAD_RC system/etc/init/miku_preload.rc" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "set_inode_field system/etc/init/miku_preload.rc mode 0100644" "$OUTPUT_DIR/system.img" 2>/dev/null || true
label "$OUTPUT_DIR/system.img" system/etc/init/miku_preload.rc u:object_r:system_file:s0
rm -f "$TMP_PRELOAD_RC"

# Inject Device Identity, MTP & ADB defaults into system/build.prop
TMP_PROP="/tmp/miku_build.prop"
debugfs -R "cat system/build.prop" "$OUTPUT_DIR/system.img" > "$TMP_PROP" 2>/dev/null || true

# Sed replace stock secure flags and model identity
sed -i 's/^ro.secure=.*/ro.secure=0/' "$TMP_PROP"
sed -i 's/^ro.adb.secure=.*/ro.adb.secure=1/' "$TMP_PROP"
sed -i 's/^ro.debuggable=.*/ro.debuggable=1/' "$TMP_PROP"
sed -i 's/^ro.force.debuggable=.*/ro.force.debuggable=1/' "$TMP_PROP"
sed -i "s/^ro.product.model=.*/ro.product.model=${DEVICE_IDENTITY}/" "$TMP_PROP"
sed -i "s/^ro.product.system.model=.*/ro.product.system.model=${DEVICE_IDENTITY}/" "$TMP_PROP"
sed -i "s/^ro.product.name=.*/ro.product.name=m500_mikuOS/" "$TMP_PROP"
sed -i "s/^ro.product.system.name=.*/ro.product.system.name=m500_mikuOS/" "$TMP_PROP"
sed -i "s/^ro.product.device=.*/ro.product.device=m500_mikuOS/" "$TMP_PROP"
sed -i "s/^ro.product.system.device=.*/ro.product.system.device=m500_mikuOS/" "$TMP_PROP"
sed -i "s/^ro.build.display.id=.*/ro.build.display.id=${DEVICE_IDENTITY}/" "$TMP_PROP"
sed -i "s/^ro.build.version.incremental=.*/ro.build.version.incremental=${DEVICE_IDENTITY}/" "$TMP_PROP"
sed -i "s/^ro.build.id=.*/ro.build.id=m500_mikuOS/" "$TMP_PROP"

cat << PROPS >> "$TMP_PROP"

# ========================================================
# MikuOS Device Identity & Host Reporting (MTP / USB / OS / ADB)
# ========================================================
ro.product.model=${DEVICE_IDENTITY}
ro.product.system.model=${DEVICE_IDENTITY}
ro.product.vendor.model=${DEVICE_IDENTITY}
ro.product.product.model=${DEVICE_IDENTITY}
ro.product.system_ext.model=${DEVICE_IDENTITY}
ro.product.odm.model=${DEVICE_IDENTITY}
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

# ========================================================
# MikuOS Display Scaling & Legibility Defaults (4-inch DAP)
# ========================================================
ro.sf.lcd_density=360
persist.sys.display_density=360

# ========================================================
# MikuOS Development & Connectivity Defaults
# ========================================================
persist.sys.usb.config=mtp,adb
persist.service.adb.enable=1
persist.service.debuggable=1
ro.debuggable=1
# adb requires an authorized key even on dev builds: /adb_keys carries the build host's key,
# so the dev PC stays authorized and nobody else on the Wi-Fi gets an unauthenticated shell.
ro.adb.secure=1
service.adb.root=1
# Wireless adb, so pulling the USB cable does not end the session.
#
# BOTH keys are set deliberately. adbd reads service.adb.tcp.port, and persist.adb.tcp.port is
# the one that survives across boots; which of the two a given build honours has moved around
# between AOSP releases, and setting both costs one line and removes the question. adbd keeps
# the USB interface at the same time, so the device is reachable either way and swapping
# between them mid-session costs nothing.
#
# The host key is pre-authorized (see the /adb_keys bake), so a wireless connection does not
# sit waiting on an on-screen "Allow USB debugging" prompt nobody is there to tap.
persist.adb.tcp.port=5555
service.adb.tcp.port=5555

# ========================================================
# MikuOS Boot Experience (welcome-voice + locale defaults)
# ========================================================
# HiBy's libbootanimation.so plays the audio track of
# /vendor/media/bootanimation_<locale>.mp4 only when this gate prop is truthy.
# The lib links android::base::GetBoolProperty, so "1" enables it.
# (Value confirmed as a valid boolean; that this specific prop is read via the
# boolean reader is inferred, not disassembly-verified.)
persist.sys.customanim.boot.sounds=1
# libbootanimation.so selects bootanimation_<persist.sys.locale>.mp4; default to
# the English variant on a factory-fresh boot.
persist.sys.locale=en-US

# ========================================================
# MikuOS Audio: no safe-media-volume ceiling on a DAP
# ========================================================
# AudioService caps incremental (hardware knob/key) volume raises at the "safe
# headphone" index and silently swallows raises past it — on the M500 that read
# as "the roller has an arbitrary top the GUI doesn't". This is an audiophile
# DAP with its own analog gain staging; bypass the framework nanny entirely.
audio.safemedia.bypass=true
ro.audio.safemedia.bypass=true

# ========================================================
# Disable RescueParty (prevents the GMS-crash boot loop)
# ========================================================
# This device's bundled GMS (accountsettings SafetyCenter module) throws a benign
# SecurityException on READ/SEND_SAFETY_CENTER_* -- a signature-protected permission
# GMS cannot hold (it is allowlisted in privapp-permissions-google.xml but granted=false
# because GMS is not platform-signed). It fires on EVERY boot, stock and custom. On a
# FRESH image flash it crashes fast/often enough during boot (the Fi APN spins up GMS's
# carrier/Fi modules earlier) that RescueParty escalates to a reboot -> boot loop
# (verified: sys.boot.reason=reboot,rescueparty, only com.google.android.gms in dropbox).
# The crash is cosmetic (GMS retries post-boot), so disable RescueParty so a benign app
# crash can never reboot-loop the device. Recovery net remains: recovery adb -> fastboot.
persist.sys.disable_rescue=true
persist.device_config.configuration.disable_rescue_party=true

# ========================================================
# AUDIO LOCKDOWN — highest-quality-by-default, NO low-res delivery (user directive 2026-08-27)
# ========================================================
# Bluetooth A2DP: default every codec knob to its maximum. LDAC pinned to 990kbps and its
# adaptive-bitrate (which silently drops to 660/330 on a weak link) DISABLED, so BT never
# self-lowers without the explicit in-OS confirmation. aptX-HD/Adaptive enabled; plain SBC/AAC
# stay available only as last-resort sink compatibility, never as a preferred downgrade.
persist.bluetooth.a2dp.ldac.quality=1000
persist.bluetooth.ldac.quality=1000
persist.vendor.bt.a2dp.ldac.quality=1000
persist.vendor.qcom.bluetooth.ldac_abr=false
persist.vendor.qcom.bluetooth.enable.splita2dp=true
persist.vendor.qcom.bluetooth.aptxadaptive_support=true
persist.vendor.bt.a2dp.aptx_hd=true
persist.bluetooth.bluetooth_audio_hal.disabled=false
# Absolute-volume can push some sinks into a lower-fidelity mode; leave BT volume native.
persist.bluetooth.disableabsvol=false
# Miku-side lockdown flags read by MikuAudioLockdown at boot (enforcer re-applies the max codec;
# a lower codec/bitrate requires miku_bt_quality_unlock_confirm=1 set by the confirm dialog).
persist.sys.miku.audio_lockdown=1
PROPS
# Release build: drop every debug/adb line above (and the stock-replacing seds) and put back the
# stock secure values. ro.* is first-set-wins across files, so the old lines are deleted, not shadowed.
if [ "$MIKUOS_RELEASE" = "1" ]; then
    sed -i -e '/^ro\.secure=/d' -e '/^ro\.adb\.secure=/d' -e '/^ro\.debuggable=/d' -e '/^ro\.force\.debuggable=/d' \
        -e '/^persist\.sys\.usb\.config=/d' -e '/^persist\.service\.adb\.enable=/d' -e '/^persist\.service\.debuggable=/d' \
        -e '/^service\.adb\.root=/d' -e '/^persist\.adb\.tcp\.port=/d' -e '/^service\.adb\.tcp\.port=/d' "$TMP_PROP"
    cat >> "$TMP_PROP" << 'RELPROPS'

# MikuOS release build (MIKUOS_RELEASE=1)
ro.secure=1
ro.adb.secure=1
ro.debuggable=0
ro.force.debuggable=0
persist.sys.usb.config=mtp
ro.miku.release=1
RELPROPS
else
    echo "ro.miku.release=0" >> "$TMP_PROP"
fi
# build.prop already exists -> must rm before write (debugfs won't overwrite).
dfput "$OUTPUT_DIR/system.img" "$TMP_PROP" "system/build.prop" \
    || { echo "!! FATAL: could not write system/build.prop (adb.secure/usb config would be stock)"; exit 1; }
label "$OUTPUT_DIR/system.img" system/build.prop u:object_r:system_file:s0
rm -f "$TMP_PROP"

# Patch vendor.img build.prop for ADB authorization and device identity
TMP_VEN_PROP="/tmp/miku_vendor_build.prop"
debugfs -R "cat build.prop" "$OUTPUT_DIR/vendor.img" > "$TMP_VEN_PROP" 2>/dev/null || true
sed -i 's/^ro.adb.secure=.*/ro.adb.secure=1/' "$TMP_VEN_PROP"
sed -i "s/^ro.product.vendor.model=.*/ro.product.vendor.model=${DEVICE_IDENTITY}/" "$TMP_VEN_PROP"
sed -i "s/^ro.product.vendor.name=.*/ro.product.vendor.name=m500_mikuOS/" "$TMP_VEN_PROP"
sed -i "s/^ro.product.vendor.device=.*/ro.product.vendor.device=m500_mikuOS/" "$TMP_VEN_PROP"
sed -i "s/^ro.vendor.product.model=.*/ro.vendor.product.model=${DEVICE_IDENTITY}/" "$TMP_VEN_PROP"
sed -i "s/^ro.product.model=.*/ro.product.model=${DEVICE_IDENTITY}/" "$TMP_VEN_PROP"

cat << VENPROPS >> "$TMP_VEN_PROP"
ro.product.model=${DEVICE_IDENTITY}
ro.product.vendor.model=${DEVICE_IDENTITY}
bluetooth.device.default_name=${DEVICE_IDENTITY}
ro.bluetooth.name=${DEVICE_IDENTITY}
persist.vendor.usb.product_string=${DEVICE_IDENTITY}
vendor.usb.product_string=${DEVICE_IDENTITY}
persist.vendor.usb.config=mtp,adb
vendor.usb.config=mtp,adb
VENPROPS
if [ "$MIKUOS_RELEASE" = "1" ]; then
    sed -i -e 's/^ro\.adb\.secure=.*/ro.adb.secure=1/' -e 's/^persist\.vendor\.usb\.config=.*/persist.vendor.usb.config=mtp/' \
        -e 's/^vendor\.usb\.config=.*/vendor.usb.config=mtp/' "$TMP_VEN_PROP"
fi
# Cross-window background blur for the SystemUI shade and the other glass surfaces. HiBy ships
# without it (the prop was unset on 0.1.16), so FLAG_BLUR_BEHIND / setBackgroundBlurRadius did
# nothing and the "glass" was flat. SurfaceFlinger does the blur on the GPU (Adreno here); if it
# costs frames on this part, set MIKU_BLUR=0 to build without it.
if [ "${MIKU_BLUR:-1}" = "1" ]; then
    sed -i '/^ro.surface_flinger.supports_background_blur=/d' "$TMP_VEN_PROP"
    echo "ro.surface_flinger.supports_background_blur=1" >> "$TMP_VEN_PROP"
fi

dfput "$OUTPUT_DIR/vendor.img" "$TMP_VEN_PROP" "build.prop" \
    || { echo "!! FATAL: could not write vendor/build.prop"; exit 1; }
label "$OUTPUT_DIR/vendor.img" build.prop u:object_r:vendor_file:s0
rm -f "$TMP_VEN_PROP"

# Inject init RC to force ADB online unconditionally at early-init, init, post-fs-data, and boot
TMP_RC="/tmp/miku_adb.rc"
cat << 'RCEOF' > "$TMP_RC"
on early-init
    setprop ro.adb.secure 1
    setprop ro.secure 0
    setprop ro.debuggable 1
    # Welcome boot audio (set early, before bootanimation, since debugfs can't overwrite build.prop).
    setprop persist.sys.customanim.boot.sounds 1
    setprop persist.sys.locale en-US

on init
    setprop persist.sys.usb.config mtp,adb
    setprop persist.vendor.usb.config mtp,adb
    setprop persist.service.adb.enable 1
    setprop persist.service.debuggable 1
    setprop service.adb.root 1

on post-fs-data
    setprop persist.sys.usb.config mtp,adb
    setprop persist.vendor.usb.config mtp,adb
    setprop sys.usb.config mtp,adb
    setprop vendor.usb.config mtp,adb
    # Seed the pre-authorized host adb key into /data (wiped on fresh flash) before adbd starts,
    # so no "Allow USB debugging?" prompt is needed.
    mkdir /data/misc 0771 system system
    mkdir /data/misc/adb 0750 system shell
    copy /system/etc/miku_adb_keys /data/misc/adb/adb_keys
    chown system shell /data/misc/adb/adb_keys
    mkdir /data/adb 0700 root root
    mkdir /data/adb/post-fs-data.d 0755 root root
    mkdir /data/adb/service.d 0755 root root
    copy /system/etc/miku_root_boot.sh /data/adb/post-fs-data.d/00-miku-root.sh
    chmod 0755 /data/adb/post-fs-data.d/00-miku-root.sh
    copy /system/etc/miku_root_boot.sh /data/adb/service.d/00-miku-root.sh
    chmod 0755 /data/adb/service.d/00-miku-root.sh
    chmod 0640 /data/misc/adb/adb_keys
    restorecon_recursive /data/misc/adb
    start adbd

on boot
    setprop persist.sys.usb.config mtp,adb
    setprop persist.vendor.usb.config mtp,adb
    setprop sys.usb.config mtp,adb
    setprop vendor.usb.config mtp,adb
    setprop sys.usb.state mtp,adb
    start adbd
# (A boot_completed `exec_background - root root -- sh miku_root_boot.sh` used to sit here. On
# this enforcing build init cannot run it, so it never ran. The service.d seed above only takes
# effect if Magisk is installed; release builds drop both.)
RCEOF
# Release build: same file names (the bake gate below checks them), none of the adb forcing, no
# root seed. The persist resets undo what a dev build left in /data, so an image flashed over a
# dev install without a wipe does not keep adb over Wi-Fi. (A dev host key already copied to
# /data/misc/adb stays authorized until a wipe; release installs are expected to wipe.)
if [ "$MIKUOS_RELEASE" = "1" ]; then
    cat << 'RELRCEOF' > "$TMP_RC"
on early-init
    setprop persist.sys.customanim.boot.sounds 1
    setprop persist.sys.locale en-US

on property:persist.adb.tcp.port=5555
    setprop persist.adb.tcp.port 0

on property:persist.sys.usb.config=mtp,adb
    setprop persist.sys.usb.config mtp
RELRCEOF
fi

debugfs -w -R "write $TMP_RC system/etc/init/miku_adb.rc" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "set_inode_field system/etc/init/miku_adb.rc mode 0100644" "$OUTPUT_DIR/system.img" 2>/dev/null || true
label "$OUTPUT_DIR/system.img" system/etc/init/miku_adb.rc u:object_r:system_file:s0
debugfs -w -R "write $TMP_RC etc/init/miku_vendor_adb.rc" "$OUTPUT_DIR/vendor.img" 2>/dev/null || true
debugfs -w -R "set_inode_field etc/init/miku_vendor_adb.rc mode 0100644" "$OUTPUT_DIR/vendor.img" 2>/dev/null || true
label "$OUTPUT_DIR/vendor.img" etc/init/miku_vendor_adb.rc u:object_r:vendor_file:s0

# ============================================================================
# FRONT PULSAR INDICATOR — turn the vendor's standby glow OFF.
#
# The solid blue light is NOT ours and is NOT an activity indicator. HiBy's
# /vendor/etc/init/hw/init.hiby.led.rc does, at boot:
#     setprop vendor.audio.hiby.hw.led on
#     setprop vendor.audio.hiby.hw.sample_quality none
#     setprop vendor.audio.hiby.charging no
# and its rule  led=on && sample_quality=none && charging=no  writes
# `led_pattern 1` — the steady blue "powered, nothing special playing" state.
# On stock, HiBy Music updated sample_quality per track so the colour tracked the
# format (2 low / 3 standard / 4 high / 5 DSD / 8 MQA / 9 MQA-Studio / 10 MQB,
# 6-7 charging). MikuOS replaced HiBy Music, so nothing updates it any more and it
# is pinned on "none" — a light that says nothing, forever.
#
# No app can change this: /sys/class/leds is SELinux-denied to apps, and
# LightsManager reports zero lights even with CONTROL_DEVICE_LIGHTS granted
# (verified 2026-09-13). Only init may write vendor_audio_prop — hence this rc.
# The vendor's own led=off rule writes `led_pattern 0`, which is the real off.
#
# To make the light MEANINGFUL instead of off, set sample_quality per track from a
# privileged context rather than removing this — see the pattern map above.
# ============================================================================
TMP_LED_RC="$(mktemp)"
cat > "$TMP_LED_RC" <<'LEDRCEOF'
# MikuOS: silence the vendor standby glow (see build_mikuos_super.sh for why).
on property:sys.boot_completed=1
    setprop vendor.audio.hiby.hw.led off
LEDRCEOF
debugfs -w -R "rm etc/init/miku_led.rc" "$OUTPUT_DIR/vendor.img" 2>/dev/null || true
debugfs -w -R "write $TMP_LED_RC etc/init/miku_led.rc" "$OUTPUT_DIR/vendor.img" 2>/dev/null || true
debugfs -w -R "set_inode_field etc/init/miku_led.rc mode 0100644" "$OUTPUT_DIR/vendor.img" 2>/dev/null || true
label "$OUTPUT_DIR/vendor.img" etc/init/miku_led.rc u:object_r:vendor_file:s0
rm -f "$TMP_LED_RC"

# ============================================================================
# DAC controls that reach hardware (mikuos/docs/hiby-audio-knobs.md). Of the 31 nodes in
# /sys/devices/platform/sa_sound_setting only high_power_mode, dre_mode, digital_filter and gain
# change anything on the M500. Stock feeds the first three from a boot service that skips any
# model not named "M500", so on MikuOS nothing ever reached them and the DAC sat on driver
# defaults. com.miku.sysbridge (system_app, allowed to set vendor_audio_prop) sets the
# persist.vendor.audio.miku.* properties from a fixed whitelist; init writes the node on every
# change and again at each boot, because persist properties re-fire their triggers. With nothing
# set the driver defaults stand: low power, DRE off, fast roll-off low latency, 0 dB.
# Never add dac_type here: its store returns 0 bytes written and loops the writer.
# ============================================================================
TMP_AUDIO_RC="$(mktemp)"
cat > "$TMP_AUDIO_RC" <<'AUDIORCEOF'
# MikuOS: DAC settings from Miku Music, via com.miku.sysbridge (see build_mikuos_super.sh).
on property:persist.vendor.audio.miku.high_power=*
    write /sys/devices/platform/sa_sound_setting/high_power_mode ${persist.vendor.audio.miku.high_power}
on property:persist.vendor.audio.miku.dre_mode=*
    write /sys/devices/platform/sa_sound_setting/dre_mode ${persist.vendor.audio.miku.dre_mode}
on property:persist.vendor.audio.miku.digital_filter=*
    write /sys/devices/platform/sa_sound_setting/digital_filter ${persist.vendor.audio.miku.digital_filter}
on property:persist.vendor.audio.miku.gain=*
    write /sys/devices/platform/sa_sound_setting/gain ${persist.vendor.audio.miku.gain}
AUDIORCEOF
debugfs -w -R "rm etc/init/miku_audio.rc" "$OUTPUT_DIR/vendor.img" 2>/dev/null || true
debugfs -w -R "write $TMP_AUDIO_RC etc/init/miku_audio.rc" "$OUTPUT_DIR/vendor.img" 2>/dev/null || true
debugfs -w -R "set_inode_field etc/init/miku_audio.rc mode 0100644" "$OUTPUT_DIR/vendor.img" 2>/dev/null || true
label "$OUTPUT_DIR/vendor.img" etc/init/miku_audio.rc u:object_r:vendor_file:s0
rm -f "$TMP_AUDIO_RC"
# Charge limit: com.miku.sysbridge's ChargeLimiter sets vendor.usb.miku.charge_hold while plugged
# in at or above the limit set in MikuSettings, and clears it 5% below or on unplug. The mp2731
# charger has no charge-disable node, so a hold drops it to its lowest input current (~100 mA).
TMP_CHARGE_RC="$(mktemp)"
cat > "$TMP_CHARGE_RC" <<'CHARGERCEOF'
# MikuOS: charge limit hold, set by com.miku.sysbridge (see build_mikuos_super.sh).
# The writes run in /vendor/bin/sh, which init starts as vendor_qti_init_shell; the image's
# vendor policy lets that domain write these two nodes (nothing could before).
on property:vendor.usb.miku.charge_hold=1
    exec_background - root system -- /vendor/bin/sh -c "echo 100000 > /sys/class/power_supply/mp2731-charger/input_current_limit; echo 0 > /sys/class/power_supply/mp2731-charger/charge_control_limit"
on property:vendor.usb.miku.charge_hold=0
    exec_background - root system -- /vendor/bin/sh -c "echo 2000000 > /sys/class/power_supply/mp2731-charger/input_current_limit; echo 4000000 > /sys/class/power_supply/mp2731-charger/charge_control_limit"
CHARGERCEOF
debugfs -w -R "rm etc/init/miku_charge.rc" "$OUTPUT_DIR/vendor.img" 2>/dev/null || true
debugfs -w -R "write $TMP_CHARGE_RC etc/init/miku_charge.rc" "$OUTPUT_DIR/vendor.img" 2>/dev/null || true
debugfs -w -R "set_inode_field etc/init/miku_charge.rc mode 0100644" "$OUTPUT_DIR/vendor.img" 2>/dev/null || true
label "$OUTPUT_DIR/vendor.img" etc/init/miku_charge.rc u:object_r:vendor_file:s0
rm -f "$TMP_CHARGE_RC"

# SELinux: the charger nodes are sysfs_batteryinfo, which no domain may write, so a charge limit
# was impossible. One rule lets vendor_qti_init_shell (what init runs /vendor/bin/sh as) write
# them. The rule goes into the vendor policy source, and the plat hash in system.img gets a marker
# first line so it no longer matches odm's precompiled policy, which makes init compile the policy from
# source at boot (the same path a GSI boots on). Checked: compiles with the same flags init uses,
# and adds no neverallow failures beyond the 105 the stock vendor policy already has.
_T="$(mktemp -d)"
debugfs -R "dump etc/selinux/vendor_sepolicy.cil $_T/v.cil" "$OUTPUT_DIR/vendor.img" 2>/dev/null
if [ -s "$_T/v.cil" ] && ! grep -q "MikuOS: charge limit" "$_T/v.cil"; then
    printf '\n; MikuOS: charge limit (miku_charge.rc)\n(allow vendor_qti_init_shell sysfs_batteryinfo_33_0 (file (write open getattr)))\n' >> "$_T/v.cil"
    dfput "$OUTPUT_DIR/vendor.img" "$_T/v.cil" etc/selinux/vendor_sepolicy.cil \
        || { echo "  !! could not write vendor_sepolicy.cil"; exit 1; }
    debugfs -w -R "set_inode_field etc/selinux/vendor_sepolicy.cil mode 0100644" "$OUTPUT_DIR/vendor.img" >/dev/null 2>&1
    label "$OUTPUT_DIR/vendor.img" etc/selinux/vendor_sepolicy.cil u:object_r:vendor_configs_file:s0
    debugfs -R "dump system/etc/selinux/plat_sepolicy_and_mapping.sha256 $_T/h" "$OUTPUT_DIR/system.img" 2>/dev/null
    # init compares only the FIRST line with odm's copy, so the marker goes first.
    if ! grep -q mikuos "$_T/h"; then
        { echo "mikuos-vendor-policy-changed-compile-on-device"; cat "$_T/h"; } > "$_T/h2"; mv "$_T/h2" "$_T/h"
    fi
    dfput "$OUTPUT_DIR/system.img" "$_T/h" system/etc/selinux/plat_sepolicy_and_mapping.sha256 \
        || { echo "  !! could not write plat_sepolicy_and_mapping.sha256"; exit 1; }
    debugfs -w -R "set_inode_field system/etc/selinux/plat_sepolicy_and_mapping.sha256 mode 0100644" "$OUTPUT_DIR/system.img" >/dev/null 2>&1
    label "$OUTPUT_DIR/system.img" system/etc/selinux/plat_sepolicy_and_mapping.sha256 u:object_r:system_file:s0
    echo "  -> vendor policy: charge-limit rule added, policy compiles on device"
fi
rm -rf "$_T"
rm -f "$TMP_RC"

# Pre-authorize THIS build host's adb key so a fresh /data wipe never shows the
# "Allow USB debugging?" prompt (ro.adb.secure=0 alone proved unreliable on this vendor build).
# adbd reads /adb_keys at startup (read-only, no timing race) and also watches
# /data/misc/adb/adb_keys, which miku_adb.rc's post-fs-data seeds from the baked copy below.
ADB_KEY="$SCRIPT_DIR/adb_keys"
if [ "$MIKUOS_RELEASE" = "1" ]; then
    echo "  -- Release build: no pre-authorized adb key"
elif [ -f "$ADB_KEY" ]; then
    debugfs -w -R "write $ADB_KEY adb_keys" "$OUTPUT_DIR/system.img" 2>/dev/null || true
    debugfs -w -R "set_inode_field adb_keys mode 0100644" "$OUTPUT_DIR/system.img" 2>/dev/null || true
    label "$OUTPUT_DIR/system.img" adb_keys u:object_r:adb_keys_file:s0
    debugfs -w -R "write $ADB_KEY system/etc/miku_adb_keys" "$OUTPUT_DIR/system.img" 2>/dev/null || true
    debugfs -w -R "set_inode_field system/etc/miku_adb_keys mode 0100644" "$OUTPUT_DIR/system.img" 2>/dev/null || true
    label "$OUTPUT_DIR/system.img" system/etc/miku_adb_keys u:object_r:system_file:s0
    echo "  -> Pre-authorized host adb key (/adb_keys + /system/etc/miku_adb_keys seed)"
fi

# Bake the MikuOS root auto-config (pre-grants su to MikuOS apps + shell, mutes su popups, kills the
# AOSP volume dialog via a fabricated overlay, dumps boot-audio diagnostics). miku_*.rc seeds it into
# Magisk's service.d and kicks it in the magisk context at boot_completed.
ROOT_SH="$SCRIPT_DIR/miku_root_boot.sh"
if [ "$MIKUOS_RELEASE" = "1" ]; then
    echo "  -- Release build: no root auto-config"
elif [ -f "$ROOT_SH" ]; then
    debugfs -w -R "rm system/etc/miku_root_boot.sh" "$OUTPUT_DIR/system.img" 2>/dev/null || true
    debugfs -w -R "write $ROOT_SH system/etc/miku_root_boot.sh" "$OUTPUT_DIR/system.img" 2>/dev/null || true
    debugfs -w -R "set_inode_field system/etc/miku_root_boot.sh mode 0100755" "$OUTPUT_DIR/system.img" 2>/dev/null || true
    label "$OUTPUT_DIR/system.img" system/etc/miku_root_boot.sh u:object_r:system_file:s0
    echo "  -> Baked MikuOS root auto-config (/system/etc/miku_root_boot.sh + service.d seed)"
fi

# Inject init RC to configure the default soft keyboard (IME) at first boot.
# With SetupWizard/Provision debloated nothing seeds Settings.Secure
# default_input_method / enabled_input_methods, so the soft keyboard never
# appears (e.g. can't type a Wi-Fi password). The IME apk (LatinIME) IS present
# at product/app/LatinIME and is NOT debloated. Component confirmed from the
# APK manifest: package com.android.inputmethod.latin, IME service class
# com.android.inputmethod.latin.LatinIME -> component
# "com.android.inputmethod.latin/.LatinIME".
# `settings` talks to SettingsProvider over binder, so it can only run once the
# framework is up: trigger on sys.boot_completed=1 (not `on boot`) and run the
# commands async via exec_background so init never blocks.
TMP_IME_RC="/tmp/miku_ime.rc"
cat << 'IMERCEOF' > "$TMP_IME_RC"
# MikuOS: intentionally empty.
# This file used to run settings, pm, appops, cmd, am, svc and sh through exec_background at
# sys.boot_completed=1. On a user build with SELinux enforcing, init refuses those execs:
# /system/bin/sh is shell_exec and the others are system_file, and the policy has no transition
# from init for either (only toolbox_exec). None of it ever ran.
# com.miku.sysbridge (BootSeeds.kt) applies the same items now, as the system uid.
# cmd lock_settings set-disabled belongs to the Miku lockscreen. The SGM31324 LED chmod is gone:
# apps cannot open those nodes under enforcing SELinux whatever the mode bits are.
IMERCEOF
debugfs -w -R "write $TMP_IME_RC system/etc/init/miku_ime.rc" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "set_inode_field system/etc/init/miku_ime.rc mode 0100644" "$OUTPUT_DIR/system.img" 2>/dev/null || true
label "$OUTPUT_DIR/system.img" system/etc/init/miku_ime.rc u:object_r:system_file:s0
rm -f "$TMP_IME_RC"

# CPU power profiles: Miku Music's MikuPowerGovernor publishes Settings.Global miku_power_profile
# (perf / balanced / audio_only / idle), com.miku.sysbridge mirrors it into
# vendor.usb.miku.power_profile, and miku_powerd.rc writes the CPU cluster caps. The audio path is
# never touched; it only starves the app cores when the screen is off and music plays.
# Source: mikuos/build/powerd/miku_powerd.rc.
POWERD_DIR="$MIKUOS_DIR/build/powerd"
if [ -f "$POWERD_DIR/miku_powerd.rc" ]; then
    debugfs -w -R "rm system/etc/miku_powerd.sh" "$OUTPUT_DIR/system.img" >/dev/null 2>&1 || true
    dfput "$OUTPUT_DIR/system.img" "$POWERD_DIR/miku_powerd.rc" system/etc/init/miku_powerd.rc \
        && label "$OUTPUT_DIR/system.img" system/etc/init/miku_powerd.rc u:object_r:system_file:s0 \
        && echo "  -> Injected MikuOS CPU power profile triggers" \
        || echo "  !! miku_powerd.rc inject failed"
else
    echo "  !! mikuos/build/powerd/ missing — no CPU power profiles in this image"
fi

# Optional dev Wi-Fi pre-seed, read on first boot by MikuWifiVault / onboarding
# (WifiManager.addNetwork). The credentials come from an UNTRACKED file next to
# this script, os/mikuos-dev-wifi.conf (gitignored), with two keys:
#   ssid_match=<substring of the SSID to connect to>
#   psk=<the passphrase>
# If the file is absent the step is skipped and the image ships with no
# pre-seeded network. Never put a real PSK in this script.
DEV_WIFI_CONF="$(dirname "$0")/mikuos-dev-wifi.conf"
if [ "$MIKUOS_RELEASE" = "1" ]; then
    echo "  -- Release build: no dev Wi-Fi pre-seed"
elif [ -f "$DEV_WIFI_CONF" ]; then
    debugfs -w -R "write $DEV_WIFI_CONF system/etc/mikuos-dev-wifi.conf" "$OUTPUT_DIR/system.img" 2>/dev/null || true
    debugfs -w -R "set_inode_field system/etc/mikuos-dev-wifi.conf mode 0100644" "$OUTPUT_DIR/system.img" 2>/dev/null || true
    label "$OUTPUT_DIR/system.img" system/etc/mikuos-dev-wifi.conf u:object_r:system_file:s0
    echo "  -> Injected dev Wi-Fi pre-seed from $DEV_WIFI_CONF"
else
    echo "  -- No os/mikuos-dev-wifi.conf; image ships without a pre-seeded network"
fi

# Platform re-key: swap every AOSP public-test-key signature for the MikuOS
# custom key set, in place inside each partition image.
#
# REKEY_MODE=debugfs (DEFAULT): rekey_debugfs.sh — rdump the tree, re-sign on the
#   host copy, dfput only the changed files back (label + mode restored, every
#   inode verified). No mount, no sudo. Images are already unshare_blocks'd by [2].
# REKEY_MODE=mount (LEGACY, DO NOT SHIP): the old rw loop-mount path. Proven to
#   corrupt images intermittently — the REKEY_NOOP=1 bisection (mount+umount only,
#   re-signs nothing) hangs on the boot splash exactly like the real re-key did.
#   Kept only for reproducing that result.
REKEY_MODE="${REKEY_MODE:-debugfs}"
if [ "$REKEY" = "1" ] && [ "$REKEY_MODE" = "debugfs" ]; then
    echo "[5b] Platform re-key (debugfs path): replacing AOSP public test keys with MikuOS keys..."
    REKEY_LOG="$OUTPUT_DIR/rekey_$(date +%Y%m%d_%H%M%S).log"
    echo "[rekey] Persistent log: $REKEY_LOG" | tee -a "$REKEY_LOG"
    if [ "$REKEY_NOOP" = "1" ]; then
        echo "  -> REKEY_NOOP=1 has no meaning on the debugfs path (nothing to bisect); skipping re-key" | tee -a "$REKEY_LOG"
    else
        for _part in system system_ext product vendor; do
            _img="$OUTPUT_DIR/$_part.img"
            [ -f "$_img" ] || continue
            echo "  -> [$_part] rekey_debugfs.sh starting..." | tee -a "$REKEY_LOG"
            APKSIGNER="$APKSIGNER" WORK_DIR="$OUTPUT_DIR" "$SCRIPT_DIR/rekey_debugfs.sh" "$_img" >>"$REKEY_LOG" 2>&1 \
                || { echo "  !! re-key failed: $_part — see $REKEY_LOG"; tail -15 "$REKEY_LOG"; exit 1; }
            grep "^\[rekey:$_part\] wrote back" "$REKEY_LOG" | tail -1 | sed 's/^/     /'
            echo "  -> [$_part] re-key complete" | tee -a "$REKEY_LOG"
        done
    fi
    echo "  Platform re-key complete."
elif [ "$REKEY" = "1" ]; then
    echo "[5b] Platform re-key: replacing AOSP public test keys with MikuOS keys..."
    REKEY_LOG="$OUTPUT_DIR/rekey_$(date +%Y%m%d_%H%M%S).log"
    echo "[rekey] Persistent log: $REKEY_LOG" | tee -a "$REKEY_LOG"
    REKEY_MNT="$(mktemp -d)"
    for _part in system system_ext product vendor; do
        _img="$OUTPUT_DIR/$_part.img"
        [ -f "$_img" ] || continue
        echo "  -> $_part.img: un-share blocks + mount + re-sign"
        e2fsck -fy "$_img" >>"$REKEY_LOG" 2>&1 || true
        # Add slack space (shrink-safe, shrunk with resize2fs -M later) so
        # unshare_blocks has room to un-dedupe without hitting disk full / read-only fallback.
        if [ "$_part" = "vendor" ] || [ "$_part" = "system_ext" ] || [ "$_part" = "product" ]; then
            truncate -s +256M "$_img"
            resize2fs "$_img" >>"$REKEY_LOG" 2>&1 || true
        fi
        echo "  -> [$_part] unshare_blocks starting..." | tee -a "$REKEY_LOG"
        e2fsck -fy -E unshare_blocks "$_img" >>"$REKEY_LOG" 2>&1 || { echo "  !! unshare_blocks failed: $_part (exit $?)" | tee -a "$REKEY_LOG"; exit 1; }
        echo "  -> [$_part] mount starting..." | tee -a "$REKEY_LOG"
        sudo mount -o loop,rw "$_img" "$REKEY_MNT" >>"$REKEY_LOG" 2>&1 || { echo "  !! rw mount failed: $_part (exit $?)" | tee -a "$REKEY_LOG"; exit 1; }
        if [ "$REKEY_NOOP" = "1" ]; then
            echo "  -> [$_part] REKEY_NOOP=1: skipping re-sign + mac_permissions (mount-mechanics bisection)" | tee -a "$REKEY_LOG"
        else
            echo "  -> [$_part] re-sign starting..." | tee -a "$REKEY_LOG"
            sudo env APKSIGNER="$APKSIGNER" JAVA_HOME="${JAVA_HOME:-}" PATH="$PATH" APPLY=1 \
                "$RESIGN_SH" "$REKEY_MNT" >>"$REKEY_LOG" 2>&1 || { sync; sudo umount "$REKEY_MNT"; echo "  !! re-sign failed: $_part (exit $?)" | tee -a "$REKEY_LOG"; exit 1; }
            # Repoint mac_permissions.xml cert pins at our new keys, or the re-signed
            # platform apps get the wrong SELinux seinfo/domain and the device hangs.
            echo "  -> [$_part] patch_mac_permissions starting..." | tee -a "$REKEY_LOG"
            sudo env PATH="$PATH" "$SCRIPT_DIR/patch_mac_permissions.sh" "$REKEY_MNT" \
                >>"$REKEY_LOG" 2>&1 || { sync; sudo umount "$REKEY_MNT"; echo "  !! mac_permissions patch failed: $_part (exit $?)" | tee -a "$REKEY_LOG"; exit 1; }
        fi
        echo "  -> [$_part] umount starting..." | tee -a "$REKEY_LOG"
        sync; sudo umount "$REKEY_MNT" >>"$REKEY_LOG" 2>&1 || { echo "  !! umount failed: $_part (exit $?)" | tee -a "$REKEY_LOG"; exit 1; }
        echo "  -> [$_part] re-key complete" | tee -a "$REKEY_LOG"
    done
    rmdir "$REKEY_MNT"
    echo "  Platform re-key complete."
fi

# Verify filesystems
e2fsck -fy "$OUTPUT_DIR/system.img" || true
e2fsck -fy "$OUTPUT_DIR/vendor.img" || true
e2fsck -fy "$OUTPUT_DIR/system_ext.img" || true
e2fsck -fy "$OUTPUT_DIR/product.img" || true

# ============================================================================
# GATE: debugfs fails SILENTLY when a fs runs out of blocks — the inode gets its
# size but ZERO data blocks, and the file reads back as NULs on device (this
# shipped once: system.img hit 1 free block and adb/ime/preload rc all baked
# empty). Verify every critical injected file actually owns data blocks, and
# that each edited fs kept real headroom, before anything gets packed.
# ============================================================================
# [5b3] Re-sign AOSP-test-key APEX modules to Falcon (no AOSP-signed code inside APEX payloads).
# The media/networkstack seinfo pins are repointed to Falcon by patch_mac_permissions; the
# APEX-internal MediaProvider/TetheringNext/CellBroadcastServiceModule must be Falcon too or they
# lose seinfo=media/network_stack -> wrong domain -> FUSE/network break. resign_apex.sh skips any
# APEX with no AOSP-test-key inner apk (exit 2). See memory m500-apex-resign-pipeline.
# HARD GATE: hand-rebuilt APEXes are REJECTED by apexd -> bootloop (tested
# 2026-08-28, memory m500-apex-resign-pipeline: "do NOT re-attempt"). This step
# may only run when the media/networkstack pins are actually repointed
# (REKEY_ROLES includes media or networkstack) - i.e. an explicitly requested
# zero-AOSP experiment - never on a normal safe-roles build.
_apex_roles="${REKEY_ROLES:-platform releasekey shared}"
if [ "$REKEY" = "1" ] && { case " $_apex_roles " in (*" media "*|*" networkstack "*) true;; (*) false;; esac; }; then
    echo "[5b3] Re-signing AOSP-keyed APEX modules to Falcon..."
    export APEX_TOOLS="${APEX_TOOLS:-/mnt/aosp-out/out/host/linux-x86/bin}"
    if [ ! -x "$APEX_TOOLS/apexer" ]; then
        echo "  !! APEX host tools not found at $APEX_TOOLS — cannot re-sign APEXes (need /mnt/aosp-out). Skipping." >&2
    else
        APEX_LOG="$OUTPUT_DIR/apex_resign_$(date +%Y%m%d_%H%M%S).log"
        _sys="$OUTPUT_DIR/system.img"
        _apextmp="$(mktemp -d)"
        _apex_done=0
        for _cap in $(debugfs -R "ls -p /system/apex" "$_sys" 2>/dev/null | awk -F/ '$6 ~ /\.capex$/ {print $6}'); do
            debugfs -R "dump /system/apex/$_cap $_apextmp/$_cap" "$_sys" >>"$APEX_LOG" 2>&1 || continue
            if "$SCRIPT_DIR/resign_apex.sh" "$_apextmp/$_cap" "$_apextmp/new_$_cap" >>"$APEX_LOG" 2>&1; then
                debugfs -w -R "rm /system/apex/$_cap" "$_sys" >>"$APEX_LOG" 2>&1
                dfput "$_sys" "$_apextmp/new_$_cap" "system/apex/$_cap" >>"$APEX_LOG" 2>&1
                label "$_sys" "system/apex/$_cap" u:object_r:system_file:s0
                echo "  -> re-signed APEX: $_cap"
                _apex_done=$((_apex_done+1))
            fi
            rm -f "$_apextmp/$_cap" "$_apextmp/new_$_cap"
        done
        rm -rf "$_apextmp"
        echo "  APEX re-sign complete: $_apex_done module(s) re-keyed to Falcon (log: $APEX_LOG)."
        # GATE: no AOSP-test-key apk may remain inside any /system/apex payload.
        e2fsck -fy "$_sys" >/dev/null 2>&1 || true
    fi
fi

echo "[5b2] Removing stock apps that duplicate MikuOS or serve nothing on a DAP..."
# Each one here was checked on 0.1.16 (2026-10-09): no MikuOS code or build step references it,
# nothing in the OS depends on it, and it is either a UI that competes with a MikuOS one or a
# feature a music player has no use for. What is NOT here, on purpose:
#   SystemUI          the window manager needs it (status/nav bar insets, keyguard, shade);
#                     removing it bootloops. MikuOS hides it instead of replacing it.
#   Settings          hosts dialogs other apps and the OS launch (Bluetooth pairing PIN,
#                     battery-optimisation and overlay grants, device admin...). It goes once
#                     MikuSettings covers every one: mikuos/docs/settings-parity.md.
#   LatinIME          the first-boot keyboard this script seeds; without it a clean flash
#                     cannot type a Wi-Fi password.
#   DeskClock, Gallery2, Calculator, SoundRecorder, Calendar, Snapcam
#                     each is the only handler of an intent other apps use (set an alarm,
#                     view an image...). They go when a MikuOS app handles those intents.
debloat() {
    local img="$1" dir="$2" why="$3"
    if img_has "$OUTPUT_DIR/$img" "$dir"; then
        rm_tree "$OUTPUT_DIR/$img" "$dir"
        if img_has "$OUTPUT_DIR/$img" "$dir"; then
            echo "  !! $img:$dir still present"
        else
            echo "  -> removed $img:$dir ($why)"
        fi
    fi
}
debloat system.img     system/app/EasterEgg                "Android version easter egg"
debloat system.img     system/app/BasicDreams              "screensaver; MikuOS has its own AOD"
debloat system.img     system/app/BookmarkProvider         "browser bookmarks provider, no AOSP browser"
debloat product.img    app/PhotoTable                      "photo screensaver"
debloat product.img    app/RideModeAudio                   "Qualcomm ride-mode audio, unused"
debloat product.img    priv-app/SettingsIntelligence       "search for the stock Settings, which is hidden"
debloat system_ext.img priv-app/AccessibilityMenu          "a second floating menu over the MikuOS bars"
debloat system_ext.img priv-app/EmergencyInfo              "phone emergency-info card"
debloat vendor.img     app/HiByTest                        "HiBy factory test app"
debloat vendor.img     app/HiByM500Widget                  "HiBy home-screen widgets for their launcher"
# Hardware the image claims and the M500 does not have. Checked on 0.1.18 (2026-10-10): no NFC
# controller node and no NFC service, and the sensor list is an accelerometer, a magnetometer and
# Qualcomm's virtual sensors only (no gyro, barometer, proximity or light sensor), and one camera,
# facing back. These feature files came from Qualcomm's reference build; they make the Play
# Store offer apps that need the hardware and make apps try it and fail.
for _f in android.hardware.nfc.xml android.hardware.nfc.ese.xml android.hardware.nfc.hce.xml \
          android.hardware.nfc.hcef.xml android.hardware.nfc.uicc.xml \
          android.hardware.sensor.barometer.xml android.hardware.sensor.gyroscope.xml \
          android.hardware.sensor.proximity.xml android.hardware.sensor.light.xml \
          android.hardware.camera.front.xml; do
    if img_has "$OUTPUT_DIR/vendor.img" "etc/permissions/$_f"; then
        debugfs -w -R "rm etc/permissions/$_f" "$OUTPUT_DIR/vendor.img" >/dev/null 2>&1
        img_has "$OUTPUT_DIR/vendor.img" "etc/permissions/$_f" && echo "  !! vendor: $_f still present" \
            || echo "  -> vendor: dropped false feature $_f"
    fi
done
if [ "$TOOLS_INJECTED" = "1" ]; then
    debloat product.img app/DeskClock          "replaced by MikuTools Clock"
    debloat vendor.img  app/ExactCalculator    "replaced by MikuTools Calculator"
    debloat product.img app/Calendar           "replaced by MikuTools Calendar"
fi
if [ "$MEDIA_INJECTED" = "1" ]; then
    debloat system.img  system/app/Gallery2          "replaced by MikuMedia Gallery"
    debloat product.img app/Gallery2                 "second copy of the stock Gallery"
    debloat system.img  system/app/SnapdragonCamera  "replaced by MikuMedia Camera"
    debloat vendor.img  priv-app/SnapdragonCamera    "vendor copy of the stock camera"
    debloat vendor.img  app/HibySound                "replaced by MikuMedia Recorder"
fi

echo "[5c] Verifying injected files own data blocks (debugfs disk-full noop guard)..."
verify_baked() { # <img> <path> — fail unless file exists, and has blocks when size>0
    local _st _sz _bc
    _st="$(debugfs -R "stat $2" "$1" 2>/dev/null)"
    _sz="$(printf '%s' "$_st" | sed -n 's/.*Size: \([0-9]*\).*/\1/p' | head -1)"
    _bc="$(printf '%s' "$_st" | sed -n 's/.*Blockcount: \([0-9]*\).*/\1/p' | head -1)"
    if [ -z "$_sz" ] || { [ "$_sz" -gt 0 ] && [ "${_bc:-0}" -eq 0 ]; }; then
        echo "  !! BAKE FAILED (size=${_sz:-missing} blocks=${_bc:-0}): $2 in $1" >&2
        return 1
    fi
    return 0
}
GATE_FAIL=0
for _f in \
    system/build.prop \
    system/etc/init/miku_adb.rc \
    system/etc/init/miku_ime.rc \
    system/etc/init/miku_preload.rc \
    system/etc/miku_preload_apks.sh \
    system/etc/init/miku_powerd.rc \
    system/app/MikuLauncher/MikuLauncher.apk \
    system/app/MikuMusic/MikuMusic.apk \
    system/priv-app/MikuSettings/MikuSettings.apk \
    system/app/MikuSystemUI/MikuSystemUI.apk \
    system/etc/permissions/privapp-permissions-mikuos.xml \
; do verify_baked "$OUTPUT_DIR/system.img" "$_f" || GATE_FAIL=1; done
verify_baked "$OUTPUT_DIR/vendor.img" "etc/init/miku_vendor_adb.rc" || GATE_FAIL=1
verify_baked "$OUTPUT_DIR/vendor.img" "etc/init/miku_audio.rc" || GATE_FAIL=1
verify_baked "$OUTPUT_DIR/vendor.img" "etc/init/miku_charge.rc" || GATE_FAIL=1
verify_baked "$OUTPUT_DIR/vendor.img" "etc/audio_policy_volumes.xml" || GATE_FAIL=1
for _img in system system_ext product vendor; do
    _free="$(debugfs -R "stats -h" "$OUTPUT_DIR/$_img.img" 2>/dev/null | sed -n 's/^Free blocks: *\([0-9]*\).*/\1/p')"
    echo "  -> $_img.img free blocks: ${_free:-?}"
    if [ "${_free:-0}" -lt 2048 ]; then   # <8MB headroom = writes may already have noop'd
        echo "  !! $_img.img nearly full (${_free:-0} free blocks) — grow its resize2fs size" >&2
        GATE_FAIL=1
    fi
done
# Release gate: refuse to pack a MIKUOS_RELEASE=1 image that still carries a dev back door.
if [ "$MIKUOS_RELEASE" = "1" ]; then
    _rp="$(debugfs -R "cat system/build.prop" "$OUTPUT_DIR/system.img" 2>/dev/null)"
    for _want in ro.secure=1 ro.adb.secure=1 ro.debuggable=0 ro.miku.release=1; do
        grep -qx "$_want" <<< "$_rp" || { echo "  !! release gate: $_want missing from system/build.prop" >&2; GATE_FAIL=1; }
    done
    if grep -qE '^((service|persist)\.adb\.tcp\.port|service\.adb\.root)=' <<< "$_rp"; then
        echo "  !! release gate: adb tcp/root props still in system/build.prop" >&2; GATE_FAIL=1
    fi
    for _bad in adb_keys system/etc/miku_adb_keys system/etc/miku_root_boot.sh system/etc/mikuos-dev-wifi.conf; do
        if img_has "$OUTPUT_DIR/system.img" "$_bad"; then echo "  !! release gate: $_bad is in system.img" >&2; GATE_FAIL=1; fi
    done
    if debugfs -R "cat system/etc/init/miku_adb.rc" "$OUTPUT_DIR/system.img" 2>/dev/null | grep -qE 'ro\.adb\.secure 0|start adbd|miku_root_boot'; then
        echo "  !! release gate: miku_adb.rc still forces adb or root" >&2; GATE_FAIL=1
    fi
    [ "$GATE_FAIL" = "0" ] && echo "  -> release gate passed (adb secure, not debuggable, no dev key/root/Wi-Fi seed)"
fi
[ "$GATE_FAIL" = "0" ] || { echo "!! Injection verification failed — NOT packing a corrupt super." >&2; exit 1; }

# Shrink each edited image to its minimal size so the generous working sizes
# above don't blow the fixed 4.5G super budget. Partitions mount read-only on
# device, so a fully-packed fs is fine.
echo "[5d] Shrinking edited images to minimal size for super packing..."
for _img in system system_ext product vendor; do
    e2fsck -fy "$OUTPUT_DIR/$_img.img" >/dev/null || true
    resize2fs -M "$OUTPUT_DIR/$_img.img"
    # resize2fs shrinks the fs, not the file — truncate to the new fs size,
    # since lpmake takes each partition's size from the image FILE size.
    _blocks="$(dumpe2fs -h "$OUTPUT_DIR/$_img.img" 2>/dev/null | sed -n 's/^Block count: *//p')"
    _bsize="$(dumpe2fs -h "$OUTPUT_DIR/$_img.img" 2>/dev/null | sed -n 's/^Block size: *//p')"
    truncate -s $(( _blocks * _bsize )) "$OUTPUT_DIR/$_img.img"
    e2fsck -fy "$OUTPUT_DIR/$_img.img" >/dev/null || { echo "!! post-shrink fsck failed: $_img" >&2; exit 1; }
    echo "  -> $_img.img shrunk to $(( _blocks * _bsize / 1024 / 1024 ))MB"
done

echo "[6/6] Synthesizing dynamic super.img container with lpmake..."
SYS_SZ=$(stat -c%s "$OUTPUT_DIR/system.img")
VEN_SZ=$(stat -c%s "$OUTPUT_DIR/vendor.img")
PROD_SZ=$(stat -c%s "$OUTPUT_DIR/product.img")
EXT_SZ=$(stat -c%s "$OUTPUT_DIR/system_ext.img")
ODM_SZ=$(stat -c%s "$FW_DIR/odm.img")
SYS_DLKM_SZ=$(stat -c%s "$FW_DIR/system_dlkm.img")
VEN_DLKM_SZ=$(stat -c%s "$OUTPUT_DIR/vendor_dlkm.img")

TOTAL_SZ=$((SYS_SZ + VEN_SZ + PROD_SZ + EXT_SZ + ODM_SZ + SYS_DLKM_SZ + VEN_DLKM_SZ))
echo "Total Partition Data Size: $TOTAL_SZ bytes ($((TOTAL_SZ / 1024 / 1024)) MB)"

SUPER_SIZE=5371461632   # M500_MIKU_4G actual: fastboot getvar partition-size:super (was 4831838208, wrong)
if [ "$TOTAL_SZ" -ge "$SUPER_SIZE" ]; then
    echo "!! Partitions ($TOTAL_SZ) exceed super budget ($SUPER_SIZE) — shrink an image." >&2
    exit 1
fi

"$LPMAKE" \
  --metadata-size 65536 \
  --super-name super \
  --metadata-slots 2 \
  --device super:$SUPER_SIZE \
  --group qti_dynamic_partitions_a:$SUPER_SIZE \
  --partition system_a:readonly:$SYS_SZ:qti_dynamic_partitions_a \
  --image system_a="$OUTPUT_DIR/system.img" \
  --partition vendor_a:readonly:$VEN_SZ:qti_dynamic_partitions_a \
  --image vendor_a="$OUTPUT_DIR/vendor.img" \
  --partition product_a:readonly:$PROD_SZ:qti_dynamic_partitions_a \
  --image product_a="$OUTPUT_DIR/product.img" \
  --partition system_ext_a:readonly:$EXT_SZ:qti_dynamic_partitions_a \
  --image system_ext_a="$OUTPUT_DIR/system_ext.img" \
  --partition odm_a:readonly:$ODM_SZ:qti_dynamic_partitions_a \
  --image odm_a="$FW_DIR/odm.img" \
  --partition system_dlkm_a:readonly:$SYS_DLKM_SZ:qti_dynamic_partitions_a \
  --image system_dlkm_a="$FW_DIR/system_dlkm.img" \
  --partition vendor_dlkm_a:readonly:$VEN_DLKM_SZ:qti_dynamic_partitions_a \
  --image vendor_dlkm_a="$OUTPUT_DIR/vendor_dlkm.img" \
  --output "$OUTPUT_SUPER"

echo "=========================================================="
echo "  MikuOS super.img Generation Complete: $(stat -c%s "$OUTPUT_SUPER") bytes"
echo "  Location: $OUTPUT_SUPER"
echo "=========================================================="
