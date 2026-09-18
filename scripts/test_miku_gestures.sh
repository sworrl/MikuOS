#!/usr/bin/env bash
# ==============================================================================
# MikuOS Automated ADB "Finger" Gesture & Interaction Test Suite
# ==============================================================================
set -e

echo "=== [MikuOS ADB Gesture Test Suite] ==="

# 1. Verify ADB connectivity
if ! adb get-state 1>/dev/null 2>&1; then
    echo "[-] ADB device not detected or unauthorized. Waiting for device..."
    adb wait-for-device
fi

echo "[+] Connected to device: $(adb get-serialno 2>/dev/null || echo 'Unknown')"

# 2. Query screen resolution dynamically
SCREEN_SIZE=$(adb shell wm size | grep -oE '[0-9]+x[0-9]+' | tail -1)
WIDTH=$(echo "$SCREEN_SIZE" | cut -d'x' -f1)
HEIGHT=$(echo "$SCREEN_SIZE" | cut -d'x' -f2)

echo "[+] Active Screen Resolution: ${WIDTH}x${HEIGHT}"

# Coordinate helper (percentage to px)
px_x() { echo $(( WIDTH * $1 / 100 )); }
px_y() { echo $(( HEIGHT * $1 / 100 )); }

sleep_gap() { sleep "${1:-1.0}"; }

# Wake up screen and unlock if needed
echo "[+] Ensuring screen is awake..."
adb shell input keyevent KEYCODE_WAKEUP
sleep_gap 0.5
adb shell input keyevent KEYCODE_MENU
sleep_gap 0.8

# Go to MikuOS Home
echo "[+] Returning to MikuOS Home..."
adb shell input keyevent KEYCODE_HOME
sleep_gap 1.5

# ------------------------------------------------------------------------------
# TEST 1: Quilt Top Bar Status Capsule Interactions
# ------------------------------------------------------------------------------
echo "--- TEST 1: Top Bar & Weather Capsule Tap (Open Weather Observatory) ---"
WX_X=$(px_x 25)
WX_Y=$(px_y 4)
echo "    -> Tapping Weather Capsule at ($WX_X, $WX_Y)..."
adb shell input tap "$WX_X" "$WX_Y"
sleep_gap 1.5

echo "    -> Testing Weather Observatory Tab Switch: Forecast..."
TAB1_X=$(px_x 50)
TAB1_Y=$(px_y 10)
adb shell input tap "$TAB1_X" "$TAB1_Y"
sleep_gap 1.0

echo "    -> Testing Weather Observatory Tab Switch: Live Doppler Radar..."
TAB2_X=$(px_x 80)
TAB2_Y=$(px_y 10)
adb shell input tap "$TAB2_X" "$TAB2_Y"
sleep_gap 1.0

echo "    -> Dismissing Weather Observatory Modal..."
adb shell input keyevent KEYCODE_BACK
sleep_gap 1.0

# ------------------------------------------------------------------------------
# TEST 2: GPS / Tactical Geodesic Modal Interaction
# ------------------------------------------------------------------------------
echo "--- TEST 2: GPS Capsule Tap (Open Tactical GPS Modal) ---"
GPS_X=$(px_x 55)
GPS_Y=$(px_y 4)
echo "    -> Tapping GPS Pod at ($GPS_X, $GPS_Y)..."
adb shell input tap "$GPS_X" "$GPS_Y"
sleep_gap 1.5

echo "    -> Dismissing GPS Modal..."
adb shell input keyevent KEYCODE_BACK
sleep_gap 1.0

# ------------------------------------------------------------------------------
# TEST 3: Cyber Battery & Power Core Modal Interaction
# ------------------------------------------------------------------------------
echo "--- TEST 3: Battery Core Tap (Open Battery Observatory) ---"
BAT_X=$(px_x 92)
BAT_Y=$(px_y 4)
echo "    -> Tapping Battery Core at ($BAT_X, $BAT_Y)..."
adb shell input tap "$BAT_X" "$BAT_Y"
sleep_gap 1.5

echo "    -> Dismissing Battery Modal..."
adb shell input keyevent KEYCODE_BACK
sleep_gap 1.0

# ------------------------------------------------------------------------------
# TEST 4: Swipe Down Gesture -> Cyber Notification Shade
# ------------------------------------------------------------------------------
echo "--- TEST 4: Swipe Down Gesture -> Open Notification Shade ---"
SHADE_START_X=$(px_x 50)
SHADE_START_Y=$(px_y 2)
SHADE_END_Y=$(px_y 70)
echo "    -> Swiping from ($SHADE_START_X, $SHADE_START_Y) down to ($SHADE_START_X, $SHADE_END_Y)..."
adb shell input swipe "$SHADE_START_X" "$SHADE_START_Y" "$SHADE_START_X" "$SHADE_END_Y" 350
sleep_gap 1.5

echo "    -> Swiping up to close Notification Shade..."
adb shell input swipe "$SHADE_START_X" "$SHADE_END_Y" "$SHADE_START_X" "$SHADE_START_Y" 250
sleep_gap 1.0

# ------------------------------------------------------------------------------
# TEST 5: Horizontal Desktop Paging Swipe Gestures
# ------------------------------------------------------------------------------
echo "--- TEST 5: Horizontal Desktop Page Swiping ---"
SWIPE_LEFT_START=$(px_x 85)
SWIPE_LEFT_END=$(px_x 15)
SWIPE_Y=$(px_y 50)

echo "    -> Swiping Left (Next Page)..."
adb shell input swipe "$SWIPE_LEFT_START" "$SWIPE_Y" "$SWIPE_LEFT_END" "$SWIPE_Y" 250
sleep_gap 1.2

echo "    -> Swiping Right (Previous Page)..."
adb shell input swipe "$SWIPE_LEFT_END" "$SWIPE_Y" "$SWIPE_LEFT_START" "$SWIPE_Y" 250
sleep_gap 1.2

# ------------------------------------------------------------------------------
# TEST 6: Swipe Up Gesture -> App Drawer
# ------------------------------------------------------------------------------
echo "--- TEST 6: Swipe Up Gesture -> Open App Drawer ---"
DRAWER_START_Y=$(px_y 90)
DRAWER_END_Y=$(px_y 30)
DRAWER_X=$(px_x 50)
echo "    -> Swiping Up from ($DRAWER_X, $DRAWER_START_Y) to ($DRAWER_X, $DRAWER_END_Y)..."
adb shell input swipe "$DRAWER_X" "$DRAWER_START_Y" "$DRAWER_X" "$DRAWER_END_Y" 250
sleep_gap 1.5

echo "    -> Swiping App Drawer contents vertically..."
adb shell input swipe "$DRAWER_X" "$(px_y 70)" "$DRAWER_X" "$(px_y 30)" 200
sleep_gap 0.8
adb shell input swipe "$DRAWER_X" "$(px_y 30)" "$DRAWER_X" "$(px_y 70)" 200
sleep_gap 0.8

echo "    -> Closing App Drawer..."
adb shell input keyevent KEYCODE_BACK
sleep_gap 1.0

# ------------------------------------------------------------------------------
# TEST 7: Launch MikuOS Settings
# ------------------------------------------------------------------------------
echo "--- TEST 7: Launch MikuOS Settings ---"
adb shell am start -n com.miku.settings/.MikuSettingsActivity
sleep_gap 2.0

echo "    -> Scrolling Settings categories..."
adb shell input swipe "$(px_x 50)" "$(px_y 70)" "$(px_x 50)" "$(px_y 30)" 250
sleep_gap 1.0

echo "    -> Returning to Home..."
adb shell input keyevent KEYCODE_HOME
sleep_gap 1.0

echo "=== [All MikuOS Gesture & Interaction Tests Completed Successfully] ==="
