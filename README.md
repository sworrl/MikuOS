<p align="center">
  <img src="assets/readme_banner.webp" alt="MikuOS">
</p>

<h1 align="center">MikuOS</h1>

<p align="center"><em>A platform-signed Android 14 replacement OS for the HiBy Digital M500 x Hatsune Miku DAP. Bit-perfect audio, no fabricated readings, no root required.</em></p>

<p align="center">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android%2014%20(SDK%2034)-3ddc84">
  <img alt="Target" src="https://img.shields.io/badge/target-HiBy%20M500%20(khaje)-39C5BB">
  <img alt="Audio" src="https://img.shields.io/badge/audio-dual%20CS43198%20%C2%B7%20DirectPCM-FF2277">
  <img alt="Root" src="https://img.shields.io/badge/root-optional%2C%20never%20required-lightgrey">
</p>

MikuOS replaces the stock HiBy software on the M500 with a suite of six platform-signed Android apps and a rebuilt system image. It keeps the vendor's audio HAL and kernel, swaps out everything the user touches, and is built around one rule that the whole project answers to: **the audio path stays bit-perfect, and nothing on screen shows you a number it did not actually measure.**

**Why it exists.** The M500 is a genuinely good piece of audio hardware (dual Cirrus Logic CS43198 DACs, balanced out, a real volume wheel) running a stock Android build that does not do it justice. There is no status bar, no navigation bar, no auto-brightness, a music app that hides most of what it can do, and an OS that spent its idle time draining the battery. MikuOS is what the device should have shipped with.

**Scope.** One device. The M500 is a Qualcomm SM6225 ("bengal", fastboot product `khaje`) and everything here is built and tested against that unit and only that unit. It is not a GSI and will not boot on anything else.

**What works today.** Everything marked ✅ below is running on the author's M500 right now. The [Tested / Not-Tested](#tested--not-tested) section is the exact line between verified and unproven.

---

## Contents

- [The device](#the-device)
- [What's in the box](#whats-in-the-box)
- [Features](#features)
- [Tested / Not-Tested](#tested--not-tested)
- [Install (web installer)](#install-web-installer)
- [Install (by hand)](#install-by-hand)
- [Build the apps](#build-the-apps)
- [Build the system image](#build-the-system-image)
- [Architecture](#architecture)
- [The poor man's ambient light sensor](#the-poor-mans-ambient-light-sensor)
- [Root is optional](#root-is-optional)
- [Permissions](#permissions)
- [Known limitations](#known-limitations)
- [Repo structure](#repo-structure)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Legal](#legal)

---

## The device

Everything below was read off a running M500, not from a spec sheet.

| | |
|---|---|
| **SoC** | Qualcomm SM6225 (Snapdragon 680), board `bengal`, 8 cores, arm64-v8a |
| **Memory** | 4 GB RAM, 64 GB storage, microSD |
| **Display** | 720 x 1280, 360 dpi, 3.2" portrait |
| **DAC** | Dual Cirrus Logic CS43198 |
| **Outputs** | 3.5 mm single-ended, 4.4 mm balanced, USB UAC2 DAC out, internal speaker |
| **Power** | CellWise CW2015 fuel gauge, MP2731 charger |
| **Controls** | Power, volume wheel, play/pause, next/prev, and a physical Fn slide switch |
| **Sensors** | No ambient light sensor. See [the poor man's ALS](#the-poor-mans-ambient-light-sensor). |
| **Android** | 14 (SDK 34) framework on a HiBy Android 13 vendor base, kernel 5.15.153 |
| **Bootloader** | fastboot product `khaje`, A/B slots, dynamic `super` partition |
| **Signing** | Falcon Technix platform key, replacing the public AOSP test keys |

---

## What's in the box

MikuOS is six Android apps in one Gradle project, plus the scripts that bake them into a system image.

| Module | Package | Version | What it is |
|---|---|---|---|
| `app` | `com.miku.player` | 2.0.266 | **Miku Music.** The player. Also published on its own at [sworrl/MikuMusic](https://github.com/sworrl/MikuMusic). |
| `mikuos-launcher` | `com.miku.launcher` | 0.1.49 | Home screen, status bar, lockscreen, always-on display, weather, observatories |
| `mikuos-systemui` | `com.miku.systemui` | 0.1.18 | Navigation gestures, notification shade, quick settings, power menu |
| `mikuos-settings` | `com.miku.settings` | 0.1.8 | System settings |
| `hardware-settings` | `com.m500.hardware` | 1.0.8 | Ambient light, Fn pocket lock, USB DAC, cell radio saver, DAC controls |
| `fmradio` | `com.caf.fmradio` | 1.0.0 | FM tuner, shipped under the vendor package name so SELinux grants it the tuner |

The M500 ships with **no navigation bar and no status bar**. MikuOS provides both; the launcher draws the status bar and the SystemUI module is an accessibility service that owns navigation.

---

## Features

### Audio

| | Status | Notes |
|---|---|---|
| Bit-perfect DirectPCM to the CS43198 | ✅ | 24 and 32 bit integer passthrough at the file's native rate. No mixer, no resampling. |
| DTA direct output | ✅ | App is added to the platform allow-list before the first AudioTrack is built; the framework checks that per track at construction. |
| Highest quality enforced, not offered | ✅ | HIGH DAC gain re-applied on every start and pushed into the HAL; full volume range unlocked past HiBy's per-jack cap. |
| DAC controls that actually land | ✅ | Digital filter, DRE, high power, DSD gain compensation, all via the HAL parameter path. |
| USB DAC mode | ✅ | Reads the real gadget state and ALSA stream params; says whether audio is actually flowing. |
| Bluetooth codec lockdown | ✅ | Asks for LDAC 990; any downgrade needs an explicit on-screen confirm. |

### System

| | Status | Notes |
|---|---|---|
| Navigation | ✅ | Edge-swipe back, home pill, top-edge pull for the shade. Overlays sit above third-party apps, so the shade pulls down over Spotify too. |
| Notification shade + quick settings | ✅ | |
| Status bar | ✅ | Clock, signal, battery, now playing, audio quality. Battery reads the sticky broadcast on first draw, never a default. |
| Lockscreen + always-on display | ✅ | Reads whatever holds the media session, so Spotify shows up in the Miku layout. |
| Fn switch pocket lock | ✅ | Root-free. Touch, transport keys, volume wheel and power are disabled via the input manager and the screen blanks. The switch itself is never disabled, so unlock always works. |
| Ambient auto-brightness | ✅ | Camera-derived. [Details below](#the-poor-mans-ambient-light-sensor). |
| Idle power | ✅ | The launcher's 24/7 GPS listener is gone; live GPS is reference-counted and only runs while the map is open. Cell radio powers down after 10 min out of service on Wi-Fi. |
| Plug-wake screen strobing | ✅ | Gated through theater mode, the only gate the HiBy framework honors. |
| WireGuard client | ✅ | In the launcher. |
| Media ingest over rsync | ✅ | |
| First-run onboarding | ✅ | |
| FM tuner | ✅ | WAV recording, spectrum computed from the live FM audio. |
| Auto-rotate | ✅ | Defaults off. Baked into the image. |

### Honesty

Every gauge, badge and status line either shows a value read from a real source or shows a dash. That sounds obvious. It was not true for a long time, and fixing it took several passes across all six modules. Things that used to be invented and are now measured: a status bar battery that read 100% while the gauge said 48; signal bars that showed full strength whenever the modem had never reported; a charging screen that dropped the sign off the current; a lockscreen that credited any untagged track to Hatsune Miku and wrote that into history; a USB DAC page claiming lock and zero underruns as fixed text; sine-wave VU meters; a BPM screen that defaulted to a hardcoded track and broadcast 165 BPM with nothing playing.

For the player's own feature list, see [sworrl/MikuMusic](https://github.com/sworrl/MikuMusic).

---

## Tested / Not-Tested

**Verified on the author's M500 (khaje), kernel 5.15.153, MikuOS image built 2026-09:**

- Full flash via the web installer, update path and clean-wipe path
- Cold boot, first-boot provisioner, adb pre-auth
- DirectPCM at 16/44.1, 24/48, 24/96, 24/192, and DSD
- Both jacks, USB DAC out, Bluetooth LDAC
- Fn lock across screen on and off
- Ambient brightness: set to 20, wake, metered 8 lux, raised to 82 (logged)
- Miku Music cold-launched four times with listening stats on, zero crashes
- 24 h idle with the launcher GPS fix in place

**Not tested, and stated plainly:**

- Any device other than the author's own M500
- Kernel 5.15.209 is built and boots but is **disqualified** (see [Known limitations](#known-limitations))
- A fresh system image built from this exact tree on a clean checkout; the author's builds come from a working tree with a few local artifacts the tree does not contain (GApps download cache, stock APK set)
- The Cloudflare entitlement worker under `tools/entitlement-worker` is written and not deployed
- The BLE remote's companion PWA under `tools/remote-pwa` needs HTTPS hosting that is not set up

If you run MikuOS on your own M500 and something in the first list does not hold, that is a bug. Open an issue with `logcat` and the output of `fastboot getvar all`.

---

## Install (web installer)

Browser-based, over WebUSB. Needs Chrome or Edge on a desktop and a USB cable. Firefox does not do WebUSB.

1. **Charge past 50%.** Fastboot does not charge the battery on this device and the flash takes about ten minutes. If the bootloader reports 0 mV, that is a fake reading from a device that has been in fastboot too long, not a dead battery; power-cycle it.
2. Reboot to the bootloader: `adb reboot bootloader`
3. Open the installer, pick the device, and confirm it reports product **`khaje`**. The installer refuses anything else.
4. Choose **update** to keep your music and settings, or **clean install** to wipe. Update is the normal path.
5. Let it run. The super image is sent in 64 MiB chunks with per-chunk verification, and the flash is resumable if the cable is knocked.

The installer is a static site under `tools/web-installer` (vendored `fastboot.js`, no server). To host your own copy, serve that directory over HTTPS and point `release.json` at your image; `make_release_manifest.py` writes the manifest with the hashes.

---

## Install (by hand)

If you would rather drive fastboot yourself, `os/` has the scripts the author uses. Read [this warning](#the-64-mib-chunk-rule) first.

```sh
# keep /data
os/flash_mikuos_keepdata.sh

# wipe /data (uses `fastboot -w`, NOT `fastboot erase userdata` - see Troubleshooting)
os/flash_mikuos_clean.sh
```

Both expect the built images in `out/` (see [Build the system image](#build-the-system-image)) and a device already in fastboot.

### The 64 MiB chunk rule

Sending the 5.4 GB `super` image in larger chunks wedges this device's USB gadget mid-flash, and a wedged gadget needs a **physical power cycle** to clear; `fastboot reboot` will not do it. The scripts and the installer chunk correctly. If you flash by hand:

```sh
fastboot -S 64M flash super out/mikuos_super.img
```

Never run two fastboot processes at once against this device.

---

## Build the apps

All six apps build from one Gradle project at the repo root.

**Prerequisites**

- JDK 17
- Android SDK with platform 34 and NDK (for the projectM native build in `app`)
- CMake 3.22+
- The libprojectM source: `app/src/main/cpp/vendor/projectm` must point at a checkout of [projectM-visualizer/projectm](https://github.com/projectM-visualizer/projectm) at 4.2.0 or later. It is a symlink in the author's tree; clone it there or symlink your own.
- For the FM module: `libqcomfm_jni.so` pulled from your own device (see `fmradio/src/main/jniLibs/arm64-v8a/README.md`)

**Signing.** The apps are platform-signed. Create `keystore.properties` next to `build.gradle.kts`:

```properties
platform.storeFile=path/to/your-platform.jks
platform.storePassword=...
platform.keyAlias=platform
platform.keyPassword=...
```

Without it, Gradle builds with the debug key and the apps will not install as system apps on a MikuOS image, because the image was signed with a different platform key. Signing material is gitignored and must never be committed.

**Build**

```sh
JAVA_HOME=~/.local/toolchains/jdk17 ./gradlew assembleDebug        # all six
JAVA_HOME=~/.local/toolchains/jdk17 ./gradlew :app:assembleDebug   # just the player
```

APKs land in `<module>/build/outputs/apk/debug/`.

**The projectM stale-build trap.** `vendor/projectm` is a symlink and Gradle will not traverse it, so after updating projectM the native build silently reports `BUILD SUCCESSFUL` doing nothing and ships the old `.so`. After any projectM update:

```sh
rm -rf app/.cxx app/build/intermediates/cmake
```

**Deploy to a device**

```sh
adb install -r app/build/outputs/apk/debug/MikuMusic-v*.apk
```

Never uninstall the player to reinstall it. A debug/release uninstall cycle wipes liked songs and listening history. `install -r` over the top is always safe.

---

## Build the system image

`os/build_mikuos_super.sh` takes stock M500 partition images and produces a MikuOS `super.img`. It is a long script with a lot of hard-won gates in it. In order, it:

1. **Expands** the stock ext4 images to make working space.
2. **Un-shares** ext4 `shared_blocks`. Stock images use them, and writing to a shared-blocks filesystem with `debugfs` silently corrupts random other files. This step **must** run before any write, and used to run after, which was the cause of a whole class of flaky boots.
3. **Injects** the six MikuOS APKs into `system`, plus the first-boot provisioner, boot voice, animation overlay, and APN config.
4. **Re-keys** the platform: replaces the AOSP public test keys throughout `system` and `product` with the MikuOS key set, preserving the `security.selinux` xattr on every file it touches (stripping it hangs the boot). NetworkStack and the mainline APEX modules are deliberately excluded; re-keying those bootloops.
5. **Verifies** every injected file owns real data blocks. `debugfs` also silently no-ops on a full filesystem, so this gate catches an image that looks built and is not.
6. **Shrinks** the images to minimal size and packs `super`.

Inputs it needs that this repo does not ship: the stock partition images from your own device, your platform keys, and optionally a GApps package. Outputs go to `out/`. Read the header of the script before running it; it names every path.

An optional Wi-Fi pre-seed for first boot comes from `os/mikuos-dev-wifi.conf` (gitignored; see the `.example`).

---

## Architecture

### Directory structure

```
MikuOS/
├── app/                      Miku Music (com.miku.player)
│   └── src/main/
│       ├── java/com/miku/player/
│       │   ├── api/          local HTTP API + web remote
│       │   ├── bpm/          on-device tempo analysis
│       │   ├── booklet/      album booklet / PDF viewer
│       │   ├── discsplit/    CUE and cue-less disc image splitting
│       │   ├── radio/        FM tuner engine + Miku Radio station mode
│       │   ├── remote/       BLE GATT peripheral (phone as remote)
│       │   ├── scrobble/     Last.fm with offline queue
│       │   ├── stats/        per-listen database
│       │   ├── taste/        affinity model + co-occurrence graph
│       │   ├── visualizer/   Miku Shaders (GLES2 feedback engine)
│       │   ├── TapeMode.kt   the cassette deck
│       │   └── ...
│       ├── cpp/              libprojectM 4.2 JNI bridge, M500 audio HAL shim
│       ├── assets/presets/   Milkdrop presets
│       └── res/font/         Audiowide, Orbitron, Righteous, Baloo 2, Mochiy Pop, DotGothic16, Monoton, Permanent Marker, Kalam
├── mikuos-launcher/          home, status bar, lockscreen, AOD, weather, observatories, VPN, ingest
├── mikuos-systemui/          accessibility-service navigation, shade, QS, power menu
├── mikuos-settings/
├── hardware-settings/        ambient light, Fn lock daemon, USB DAC, cell radio saver, DAC controls
├── fmradio/                  FM tuner UI under the vendor package name
├── qcom-fmradio-stubs/       compile-time stubs for the vendor FM API
├── os/                       system image build + flash scripts, APN config
├── tools/
│   ├── web-installer/        WebUSB flasher (static site)
│   ├── remote-pwa/           Web Bluetooth remote for the player
│   ├── entitlement-worker/   Cloudflare Worker (not deployed)
│   ├── rsync/                media ingest daemon config
│   └── *.sh, *.py            signing, verification, unbrick, library DB
├── docs/                     hardware report, audio architecture, signing/PKI, reverse-engineering reference
└── assets/                   README images
```

### How navigation works with no system bars

The M500's stock framework ships without a status bar or navigation bar. `mikuos-systemui` is an **accessibility service**, which is the one process type Android lets draw over every other app and receive every touch. It puts four transparent overlays on the edges: left and right for back, bottom for the home pill, and a 40 dp strip at the top for the shade pull. Because they are accessibility overlays they sit above third-party apps, so the shade pulls down over Spotify. The power menu rides the long-press-power-to-assistant path, since that is the only long-press hook the HiBy framework exposes.

### How the audio lock works

HiBy's framework has a per-jack volume cap and a "raise lock" that only gates the knob's `adjustStreamVolume` path. Miku Music drives the wheel through `setStreamVolume` instead, which the lock does not cover, and asks the HAL for the full range once at startup. DAC settings (`vendor.audio.hiby.*`) are written to `Settings.Global` **and** pushed through `AudioManager.setParameters`, because the HAL reads them from parameters at track construction and only some paths re-read the setting.

### How the Fn lock works

The HiBy framework honors `Settings.Global.button_lock`: with it set, the framework itself ignores every hardware key, screen on or off. `FnLockDaemon` in the hardware module is the always-alive applier; it watches the switch and writes the setting. Touch is disabled through `InputManager.disableInputDevice` on the Goodix controller, and the screen is blanked. The `gpio-keys-hiby` device is **never** disabled, because the Fn switch is on it.

### Signing

The whole OS is signed with the Falcon Technix platform key. The public AOSP test keys are replaced throughout `system` and `product` at image build time, so MikuOS apps get signature-level permissions (`WRITE_SECURE_SETTINGS`, `MANAGE_APP_OPS_MODES`, `DISABLE_INPUT_DEVICE`, and so on) without root. Two things stay on their original signatures: NetworkStack, whose shared UID is split with an APEX and cannot be re-keyed on Android 14 without a PMS fatal, and the mainline APEX modules, which `apexd` rejects when re-signed by hand. `docs/09_mikuos_signing_and_pki_architecture.md` has the full story.

---

## The poor man's ambient light sensor

The M500 has no ambient light sensor. There is no ALS in the hardware, nothing under `/sys/class/sensors`, and `SensorManager.getDefaultSensor(TYPE_LIGHT)` returns null. Stock firmware has no auto-brightness for that reason, which is a genuine problem outdoors: walk into direct sun with the screen still on an indoor level and it is too dim to read well enough to find the brightness slider.

So MikuOS measures the light with the only light-sensitive part the device actually has: **the camera**. Auto-exposure is a light meter. Point one at a scene, let it settle, and ask it what exposure it chose; that answer is a measurement of how bright the room is.

**How it works** (`hardware-settings`, `AmbientCamera.kt` and `AmbientBrightnessManager.kt`):

1. The screen turns on. `AmbientBrightnessService` holds a runtime-registered `ACTION_SCREEN_ON` receiver (that broadcast cannot be declared in a manifest, so something resident has to own it).
2. `AmbientCamera` opens the camera, captures **one** frame, and reads back the exposure the auto-exposure algorithm settled on: ISO, exposure time, aperture.
3. Those go through the photographic exposure equation: `EV100 = log2(N² / t) − log2(S / 100)`, and `lux ≈ 2.5 × 2^EV100`. This is real photometry, the same maths a light meter uses. If the exposure metadata is unavailable it falls back to mean frame luma and marks the reading untrusted.
4. `AmbientBrightnessManager` maps lux to brightness on a logarithmic curve (perception is logarithmic, and the useful range spans ~5 lux to ~50,000 lux) and applies it.

**The rules it follows, and why:**

- **Sample on wake, never continuously.** In a pocket the lens is covered and reads near-black. A continuous loop would drive brightness *down* right before you pull the device out. Screen-on is the moment the reading is both meaningful and needed, and the camera privacy indicator never flashes at random.
- **Eager to raise, reluctant to lower.** A wrong bright reading costs a little battery. A wrong dark reading costs an unreadable screen, which is the failure this exists to fix. Lowering needs a trusted exposure-derived reading and is floored at 40/255.
- **Never fight the user.** A manual brightness change stands until the next wake.
- **Never sample while the Fn switch is locked.** The lens is covered and the reading means nothing.
- **Hysteresis of 18/255**, so it does not hunt.

**Verified:** brightness set to 20, device slept and woken in a dim room, camera metered 8 lux from a trusted exposure, brightness raised to 82. `settings get global m500_ambient_last_lux` shows the last reading.

**Limits.** One frame per wake, so it reacts at wake and not before. It meters the *back* of the device, which is usually but not always the light at the front. A lens covered by a finger reads dark, and the eager-to-raise rule is what stops that mattering.

---

## Root is optional

Nothing in MikuOS requires root. The platform signature is what grants the system permissions it needs, and every feature ships a working root-free path.

Root is supported as a **power-user enhancement**. Where `su` is present, `RootShell` uses it to reach things the platform will not hand over; the SELinux-locked Pulsar LED nodes are the obvious case. Where it is absent, the probe runs once, logs once, and stops, and the feature either works through its platform path or says it is unavailable in the interface. `RootShell.recheck()` clears that answer for a user who grants root later. Before this was fixed, an animation loop in the hardware daemon was forking a nonexistent `su` thirty times a second; if you see a `RootShell` stack trace flood in `logcat`, you are on an old build.

`os/enable_root.sh` and `os/disable_root.sh` flash a Magisk-patched or stock `init_boot` respectively. That is the whole root story: it is an `init_boot` swap, nothing in `system` changes.

---

## Permissions

Miku Music declares the following. Most are signature-level and only work because the app is platform-signed on a MikuOS image.

| Permission | Why |
|---|---|
| `MODIFY_AUDIO_SETTINGS`, `WRITE_SECURE_SETTINGS`, `WRITE_SETTINGS` | DAC gain/filter/DRE, volume range, HiBy vendor settings |
| `DISABLE_INPUT_DEVICE`, `DEVICE_POWER` | Fn pocket lock |
| `MANAGE_APP_OPS_MODES` | Self-grants the appops the HiBy framework gates features on |
| `BLUETOOTH_*`, `BLUETOOTH_PRIVILEGED` | LDAC codec preference, BLE remote peripheral |
| `RECORD_AUDIO` | Visualizer audio capture, FM recording |
| `CAMERA` | Not used by the player; the ambient light sensor lives in `hardware-settings` |
| `ACCESS_FINE_LOCATION` | Listen locations for stats, GPS observatory. Opt-in. |
| `MANAGE_EXTERNAL_STORAGE`, `READ_MEDIA_*` | The music library on the SD card |
| `SCHEDULE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`, `WAKE_LOCK` | The alarm clock, which has to ring from deep sleep |
| `SYSTEM_ALERT_WINDOW` | Fn lock touch-eating overlay, now-playing HUD |
| `QUERY_ALL_PACKAGES` | The launcher and the car/BT audio router need to see every app |
| `INTERNET`, `ACCESS_NETWORK_STATE` | Last.fm, weather, artist photos, MusicBrainz. Every one is opt-in or off by default. |

---

## Known limitations

Current, and stated plainly rather than left for you to find.

| | |
|---|---|
| **Pulsar RGB indicator** | Does not work on this unit without root. SELinux-locked with no consumer service and a missing factory-test config. The setting is stored, the interface says the light will not respond. With root it may. |
| **Kernel 5.15.209** | Builds and boots, the DAC works, but the MP2731 charger driver never qualifies the input, so it drains on the cable, and the plug-wake path strobes the screen. Disqualified after an A/B test. The release ships stock 5.15.153. |
| **Visualizer frame rate** | Heavy Milkdrop presets run ~24 fps at half resolution. That is this GPU. Mesh is capped at 24x18 and hard cuts are off; the perf ledger retires the worst presets automatically. |
| **Google Fi** | A data-only Fi SIM is T-Mobile-only and cannot switch carriers without the Fi app. The `h2g2` APNs are baked in and there is a force-T-Mobile toggle, which needs T-Mobile coverage to help. |
| **APEX modules** | Keep their original signatures; see [Signing](#signing). |
| **Fresh-build GMS loop** | A fresh `/data` with GApps can RescueParty-loop because GMS loses the SafetyCenter privapp permission. This is a GApps packaging issue, not a MikuOS bug; the provisioner works around it. |
| **Miku Shaders** | Five presets. Real Milkdrop presets number in the thousands, and projectM is the engine for those; the shader engine is the lighter option for when the GPU is hot. |

---

## Repo structure

| Path | What |
|---|---|
| `app/` … `fmradio/` | The six apps. Each is a standard Android Gradle module. |
| `qcom-fmradio-stubs/` | Compile-time stubs so `fmradio` builds without the vendor jar. |
| `os/` | `build_mikuos_super.sh` and the flash/root/resign scripts. |
| `tools/web-installer/` | The WebUSB flasher. Static; host it anywhere with HTTPS. |
| `tools/remote-pwa/` | Web Bluetooth remote for the player. Needs HTTPS hosting. |
| `tools/entitlement-worker/` | Cloudflare Worker for optional entitlement checks. Not deployed; the client is fail-open. |
| `tools/rsync/` | rsync daemon config for media ingest. PII-free template. |
| `tools/*.sh` | `sign_apk.sh`, `verify_signatures.sh`, `unbrick_factory.sh`, `root_device.sh`, `unroot_device.sh`, `package_mikuos_system.sh` |
| `docs/` | Numbered reports. `06_m500_complete_reverse_engineering_reference.md` and `03_audio_architecture_guide.md` are the ones to read first. |
| `CHANGELOG.md` | Player changelog. |

Not in the repo, on purpose: signing keys, `local.properties`, the stock partition images, the GApps cache, decompiled HiBy vendor code, and `libqcomfm_jni.so`.

---

## Troubleshooting

**Device shows in `fastboot devices` but every command says `< waiting for device >`.** Something else holds the USB device. On a Proxmox host that is a VM with USB passthrough. Detach it, flash, re-attach.

**Flash hangs at 0 bytes, fastboot is in D state.** The USB gadget is wedged. Physical power cycle. Do not send `super` in chunks bigger than 64 MiB.

**`fastboot erase userdata` then bootloop.** Raw-erased `userdata` has no filesystem and the device will not format it. Use `fastboot -w`, or `os/flash_mikuos_clean.sh` which does.

**Boot hangs after re-signing anything.** The `security.selinux` xattr was stripped. `os/resign_system.sh` preserves it; if you re-signed by hand, re-run through the script.

**`com.android.systemui` crash-loops, no navigation, FM dead.** SystemUI got signed with the Falcon key on an image whose framework was not re-keyed, or vice versa. The build script re-signs SystemUI to whichever platform key the image is on and gates on it before flash; a hand-built image can skip that.

**Fresh image, "Allow USB debugging" prompt on every wipe.** The host adb key is baked into `/adb_keys` and a `/data` seed by the build script; `ro.adb.secure=0` alone is not reliable. Rebuild with your own `~/.android/adbkey.pub` in place.

**`debugfs` writes report success but the file is unchanged on the device.** `debugfs write` silently no-ops on an existing path and on a full filesystem. The build script uses a delete-then-write helper and gates on free space; if you are hand-editing an image, delete first and check `df`.

**Miku Music crashes at launch with "Unsupported concurrent change during composition."** You are on a build older than 2.0.263. Object-scope Compose state was being written from a background thread.

**Launcher flooding Magisk with greyed-out su prompts.** Old build. See [Root is optional](#root-is-optional).

---

## Contributing

Issues and pull requests are welcome. Things that would help most:

- Reports from other M500 units, especially the non-Miku edition. The hardware should be identical and the images should boot; nobody has confirmed it.
- Kernel work on the MP2731 charger path in 5.15.209, which is the only thing keeping the release on 5.15.153.
- Milkdrop preset curation for the Adreno 610. The perf ledger will tell you which ones it retired.
- A DAC/HAL-level route for the Pulsar LED that does not need root.

Attribution goes to the human author only. No AI co-author trailers in commits.

---

## Legal

MikuOS is released under the [MIT License](LICENSE).

MikuOS is an independent project. It is not affiliated with, endorsed by, or supported by HiBy Digital or Crypton Future Media. Hatsune Miku is a trademark of Crypton Future Media, Inc. The HiBy vendor partitions, kernel, audio HAL, and `libqcomfm_jni.so` are HiBy's and Qualcomm's and are not redistributed here; you supply them from your own device.

Built on [libprojectM](https://github.com/projectM-visualizer/projectm) (LGPL-2.1), [Media3](https://github.com/androidx/media), and AOSP.

Maintained by **sworrl** <agent.jearl@gmail.com>.
