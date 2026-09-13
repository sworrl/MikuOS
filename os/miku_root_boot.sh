#!/system/bin/sh
# ==============================================================================
# MikuOS Boot-Time Root Auto-Config & Permission Authority
# ==============================================================================
# Pre-configures Magisk SQLite policy database to AUTO-GRANT root to all MikuOS apps
# and disable tapjacking protection so overlays never block root grants.
# ==============================================================================

L(){ log -t MikuRoot "$*"; }
LOG=/data/local/tmp/miku_root_boot.log; : >"$LOG" 2>/dev/null; chmod 0644 "$LOG" 2>/dev/null
L "start uid=$(id -u) ctx=$(cat /proc/self/attr/current 2>/dev/null)"

# Locate Magisk binary
MAGISK=""
for m in magisk /data/adb/magisk/magisk64 /data/adb/magisk/magisk32 /system/bin/magisk /sbin/magisk; do
  if command -v "$m" >/dev/null 2>&1 || [ -x "$m" ]; then MAGISK="$m"; break; fi
done
L "magisk=$MAGISK ver=$($MAGISK -v 2>&1 | head -1)"

mkdir -p /data/adb /data/adb/post-fs-data.d /data/adb/service.d 2>/dev/null
chmod 700 /data/adb 2>/dev/null

# 1) Pre-configure Magisk SQLite settings:
# - auto_response=1 (Auto Grant root to all requests)
# - su_tapjacking=0 (Disable overlay/tapjacking blocking)
# - root_access=3 (Apps and ADB)
# - su_notification=0 (Silent, no popups)
# - su_biometric=0
# - su_mnt_ns=0 (Global mount namespace)
if [ -n "$MAGISK" ]; then
  "$MAGISK" --sqlite "CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value INT);" 2>/dev/null || true
  "$MAGISK" --sqlite "CREATE TABLE IF NOT EXISTS policies (uid INT PRIMARY KEY, policy INT, until INT, logging INT, notification INT);" 2>/dev/null || true
  
  "$MAGISK" --sqlite "REPLACE INTO settings (key,value) VALUES ('auto_response', 1);" 2>/dev/null || true
  "$MAGISK" --sqlite "REPLACE INTO settings (key,value) VALUES ('su_auto_response', 1);" 2>/dev/null || true
  "$MAGISK" --sqlite "REPLACE INTO settings (key,value) VALUES ('su_tapjacking', 0);" 2>/dev/null || true
  "$MAGISK" --sqlite "REPLACE INTO settings (key,value) VALUES ('su_biometric', 0);" 2>/dev/null || true
  "$MAGISK" --sqlite "REPLACE INTO settings (key,value) VALUES ('su_mnt_ns', 0);" 2>/dev/null || true
  "$MAGISK" --sqlite "REPLACE INTO settings (key,value) VALUES ('root_access', 3);" 2>/dev/null || true
  "$MAGISK" --sqlite "REPLACE INTO settings (key,value) VALUES ('su_notification', 0);" 2>/dev/null || true
  
  # Pre-grant ADB shell (2000) and System (1000)
  "$MAGISK" --sqlite "REPLACE INTO policies (uid,policy,until,logging,notification) VALUES (2000,2,0,0,0);" 2>/dev/null || true
  "$MAGISK" --sqlite "REPLACE INTO policies (uid,policy,until,logging,notification) VALUES (1000,2,0,0,0);" 2>/dev/null || true
  "$MAGISK" --sqlite "REPLACE INTO policies (uid,policy,until,logging,notification) VALUES (0,2,0,0,0);" 2>/dev/null || true
  
  L "Magisk settings configured: auto_response=1, su_tapjacking=0"
fi

# Self-seed into magisk service.d and post-fs-data.d
cp -f /system/etc/miku_root_boot.sh /data/adb/service.d/miku_root_boot.sh 2>/dev/null || true
cp -f /system/etc/miku_root_boot.sh /data/adb/post-fs-data.d/miku_root_boot.sh 2>/dev/null || true
chmod 0755 /data/adb/service.d/miku_root_boot.sh 2>/dev/null || true
chmod 0755 /data/adb/post-fs-data.d/miku_root_boot.sh 2>/dev/null || true

# Wait for framework if running at early boot
i=0; while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done

# 2) Pre-grant UIDs of all installed MikuOS packages
if [ -n "$MAGISK" ]; then
  for pkg in com.miku.launcher com.miku.music com.miku.player com.miku.systemui com.miku.settings com.miku.hardware; do
    uid=$(stat -c %u "/data/data/$pkg" 2>/dev/null || pm list packages -U 2>/dev/null | grep "package:$pkg " | awk -F'uid:' '{print $2}')
    if [ -n "$uid" ]; then
      "$MAGISK" --sqlite "REPLACE INTO policies (uid,policy,until,logging,notification) VALUES ($uid,2,0,0,0);" 2>/dev/null || true
      L "granted root to $pkg (uid=$uid)"
    fi
  done
fi

# 3) Suppress stock volume dialogs
cmd overlay fabricate --target com.android.systemui --name miku_killvol com.android.systemui:bool/enable_volume_ui 0x12 0x0 >/dev/null 2>&1 || true
cmd overlay enable com.android.systemui:miku_killvol >/dev/null 2>&1 || true
settings put global hiby_volume_dialog_enable 0 2>/dev/null || true
settings put global hiby_volume_dialog_indicator 0 2>/dev/null || true

L "done"
