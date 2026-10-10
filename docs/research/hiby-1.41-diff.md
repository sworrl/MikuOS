# HiBy stock firmware: what changed after the MikuOS base

## What changed from 1.00 to 1.41

### Coverage

So far this page only covers firmware 1.20 to 1.30. 1.40G and 1.41 have not been obtained yet.

- **Base.** `mSHAY1Ex.zip`, the archive's "v1.00", is firmware 1.20: vendor `ro.fota.version=1.20_20260228-1619`, build `eng.HiBy.20260228.173244`. MikuOS is built on it.
- **1.30.** `mOGC5azx.zip` is the 1.20 to 1.30 incremental: vendor `ro.fota.version=1.30_20260509-1120`. It was applied locally to the 1.20 images, and every resulting partition matches the manifest's sha256 (method in `m500-nos-filter.md`, "Checked firmware versions").
- **1.40G.** HiBy's guide lists 1.40G (`HiByDigitaly_M500_MIKU_4G_1.40G_20260703-1757`) only as a Baidu Pan link.
- **1.41.** 1.41 is only distributed through the on-device updater (`com.hiby.update`, Adups IoT FOTA SDK 2.1.36, product id 1750730662, API `https://iotapi.abupdate.com`). That host is blocked by this network's DNS filter. Rechecked 2026-10-10: it resolves to 149.248.211.216, which answers with `blocked-by: NextDNS` and an empty body. The API was not queried. The request format is in `hiby-firmware-history.md`, section 1.
- **Official changelog for later versions** (help center):
  - 1.40: DTA, a charge limit of 50 to 100 %, other fixes. DTA is only on the PO and BAL.PO outputs, at 44.1 to 384 kHz.
  - 1.41: Mini Miku birthday animation, other fixes.

The changelog lists these as 1.30 features: cassette UI, FM Bluetooth output, desktop pet toggle, FM recording that stops on a Bluetooth change. All four are found below.

### Kernel and boot

- **Kernel rebuilt.** It went from `5.15.153-android13-8-gca6de2449164-dirty` (built 2026-02-04) to `5.15.153-android13-8-g7199799f26f2` (built 2026-04-23).
- **vendor_dlkm.** Every vendor_dlkm module's md5 changed. For most of them only the vermagic changed (`5.15.153-g7199799f26f2`), so the 1.30 modules need the 1.30 boot image.
- **Changed partitions.** boot, vendor_boot, init_boot, dtbo and recovery all changed.
- **dtbo.** It adds overlays for other HiBy products (M300MAX, "TY HG5"). In the M500 overlays, `qcom,msm-mi2s-master` and `qcom,mi2s-mclk-enable` move to another fragment that targets the same `&bengal_snd` node. The merged result looks unchanged.

### vendor_dlkm modules

Code was compared byte for byte (`.text`, `.rodata`, `.data`, relocations).

**cs43198_dlkm.ko** (`6ef92ff320d4b64f101eee7262260a2d` to `12ded9dcbdf308f4d43ff56aaeca59e8`):
- **NOS fixed.** The PCM filter mask goes from 0xC0 to 0xE0 at every write to `0x090000`, so NOS now reaches the chip.
- **Second DAC.** It is now written whatever the output target is. In 1.20 it was only written in balanced mode. This applies to `cs43198_codec_digital_filter_set`, `init_reg_val`, `dai_hw_params`, `dre_function_enable`, `write_reg` and `sys_set_reg_val`.
- **MQA.** `codec_set_mqa_source("yes")` forces `0x090000 = 0x02`. Any other value restores the user filter.

**radio-si4705-common.ko / radio-si4705-i2c.ko** (1.30: `f6e017965ce2da4355524138e547b1ce` / `db0f78e3af458a180a0b1b5e8eda5a9c`):
- **No code change.** Only `.modinfo` differs.
- **RDS copy.** It still copies 4 of 8 bytes (`.text 0x18e0 adds x11, x11, #0x4`, `0x195c mov w2, #0x4`).
- **RDS arming.** RDS is still armed only in `si4705_fops_poll` (`0x175c`/`0x1760`).
- **Pilot.** The pilot indicator is still dropped (`0x624`, `0x648`, `0x664` unchanged).
- **Tuning tables.** The band table (`.rodata+0x39c`) and RSQ thresholds are unchanged.

**hiby_m500_plat_dlkm.ko** (`133aa6b488e4db0b9d9d962220473274` to `e367481fe7342c35bc571c86629499ff`): `.text` is identical. Only the string pool and one printk format changed.

**sa_sound_settings_dlkm.ko**: no code change.

**sa_sound_switch_dlkm.ko**:
- `sa_switch_enable` gains a show handler, so it can be read back.
- `set_sa_switch_enable` gains a "report_only_and_last_one" mode.
- It exports `muti_button_headset_status`, which the 1.30 `mbhc_dlkm` uses for headset button reporting.

**machine_dlkm.ko**:
- New kcontrols "Headphone Switch" and "Speaker Switch".
- When `output_select_put` gets None, it now falls back to headset if Headphone Switch is set, otherwise to speaker if Speaker Switch is set.

**mp2731_charger.ko**: new DT properties `mp,otg-gpio` and `mp,recharge-voltage`. This is not the 1.40 charge limit.

**cw2015_battery.ko**: adds `cw_update_charge_status`.

**sgm3804.ko** (new, `473c6b2916e2ab5c08428449798fd7ad`): an SGM3804 ±V regulator driver. It is in `modules.load`, but only the M300MAX overlay has the node, so nothing binds it on the M500.

### Vendor init, properties, mixer paths, HAL

- **init.hiby.audio.rc.** The filter trigger moved from `vendor.audio.hiby.digital_filter` to `vendor.audio.hiby.hw.digital_filter`. It still writes `/sys/devices/platform/sa_sound_setting/digital_filter`. No other rc change.
- **vendor build.prop** adds:
  - `ro.vendor.cpu_model=sm6225`
  - `ro.vendor.hires_support=no`
  - `ro.vendor.vibration_support=yes`
  - `ro.vendor.fn_buttion_support=yes`
  - `ro.vendor.dre_support=yes`
  - `ro.vendor.high_power_support=yes`
- **system_ext_property_contexts** adds these as `exported_default_prop`:
  - the property names above
  - `ro.vendor.gain_support`, `dsdgain_support`, `lrbalance_support`, `maxvolume_support`, `volume_ring_reverse_support`, `peq`, `fm.enable`, `workmode_support`
  - `vendor.audio.hiby.hw.diect_list_app` (spelled that way)
- **mixer_paths_bengal_idp.xml:**
  - Speaker Switch and Headphone Switch default to 0, and are set to 1 in the `speaker` path and in the `headphones`, `lineout`, `balancelo` and `iis` paths.
  - `TX_DEC2 Volume` goes from 84 to 100 in the handset dmic paths, and is added to the amic1 paths.
- **libfmpal.so.** The FM output-device switch gains a `PAL_DEVICE_OUT_A2DP` case, next to the existing WIRED_BALANCE, SPEAKER and WIRED_HEADPHONE cases.
- **audio.primary.bengal.so.** Only a USB-headset naming change ("Headset365" becomes "Headset", plus a "plugin card=%d device num=%d" log).
- **init.hiby.set.dwc3.rt.sh.** Comment changes only.
- **vendor sepolicy.** `vendor_qti_init_shell` gets proc/interrupts/pid_max reads and `vendor_file` execute_no_trans.

### Apps and framework

**Settings.apk:**
- **Filter list.** It is unchanged: four roll-off values plus `nos`.
- **Filter property.** It moves to `vendor.audio.hiby.hw.digital_filter`, written as a system property and as `Settings.Global`.
- **New preferences:**
  - Desktop pet: `Settings.Global desktop_pet_enable`, yes/no, read by Launcher3QuickStep.
  - Dynamic theme: `Settings.Global dynamic_theme`.
  - Kill task: `Settings.Global kill_service`.
- **Already in 1.20.** The Fn settings (`fn_status`, `fn_settings`) and the LDAC strings. The Fn page is now gated on `ro.vendor.fn_buttion_support=yes`.
- **Not yet present.** No DTA or charge-limit code.

**services.jar, `HibyAudioSettingInitUtils`:**
- The filter is restored at boot without the 1.20 model gate (`Build.MODEL` M500/M500_MIKU), from `Settings.Global vendor.audio.hiby.hw.digital_filter`. `high_power` and `dre_mode` are still model-gated.
- It also forces `persist.vendor.service.bt.a2dp.sink=false` and `sys.audio.mqa.max_rate=16`.

**FM2.apk (com.caf.fmradio), FM Bluetooth output:**
- **Routing.** When A2DP is the active media device, it sends `handle_fm=1048584` (0x100008). Other routes use 0x100003 (balanced), 0x100004 (h2w) and 0x100002 (otherwise).
- **Audio path.** It captures with `AudioRecord(source 1998 RADIO_TUNER, 48 kHz, stereo, 16-bit)` and plays that through an `AudioTrack` (USAGE_MEDIA). It retries 3 times at 500 ms.
- **Recording.** While on A2DP, recording writes WAV from the same capture.
- **Media keys.** A new MediaSession maps play/pause to mute, next/prev to station change, and long press to seek.
- **Mic indicator.** It sets `Settings.Global hide_mic_privacy_indicator` while on A2DP, and SystemUI honours it.

**HiByTape.apk** (new, `/vendor/app/HiByTape`, `com.hiby.tape`):
- It is the cassette UI: a launcher-style activity that controls the active media session through `MediaController`.
- It asks the HAL for `get_vu_data_str` and `set_vu_modify_pts=`. No 1.30 native library contains those keys.

**HiByMusic:**
- `createAudioTrackHires` adds AudioAttributes tags `hiby_sr=`, `hiby_bits=` and `hiby_dsd=1`, gated on `ro.vendor.hires_support` (`no` on 1.30).
- It also adds a DLNA server and `/vendor/etc/default-permissions/com.hiby.music.xml`.

**libandroid_runtime.so:** the AudioTrack JNI reads those tags. `hiby_sr` overrides the sample rate, `hiby_bits` the format, and `hiby_dsd` enables DSD. This looks like groundwork for 1.40's DTA.

**framework.jar:** `AudioManager.setParameters` intercepts about 30 key prefixes and forwards them to a new `IAudioService.setProperties(key, value)`. Examples: `vendor.audio.hiby.hw.*`, `vendor.audio.hiby.charging`, `mqaflag` to `vendor.audio.hw.mqa_source`, `A2dpConnect` to `sys.audio.uac.bluetooth`, and `car_mode_shutdown` to `sys.powerctl=shutdown`.

**services.jar:** `AudioService.setProperties` calls `SystemProperties.set` with no permission check, which gives any app a binder path to set properties as system_server.

**libbluetooth_qti.so:** remembers the last sink codec per device ("LastUsedSinkCodec") and retries it on reconnect.

**Bluetooth.apk:** code-only change, with no new codec strings.

**Launcher3QuickStep:**
- Adds `desktop_pet_enable`, the `negative_one_screen*` keys and a `com.hiby.tape` entry.
- `com.android.launcher3.xml` grants it MEDIA_CONTENT_CONTROL.

### Items for MikuOS

1. **NOS:** HiBy's 1.30 fix confirms the MikuOS diagnosis and fix value (mask 0xE0). `patch_cs43198_nos.py` changes all four 1.20 sites: the two in `cs43198_codec_digital_filter_set` (`.text 0x1118`, `0x1144`) and the two in `cs43198_init_reg_val` (`0x0B6C`, `0x0B9C`), which re-apply the filter on every `hiby_target_poweron`. That matches the sites HiBy changed. Nothing more to do for the mask.
2. **Second DAC:** decide whether to drop the balanced-only gate on second-DAC writes, as 1.30 does, so the filter is already set on the second DAC when the output switches to balanced.
3. **Si4705:** keep `patch_si4705_rds.py`. HiBy fixed neither the RDS copy, the RDS arming nor the pilot readout in 1.30. The patch sites hold the same instructions in the 1.30 module, so add its md5 if MikuOS ever rebases.
4. **FM Bluetooth output:** add it using the same mechanism, and add a MediaSession so hardware keys work during FM.
5. **Filter restore at boot:** restore it without a model-name check. MikuOS already does this through `persist.vendor.audio.miku.*`; keep it that way if HiBy's rc is reused, and note the 1.30 rc listens on `vendor.audio.hiby.hw.digital_filter`.
6. **Bluetooth codec:** remember the sink codec per device, if MikuOS configures the BT stack.
7. **Do not adopt `AudioService.setProperties`.** Keep property writes behind the sysbridge.
8. **Not needed on the M500:** `sgm3804.ko` and the M300MAX/HG5 overlays.
9. **Still to do:** obtain 1.40G or 1.41 and repeat the comparison, for DTA and the charge limit. This needs either the Baidu Pan 1.40 file (logged-in account) or the updater API (blocked by the DNS filter here).
