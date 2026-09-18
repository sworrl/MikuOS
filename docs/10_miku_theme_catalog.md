# MikuOS Theme Catalog — Foundation Pass

Cataloging + asset-prep + planning pass for a MikuOS system theming suite. No monolith
source files were edited (`MikuLauncherActivity.kt`, `MainActivity.kt`). The device was not
touched. All work is new files: this catalog, `miku-assets/themes/`, and
`miku-player-kotlin/mikuos-launcher/src/main/java/com/miku/launcher/theme/MikuThemeRegistry.kt`.

## 0. Read this first — key findings that don't match the brief

- **No Halloween Miku art exists anywhere in this repo.** Checked every image in
  `miku-assets/` (official-device, miku_renders + banners, reference_favorites, online) and
  every drawable in both `miku-player-kotlin/app` and `.../mikuos-launcher`. Nothing
  jack-o-lantern/witch/autumn themed turned up. **Please confirm**: source new art, or point
  me at where it actually lives if I missed a location.
- **No "Miku eating ice cream on a beach" art exists either.** There *is* a beach/ocean Miku
  (see below — it's the shipping default wallpaper), but she's not eating ice cream in it,
  and no other beach render exists. Same ask: source new art or correct me.
- **No "Miku at her computer/keyboard" art exists.** Nothing depicting a desk, monitor, or
  physical keyboard turned up anywhere.
- **The "~2 usable Yume IEM + M500 renders" were identified with high confidence** — see
  §2.2. `miku-assets/gallery.html` (a pre-existing curated review page already in the repo)
  names two specific "hero" shots, `m500_iem_hero_black.jpg` and `m500_iem_hero_white.jpg`,
  that no longer exist under those filenames. Their pixel content, resolution, and pose match
  `miku_renders/01_waifu_classic_black.jpg` and `02_waifu_classic_white.jpg` exactly, so those
  two are almost certainly the same files after a later rename/reorg. Everything else in
  `miku_renders/` (03–09 + banners) is the same DAP+IEM prop repeated across different
  outfits/backgrounds — consistent with "the rest were AI-slopped."
- **Correction to the brief:** the current default launcher wallpaper is **not**
  `miku_wall_0X.webp`. Those ten files (`miku_wall_00`–`09.webp`, and their PNG twins
  `wall_paper_0`–`9.png` in `official-device/`) are generic **non-Miku stock abstract
  wallpapers** (silk ribbons, ocean-wave splash, marble spheres, gradients — the kind of
  wallpaper set that ships on stock Android/OnePlus devices). The actual beach/ocean **Miku**
  wallpaper — the one matching the brief's description — ships as `R.drawable.miku_wallpaper`
  (`miku_wallpaper.png`, id `"classic"`, labeled *"Concert Stage (Default)"* in
  `MikuLauncherActivity.kt`'s wallpaper picker — that label itself looks like a copy/paste
  leftover, since the picture is clearly a beach scene, not a stage). It's also exactly
  **720×1280**, the M500's native panel resolution.

## 1. Full image catalog

### 1.1 `miku-assets/official-device/` — original HiBy device art

| File | Description | Best use | Maps to requested theme |
|---|---|---|---|
| `wall_paper_0.png` … `wall_paper_9.png` (10 files) | Generic abstract stock wallpapers: silk ribbon (0/1), green twist (5, dark), marble/oil sphere (4/9), planet crescent (6), ocean-wave splash **photo, not art** (2), pastel bubble (7), red/blue gradient blob (8), watercolor brushstrokes (9). **None feature Miku.** | Non-Miku fallback wallpaper pool only | None — not Miku art |
| `miku_background_view.png` | Chibi Miku, teal twintails, eyes-closed big laugh, arms up, holding/swinging a small grey-and-white cartoon penguin plush | Widget/notification header art | Not requested; candidate mascot for a future "chibi" theme |
| `miku_default_cover.png` | Square crop of the beach/ocean render (see `miku_wallpaper.png` below) — used as default "now playing" album art | Default now-playing placeholder cover | Same source as Default theme |
| `clock_widget_miku_preview.png` | `miku_background_view.png` composited next to a "09:01" clock readout | Home-screen clock widget preview thumbnail | n/a |
| `ic_sprite.png` | Not viewed in detail (icon sprite sheet, not a wallpaper candidate) | Icon sheet | n/a |

### 1.2 `miku-assets/miku_renders/` — 9 waifu renders + banners

All nine share **the same pose prop**: Miku holding a teal/cyan rectangular portable player
with a knurled volume dial and PREV/PLAY/NEXT/POWER/.fn buttons, screen showing a cassette-reel
UI — i.e. the M500 + a wired IEM. This is the DAP+IEM series referenced in the brief.

| File | Description | Best use | Maps to |
|---|---|---|---|
| `01_waifu_classic_black.jpg` | Classic idol outfit (grey/teal vest, tie, pleated skirt), solid **black** bg, holding the DAP, IEM cable visible | **Yume IEM + M500 hero shot** (portrait, clean bg, great for key art / store listing / about-screen) | **YUME IEM + M500 (pick #1)** — matches deleted `m500_iem_hero_black.jpg` from gallery.html |
| `02_waifu_classic_white.jpg` | Same outfit/pose, solid **white** bg | **Yume IEM + M500 hero shot**, alt background for light-mode contexts | **YUME IEM + M500 (pick #2)** — matches deleted `m500_iem_hero_white.jpg` |
| `03_waifu_classic_stage.jpg` | Same outfit/pose, concert-stage laser/HUD background | Alt key art / loading screen | AI-slop variant of pick #1/#2 |
| `04_waifu_streetwear_black.jpg` | Black techwear hoodie + pleated skirt, same DAP prop, black bg | Alt style variant | AI-slop variant |
| `05_waifu_streetwear_white.jpg` | Same streetwear, white bg | Alt style variant | AI-slop variant |
| `06_waifu_streetwear_tokyo.jpg` | Full-body, streetwear, walking through a neon Shibuya-style street (crowd, Japanese signage, flying cars) | App "drawer" background (already used as `miku_bg_drawer.jpg` / `miku_drawer_bg_tokyo.jpg`) | AI-slop variant; decent standalone Tokyo backdrop |
| `07_waifu_cozy_black.jpg` | Grey knit sweater + pleated skirt, sitting on a bar stool, eyes closed smiling, DAP in lap, black bg | Alt cozy portrait | AI-slop variant |
| `08_waifu_cozy_white.jpg` | Same cozy pose, white bg | Alt cozy portrait | AI-slop variant |
| `09_waifu_cozy_cafe.jpg` | Same cozy pose, seated in a warm "Cybernetic Vinyl Lounge" — record-shelf café, pendant bulbs, espresso machine, rain-streaked window | **Full scene, genuinely good standalone theme art** | Used as **"Cozy Cafe"** bonus theme (§3) |
| `banners/banner_01_waifu_vinyl_cafe_16x9.jpg` | 16:9 crop/variant of the cafe scene | Landscape banner / header art | Cafe theme banner crop |
| `banners/banner_02_waifu_cyber_stage_16x9.jpg` | 16:9 full-body idol outfit, mid-air jump pose on a concert stage, crowd + lasers + EQ bars | **Full scene, genuinely good standalone theme art** | Used as **"Cyber Stage"** bonus theme (§3); also exists pre-copied into app resources as `miku_banner_cyber_stage.webp` |
| `banners/banner_03_waifu_tokyo_shibuya_16x9.jpg` | 16:9 crop of the Tokyo street scene | Landscape banner | Same scene as `06_waifu_streetwear_tokyo.jpg` |
| `banners/header_closeup_01_cafe_16x9.jpg` | Tight close-up crop, DAP UI clearly legible, cafe bg | Settings-header / about-screen banner | Cafe theme detail crop |
| `banners/header_closeup_03_streetwear_16x9.jpg` | Tight close-up, streetwear hood, DAP UI fully legible (PREV/PLAY/NEXT buttons readable) with rainy Tokyo street bokeh | Best close-up of the DAP UI itself — good for a "what your player can do" marketing shot | Alt IEM+M500 close-up |

### 1.3 `miku-assets/reference_favorites/` — curated 2-image folder

| File | Description | Best use | Maps to |
|---|---|---|---|
| `miku_waifu_leap_stage.jpg` | Idol outfit, open-mouth cheerful, leaping mid-air on stage holding the DAP with both hands, screen fully legible ("SHE MOVES LIKE A KNIFE" track title) | High-energy hero shot | Strong 3rd IEM+M500 candidate if you want more than 2 |
| `miku_waifu_peace_stage.jpg` | Idol outfit, winking peace-sign, one hand up, other holding the DAP by its side volume dial (very clean device read), IEM housing visible dangling from cable, stage bg | High-energy hero shot, best single view of the physical IEM earpiece itself | Strong 3rd IEM+M500 candidate |

*These being the only two files in a folder literally named "favorites" is itself a signal —
flagging in case these, not `01`/`02`, are what you actually meant by "the ~2 usable renders."
**Please confirm which pair (01+02, or these two, or a mix) you want as the canonical
IEM+M500 key art** — I staged 01+02 in `themes/keyart_yume_m500/` based on the gallery.html
filename match, but swapping in these two is a one-line change.*

### 1.4 `miku-assets/online/` — 23 files, all one small sprite family

Not 100+ files as expected — only 23. All 23 are **transparent-background "gacha card" style
character cutouts**, not backgrounds/wallpapers:

- `sb_00`…`sb_04` (5 base sprites): cyan idol dance pose, pink/cherry idol pose (×2 near-dupes),
  cyan DJ-megaphone-on-amp pose, mint sailor-outfit pose holding a giant DAP prop.
- `var_100`–`var_117` (18 files): `var_100`–`103` are byte-identical dupes of `sb_00`–`03`;
  `var_104`–`117` are **facial-expression variants of `sb_04`** (same mint sailor pose, eyes
  open/closed/winking/laughing). Sampled `var_105`, `var_110`, `var_117` — confirmed identical
  pose, only the face changes.

None of these are wallpaper-scale scenes and none match Halloween/beach/keyboard.

### 1.5 App resource drawables (`app/` and `mikuos-launcher/` `res/drawable*`)

These two module trees are byte-identical copies of each other. Cross-referenced every unique
filename against the images above:

| File | Identical to | Notes |
|---|---|---|
| `miku_wallpaper.png` | — (unique) | **This is the real beach/ocean default.** 720×1280. Miku in a white off-shoulder dress, back tattoo "01", standing in shallow surf, looking over her shoulder, holding a small teal device at her side. Open sky in the upper-right = good clock/status-bar headroom. |
| `miku_cover.webp`, `miku_sprite.webp` | crops of `miku_wallpaper.png` | Reused crops |
| `miku_bg_fm.jpg` | `03_waifu_classic_stage.jpg` | dupe |
| `miku_bg_drawer.jpg`, `miku_drawer_bg_tokyo.jpg` | `06_waifu_streetwear_tokyo.jpg` | dupe |
| `miku_bg_page1.jpg` | `01_waifu_classic_black.jpg` | dupe |
| `miku_bg_settings.jpg` | `03_waifu_classic_stage.jpg` (near-identical closeup) | dupe |
| `miku_clock_preview.webp` | `clock_widget_miku_preview.png` | dupe |
| `miku_extra_00`–`17.webp` (18 files) | `sb_04` / `var_1xx` sailor-DAP sprite, expression variants | dupe set |
| `miku_banner_cyber_stage.webp` | `banners/banner_02_waifu_cyber_stage_16x9.jpg` | dupe |
| `miku_boot_splash.webp` | new full-body cassette-DAP render, "CHEERING!" crowd text, very clean device read | Good boot-splash / "Cyber Stage" alt |
| `miku_boot_splash_pose2.webp` | new — peace-sign, holding DAP screen-out, stage bg | Alt boot-splash |
| `miku_audiophile_art.webp` | new — Miku in tactical/cyber outfit holding a **phone-shaped** player (not the M500-style DAP) in a server-room "CYBER AUDIOPHILE / VOL:MAX / FREQ:44.1kHz" scene | Settings/DSP screen art |
| `miku_dj_megaphone.webp`, `miku_pose_chibi_dj.webp` | `sb_02` DJ-megaphone sprite / new chibi DJ sticker | Widget/sticker art |
| `miku_pose_dance.webp` | `sb_00` | dupe |
| `miku_pose_headphones.webp`, `miku_pose_vocal.webp`, `miku_pose_peace.webp`, `miku_render_stage_dj.webp` | all new full-body stage/idol renders, generic neon-stage backgrounds, no new locations | Stage art pool |
| `miku_chibi_hearts.webp` | new chibi sticker, rainbow heart | Sticker/emote art |
| `ic_*_miku.png` (~70 files in `drawable-xxxhdpi/`) | app-icon badge overlays (Spotify, Chrome, etc.) | Not wallpaper candidates, not reviewed individually |

**Conclusion: the entire image asset library in this repo — every directory, every module —
was fully cross-referenced. There is no Halloween, no ice-cream/beach combo, and no
computer/keyboard Miku art anywhere.** This isn't a search miss; it's a real content gap.

## 2. Lockscreen + IEM/M500 key art picks

### 2.1 Best portrait lockscreen image
**`miku_wallpaper.png`** (the beach/ocean default) — recommended primary pick:
- Exactly 720×1280, the M500's native panel resolution (no crop/scale needed).
- Open sky/water in the upper third gives clean space for a clock + notification overlay.
- Already proven, already shipping, already the "face" of the device.

**Alternate** (more dramatic, if you want the lockscreen visually distinct from the home
wallpaper): `01_waifu_classic_black.jpg` (768×1376, solid black background, crops cleanly to
720×1280). Trade-off: her face/hair fill the top of the frame, less headroom for a clock.

Both are staged in `miku-assets/themes/lockscreen/`.

### 2.2 Yume IEM + M500 key art (the "~2 usable renders")
Staged in `miku-assets/themes/keyart_yume_m500/`:
- `hero_black.jpg` ← `miku_renders/01_waifu_classic_black.jpg`
- `hero_white.jpg` ← `miku_renders/02_waifu_classic_white.jpg`

Picked over the `reference_favorites/` pair because their content/resolution/pose matches the
now-deleted `m500_iem_hero_black.jpg` / `m500_iem_hero_white.jpg` filenames still referenced
in `miku-assets/gallery.html`'s own curated review gallery — i.e. these were *already*
identified as the two best shots once, by whatever process built that gallery page. **Flagging
for confirmation per §1.3** in case you actually meant the `reference_favorites/` pair instead.

## 3. Staged theme assets — `miku-assets/themes/`

```
miku-assets/themes/
├── default/wallpaper.png                    ← miku_wallpaper.png (beach/ocean, 720×1280)
├── halloween/MISSING_ART.txt                ← no art exists; explains the gap, no image
├── beach_icecream/wallpaper_PLACEHOLDER.png  ← reuses default art; no ice-cream render exists
├── cyber_stage/wallpaper.webp                ← miku_banner_cyber_stage.webp (real dedicated art)
├── cozy_cafe/wallpaper.jpg                   ← 09_waifu_cozy_cafe.jpg (real dedicated art)
├── lockscreen/
│   ├── miku_lockscreen.png                   ← primary pick (= default art, native res)
│   └── miku_lockscreen_alt_hero_black.jpg    ← alt dramatic pick
└── keyart_yume_m500/
    ├── hero_black.jpg                        ← 01_waifu_classic_black.jpg
    └── hero_white.jpg                        ← 02_waifu_classic_white.jpg
```

All copies made with `cp -p` (preserves original timestamps); originals untouched.

### Suggested accent palettes per theme

| Theme | Primary | Secondary | Tertiary | Background |
|---|---|---|---|---|
| Default (Beach) | `#39C5BB` Miku teal | `#7ED6E0` sea-foam | `#FF9E80` coral | `#EAF6F6` |
| Halloween *(no art yet)* | `#FF7518` pumpkin | `#6A3FA0` witch violet | `#39C5BB` teal sliver | `#140A10` |
| Beach (Ice Cream) *(placeholder art)* | `#39C5BB` teal | `#FFB6C1` strawberry pink | `#FFF3D6` vanilla | `#EAF6F6` |
| Cyber Stage | `#39C5BB` teal | `#E03177` neon magenta | `#2F5DFF` laser blue | `#060B18` |
| Cozy Cafe | `#D89B4A` amber bulb | `#4FB3AC` muted teal | `#F0DFC0` cream | `#2A1B12` dark wood |

These were chosen by eye from each scene's actual lighting/props (not automated dominant-color
extraction — a naive histogram on these images is dominated by flat white/black photo
backgrounds, not Miku's actual palette, so it wasn't useful here). Treat as a starting point,
not final brand colors.

## 4. Theming engine design

New file: `miku-player-kotlin/mikuos-launcher/src/main/java/com/miku/launcher/theme/MikuThemeRegistry.kt`
(package `com.miku.launcher.theme`, mirrors the style of the existing `CyberTheme.kt` /
`MikuDiurnalTheme.kt` in the same package). Not imported by `MikuLauncherActivity.kt` yet.

**Model:**
- `MikuAccentPalette(primary, secondary, tertiary, background: Color)`
- `MikuTheme(id, displayName, description, wallpaperDrawableName, lockscreenDrawableName, accentPalette, keyboardThemeRef, hasRealArt)`
- `MikuThemeRegistry` object: `builtIns` list (Default, Halloween, BeachIcecream, CyberStage,
  CozyCafe — the 2 requested + 2 bonus themes with real finished art), a persisted
  `StateFlow<MikuTheme> selectedTheme` (SharedPreferences-backed, prefs name
  `mikuos_theme_prefs`), `init(context)`, `selectTheme(context, id)`, `byId(id)`, and
  `resolveDrawableRes(context, name)`.

**Why themes hold drawable *names* (String) instead of `@DrawableRes Int`:** none of the
staged bitmaps in `miku-assets/themes/` have been copied into any module's
`res/drawable(-nodpi)` yet — that's app-resource wiring, explicitly out of scope for this
pass. Hardcoding `R.drawable.theme_cyber_stage_wallpaper` today would fail to compile. Instead
each theme names the resource it *expects*, and `resolveDrawableRes()` looks it up at runtime
via `Resources.getIdentifier()`, falling back to the Default theme's art (then to 0) if the
name hasn't been wired in yet. `Default` and `CyberStage` already resolve for real today
(`miku_wallpaper` / `miku_banner_cyber_stage` already exist in `res/drawable`); the other three
resolve to the Default fallback until their placeholder/TODO drawable names are wired.

### How to wire it up (future work, not done here)
1. Copy the relevant files from `miku-assets/themes/<id>/` into
   `mikuos-launcher/src/main/res/drawable-nodpi/` under the exact names each `MikuTheme`
   expects (e.g. `theme_cozy_cafe_wallpaper.jpg`, `theme_halloween_wallpaper.png` once that
   art exists).
2. In `MikuLauncherActivity.kt`: call `MikuThemeRegistry.init(context)` once on launch, add a
   theme-picker entry point (the existing long-press wallpaper/theme modal at line ~1450 is
   the natural home for it), and on selection call
   `MikuThemeRegistry.selectTheme(context, theme.id)`.
3. Read `MikuThemeRegistry.selectedTheme` as Compose state; use
   `resolveDrawableRes(context, theme.wallpaperDrawableName)` for the home background and
   `theme.lockscreenDrawableName` for the lock background.
4. Push `theme.accentPalette` into wherever `CyberTheme.kt`'s static color vals /
   `MikuDiurnalTheme`'s dynamic palette currently feed the launcher chrome, Settings
   (`mikuos-settings` module), and SystemUI (`mikuos-systemui` module) — those two modules
   currently have no theme awareness at all and would need their own small reader of the same
   SharedPreferences key (`mikuos_theme_prefs` / `selected_theme_id`) since they're separate
   processes/APKs from the launcher.

## 5. Keyboard/IME theming feasibility

**GBoard is not present in the repo.** Only AOSP LatinIME is bundled, at
`m500-system-archive/extracted_fs/product/app/LatinIME/LatinIME.apk`. To ship GBoard at all,
its APK (Google-signed, not redistributable from this repo) needs to be obtained separately
and dropped into `mikuos/build/preloaded_apks/` — flagging that this is a licensing/sourcing
task, not something I can do from inside this repo.

### AOSP LatinIME (already bundled) — investigated by decompiling `LatinIME.apk`
Decompiled with `apktool` into a scratch dir (not committed) and inspected
`res/values/{arrays,styles}.xml` and the `KeyboardTheme`/`ThemeSettingsFragment` smali. This is
stock, unmodified AOSP LatinIME (`com.android.inputmethod.latin`, standard package names).

- It ships **4 fixed built-in themes**: Material Light, Material Dark, Holo White, Holo Blue —
  selected by an `integer-array` of theme ids (`keyboard_theme_ids` = `3,4,2,0`) mapped to
  `<style name="KeyboardTheme.*">` blocks in `styles.xml`.
- Each theme style sets `android:background="@drawable/keyboard_background_*"` — a real
  drawable reference, not a hardcoded solid color. **This means a custom background image is
  architecturally supported by the framework** — LatinIME's keyboard view background is just
  whatever drawable that style points at.
- **Feasibility: yes, but requires an APK patch, not a source rebuild** (no full AOSP LatinIME
  source tree is in this repo, only the compiled APK). The approach, comparable in effort to
  this repo's existing Fn-lock system patch (`docs/05_fn_switch_system_mod_spec.md`):
  1. `apktool d` the APK (already proven to work, see this investigation).
  2. Add a bitmap/gradient-scrim drawable (`theme_miku_keyboard_bg.xml` or a PNG) referencing a
     "Miku at her keyboard" render — once that art exists (§0).
  3. Add a 5th `<style name="KeyboardTheme.Miku">` inheriting key/spacebar/functional-key
     drawables from `KeyboardTheme.LXXDark` (so keys stay legible) but overriding
     `android:background` with the new drawable, dimmed/scrimmed so key glyphs stay readable
     over a busy photo.
  4. Add the new theme id to `keyboard_theme_ids` / `keyboard_theme_names` in `arrays.xml`, and
     patch `KeyboardTheme.smali`'s theme-id table so the new id resolves to the new style
     (this is the one genuinely fiddly step — it's an enum-like static table in smali, not XML).
  5. `apktool b`, re-sign, replace the system LatinIME.apk (system-app, needs the same
     replace-and-reboot flow used for other system APK mods in this repo).
- **Not implemented here** — this is a report of feasibility + approach only, per the task.
  Also blocked in practice on §0: there's no "Miku at her keyboard" art to put in that
  drawable yet.

### Summary
| Keyboard | Bundled? | Native custom-photo theming? | Effort to add a Miku background |
|---|---|---|---|
| GBoard | No — needs external APK, not in repo | Yes, built-in (Settings → Themes → custom photo) | Trivial *if* the APK can be sourced/licensed |
| AOSP LatinIME | Yes, at `LatinIME.apk` | Not exposed in the stock UI, but the theme framework supports arbitrary background drawables | Moderate — apktool res + smali patch, ~comparable to the existing Fn-lock patch in this repo |

Either path is still blocked on **not having "Miku at her keyboard" art** (§0) — that's the
prerequisite before either integration is worth doing.
