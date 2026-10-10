# M500 haptics

What the vibration motor in the M500 can do, what Android does with it, and the pulse lengths MikuOS uses. Measured on MikuOS 0.3.0 (Android 14, SDK 34) on 2026-10-10.

## Hardware

- **One vibrator.** `cmd vibrator_manager list` prints only id `0`.
- **Driver.** The motor hangs off a GPIO. The kernel side is the old Android `timed_gpio` driver (`timed_gpio.ko` plus `timed_output.ko` in vendor_dlkm, platform device `soc:timed-gpio`, node `/sys/class/timed_output/vibrator/enable`). It sets the GPIO high, starts an hrtimer for the requested milliseconds, then sets it low. There is no amplitude control, no braking and no effect library.
- **Other haptic drivers.** `leds_qpnp_vibrator_ldo` is loaded but nothing binds to it. `/sys/class/qcom-haptics` does not exist. The vendor init still writes `transient` to `/sys/class/leds/vibrator/trigger`, which is a leftover.
- **HAL.** `vendor.qti.hardware.vibrator.service` (QTI AIDL, `android.hardware.vibrator-V2`). It probes an input force-feedback device first, then `timed_output`, then the LED class. On the M500 it ends up on `timed_output`.
- **What the framework sees.** Capabilities `ON_CALLBACK, PERFORM_CALLBACK` (flags 11). `mSupportedEffects=[]`. Primitives are listed with 0 ms, but none of them play. No amplitude control, no compose.
- **Sysfs from adb.** The `enable` node is SELinux `sysfs_vibrator` and the shell cannot read or write it. There is no `su`.

## What plays and what does not

Each test was run with `cmd vibrator_manager synced -f ...` and read back from `dumpsys vibrator_manager` ("Previous vibrations"), with `haptic_feedback_enabled=1`.

| Request | Status | Measured length |
|---|---|---|
| oneshot 5 ms | finished | 7 ms (one cold call took 49 ms) |
| oneshot 8 ms | finished | 11 ms |
| oneshot 10 ms | finished | 12 to 13 ms |
| oneshot 12 ms | finished | 14 to 15 ms |
| oneshot 15 ms | finished | 16 to 17 ms |
| oneshot 20 ms | finished | 22 ms |
| oneshot 25 ms | finished | 28 ms |
| oneshot 30 ms | finished | 32 ms |
| oneshot 40 ms | finished | 42 ms |
| prebaked CLICK, fallback on | finished | 52 ms |
| prebaked TICK, fallback on | finished | 52 ms |
| prebaked HEAVY_CLICK, fallback on | finished | 55 ms |
| prebaked DOUBLE_CLICK, fallback on | finished | 253 ms |
| prebaked TEXTURE_TICK, fallback on | ignored_unsupported | nothing |
| any prebaked, fallback off | ignored_unsupported | nothing |
| primitives CLICK, THUD, TICK, LOW_TICK | ignored_unsupported | nothing |

One-shots run 2 to 3 ms longer than asked. That is framework and HAL overhead. Apart from that the timing is exact.

The fallbacks come from HiBy's framework overlay. `config_virtualKeyVibePattern`, `config_longPressVibePattern` and `config_clockTickVibePattern` are all `0, 50`, and `config_doubleClickVibePattern` is `0, 50, 150, 50` (checked with `cmd overlay lookup android android:array/<name>`). What that means for app code:

- **View and Compose haptics are one flat buzz.** `View.performHapticFeedback` and Compose `LocalHapticFeedback` give the same 50 ms pulse for CLICK, TICK, CONTEXT_CLICK, VIRTUAL_KEY, LONG_PRESS and friends, and 250 ms for REJECT.
- **Some constants play nothing.** CLOCK_TICK, TEXT_HANDLE_MOVE and SEGMENT_FREQUENT_TICK map to TEXTURE_TICK. AOSP 14 falls TEXTURE_TICK back to TICK with fallback turned off, so it ends as `ignored_unsupported`.
- **Amplitude waveforms play as on/off.** There is no amplitude control. From the AOSP code, any nonzero step is driven at full strength. This part was not measured.
- **Use timed one-shots of 20 ms or more.** `VibrationEffect.createOneShot(ms, DEFAULT_AMPLITUDE)` and plain on/off `createWaveform(timings, -1)` are the only things that give a chosen length.

## Settings that gate it

- **`Settings.System.haptic_feedback_enabled` ships as 0.** HiBy's SettingsProvider overlay sets `def_haptic_feedback` to false. With it at 0 the framework sets the TOUCH usage to OFF and drops every short vibration with `ignored_for_settings`. That includes plain `vibrate()` calls with no attributes, because the framework files short effects under TOUCH. This device had it at 0 until 2026-10-10, so every MikuOS haptic before that was silently dropped.
- **Hardware feedback is separate.** `USAGE_PHYSICAL_EMULATION` and `USAGE_HARDWARE_FEEDBACK` follow `hardware_haptic_feedback_intensity` and ignore `haptic_feedback_enabled`. dumpsys showed `TOUCH=OFF` next to `PHYSICAL_EMULATION=MEDIUM`.
- **MikuOS toggle.** `Settings.Global miku_haptics`, default on, is the switch "MikuOS haptics" in Settings > Sound & vibration. The SystemUI, launcher and Miku Music helpers check it together with `haptic_feedback_enabled`. Turning it on also turns Touch vibration on.
- **First run.** The first time MikuOS SystemUI starts and finds `miku_haptics` unset, it writes `miku_haptics=1` and `haptic_feedback_enabled=1`. After that it leaves both alone.
- **Intensity sliders do nothing here.** Without amplitude control the touch intensity scale has nothing to scale.

## How it feels

The motor's mechanical response could not be measured from adb:

- **Accelerometer.** The qma6100 runs at 200 Hz at most. It showed nothing above its noise floor even during a 600 ms pulse, so the motor's vibration is above what it can see.
- **Microphone.** Recording from the shell was refused.

The user's own report decides the floor. MikuPod's 10 ms one-shots reach the HAL as `finished` but cannot be felt. Riot's 22 ms pulses can. So the shortest pulse worth sending is about 20 ms. A DC motor switched by a GPIO, with no overdrive and no braking, needs that long to spin up enough to feel, and it coasts for a while after the GPIO drops. The coast-down length is inferred, not measured, at roughly 30 to 50 ms. HiBy's 50 ms for every system effect reads as a buzz, not a click.

## Recommended values

| Use | Pattern | Notes |
|---|---|---|
| tick: scroll detent, list letter, volume knob step, seek detent, click wheel | 22 ms | Rate limited, see below. 10 ms is not felt |
| click: button, tile tap, dock tap, play/pause, skip | 32 ms | |
| heavy click: confirm, long press, like, BPM perfect | 45 ms | |
| error: refused action, double buzz | 35 on, 80 off, 35 on | The gap is longer than the coast-down, so it reads as two |
| like (launcher) | 22 on, 60 off, 40 on | Light then firm |
| secret or reward unlock (launcher) | 22, 70, 22, 70, 45 | Three rising pulses |
| BPM game | perfect 45 ms, good 22 ms, miss nothing | There is no faint pulse for a miss without amplitude control |

All of these are constants at the top of each helper, so retuning is a one-line change.

## Rate limits

- **A new vibration replaces the running one.** AOSP 14 cancels the current pulse when a new one starts. Firing faster than the pulse length gives one long buzz, not separate clicks.
- **Tick gap.** The helpers drop a tick if the motor is still running the last pulse or fired less than 45 ms ago. Clicks, heavy clicks and patterns always play.
- **Why 45 ms.** That is a 22 ms tick plus some coast-down, about 22 ticks a second at most. At that rate the motor is on half the time. Closer than that, the coast-down from one tick runs into the next and the ticks blur into a hum.
- **Seek scrubbing.** One tick per 10 s of track. On tracks over 10 minutes the step grows to duration / 60, so a full sweep is never more than about 60 ticks.
- **BPM beats are not rate limited.** Beats are always further apart than the gap.

## Where the code is

- SystemUI: `miku-player-kotlin/mikuos-systemui/src/main/java/com/miku/systemui/MikuHaptics.kt`
- Launcher: `miku-player-kotlin/mikuos-launcher/src/main/java/com/miku/launcher/haptics/MikuHaptics.kt`
- Miku Music: `object Haptics` in `miku-player-kotlin/app/src/main/java/com/miku/player/Haptics.kt`
- Settings switch: `miku-player-kotlin/mikuos-settings/src/main/java/com/miku/settings/pages/DevicePages.kt`, Sound page

All three helpers send `USAGE_TOUCH`, so the system Touch vibration setting stays in charge as well.

## Testing from adb

```
adb shell settings get system haptic_feedback_enabled     # must be 1
adb shell settings get global miku_haptics                # null or 1 = on
adb shell cmd vibrator_manager synced -f oneshot 22       # tick
adb shell cmd vibrator_manager synced -f waveform 0 35 80 35   # error pattern
adb shell dumpsys vibrator_manager | grep -A40 "Previous vibrations"
```

`ignored_for_settings` in the dumpsys output means `haptic_feedback_enabled` is 0. `ignored_unsupported` means the effect needs something this motor does not have.
