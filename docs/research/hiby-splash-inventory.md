# HiBy splash and popup art inventory

Where HiBy's event art lives on the stock M500 image, what shows it, and what MikuOS replaces.
Everything here was read from the stock 1.00 firmware (`m500-system-archive/firmware/extracted_1.00`,
same bytes as `extracted_fs/`) with debugfs, aapt2 and apktool. No device was used.

Short version: nearly all of HiBy's event art is one set of chibi Miku frame animations inside the
stock SystemUI (`com.android.systemui`, `/system_ext/priv-app/SystemUI/SystemUI.apk`). They are
ordinary drawables referenced by name from `anim_miku_*` animation-lists, so a static RRO can swap
every one of them. There is no separate 3.5mm vs 4.4mm art, no USB / USB DAC / line out / Bluetooth
popup art, and no HiBy-branded off-mode charging art.

Device: 720x1280, `ro.sf.lcd_density=320` (xhdpi). The stock frames only ship at hdpi, so the device
scales them up by 4/3.

## Replaced (SystemUI, via MikuSplashOverlay)

All frames: `res/drawable-hdpi-v4/<name>.png`, 240x240 RGBA, transparent background, character
bottom-aligned. Each animation is an `<animation-list>` in `res/drawable/anim_miku_*.xml` played in a
loop by `com.android.systemui.LoopAnimImageView`.

| Event (how to trigger it) | Animation | Frames | Loop | Where it renders |
|---|---|---|---|---|
| Headphones plugged in (any wired output, 3.5mm or 4.4mm) | `anim_miku_music` | `listenmusic01..04` | 0.9 s | `hiby_headset_plugged_dialog`, 150x130dp box to the right of the "Headphones plugged in!" text, full-screen black dialog. Shown by `volumedialog/HeadSetPluggedDialog`, fired from the `AudioDeviceCallback` in `VolumeDialogImpl$8`. |
| Headphones unplugged | `anim_miku_notmusic` | `notlistenmusic01..23` | 2.9 s | Same dialog and box, swapped in code (`setImageResource`). |
| Charger connected | `anim_miku_pigeon` | `pigeon01..10` | 2.1 s | `hiby_charge_dialog`, 140dp tall, standing on top of the battery outline (`battery_border`). `batterydialog/ChargingDialog` when `mCharging` is true. Shown from `power/PowerUI`. |
| Low battery warning (not charging) | `anim_miku_cry` | `cry01..12` | 1.9 s | Same dialog, same spot, when `mCharging` is false. |
| Low battery, about to shut down | `anim_miku_tired` | `tired01..04` | 0.85 s | `hiby_charge_dialog` `shutdown_warning_container`, 160x140dp at the right end of the "power low, shutting down" banner. |
| Power off and reboot | `anim_miku_bye` | `bye01..14` | 2.95 s | `full_screen_anim`, centred (wrap_content) over `shutdown_bg`. `globalactions/GlobalActionsImpl.showShutdownUi`, only when `ro.vendor.boot.miku=yes`. |
| Volume above the hearing-safety limit | `anim_miku_dizzy` | `dizzy01..19` | 3.8 s | `hiby_volume_warning_dialog`, 150x130dp beside the warning text, above the cancel/confirm buttons. `volumedialog/VolumeWarningDialog`. |
| HiBy volume dial | `anim_miku_lift` | `lift01..12` | 3.3 s | `dialog_volume_control_layout`, `MikuAnimView` bottom centre at 0.9 scale. `volumedialog/HiByVolumeDialog`. Probably never seen on MikuOS: MikuSystemUIOverlay sets `enable_volume_ui=false` and the launcher draws its own volume modal. Replaced anyway so no HiBy frame is left. |
| Shutdown backdrop | `shutdown_bg` | 1 | n/a | `res/drawable-xhdpi-v4/shutdown_bg.png`, 1440x2560, palette PNG, no alpha. Background of `full_screen_anim`. The stock image is a line drawing of the player with labels (TYPE-C, BAL. PO, PO, VOL+, VOL-, PREV, NEXT). The replacement has no text. |

The voice clips that go with these dialogs (`res/raw/headset_plugged_*`, `charging*`, `battery_low*`,
`shutdown*`, `volume_high*`) are already silenced by `build_mikuos_super.sh` step [3/6].

## Not replaced

| What | Where | Why |
|---|---|---|
| `battery_border` (1030x741 LA, xxhdpi) and `hiby_charge_bg` | SystemUI, charging dialog | UI chrome (battery outline and fill), not art. The new charging Miku still stands on it. |
| `volume_base` (434x230 LA, xxhdpi), `ic_vol_*_miku`, `ic_note1/2` | SystemUI, HiBy volume dial | Dial chrome and icons, not art. The dial is likely disabled on MikuOS anyway. |
| `hiby_headset_plugged_bg/_border`, `hiby_vol_warning_bg/_border` | SystemUI | Shape drawables (panel behind the text), not images. |
| `anim_miku_drink` (`drink01..33`, 240x240 RGBA, hdpi) | Settings (`com.android.settings`), About page, 150x150dp corner decoration | Settings page decoration, not an event popup. Same approach would work with a second RRO targeting `com.android.settings`. |
| `usb_dac.png`, `bluetooth_in.png` (1080x1080 RGB, xxhdpi) | Settings | Glowing ring images with no references in code or layouts. Dead resources. |
| `usb_dac_icon`, `bluetooth_dac_icon` (250x250, xxhdpi) | Settings `WorkModeActivity` (USB DAC / Bluetooth receive mode page) | Plain grey icons on a settings page, not splash art. |
| `anim_miku_heart` (`heart01..10`), `startup_pic*` | Provision (setup wizard) | Provision is deleted by the build. |
| `bootanimation*.mp4` (1.7 MB each, 4 locales) | `/vendor/media` | Video, not a resource. The build already swaps its audio track. A new boot video would be a separate job. |
| Off-mode charger images (`battery_scale_720p`, `battery_fail_720p`, digit strips) | `/vendor/etc/res/images/charger` | Generic QTI charger graphics, not HiBy art. |
| `default_wallpaper.jpg` 720x1280 | `/vendor/overlay/FrameworksResM500_MIKU.apk` | Wallpaper, not a splash. |
| `m500_01..10.png`, `m500_default.jpg` 720x1280 | Gallery2 `res/raw` | Wallpaper picker set, not a splash. |
| Boot logo | no logo/splash partition in the firmware set | Nothing to replace. |

## Notes for the replacements

- Only one plug-in resource exists, so 3.5mm and 4.4mm show the same art. The new plug-in art shows
  a 4.4mm balanced plug. Different art per jack would need a SystemUI code change, not an overlay.
- Frame names, counts and sizes match stock exactly, and the `anim_miku_*` XML is left alone, so the
  timing is HiBy's. Each event uses one generated illustration with simple motion applied per frame
  (bob, sway, shake, hop) plus a pulsing neon rim.
- If the hdpi frames look soft on the 320dpi panel, `build_frames.py` can also write a 320x320
  `drawable-xhdpi` set. An overlay may add a density the target lacks; that was left out to match
  stock exactly.
- Source, candidates and scripts: `mikuos/art/hiby-splash/`. Overlay source:
  `tools/custom_overlays/MikuSplashOverlay/`.

## Regenerating

```
cd mikuos/art/hiby-splash
python3 gen.py                 # 2 candidates per image into candidates/ (needs the Gemini key)
# look at the candidates, set the letter per event in picks.json
./make_overlay.sh              # frames + MikuSplashOverlay.apk + size/name check against stock
python3 contact_sheet.py       # contact_sheet.png: stock vs a vs b vs new (gitignored)
```

`gen.py --only bye --n 1 --suffix c` adds a third candidate for one event.

Build hookup, in `build_mikuos_super.sh` next to the other `inject_overlay` lines:

```
inject_overlay "$REPO_DIR/tools/custom_overlays/MikuSplashOverlay/MikuSplashOverlay.apk" MikuSplashOverlay.apk "Miku splash art (headphones, charging, low battery, shutdown, volume warning)"
```
