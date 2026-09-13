# M500 — the Miku Music suite

Modding workspace for the **HiBy Digital M500 x Hatsune Miku** DAP: a full replacement software
suite (player, widget, tape deck, tools) that turns the stock HiBy firmware experience into a
Miku-branded, open, hackable one — while keeping bit-perfect output on the M500's dual CS43198
DACs.

## What's in here

| Directory | What it is |
| --- | --- |
| `miku-player-kotlin/` | **Miku Music — An Open Source Music Player.** Native Kotlin/Compose player (`com.miku.player`): Media3 playback + MediaSession, real libprojectM 4.2 visualizer, spec-exact Tape Mode, native Now-Playing home-screen widget, likes/playlists/history, HiBy DAC-settings awareness. *Its own git repo — push separately.* |
| `miku-assets/` | Icons, artwork, fonts, and other shared brand assets. |
| `library/` | On-device library DB work: true per-track sample rate / bit depth read via `MediaMetadataRetriever`. |
| `tools/` | apktool, signing helpers, `framework-m500` staging, misc scripts. *(Gradle distribution and keystores are not committed.)* |
| `notes/` | The M500/MIKU audio guide, metrics reports, and research notes. |
| `device-dumps/`, `crash-logs/` | Small device configs and debugging breadcrumbs. |

**Zero-Smali Production Policy & Pure Kotlin Target:** All decompiled/modded HiBy smali material is archived. The suite's production target is **100% Native Kotlin & Compose** with zero smali patches in final releases. Smali modification is permitted solely as a development-phase prototyping tool to reverse-engineer vendor registers before writing full Kotlin implementations (see [docs/08_architecture_directive_pure_kotlin_target.md](docs/08_architecture_directive_pure_kotlin_target.md)).

## The device

- HiBy Digital M500 (x Hatsune Miku edition), Android 14-based firmware, 3.2" portrait screen.
- Dual Cirrus Logic CS43198 "MIKU DAC"; audio behavior is driven by `vendor.audio.hiby.*` global
  settings (filter, DRE, gain) — see `notes/M500_MIKU_Audio_Guide.md`.
- Physical controls (power, volume wheel, play/pause, next/prev, Fn) on the right edge.

## The poor man's ambient light sensor

The M500 has no ambient light sensor. There is no ALS in the hardware, nothing under
`/sys/class/sensors`, and `SensorManager.getDefaultSensor(TYPE_LIGHT)` returns null. Stock firmware
has no auto-brightness for that reason, which is a genuine problem on a device you use outdoors:
walk into direct sun with the screen still on an indoor level and it is too dim to read well enough
to find the brightness slider.

So MikuOS measures the light with the only light-sensitive part the device actually has: **the
camera**. Auto-exposure is a light meter. Point one at a scene, let it settle, and ask it what
exposure it chose — that answer is a measurement of how bright the room is.

**How it works** (`hardware-settings/`, package `com.m500.hardware`):

1. The screen turns on. `AmbientBrightnessService` holds a runtime-registered `ACTION_SCREEN_ON`
   receiver (that broadcast cannot be declared in a manifest, so something resident has to own it).
2. `AmbientCamera` opens the camera, captures **one** frame, and reads back the exposure the
   auto-exposure algorithm settled on: ISO, exposure time, and aperture.
3. Those go through the standard photographic exposure equation to an EV100 value, and EV100
   converts to lux. This is real photometry, not a guess — it is the same maths a light meter uses.
   If the exposure metadata is unavailable it falls back to mean frame luma, and marks the reading
   as untrusted.
4. `AmbientBrightnessManager` maps lux to a 0-255 brightness on a logarithmic curve (perception of
   brightness is logarithmic, and the useful range spans ~5 lux to ~50,000 lux — four orders of
   magnitude) and applies it.

**The rules it follows, and why:**

- **Sample on wake, never continuously.** In a pocket the lens is covered and reads near-black. A
  continuous loop would drive brightness *down* right before you pull the device out, which is the
  exact opposite of what is wanted. Screen-on is the moment the reading is both meaningful and
  needed. It also means the camera privacy indicator never flashes at random.
- **Eager to raise, reluctant to lower.** A wrong bright reading costs a little battery. A wrong
  dark reading costs an unreadable screen, which is the failure this exists to fix. Lowering
  requires a trusted exposure-derived reading and is clamped to a floor of 40/255.
- **Never fight the user.** A manual brightness change stands until the next wake.
- **Never sample while the Fn switch is locked.** The device is in a pocket or a bag, the lens is
  covered, and the reading means nothing.
- **Hysteresis of 18/255**, so it does not visibly hunt.

**Requirements.** `CAMERA` (granted at build time, it is a system app), and the `WRITE_SETTINGS`
appop, which the build script grants on first boot. No root. `AmbientBrightnessManager.probe()`
reports what the camera currently thinks without changing anything, and the last reading is
readable from `settings get global m500_ambient_last_lux`.

**Limits, stated plainly.** One frame per wake, so it reacts at wake and not before. It reads the
light at the *back* of the device, which is usually but not always the light at the front. A lens
covered by a finger or a case reads dark, and the eager-to-raise rule is what stops that mattering.

## Root is optional

Nothing in MikuOS requires root. The OS is platform-signed with the Falcon Technix key, which is
what grants it the system permissions it needs, and every feature ships a working root-free path.

Root is supported as a **power-user enhancement**: where su is present, `RootShell` will use it to
reach things the platform will not hand over (the SELinux-locked Pulsar LED nodes being the obvious
one). Where it is absent, the probe latches once, logs once, and stops — and the feature either
works through its platform path or honestly reports itself unavailable in the interface.
`RootShell.recheck()` clears that latch for a user who grants root later.

## Rebuilding the smali mods

The HiBy apps reference private Android 14 framework resources, so apktool needs the device's own
framework:

```sh
# once: stage the device framework for apktool
adb pull $(adb shell pm path android | cut -d: -f2) framework-res.apk
mkdir -p framework-m500 && cp framework-res.apk framework-m500/1.apk

# rebuild a decompiled tree
apktool b music-mod/decoded -p framework-m500
# then zipalign + sign (platform keys for WRITE_SECURE_SETTINGS features)
```

Gotchas that are already handled in the decompiled trees: private `@android:` refs are prefixed
`@*android:`, and dangling Material palette color refs are inlined as hex.

## The Kotlin player

`miku-player-kotlin/` carries its **own** git history and README — build with:

```sh
cd miku-player-kotlin
JAVA_HOME=~/.local/toolchains/jdk17 ./gradlew :app:assembleDebug
```

## Status / roadmap

Live TODOs tracked out-of-repo: Last.fm scrobbling + listen locations, gamification
(100+ achievements), station/auto-DJ mode, BT phone remote, weather widget, HiBy Tape mod,
pocket-lock OS patch, taste/affinity engine.

---
Open source — have fun with it! But if you're from HiBy and use this code, please attribute me and MAYBE send over some free samples of new gear! 😉

Maintained by **sworrl** <agent.jearl@gmail.com>.
