<h1 align="center">MikuOS</h1>

<p align="center"><em>A platform-signed Android 14 replacement for the HiBy Digital M500 x Hatsune Miku. You own the keys, the DACs, and every number on the screen.</em></p>

<p align="center">
  <img alt="License" src="https://img.shields.io/badge/license-GPL--3.0--or--later-blue">
  <img alt="Base" src="https://img.shields.io/badge/base-Android%2014%20(QSSI)-3ddc84">
  <img alt="Device" src="https://img.shields.io/badge/device-HiBy%20M500%20(khaje)-39C5BB">
  <img alt="Signing" src="https://img.shields.io/badge/signing-your%20own%20platform%20key-FF5FA2">
  <img alt="Root" src="https://img.shields.io/badge/root-not%20required-success">
  <img alt="Status" src="https://img.shields.io/badge/status-daily%20driver-B388FF">
</p>

MikuOS replaces the software on a HiBy Digital M500 x Hatsune Miku DAP. Home screen, system UI,
navigation, settings, hardware controls and [Miku Music](https://github.com/sworrl/MikuMusic) are
ours, re-signed with a platform key you generate yourself, so they run with platform permissions on
a device that is not rooted and does not need to be.

**Why it exists.** The M500 is a very good piece of audio hardware running software that gets in its
way. Playback goes through Android's mixer, so a 44.1kHz file is resampled before it reaches a pair
of DACs chosen specifically for not needing that. The launcher cannot be replaced properly. The
system UI shows readings it did not take. None of that is a hardware limit, all of it is fixable,
and the fix is to replace the software rather than patch around it.

**No root.** Every earlier attempt at this reached for Magisk. MikuOS does not. The apps are signed
with the same platform key as the framework they run beside, so they simply HAVE the permissions
instead of asking a root daemon for them. A `su` failure in this codebase is treated as a bug in the
code, not a reason to install a root daemon.

---

## Contents

- [What is verified](#what-is-verified)
- [What is in the OS](#what-is-in-the-os)
- [The poor man's ambient light sensor](#the-poor-mans-ambient-light-sensor)
- [Building an image](#building-an-image)
- [Flashing](#flashing)
- [Signing and keys](#signing-and-keys)
- [Hard-won platform facts](#hard-won-platform-facts)
- [Repo structure](#repo-structure)
- [The device](#the-device)
- [Known limitations](#known-limitations)
- [Legal](#legal)

---

## What is verified

The line between confirmed on real hardware and not. It is the first section on purpose.

Legend: ✅ confirmed on a real M500 · ⚠️ implemented, not proven · ❌ tried, does not work.

| Thing | State | How it was checked |
|---|---|---|
| Platform-signed apps, no root | ✅ | Running daily. `su` is never invoked anywhere in the shipped code |
| Re-keyed system image boots | ✅ | Known-good image `mikuos_super_rekey1_GOOD_20260827.img`, boot-verified |
| APEX re-signing to a custom key | ✅ | Proven on `com.android.mediaprovider`, compressed `.capex` included |
| Bit-perfect DIRECT output to the DACs | ✅ | 44.1 / 48 / 192kHz, 24-bit packed, confirmed with `dumpsys audio` |
| Gesture navigation replacing the stock nav bar | ✅ | An accessibility service IS the navigation on this device |
| OS-wide idle dim on real system brightness | ✅ | Four-tier ladder writing `Settings.System.SCREEN_BRIGHTNESS` |
| Fn-key pocket lock without root | ✅ | HiBy's framework honors `Settings.Global button_lock` |
| Camera used as an ambient light sensor | ✅ | See below. The device has no ALS at all |
| Custom LED behavior | ✅ | `miku_led.rc` baked into vendor, needs a reflash to take |
| WireGuard client in the launcher | ⚠️ | Implemented, the VPS-relay path for CGNAT is the untested part |
| Web installer (WebUSB fastboot) | ⚠️ | Built and self-contained, never hosted, `EXPECTED_PRODUCTS` unconfirmed |
| Full AOSP-from-source build | ⚠️ | Device tree and lunch combo exist, the sync is RAM-constrained and unfinished |
| GSI (generic system image) | ❌ | Vendor mandates six legacy HIDL services Android 14 dropped. Abandoned for a stock-QSSI base |
| FM tuner | ❌ | SELinux denies `platform_app` access to `/dev/radio0`. Two real paths documented, neither shipped |
| Kernel 5.15.209 | ❌ | A/B proven to break charging: `mp2731` never qualifies the input and the device drains on the cable. Stock 5.15.153 stays |

---

## What is in the OS

| Component | Package | What it does |
|---|---|---|
| **Miku Music** | `com.miku.player` | The player. Bit-perfect, libprojectM, cassette deck. [Its own repo](https://github.com/sworrl/MikuMusic) |
| **Launcher** | `com.miku.launcher` | Home screen, app drawer, lockscreen, AOD, weather, GPS map, network and battery observatories, the ingest engine, the BPM game |
| **System UI** | `com.miku.systemui` | Gesture navigation, notification shade, quick settings, power menu, recents, idle dim, the Pulsar LED |
| **Settings** | `com.miku.settings` | The MikuOS settings app |
| **Hardware** | `com.m500.hardware` | DAC filter, DRE, gain, high-power mode, thermal, the camera light meter |

The launcher and system UI are Gradle modules of the Miku Music build, so they share its theme,
motion and audio code. They live in that repo and ship from this one.

---

## The poor man's ambient light sensor

The M500 has no ambient light sensor. There is no ALS in the hardware, nothing under
`/sys/class/sensors`, and `SensorManager.getDefaultSensor(TYPE_LIGHT)` returns null. Stock firmware
has no auto-brightness for that reason, which is a real problem on a device you use outdoors: walk
into direct sun with the screen on an indoor level and it is too dim to read well enough to find the
brightness slider.

So MikuOS measures the light with the only light-sensitive part the device actually has. The camera.

Auto-exposure is a light meter. Point a camera at a scene, let it settle, and ask it what exposure it
chose. That answer is a measurement of how bright the room is. `com.m500.hardware` opens the camera
at the smallest resolution it supports, waits for AE to converge, reads back the exposure time, ISO
and aperture, and converts them to an EV and then to approximate lux. It samples on a long interval
and only when the screen is on, because a camera left running is a battery and a privacy problem.

It is an inference from a real measurement, not a guess. The reading and its confidence are both
shown, and when AE has not converged it says so instead of printing a number.

---

## Building an image

You need the stock M500 firmware. It is not in this repo and it is not ours to distribute.

```bash
# 1. Put the extracted stock firmware here
#    m500-system-archive/firmware/extracted_1.00/{boot,init_boot,dtbo,vendor_boot,super}.img

# 2. Generate your own platform key set (see Signing and keys)
./mikuos/build/generate_keys.sh        # or bring your own into mikuos/signing/

# 3. Build the super image
./mikuos/build/build_mikuos_super.sh
```

`build_mikuos_super.sh` unpacks super, resizes the partitions, re-keys the framework and apps to
your platform key, injects the MikuOS apps and configs, and repacks. It produces
`mikuos/out/mikuos_system_bundle.img`, about 5GB.

**Order matters and the script is the documentation.** Stock images use ext4 `shared_blocks`. You
MUST `resize2fs` first, then `e2fsck -E unshare_blocks`, then write with debugfs. Unshare on a full
filesystem fails with "Could not allocate block", leaves the filesystem still marked with errors,
and every subsequent debugfs write then corrupts a neighboring file. A build that boots to a hung
splash is almost always this, not app code.

---

## Flashing

This can brick your device. Read the whole section.

```bash
# Keeps /data: likes, history, WiFi, installed apps
./mikuos/build/flash_mikuos_keepdata.sh

# Wipes /data
./mikuos/build/flash_mikuos_clean.sh
```

**Use `fastboot -w`, never `fastboot erase userdata`.** Erasing leaves userdata raw and the device
bootloops. Metadata holds the FBE keys, so erasing it without erasing userdata gives you an
undecryptable partition.

**Super needs 64MB chunks.** `fastboot -S 64M flash super`. Larger chunks wedge the M500's USB
gadget partway through a 5GB transfer. Never run two fastboot processes at once.

**A wedged gadget needs a physical power cycle.** Once fastboot goes D-state and transfers 0 bytes,
no amount of retrying or re-plugging fixes it. Pull the cable, hold power, start over.

**Fastboot does not charge the battery.** A device reading 0mV in fastboot is not dying, it is not
being told. Do not flash on a low battery.

---

## Signing and keys

MikuOS replaces the public AOSP test keys, which every Android developer on earth already has, with
a key set you generate. That is the entire security model, so it is worth being precise about it.

Four key roles, matching AOSP: `platform`, `releasekey`, `media`, `shared`. The framework, the system
apps and our apps are all re-signed to your `platform` key, which is why our apps get platform
permissions without root. Generate them once, back them up somewhere that is not the build machine,
and never commit them. The `.gitignore` in this repo is written to make committing them difficult on
purpose.

Two things that will cost you a day if you do not know them:

**Re-signing strips the SELinux label.** An unlabeled `/system` app cannot be read by its own process
and init will not process an unlabeled `.rc` file. Every injected file needs its `security.selinux`
extended attribute set afterwards, and the build script does that with `debugfs ea_set`.

**Do not re-key NetworkStack.** Splitting `android.uid.networkstack` across an APEX boundary is fatal
to Android 14's package manager, and the failure looks like a boot hang rather than anything
informative. `REKEY_ROLES` excludes it.

---

## Hard-won platform facts

Things this project had to find out the expensive way, written down so nobody has to find them twice.

| Fact | Why it matters |
|---|---|
| `debugfs write` silently no-ops on a file that already exists | Every build.prop edit "succeeded" and none of them applied. Delete first, then write |
| `debugfs` also no-ops on a full filesystem, producing zero-block inodes | A full image looks like a successful build and boots to nothing |
| ART refuses to JIT a method over 16384 dex instructions | Compose composables cross it easily and then run interpreted forever. `tools/scan_jit_limit.sh` catches it |
| Reading animated state in a composable's body recomposes it every frame | 39% janky frames on the shade until the reads moved into layout and draw lambdas |
| Object-scope Compose state is main-thread-write-only | A `mutableStateMapOf` written from an IO thread crash-looped the app |
| A force-stopped package is dropped from `enabled_accessibility_services` | `am force-stop com.miku.systemui` kills the device's navigation until you re-enable it by hand |
| Android promotes an AudioTrack to `FLAG_DEEP_BUFFER` at about 100ms | Which silently opts you out of DIRECT output. This is the whole bit-perfect problem |
| `VOLUME_CHANGED_ACTION` fires for every stream | And a `Settings.System` observer fires for every setting, which made a volume HUD pop up at random |

---

## Repo structure

| Path | What it is |
|---|---|
| `mikuos/build/` | The build and flash scripts. `build_mikuos_super.sh` is the main event |
| `mikuos/web-flasher/` | A Go server and WebUSB front end for flashing from a browser |
| `tools/` | Signing helpers, the JIT scanner, the preset generator, the sync tooling, the entitlement Worker |
| `tools/web-installer/` | Static WebUSB installer site, vendored fastboot.js, resumable, 64MB chunks |
| `docs/` | The reverse-engineering reference, audio architecture, PKI design, security review, roadmap |
| `notes/` | The audio guide and metrics reports |
| `miku-assets/` | Artwork generated for this project, theme wallpapers, the brand mark |

[Miku Music](https://github.com/sworrl/MikuMusic) is a separate repo and holds the player, launcher,
system UI, settings and hardware apps.

---

## The device

HiBy Digital M500 x Hatsune Miku edition, product `khaje`. Snapdragon 665, Android 14 QSSI base,
3.2 inch 720x1280 portrait panel at 270dpi. Dual Cirrus Logic CS43198 in the "MIKU DAC"
configuration, 3.5mm single ended and 4.4mm balanced, plus USB DAC output. Physical power, volume
wheel, play/pause, next, previous and Fn on the right edge. No ambient light sensor, no pstore.

Audio behavior is driven by `vendor.audio.hiby.*` global settings: digital filter, DRE, gain,
high-power mode. Only init can set them, which is why the LED fix needs a reflash rather than a
setting.

---

## Known limitations

- **One device.** Everything here is verified on an M500 and nothing else.
- **FM does not work.** SELinux denies `/dev/radio0` to a `platform_app`.
- **No AOSP-from-source build yet.** The device tree exists, the sync is unfinished.
- **The web installer has never been hosted**, and its `EXPECTED_PRODUCTS` list needs confirming
  against `fastboot getvar product` before anyone trusts it.
- **Stock firmware is not included** and will not be. Bring your own.

---

## Legal

GPL-3.0-or-later for our code. See [LICENSE](LICENSE).

Hatsune Miku and the associated character designs are the property of Crypton Future Media. This is
an unaffiliated hobby project for a device Crypton licensed, and it ships no Crypton artwork. HiBy
Digital's firmware, applications, artwork and audio are theirs; none of it is in this repo and the
build scripts expect you to supply your own copy of the stock firmware you already own. Qualcomm and
Google components are under their own licenses.

Flashing a replacement OS onto a device can brick it. This one is used daily on the author's own
M500, which is a statement about one device and not a warranty about yours.
