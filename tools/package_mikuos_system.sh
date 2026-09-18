#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$DIR/mikuos_system_build"

echo "========================================="
echo "   MikuOS System Image Packaging Engine  "
echo "========================================="

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/system_ext/priv-app/Settings"
mkdir -p "$BUILD_DIR/system_ext/priv-app/SystemUI"
mkdir -p "$BUILD_DIR/system_ext/priv-app/Launcher3QuickStep"
mkdir -p "$BUILD_DIR/system/etc/permissions"

echo "[1/4] Copying platform-signed System APKs..."
# Resolve versioned APK names (e.g. MikuOS_Settings-v0.1.0.apk); newest wins.
latest_apk() { ls -1t $1 2>/dev/null | head -n1; }
cp "$(latest_apk "$DIR/miku-player-kotlin/mikuos-settings/build/outputs/apk/release/MikuOS_Settings-v*.apk")" "$BUILD_DIR/system_ext/priv-app/Settings/Settings.apk"
cp "$(latest_apk "$DIR/miku-player-kotlin/mikuos-systemui/build/outputs/apk/release/MikuOS_SystemUI-v*.apk")" "$BUILD_DIR/system_ext/priv-app/SystemUI/SystemUI.apk"
cp "$(latest_apk "$DIR/miku-player-kotlin/mikuos-launcher/build/outputs/apk/release/MikuOS_Launcher-v*.apk")" "$BUILD_DIR/system_ext/priv-app/Launcher3QuickStep/Launcher3QuickStep.apk"

echo "[2/4] Generating privapp-permissions-mikuos.xml..."
cat << 'PERM_EOF' > "$BUILD_DIR/system/etc/permissions/privapp-permissions-mikuos.xml"
<?xml version="1.0" encoding="utf-8"?>
<permissions>
    <privapp-permissions package="com.miku.systemui">
        <permission name="android.permission.STATUS_BAR_SERVICE"/>
        <permission name="android.permission.STATUS_BAR"/>
        <permission name="android.permission.EXPAND_STATUS_BAR"/>
        <permission name="android.permission.INTERNAL_SYSTEM_WINDOW"/>
        <permission name="android.permission.SYSTEM_ALERT_WINDOW"/>
        <permission name="android.permission.WRITE_SECURE_SETTINGS"/>
        <permission name="android.permission.WRITE_SETTINGS"/>
        <permission name="android.permission.MODIFY_AUDIO_ROUTING"/>
        <permission name="android.permission.CONTROL_DISPLAY_BRIGHTNESS"/>
        <permission name="android.permission.INTERACT_ACROSS_USERS"/>
    </privapp-permissions>

    <privapp-permissions package="com.miku.settings">
        <permission name="android.permission.WRITE_SECURE_SETTINGS"/>
        <permission name="android.permission.WRITE_SETTINGS"/>
        <permission name="android.permission.MODIFY_AUDIO_ROUTING"/>
        <permission name="android.permission.CHANGE_NETWORK_STATE"/>
        <permission name="android.permission.CHANGE_WIFI_STATE"/>
        <permission name="android.permission.BLUETOOTH_ADMIN"/>
        <permission name="android.permission.BLUETOOTH_CONNECT"/>
        <permission name="android.permission.BLUETOOTH_SCAN"/>
        <permission name="android.permission.INTERACT_ACROSS_USERS"/>
    </privapp-permissions>
</permissions>
PERM_EOF

echo "[3/4] Packaging live Magisk testing overlay..."
MAGISK_MOD="$BUILD_DIR/mikuos_live_system_module"
mkdir -p "$MAGISK_MOD/system/system_ext/priv-app/Settings"
mkdir -p "$MAGISK_MOD/system/system_ext/priv-app/SystemUI"
mkdir -p "$MAGISK_MOD/system/system_ext/priv-app/Launcher3QuickStep"
mkdir -p "$MAGISK_MOD/system/etc/permissions"

cp "$BUILD_DIR/system_ext/priv-app/Settings/Settings.apk" "$MAGISK_MOD/system/system_ext/priv-app/Settings/"
cp "$BUILD_DIR/system_ext/priv-app/SystemUI/SystemUI.apk" "$MAGISK_MOD/system/system_ext/priv-app/SystemUI/"
cp "$BUILD_DIR/system_ext/priv-app/Launcher3QuickStep/Launcher3QuickStep.apk" "$MAGISK_MOD/system/system_ext/priv-app/Launcher3QuickStep/"
cp "$BUILD_DIR/system/etc/permissions/privapp-permissions-mikuos.xml" "$MAGISK_MOD/system/etc/permissions/"

cat << 'MOD_EOF' > "$MAGISK_MOD/module.prop"
id=mikuos_system_core
name=MikuOS Core System Suite
version=v1.0.0-release
versionCode=100
author=FalconTechnix / MikuOS Team
description=Core MikuOS System Suite: Native Jetpack Compose SystemUI, Settings & Launcher with platform privileges.
MOD_EOF

echo "[4/4] Done! MikuOS System tree packaged in: $BUILD_DIR"
