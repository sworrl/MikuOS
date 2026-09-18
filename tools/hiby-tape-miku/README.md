# Miku Tape — HiBy Tape rebranded for MikuOS

Turns the stock HiBy M500 cassette-deck app **HiBy Tape** (`com.hiby.tape`)
into a Miku-branded MikuOS suite member, re-signed with the Falcon Technix
platform key.

```
tools/hiby-tape-miku/build_miku_tape.sh          # -> out/MikuTape.apk
tools/hiby-tape-miku/build_miku_tape.sh --keep-work   # keep work/ for inspection
```

## What the stock app is

* `m500-system-archive/vendor_software/HiByTape.apk` (20 MB, versionCode 1,
  minSdk 24 / target 29, compiled against SDK 36).
* It is a stripped Launcher3 "negative-one screen" (`com.android.launcher3.Launcher`)
  with two skins: a cassette deck (`negative_one_screen_tape*.xml`) and a
  VU-meter/amp panel (`negative_one_screen.xml`). It listens to media sessions
  (`MEDIA_CONTENT_CONTROL`) and taps the cover to open `com.hiby.music`.
* Stock signer: the public AOSP **platform** test key (SHA-256 `c8a2e9bc…`).
  It holds signature-level perms (`WRITE_SECURE_SETTINGS`, `DEVICE_POWER`,
  `MEDIA_CONTENT_CONTROL`), so on a re-keyed MikuOS image it *must* be
  re-signed with our platform key or those grants silently die.
* No signature / manufacturer / brand checks in the smali (the only "hiby"
  string in code is the `com.hiby.music` launch target). Re-signing is safe.

## What the build changes

| Area | Change |
|------|--------|
| Label | `app_name` "HiBy Tape" → **"Miku Tape"** (CJK locales already say "tape deck", untouched); `title` "HiBy" → "Miku"; slogan → "Powered by MikuOS" |
| Layout placeholders | cassette label defaults "HiBy Music"/"HiBy" → "Miku Music"/"Miku"; artist line tinted Miku pink `#FF2277` |
| Icon | new PIL-drawn Miku cassette (teal shell, pink stripe, "01"), `ic_app.png` at every density + the unused `ic_launcher*.webp` |
| Artwork | `tape_bg` (opaque deck) → deep teal-charcoal; `tape_wheel` hubs → Miku teal; `tape_switch` glyph → pink. Luminance-preserving tint, alpha untouched. `tape_front*` (translucent glass film over the album art) and `tape_mask*` are **not** tinted so cover art stays true. |
| Colours | amp/VU-skin pure-green LED dot shapes → teal `#39C5BB` (own alpha kept) |
| Package | **unchanged** `com.hiby.tape` (coexists, HiBy intents keep working) |
| Signing | zipalign `-p 4` + `tools/sign_apk.sh --platform` (v2+v3, no v1) |

## apktool pitfall handled

A plain `apktool d` → `apktool b` of the stock APK fails: `values-v34/colors.xml`
references framework colours by id that apktool resolves against its bundled
framework to *private* names (`@android:color/bright_foreground_dark_disabled`
etc.), and aapt2 refuses private `@android:` references. Deleting the file is
not an option either (eight `m3_sys_color_dynamic_*_error*` symbols are defined
only there). The patcher rewrites them to `@*android:color/…`, which aapt2
links to the identical resource ids the stock binary carries — behaviour on
device is unchanged. Full resource decode is used (no `-r`), since strings,
layouts, drawables and mipmaps are all edited. Code is not touched, so the decode
uses `-s`: both `classes*.dex` in the output are byte-identical to stock (no
smali round-trip), and the shipped `assets/dexopt/baseline.prof` stays valid.

## Tooling

* apktool: `tools/apktool.jar` (3.0.3) preferred; falls back to `apktool` on PATH
  (system 2.7.0 also decodes this APK).
* apksigner / zipalign: auto-found in `~/Android/Sdk/build-tools/*` (35.0.0 present)
  or via `APKSIGNER=` / `ZIPALIGN=`.
* python3 + Pillow (icon + tints). No network, no adb, no git.

## Outputs

* `out/MikuTape.apk` — signed, aligned, ready for `mikuos/build` optional apps
* `out/MikuTape.apk.sha256`, `out/signature.txt`, `out/badging.txt`, `out/icon_preview.png`

Install path on device: this is a platform-signed system-style app; ship it as
an optional APK in the MikuOS image (same place stock HiByTape.apk lives) or
`adb install` over the stock one *after* the image is re-keyed to Falcon
(signature must match the installed one for an in-place update — on a stock
c8a2e9bc image you must uninstall the stock app first).
