# HiBy M500 — System-Level Fn Lock OS Patch Specification

## Overview

This specification details the OS-level system modification for the **HiBy Digital M500** Android 14 firmware.

Currently, the hardware **Fn switch** (tracked by system property `fn_status` in `Settings.Global`) triggers HiBy's system service, but suffers from edge case latency and incomplete coverage when attempting to block both touch AND physical side buttons simultaneously.

The **in-app `FnTouchGuard`** in `com.miku.player` serves as an application-level stopgap. The definitive solution described here is an AOSP framework patch in `services.jar` (`com.android.server.policy.PhoneWindowManager` and `com.android.server.input.InputManagerService`).

---

## Technical Design: System-Level Patch

### 1. Targets & Scope
- **Target File:** `/system/framework/services.jar`
- **Classes to Patch:**
  - `com.android.server.policy.PhoneWindowManager`
  - `com.android.server.input.InputManagerService`

### 2. Behavior Specification
When the Fn physical switch is toggled **ON** (`Settings.Global.fn_status == 1`):
1. **Touch Interception:**
   - Registers a system-wide `InputConsumer` (`fn_touch_lock`) directly in the Window Manager Service (WMS) input pipeline.
   - All MotionEvents (`ACTION_DOWN`, `ACTION_MOVE`, `ACTION_UP`) across all layers, SystemUI, and third-party apps are consumed and dropped at the driver level before hit-testing.
2. **Physical Key Interception:**
   - In `PhoneWindowManager.interceptKeyBeforeQueueing(KeyEvent event, int policyFlags)`:
     - Checks `fn_status == 1`.
     - When active, swallows all physical key events:
       - `KEYCODE_VOLUME_UP` / `KEYCODE_VOLUME_DOWN`
       - `KEYCODE_MEDIA_PLAY_PAUSE` / `KEYCODE_MEDIA_PLAY` / `KEYCODE_MEDIA_PAUSE`
       - `KEYCODE_MEDIA_NEXT` / `KEYCODE_MEDIA_PREVIOUS`
     - **Safety Bypass:** Allows a 3-second long-press on `KEYCODE_POWER` to pass through for emergency reboots/screens.
3. **Instant Off-Edge Release:**
   - Binds a native ContentObserver directly inside SystemServer on `Settings.Global.getUriFor("fn_status")`.
   - On `fn_status -> 0`, immediately unregisters `InputConsumer` and clears key drop flags with <1ms latency.

---

## Assembly / Smali Blueprint

### `PhoneWindowManager.smali` Patch Point

In `interceptKeyBeforeQueueing(Landroid/view/KeyEvent;I)I`:

```smali
# Read Settings.Global.fn_status
const-string v0, "fn_status"
const/4 v1, 0x0
invoke-static {p0, v0, v1}, Landroid/provider/Settings$Global;->getInt(Landroid/content/ContentResolver;Ljava/lang/String;I)I
move-result v0

if-eqz v0, :fn_normal_processing

# If fn_status == 1, check if key is Power (26)
invoke-virtual {p1}, Landroid/view/KeyEvent;->getKeyCode()I
move-result v1
const/16 v2, 0x1a # KEYCODE_POWER
if-ne v1, v2, :drop_key

# Drop key event
const/4 v0, 0x0 # ACTION_PASS_TO_USER = 0, return 0 to swallow
return v0

:fn_normal_processing
```

---

## Status & Migration Plan

- **Phase 1 (Current):** Application-level guard (`FnTouchGuard` in `com.miku.player`) catches touches inside Miku Music + sets `fn_settings = "Both"`.
- **Phase 2 (Planned Framework Build):** Decompile device `services.jar` via `apktool` / `baksmali`, inject the `fn_status` double-interceptor, reassemble, sign with platform keys, and flash to `/system/framework/services.jar`.
