# MikuOS press kit

**For:** whoever is building the falcontechnix.com pages (the flasher, the project page, the press
post). This file is the brief. Everything in it is either verifiable in the repos or measured on
the device, and where something is unproven it says so.

**Status: work in progress, and help is wanted.** Say that plainly on every page. Issues and pull
requests are welcome at both repos. This is one person, one device, and a lot of measurement.

---

## The one-liner

> MikuOS is a platform-signed Android 14 replacement for the HiBy Digital M500 x Hatsune Miku
> digital audio player. It plays local files straight to the device's dual Cirrus Logic CS43198
> DACs with no resampling and no mixer in the path, and it does not display a number it did not
> measure.

## The repos

| Repo | What it is |
|---|---|
| https://github.com/sworrl/MikuOS | The OS: build and flash scripts, the web installer, the docs, the tooling |
| https://github.com/sworrl/MikuMusic | The apps: the player, launcher, system UI, settings, hardware controls |

Both GPL-3.0-or-later. Both public.

---

## Why it exists (use this framing, not a feature list)

The M500 is very good audio hardware running software that gets in its way. Stock firmware routes
music through Android's mixer, so a 44.1kHz file is resampled to whatever the mixer happens to be
running at before it reaches a pair of DACs chosen specifically for not needing that. None of that
is a hardware limit. All of it is fixable. The fix is to replace the software rather than patch
around it.

The second reason is smaller and matters more in practice: audio apps lie constantly. They show a
bit depth taken from a filename, a sample rate that is the mixer's and not the file's, a BPM
invented from the title, an EQ curve connected to nothing. MikuOS shows a dash where it does not
know, and the contributing rule in the README is "never display a value you did not measure".

---

## The proof, captured on the device

This is the strongest thing the site can show. It is a live `dumpsys media.audio_flinger` while a
24-bit / 96kHz FLAC plays, and it is in the repo at `docs/screenshots/bitperfect-audioflinger.txt`:

```
Output thread 0xb400007846c31840, name AudioOut_14D, tid 25861, type 1 (DIRECT):
  Sample rate: 96000 Hz
  HAL format: 0x6 (AUDIO_FORMAT_PCM_24_BIT_PACKED)
  Channel count: 2
  Processing format: 0x6 (AUDIO_FORMAT_PCM_24_BIT_PACKED)
  AudioStreamOut: flags 0x1 (AUDIO_OUTPUT_FLAG_DIRECT)
  Output devices: 0x8 (AUDIO_DEVICE_OUT_WIRED_HEADPHONE)
```

Read it out for the reader, because the detail is the point: the output thread is **DIRECT**, not
MIXER. The sample rate is the FILE's 96kHz, not the mixer's. The processing format is 24-bit packed
integer end to end, so there is no float conversion and no dither anywhere between the file and the
DAC. Pair it with `docs/screenshots/01-now-playing-hires.png`, which is the same moment on screen.

### The bug worth telling, if the post wants one technical story

Android's `AudioTrack.Builder.build()` quietly adds `FLAG_DEEP_BUFFER` when the requested buffer is
around 100ms or larger, and Qualcomm's policy manager only routes to the `direct_pcm` profile when
the flags are NONE. So asking for a comfortable buffer silently opts you out of direct output. The
custom sink asks for a buffer under that threshold on purpose.

It then had a bug for months: it computed the small buffer and clamped it with
`max(getAudioTrackMinBufferSize(), threshold)`. On this device the platform minimum is about double
the threshold, so the `max` always won, every track was deep-buffered onto a 192kHz mixer, and the
app cheerfully reported bit-perfect the whole time. Fixed 2026-09-17. If you are writing a direct
output sink for any Android device, that is the trap.

---

## Screenshots

All in `docs/screenshots/` in the MikuOS repo, 720x1280, captured from the running device.

| File | What it shows | Best used for |
|---|---|---|
| `01-now-playing-hires.png` | Now Playing during a 24/96 FLAC: FLAC / 24-BIT / 96KHZ / 3328 kbps / HI-RES badges, wavy scrubber, UI colored from the album art | The hero image |
| `02-fullscreen-visualizer.png` | Real libprojectM with the "projectM 4.2.0" credit read from the loaded library at runtime | The visualizer section |
| `03-tape-mode.png` | The cassette deck, grading itself TYPE IV / IEC IV / 70µs EQ from the actual 24-bit 96kHz stream | The "this is not a skin" section |
| `04-library.png` | Home: daily highlight, 17,048 tracks, the vibe prompt | Scale |
| `06-albums.png` | 1,777 albums with per-album format badges and year badges | The library |
| `07-hardware-observatory.png` | CS43198 ×2, NOS digital filter, High Gain, DRE enabled, real per-core CPU MHz, and honest "Light sensor: None on this device" / "FM present · no access" | The honesty section. This one is the argument |
| `08-bpm-game.png` | The rhythm game with the note highway and a locked 130 BPM | The fun section |
| `09-launcher-home.png` | The launcher: clock, weather with real AQI and sun times, DAC and battery tiles | The OS section |

`07-hardware-observatory.png` is worth its own callout. It says a sensor is missing instead of
inventing a reading, and it says the FM radio node exists but is not accessible. Most projects
would hide both.

---

## What is actually verified (do not overclaim)

Copy this honestly. Both READMEs open with a table like it.

**Confirmed on hardware:** DIRECT PCM output at 44.1 / 48 / 96 / 192kHz, 24-bit packed. Platform
signing with no root. A re-keyed system image that boots. APEX re-signing. Gesture navigation
replacing the stock nav bar. OS-wide idle dim on real system brightness. Fn-key pocket lock without
root. Using the camera's auto-exposure as an ambient light sensor, because the device has no ALS at
all. Real libprojectM 4.2.0, and the 80 bundled Miku presets self-tested on device: 90 tried, 0
failed.

**Implemented but not proven:** the LDAC push path (no LDAC sink has ever been connected to it). The
web installer (built, never hosted, `EXPECTED_PRODUCTS` needs confirming against a real
`fastboot getvar product`). A full AOSP-from-source build.

**Tried, does not work:** the FM tuner (SELinux denies a `platform_app` direct access to
`/dev/radio0`; the UI exists, the tuner does not). A generic system image (the vendor mandates six
legacy HIDL services Android 14 dropped). Kernel 5.15.209 (A/B proven to break charging: the mp2731
never qualifies the charger input and the device drains on the cable).

---

## The flasher page

The installer already exists, written and unhosted, at `tools/web-installer/` in the MikuOS repo.
It is a GrapheneOS-style browser installer: static files, no build step, no backend. The user plugs
the M500 into a PC, opens the page in Chrome or Edge, and clicks through a wizard. Everything runs
client-side over **WebUSB fastboot** using kdrag0n's `fastboot.js` (MIT, vendored unmodified).

Read `tools/web-installer/README.md` before writing a line of it. The short version of what it
already handles, and why, because these are device facts and not preferences:

* **super is 5,371,461,632 bytes exactly.** The installer refuses a bundle of any other size and
  refuses a device whose super partition differs.
* **The M500's USB gadget wedges on big bulk pushes.** Every payload goes as a self-contained
  sparse image of 64 MiB or less, one at a time, each chunk retried up to three times. A 90 second
  no-progress watchdog detects a wedged gadget, closes the USB device, and tells the user to
  power-cycle. "Reconnect & Resume" continues at the exact chunk.
* **Never two fastboot streams.** A single lock serialises every command.
* **Fastboot does not charge the battery.** A device reading 0mV in fastboot is not dying, it is
  not being told. The wizard requires a battery check before it will start.
* **Integrity before upload.** Every image carries a whole-file SHA-256; images over 128 MiB also
  carry one per 63 MiB chunk. The browser verifies with Web Crypto before sending, so a bad chunk
  is never written.

What the page still needs from whoever builds it: hosting, a `release.json` produced by
`make_release_manifest.py`, and a decision on whether HiBy's stock boot-chain images may be hosted
alongside (they come from HiBy's public OTA; the rollback-to-stock path additionally needs their
`super.img`, which is more clearly theirs).

**Say on the page that flashing can brick the device.** It is used daily on the author's own M500.
That is a statement about one device, not a warranty about the reader's.

---

## Tone

Match the repo READMEs. Plain, short sentences. US English. No brochure language, no invented
product names, no "revolutionary". Lead with what was measured. Where something is unproven, say
"not proven" rather than softening it. The project's whole pitch is that it does not overclaim, so
a press page that overclaims would undercut it.

Do not write "AI-generated" or credit any tooling. Attribute the author: **sworrl**.

---

## Legal, put a version of this on every page

GPL-3.0-or-later. Hatsune Miku and the associated character designs are the property of Crypton
Future Media; this is an unaffiliated hobby project for a device Crypton licensed, and it ships no
Crypton artwork. HiBy Digital's firmware, applications, artwork and audio are theirs and none of it
is redistributed. libprojectM is LGPL-2.1 and used as a library. Media3 and AndroidX are
Apache-2.0.

---

## Contributing, and please make this prominent

The project is a work in progress and help is welcome. Issues and pull requests at
github.com/sworrl/MikuOS and github.com/sworrl/MikuMusic.

Things that would genuinely help:

* **Another M500.** Everything is verified on exactly one device.
* **An LDAC sink**, to prove or disprove the Bluetooth codec path.
* **A route to the FM tuner** that works within SELinux.
* **Hosting and testing the web installer**, including a real `fastboot getvar product`.
* **More `.milk` presets** for the visualizer.
* Anywhere a number on screen is not measured. That is treated as a bug, and a report of one is
  as useful as a patch.

One house rule for contributors, stated in the README and worth repeating on the site: **never
display a value you did not measure.** No placeholder percentages, no bit depth inferred from a
file extension, no BPM guessed from a title. If the data is not there, show a dash and say why.
