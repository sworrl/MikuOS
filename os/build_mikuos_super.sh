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
MIKUOS_VERSION="${MIKUOS_VERSION:-0.1.0}"
DEVICE_IDENTITY="m500_mikuOS-v${MIKUOS_VERSION}"
RESIGN_SH="$SCRIPT_DIR/resign_system.sh"
APKSIGNER="${APKSIGNER:-$(ls ~/Android/Sdk/build-tools/*/apksigner 2>/dev/null | tail -1)}"

# debugfs 'write' creates files UNLABELED. Under enforcing SELinux an unlabeled
# /system app can't be read by its own process (resources NPE / crash loop) and
# init won't process an unlabeled .rc — so every injected file must be given its
# SELinux context. label <img> <path-in-img> <context>
label() { debugfs -w -R "ea_set $2 security.selinux $3\\000" "$1" >/dev/null 2>&1; }

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
    ./gradlew :mikuos-launcher:assembleRelease :app:assembleRelease :mikuos-settings:assembleRelease :mikuos-systemui:assembleRelease :fmradio:assembleRelease
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
if [ -z "$SYSTEMUI_APK" ]; then
    SYSTEMUI_APK="$(latest_apk "$REPO_DIR/miku-player-kotlin/mikuos-systemui/build/outputs/apk/release/*.apk")"
fi
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

echo "[2b] Setting boot 'welcome' voice (trimmed to play immediately, not at ~9s)..."
# The stock bootanimation_<locale>.mp4 has the "Welcome to HiBy Music, the show
# starts now" voice buried ~8.3s into a 12.5s clip (long silent lead-in). We keep
# the voice (user-approved) but replace the audio track with the pre-trimmed
# voice-only clip at t=0, so it speaks right away. Per-locale voice mapping:
#   base .mp4 = Chinese, _en = English, _jp = Japanese, _cn = Chinese variant.
# (Gated by persist.sys.customanim.boot.sounds=1, set in build.prop.)
VOICE_DIR="$SCRIPT_DIR/boot_voice"
TMP_ANIM_DIR="$(mktemp -d)"
for pair in "bootanimation.mp4:welcome_voice.ogg" \
            "bootanimation_en.mp4:welcome_voice_en.ogg" \
            "bootanimation_jp.mp4:welcome_voice_jp.ogg" \
            "bootanimation_cn.mp4:welcome_voice_cn.ogg"; do
    anim="${pair%%:*}"; voice="${pair##*:}"
    debugfs -R "dump media/$anim $TMP_ANIM_DIR/$anim" "$OUTPUT_DIR/vendor.img" 2>/dev/null || true
    [ -s "$TMP_ANIM_DIR/$anim" ] || continue
    if [ -f "$VOICE_DIR/$voice" ]; then
        # keep the original video, swap in the trimmed voice as the audio at t=0.
        # No -shortest: output keeps the full video length; voice plays up front,
        # silence for the remainder.
        ffmpeg -y -i "$TMP_ANIM_DIR/$anim" -i "$VOICE_DIR/$voice" \
            -map 0:v -map 1:a -c:v copy -c:a aac "$TMP_ANIM_DIR/new_$anim" 2>/dev/null || true
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

# Google Fi APN: bake the h2g2-t data APN into product/etc/apns-conf.xml so a Fi SIM gets
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
inject_overlay "$REPO_DIR/tools/custom_overlays/MikuSystemUIOverlay/com.miku.systemui.overlay.apk" MikuSystemUIOverlay.apk "stock volume dialog off + HiBy strings"
inject_overlay "$REPO_DIR/tools/custom_overlays/MikuFrameworkOverlay/MikuFrameworkOverlay.apk" MikuFrameworkOverlay.apk "gestural nav config"
inject_overlay "$REPO_DIR/tools/custom_overlays/MikuThemeOverlay/MikuThemeOverlay.apk" MikuThemeOverlay.apk "power menu + dialog retint"
inject_overlay "$MIKUOS_DIR/build/MikuAnimOverlay.apk" MikuAnimOverlay.apk "KDE window animations"

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

# Inject MikuSettings into system/app/
debugfs -w -R "mkdir system/app/MikuSettings" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "set_inode_field system/app/MikuSettings mode 040755" "$OUTPUT_DIR/system.img"
debugfs -w -R "write $SETTINGS_APK system/app/MikuSettings/MikuSettings.apk" "$OUTPUT_DIR/system.img"
debugfs -w -R "set_inode_field system/app/MikuSettings/MikuSettings.apk mode 0100644" "$OUTPUT_DIR/system.img"
label "$OUTPUT_DIR/system.img" system/app/MikuSettings u:object_r:system_file:s0
label "$OUTPUT_DIR/system.img" system/app/MikuSettings/MikuSettings.apk u:object_r:system_file:s0

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
sed -i 's/^ro.adb.secure=.*/ro.adb.secure=0/' "$TMP_PROP"
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
ro.adb.secure=0
service.adb.root=1
# Wireless adb (dev copy): persist.adb.tcp.port makes adbd ALSO listen on TCP 5555
# while keeping the USB interface. Reach it with adb connect IP:5555 on LAN.
# The host key is pre-authorized so no on-screen prompt.
persist.adb.tcp.port=5555

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
# build.prop already exists -> must rm before write (debugfs won't overwrite).
dfput "$OUTPUT_DIR/system.img" "$TMP_PROP" "system/build.prop" \
    || { echo "!! FATAL: could not write system/build.prop (adb.secure/usb config would be stock)"; exit 1; }
label "$OUTPUT_DIR/system.img" system/build.prop u:object_r:system_file:s0
rm -f "$TMP_PROP"

# Patch vendor.img build.prop for ADB authorization and device identity
TMP_VEN_PROP="/tmp/miku_vendor_build.prop"
debugfs -R "cat build.prop" "$OUTPUT_DIR/vendor.img" > "$TMP_VEN_PROP" 2>/dev/null || true
sed -i 's/^ro.adb.secure=.*/ro.adb.secure=0/' "$TMP_VEN_PROP"
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

dfput "$OUTPUT_DIR/vendor.img" "$TMP_VEN_PROP" "build.prop" \
    || { echo "!! FATAL: could not write vendor/build.prop"; exit 1; }
label "$OUTPUT_DIR/vendor.img" build.prop u:object_r:vendor_file:s0
rm -f "$TMP_VEN_PROP"

# Inject init RC to force ADB online unconditionally at early-init, init, post-fs-data, and boot
TMP_RC="/tmp/miku_adb.rc"
cat << 'RCEOF' > "$TMP_RC"
on early-init
    setprop ro.adb.secure 0
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

on property:sys.boot_completed=1
    exec_background - root root -- /system/bin/sh /system/etc/miku_root_boot.sh
RCEOF

debugfs -w -R "write $TMP_RC system/etc/init/miku_adb.rc" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "set_inode_field system/etc/init/miku_adb.rc mode 0100644" "$OUTPUT_DIR/system.img" 2>/dev/null || true
label "$OUTPUT_DIR/system.img" system/etc/init/miku_adb.rc u:object_r:system_file:s0
debugfs -w -R "write $TMP_RC etc/init/miku_vendor_adb.rc" "$OUTPUT_DIR/vendor.img" 2>/dev/null || true
debugfs -w -R "set_inode_field etc/init/miku_vendor_adb.rc mode 0100644" "$OUTPUT_DIR/vendor.img" 2>/dev/null || true
label "$OUTPUT_DIR/vendor.img" etc/init/miku_vendor_adb.rc u:object_r:vendor_file:s0
rm -f "$TMP_RC"

# Pre-authorize THIS build host's adb key so a fresh /data wipe never shows the
# "Allow USB debugging?" prompt (ro.adb.secure=0 alone proved unreliable on this vendor build).
# adbd reads /adb_keys at startup (read-only, no timing race) and also watches
# /data/misc/adb/adb_keys, which miku_adb.rc's post-fs-data seeds from the baked copy below.
ADB_KEY="$SCRIPT_DIR/adb_keys"
if [ -f "$ADB_KEY" ]; then
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
if [ -f "$ROOT_SH" ]; then
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
on property:sys.boot_completed=1
    exec_background - system system -- /system/bin/settings put secure default_input_method com.android.inputmethod.latin/.LatinIME
    exec_background - system system -- /system/bin/settings put secure enabled_input_methods com.android.inputmethod.latin/.LatinIME
    exec_background - system system -- /system/bin/settings put secure show_ime_with_hard_keyboard 1
    exec_background - system system -- /system/bin/settings put global hiby_miku_sounds_enable 0
    exec_background - system system -- /system/bin/settings put global hiby_miku_sounds_list 0
    exec_background - system system -- /system/bin/settings put global headset_connect_sound 0
    # Developer Options + USB debugging always ON (Settings couldn't reach Dev Tools;
    # also guarantees adb comes up authorized on every boot for debugging/tracing).
    exec_background - system system -- /system/bin/settings put global development_settings_enabled 1
    exec_background - system system -- /system/bin/settings put global adb_enabled 1
    exec_background - system system -- /system/bin/settings put global adb_wifi_enabled 1
    exec_background - system system -- /system/bin/settings put global stay_on_while_plugged_in 3
    exec_background - system system -- /system/bin/svc power stayon true
    # DTA bit-perfect allow-list: the vendor framework's AudioTrack grants the DIRECT
    # (native-rate, mixer-bypass) path to the CS43198 DACs only to packages in this
    # Global setting (factory default = com.hiby.music only). Seed it with Miku Music
    # so OUR player rides the same hardware path. No spaces in the JSON = one rc token.
    exec_background - system system -- /system/bin/settings put global direct_support_app_list {"list":[{"packageName":"com.hiby.music"},{"packageName":"com.miku.player"}]}
    # Location runtime grants: the launcher/player never show a permission prompt, so
    # without these the weather stack can never read GNSS (device HAS gnss_service) and
    # silently falls back to IP-geo/default coords ("weather wrong, no location" bug).
    exec_background - system system -- /system/bin/pm grant com.miku.launcher android.permission.ACCESS_FINE_LOCATION
    exec_background - system system -- /system/bin/pm grant com.miku.launcher android.permission.ACCESS_COARSE_LOCATION
    # Cellular signal meter on the status bar needs READ_PHONE_STATE (runtime perm).
    exec_background - system system -- /system/bin/pm grant com.miku.launcher android.permission.READ_PHONE_STATE
    # Live BPM/beat detector (Visualizer on output session 0) so the BPM counter "sees ALSA"
    # for ANY source (Spotify etc). RECORD_AUDIO is a runtime perm; a system app doesn't get it
    # auto-granted, so grant it on boot or the detector fails soft and the counter reads standby.
    exec_background - system system -- /system/bin/pm grant com.miku.launcher android.permission.RECORD_AUDIO
    # Ambient-light auto-brightness (camera EV100 proxy) — grant CAMERA, enable, and start the service.
    exec_background - system system -- /system/bin/pm grant com.m500.hardware android.permission.CAMERA
    exec_background - system system -- /system/bin/appops set com.m500.hardware CAMERA allow
    # Ambient auto-brightness must WRITE screen_brightness: needs the WRITE_SETTINGS appop, not
    # just the perm (without it the service samples fine but every brightness write silently
    # no-ops - "activates but never adjusts", found 2026-09-10).
    exec_background - system system -- /system/bin/appops set com.m500.hardware WRITE_SETTINGS allow
    exec_background - system system -- /system/bin/appops set --uid com.m500.hardware CAMERA allow
    # SYSTEM_ALERT_WINDOW appop = A14 while-in-use exemption; without it a
    # camera-type FGS cannot start from BOOT_COMPLETED (throws SecurityException).
    exec_background - system system -- /system/bin/appops set com.m500.hardware SYSTEM_ALERT_WINDOW allow
    # Theater mode ON: the ONLY working suppressor of screen-wake on charger plug/unplug flaps.
    # config_unplugTurnsOnScreen cannot be overridden by RRO (framework overlayable policy rejects
    # it - verified via cmd overlay lookup with the overlay enabled), but PMS honors
    # theater + config_allowTheaterModeWakeFromUnplug=false (stock on this build). Note: theater
    # also suppresses gesture wakes (double-tap) by AOSP default.
    exec_background - system system -- /system/bin/settings put global theater_mode_on 1
    # Auto-rotate OFF by default (user preference): portrait-locked DAP, rotation is a nuisance.
    exec_background - system system -- /system/bin/settings put system accelerometer_rotation 0
    # BEST AUDIO MODE from first boot: HIGH DAC gain (audio-lockdown directive). The player also
    # re-asserts this and pushes it into the HAL on every start (MikuDirectAudio.ensureMaxGain).
    exec_background - system system -- /system/bin/settings put global vendor.audio.hiby.hw.gain high
    exec_background - system system -- /system/bin/settings put global vendor.audio.hiby.gain high
    # Listen-stats/scrobble tracker: ENABLED. The 2026-09-10 crash-loop was root-caused 09-11 to
    # TrackTech.cache (a mutableStateMapOf written by composition AND by the stats io thread) and
    # fixed in player 2.0.263; the kill switch remains available for future bisects.
    exec_background - system system -- /system/bin/settings put global miku_dbg_off_stats 0
    exec_background - system system -- /system/bin/settings put global m500_ambient_auto_brightness 1
    exec_background - system system -- /system/bin/am start-foreground-service -n com.m500.hardware/.AmbientBrightnessService
    # ...and make the RECORD_AUDIO app-op unrestricted (not foreground-only) so output capture
    # keeps running while a 3rd-party player (Spotify) is the foreground app.
    exec_background - system system -- /system/bin/appops set com.miku.launcher RECORD_AUDIO allow
    # Bluetooth device picker + alarm/haptics in the music app.
    exec_background - system system -- /system/bin/pm grant com.miku.player android.permission.BLUETOOTH_CONNECT
    exec_background - system system -- /system/bin/pm grant com.miku.player android.permission.ACCESS_FINE_LOCATION
    exec_background - system system -- /system/bin/pm grant com.miku.player android.permission.ACCESS_COARSE_LOCATION
    exec_background - system system -- /system/bin/settings put secure location_mode 3
    # Safe-media-volume state = 1 (DISABLED) — the runtime half of the roller-ceiling
    # fix (props above handle boot; this clears any persisted ACTIVE state).
    exec_background - system system -- /system/bin/settings put global audio_safe_volume_state 1
    # Stock keyguard OFF (authoritative — LockPatternUtils/lockscreen.disabled setting alone did NOT
    # stick on this device; cmd lock_settings does). The Miku lockscreen then layers on via SCREEN_ON.
    exec_background - system system -- /system/bin/cmd lock_settings set-disabled true
    exec_background - system system -- /system/bin/settings put global miku_audio_lockdown 1
    exec_background - system system -- /system/bin/settings put global miku_bt_quality_locked 1
    # HiBy volume lock OFF: ro.vendor.volume_lock_enable=yes arms a vendor cap that pins
    # STREAM_MUSIC at index 35 (balanced/single-ended phone-out) / 40 (h2w, lineout) / 80 (USB)
    # while Settings.Global vendor.audio.hw.volume_lock is "yes" — enforced by SystemUI's
    # HibyBarTool/HiByNewVolumeDialog on every knob/plug event, NOT by the policy volume curves.
    # "no" is the vendor's own unlock switch (HibyAudioSettingInitUtils preserves a non-empty
    # value across boots), so the wired outputs reach the full 0-100 range / 0 dB curve top.
    exec_background - system system -- /system/bin/settings put global vendor.audio.hw.volume_lock no
    # Pulsar Light (SGM31324 RGB): open the sysfs nodes that stock SELinux locked away
    # from everything — the launcher drives them (as root) for volume-level color.
    exec_background - root root -- /system/bin/sh -c "chmod 666 /sys/devices/platform/soc/4ac0000.qcom,qupv3_0_geni_se/4a94000.i2c/i2c-2/2-0030/leds/sgm31324-leds/* 2>/dev/null || true"
    # Enable full-screen gesture navigation (swipe-back / swipe-up-home). The nav
    # mode follows the enabled navbar RRO overlay: enable gestural, disable the
    # three-button overlay, and set navigation_mode=2. (NOTE: this device's
    # `cmd overlay` has NO `enable-exclusive-category` verb — verified on-device;
    # use plain enable/disable, which is what actually flips the mode.)
    exec_background - system system -- /system/bin/cmd overlay enable com.android.internal.systemui.navbar.gestural
    exec_background - system system -- /system/bin/cmd overlay disable com.android.internal.systemui.navbar.threebutton
    exec_background - system system -- /system/bin/settings put secure navigation_mode 2
    exec_background - system system -- /system/bin/settings put secure back_gesture_inset_scale_left 1
    exec_background - system system -- /system/bin/settings put secure back_gesture_inset_scale_right 1
    # MikuOS navigation: this device's stock SystemUI draws NO nav bar / status bar, so the
    # MikuOS accessibility service (edge back, gesture pill home/recents/quick-switch, top
    # shade pull) IS the navigation. Keep it enabled every boot (the launcher also
    # self-enables on first run). Verified 2026-08-25: it is NOT a boot-hang cause.
    exec_background - system system -- /system/bin/settings put secure enabled_accessibility_services com.miku.systemui/.MikuNotificationShadeService
    exec_background - system system -- /system/bin/settings put secure accessibility_enabled 1
    # MikuOS power modal: long-press power -> framework "assistant" path -> stock SystemUI
    # launches Settings.Secure `assistant` (our MikuPowerMenuActivity) with ACTION_ASSIST.
    # 5 = LONG_PRESS_POWER_ASSISTANT. No accessibility dependency; very-long-press still
    # reaches the (Miku-retinted) stock global actions dialog.
    exec_background - system system -- /system/bin/settings put secure assistant com.miku.systemui/.MikuPowerMenuActivity
    exec_background - system system -- /system/bin/settings put global power_button_long_press 1
    exec_background - system system -- /system/bin/settings put secure assist_structure_enabled 0
    exec_background - system system -- /system/bin/settings put secure assist_screenshot_enabled 0
    # Framework doze/AOD OFF: HiBy's SystemUI never creates CentralSurfaces (no status bar), so
    # DozeService NPEs (DozeUi.transitionTo → updateIsKeyguard on null) on every screen-off if
    # doze runs. MikuOS has its own AOD (launcher MikuAodActivity); keep the stock doze dream off.
    exec_background - system system -- /system/bin/settings put secure doze_enabled 0
    exec_background - system system -- /system/bin/settings put secure doze_always_on 0
    exec_background - system system -- /system/bin/settings put secure doze_pulse_on_pick_up 0
    exec_background - system system -- /system/bin/settings put secure doze_pulse_on_double_tap 0
    exec_background - system system -- /system/bin/settings put secure doze_tap_gesture 0
IMERCEOF
debugfs -w -R "write $TMP_IME_RC system/etc/init/miku_ime.rc" "$OUTPUT_DIR/system.img" 2>/dev/null || true
debugfs -w -R "set_inode_field system/etc/init/miku_ime.rc mode 0100644" "$OUTPUT_DIR/system.img" 2>/dev/null || true
label "$OUTPUT_DIR/system.img" system/etc/init/miku_ime.rc u:object_r:system_file:s0
rm -f "$TMP_IME_RC"

# MikuOS power daemon: root rc service that maps Settings.Global miku_power_profile
# (published by Miku Music's MikuPowerGovernor: perf / balanced / audio_only / idle) onto CPU
# cluster frequency caps (+ GPU devfreq when present). Audio/DAC path is never touched — it
# starves the app cores when the screen is off and music plays ("push the power to the DACs").
# Sources: mikuos/build/powerd/miku_powerd.sh + miku_powerd.rc (the rc also seeds the
# MANAGE_EXTERNAL_STORAGE appop for com.miku.player so folder art on the SD is readable from
# the very first scan).
POWERD_DIR="$MIKUOS_DIR/build/powerd"
if [ -f "$POWERD_DIR/miku_powerd.sh" ] && [ -f "$POWERD_DIR/miku_powerd.rc" ]; then
    dfput "$OUTPUT_DIR/system.img" "$POWERD_DIR/miku_powerd.sh" system/etc/miku_powerd.sh \
        && debugfs -w -R "set_inode_field system/etc/miku_powerd.sh mode 0100755" "$OUTPUT_DIR/system.img" >/dev/null 2>&1 \
        && label "$OUTPUT_DIR/system.img" system/etc/miku_powerd.sh u:object_r:system_file:s0 \
        && dfput "$OUTPUT_DIR/system.img" "$POWERD_DIR/miku_powerd.rc" system/etc/init/miku_powerd.rc \
        && label "$OUTPUT_DIR/system.img" system/etc/init/miku_powerd.rc u:object_r:system_file:s0 \
        && echo "  -> Injected MikuOS power daemon (miku_powerd) + art-access appop seed" \
        || echo "  !! miku_powerd inject failed"
else
    echo "  !! mikuos/build/powerd/ missing — no power daemon in this image"
fi

# Optional dev Wi-Fi pre-seed, read on first boot by MikuWifiVault / onboarding
# (WifiManager.addNetwork). The credentials come from an UNTRACKED file next to
# this script, os/mikuos-dev-wifi.conf (gitignored), with two keys:
#   ssid_match=<substring of the SSID to connect to>
#   psk=<the passphrase>
# If the file is absent the step is skipped and the image ships with no
# pre-seeded network. Never put a real PSK in this script.
DEV_WIFI_CONF="$(dirname "$0")/mikuos-dev-wifi.conf"
if [ -f "$DEV_WIFI_CONF" ]; then
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
    system/etc/miku_powerd.sh \
    system/app/MikuLauncher/MikuLauncher.apk \
    system/app/MikuMusic/MikuMusic.apk \
    system/app/MikuSettings/MikuSettings.apk \
    system/app/MikuSystemUI/MikuSystemUI.apk \
    system/etc/permissions/privapp-permissions-mikuos.xml \
; do verify_baked "$OUTPUT_DIR/system.img" "$_f" || GATE_FAIL=1; done
verify_baked "$OUTPUT_DIR/vendor.img" "etc/init/miku_vendor_adb.rc" || GATE_FAIL=1
verify_baked "$OUTPUT_DIR/vendor.img" "etc/audio_policy_volumes.xml" || GATE_FAIL=1
for _img in system system_ext product vendor; do
    _free="$(debugfs -R "stats -h" "$OUTPUT_DIR/$_img.img" 2>/dev/null | sed -n 's/^Free blocks: *\([0-9]*\).*/\1/p')"
    echo "  -> $_img.img free blocks: ${_free:-?}"
    if [ "${_free:-0}" -lt 2048 ]; then   # <8MB headroom = writes may already have noop'd
        echo "  !! $_img.img nearly full (${_free:-0} free blocks) — grow its resize2fs size" >&2
        GATE_FAIL=1
    fi
done
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
VEN_DLKM_SZ=$(stat -c%s "$FW_DIR/vendor_dlkm.img")

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
  --image vendor_dlkm_a="$FW_DIR/vendor_dlkm.img" \
  --output "$OUTPUT_SUPER"

echo "=========================================================="
echo "  MikuOS super.img Generation Complete: $(stat -c%s "$OUTPUT_SUPER") bytes"
echo "  Location: $OUTPUT_SUPER"
echo "=========================================================="
