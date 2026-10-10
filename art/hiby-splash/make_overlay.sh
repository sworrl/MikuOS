#!/usr/bin/env bash
# Rebuild the splash frames from picks.json and package them as the MikuSplashOverlay RRO.
#   make_overlay.sh            -> tools/custom_overlays/MikuSplashOverlay/MikuSplashOverlay.apk
# Signs the same way as the other overlays (tools/custom_overlays/build_overlay.sh; set
# OVERLAY_KEY=falcon for the custom platform key). Static overlays in /product/overlay are
# trusted by location, so the key does not have to match SystemUI.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M500="$(cd "$HERE/../../.." && pwd)"
OVL="$M500/tools/custom_overlays/MikuSplashOverlay"
python3 "$HERE/build_frames.py"
n=$(find "$OVL/res" -name '*.png' | wc -l)
[ "$n" -gt 0 ] || { echo "no frames in $OVL/res (generate candidates first: gen.py)"; exit 1; }
"$M500/tools/custom_overlays/build_overlay.sh" "$OVL" "$OVL/MikuSplashOverlay.apk"
# The overlay must only carry names SystemUI already has, or idmap2 skips them silently.
python3 "$HERE/check_overlay.py" "$OVL/MikuSplashOverlay.apk"
