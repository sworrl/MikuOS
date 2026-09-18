#!/system/bin/sh
# ==============================================================================
# Magisk Root Service Script (/data/adb/service.d/m500_rsyncd.sh)
# Boots the standalone aarch64 rsyncd daemon at device startup on the configured
# rsync port (RSYNC_PORT, default 8730 — a protocol constant, not personal data).
# ==============================================================================
RSYNC_PORT="${RSYNC_PORT:-8730}"
(
  while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
  done
  sleep 3
  killall ld-musl-aarch64.so.1 2>/dev/null || true
  setsid /data/local/tmp/m500_tools/bundle/bin/rsync_wrapper --daemon --no-detach --config=/data/local/tmp/m500_tools/etc/rsyncd.conf --port="$RSYNC_PORT" </dev/null >/data/local/tmp/m500_tools/rsync_stdout.log 2>&1 &
) &
