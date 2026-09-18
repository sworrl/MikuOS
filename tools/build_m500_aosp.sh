#!/usr/bin/env bash
# ============================================================================
# Resource-contained AOSP 14 build for the HiBy M500 (signed with Falcon keys).
#
# Runs the build inside a systemd user scope so it can NEVER bog down the
# desktop, at the cost of taking longer:
#   MemoryHigh  - soft cap. Under pressure the kernel reclaims from the BUILD's
#                 cgroup instead of evicting your desktop into swap. This is the
#                 single most important setting for responsiveness (the earlier
#                 run pushed swap 8G -> 29G and made the VM crawl).
#   CPUWeight   - build gets a small share of CPU when anything competes, and
#                 full speed when the machine is idle.
#   nice/ionice - belt-and-braces CPU + disk-IO yielding (the io controller is
#                 not delegated to the user slice, so ionice covers disk).
#   -j          - fewer parallel jobs = less peak RAM, fewer OOM/thrash risks.
#
# Usage:  tools/build_m500_aosp.sh            # gentle defaults
#         JOBS=10 MEMHIGH=18G tools/build_m500_aosp.sh   # faster, greedier
#         tools/build_m500_aosp.sh --status   # progress / ETA
#         tools/build_m500_aosp.sh --stop     # stop it
# ============================================================================
set -uo pipefail
SRC=/mnt/aosp-src
OUT=/mnt/aosp-out/out
LOG=/mnt/aosp-out/build_m500_nice.log
TARGET=aosp_m500-trunk_staging-userdebug
UNIT=m500-aosp-build
JOBS=${JOBS:-6}
MEMHIGH=${MEMHIGH:-14G}
CPUW=${CPUW:-10}

case "${1:-}" in
  --stop)
    systemctl --user stop "$UNIT.scope" 2>/dev/null
    pkill -f '[s]oong_build|[n]inja.*aosp|[s]oong_ui' 2>/dev/null
    sleep 2; echo "stopped (build procs left: $(pgrep -cf '[s]oong_build|[n]inja.*aosp' 2>/dev/null || echo 0))"; exit 0 ;;
  --status)
    echo "scope: $(systemctl --user is-active $UNIT.scope 2>/dev/null || echo inactive)"
    echo "procs: $(pgrep -cf '[s]oong_build|[n]inja.*aosp' 2>/dev/null || echo 0)"
    echo "last log write: $(( $(date +%s) - $(stat -c %Y "$LOG" 2>/dev/null || date +%s) ))s ago"
    p=$(grep -oE '^\[ *[0-9]+% [0-9]+/[0-9]+\]' "$LOG" 2>/dev/null | tail -1)
    echo "progress: ${p:-<still in soong analysis - no progress output yet>}"
    grep -cE '^error:|FAILED' "$LOG" 2>/dev/null | sed 's/^/errors: /'
    free -g | sed -n '2,3p'; exit 0 ;;
esac

echo "Starting contained AOSP build: -j$JOBS MemoryHigh=$MEMHIGH CPUWeight=$CPUW"
echo "  target: $TARGET"
echo "  log:    $LOG"
systemd-run --user --scope --quiet --unit="$UNIT" \
    -p MemoryHigh="$MEMHIGH" -p CPUWeight="$CPUW" -p TasksMax=infinity \
    nice -n 19 ionice -c 3 \
    bash -c "cd $SRC && export OUT_DIR=$OUT && source build/envsetup.sh >/dev/null 2>&1 && \
             lunch $TARGET >/dev/null 2>&1 && m -j$JOBS" > "$LOG" 2>&1
echo "M500 build exit=$?" >> "$LOG"
