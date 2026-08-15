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

**HiBy-derived code is no longer in this repo.** All decompiled/modded HiBy material (the HiBy
Music 2.1.8 smali mod, the modded widget pack, stock APKs, and built mod APKs) is archived
locally at `~/Documents/m500-hiby-archive/`. The suite going forward is our own code only —
the native Kotlin player and its widgets.

## The device

- HiBy Digital M500 (x Hatsune Miku edition), Android 14-based firmware, 3.2" portrait screen.
- Dual Cirrus Logic CS43198 "MIKU DAC"; audio behavior is driven by `vendor.audio.hiby.*` global
  settings (filter, DRE, gain) — see `notes/M500_MIKU_Audio_Guide.md`.
- Physical controls (power, volume wheel, play/pause, next/prev, Fn) on the right edge.

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
