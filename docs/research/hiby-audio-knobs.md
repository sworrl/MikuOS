# HiBy M500 audio knobs: /sys/devices/platform/sa_sound_setting/

Research date 2026-10-10. Sources: stock v1.00 images in
`m500-system-archive/firmware/extracted_1.00/` (the images `build_mikuos_super.sh` builds from),
read with `debugfs` and disassembled with `llvm-objdump`. No device access was used. "Evidence"
below means a disassembly, devicetree, rc or sepolicy line; anything inferred beyond that is
marked GUESS.

## 0. Status (MikuOS 0.3.0, 2026-10-10)

This page was written before the fix and describes the stock firmware and what MikuOS did up to
0.1.x. What shipped since:

- **0.2.0** added the route in section 6. `com.miku.sysbridge` (system UID, `system_app`) sets
  `persist.vendor.audio.miku.{high_power,dre_mode,digital_filter,gain}` from a fixed list of
  values, and `miku_audio.rc` in vendor writes the matching node on every change and again at
  every boot. The bridge then publishes what it applied as Settings.Global `miku_dac_state`, which
  the Hardware app, the status bar DAC badge, the quick settings tiles and Miku Music all read.
- **0.3.0** ships HiBy's 1.30 `cs43198_dlkm.ko` when the 1.30 parts are supplied (see
  [m500-nos-filter.md](m500-nos-filter.md)). It fixes the NOS mask and writes the second DAC in
  every output mode.
- **Confirmed on hardware, 0.3.0:** the settings reach the driver. The driver's kernel log shows
  `cs43198_i2c_write_reg` for each change, on both `addr= 0x30` and `addr= 0x33`. Reading the
  chip's registers back directly still needs root, so that is what the driver wrote, not a read of
  the chip.
- The rows in section 5 marked "No" are the old paths. They are kept as a record of why nothing
  worked before 0.2.0.

## 1. Summary

- `sa_sound_settings_dlkm.ko` ("SmartAction Sound Setting", author ringsd) is only a string
  dispatcher. It creates the 31 nodes (all mode 0644), checks the value against a fixed word list,
  stores the string for read-back, and calls a function pointer in an ops table that another module
  registers through the exported `sa_sound_setting_register()`.
- On the M500 the only registrant is `hiby_m500_plat_dlkm.ko` ("HiBy Music Sound Platform"). Its
  ops table (`setting_function`, 0x128 bytes) fills 15 of the 35 slots. Of the 31 nodes, **four
  change hardware**: `high_power_mode`, `dre_mode`, `digital_filter`, `gain`. `gain_lock`,
  `pregain` and `dsd_compensate` only re-run the volume work. Everything else is a stub, a
  `printk`, or a NULL slot: the node accepts and echoes a value and nothing happens. The R2R, tube,
  Class A/AB, P/P+, hyper, turbo, MQA and timbre nodes belong to other HiBy players that share
  this driver.
- **There are two CS43198 DACs.** The codec driver registers one I2C client at 0-0030, but for
  the 4.4 mm balanced target it also writes every register to I2C address client+3 (0x33) on
  the same bus with raw `i2c_transfer`, using a second register table. The 0x33 chip is never
  registered as a client, which is why only one shows up under `/sys/bus/i2c/devices`.
- Stock writes the nodes only from init property triggers in
  `/vendor/etc/init/hw/init.hiby.audio.rc` (three of them), with values set by HiBy's
  `AudioService` at boot (`HibyAudioSettingInitUtils.initM500AudioSettings`) and by the stock
  Settings app.
- **Before 0.2.0, MikuOS reached none of the four live knobs.** (a) MikuOS renames
  `ro.product.model` to `m500_mikuOS-v*`, and HiBy's boot restore only runs when `Build.MODEL` is
  `M500_MIKU` or `M500`, so the Settings.Global rows MikuOS writes are never applied.
  (b) `HibyDacBridge` calls `IAudioService.setProperties`, which does not exist in the v1.00
  `framework.jar`/`services.jar` that MikuOS ships. It exists only in
  `m500-system-archive/vendor_software/services.jar`, a different build (SHA-1 7eb0828d versus the
  image's b5508573). (c) `AudioManager.setParameters("vendor.audio.hiby.hw.*")` reaches the vendor
  audio HAL, which contains no `hiby` strings at all. (d) The `su`/`echo` paths have no `su` to run
  on. The DAC therefore runs on driver defaults: high power off, DRE off, filter
  fast-roll-off/low-latency, gain offset 0 dB.
- Working route: `com.miku.sysbridge` runs in `system_app`, and HiBy's plat policy lets
  `system_app` set `vendor_audio_prop`. That covers the three existing triggers right away. `gain`
  needs one new vendor rc trigger. Section 6 has the details.

## 2. Hardware behind the knobs

### 2.1 GPIO map (devicetree, dtbo entry "HiBy M500 4G", msm-id 0x206 and 0x24a, identical)

`soc:hiby,sound-plat` lines. "EXP n" is line n of the GPIO expander at I2C 8-0020. Its DT node is
`aw,aw95016` (Awinic AW95016, driven by `gpio-pca953x.ko`, which lists the `aw95016` compatible),
on the bit-banged bus `i2c_gpio_8` (TLMM 111/112).

| Line | DT name | Role (evidence: who toggles it, and when) |
|---|---|---|
| EXP 2 | cs43198 reset-gpios | DAC reset |
| EXP 4 | dac_po_power | DAC supply, set to 1 on PO/BAL power-on |
| EXP 5 | dac_bal_power | second DAC supply, set to 1 on PO/BAL power-on |
| EXP 10 | sw_en | set to 1 first on PO/BAL power-on (GUESS: analog supply switch) |
| EXP 6 | dc_en | 1 only in high power mode, followed by a 100 ms wait (GUESS: boost DC-DC for the amp rails) |
| EXP 7 | amp_po_en | 1 only in high power mode |
| EXP 8 | amp_bal_en | 1 only in high power mode (when switched live, only if target is Balance) |
| EXP 3 | po_sel | 1 only in high power mode |
| EXP 12 | po_hpo_sel | 1 only in high power mode |
| EXP 9 | bal_hpo_sel | 1 only in high power mode |
| EXP 11 | agnd_fm_sel | always driven 0 by this driver (GUESS: analog ground / FM path select) |
| EXP 15 | hp_bal_sel | target select, 3.5 mm vs 4.4 mm |
| EXP 13 | (si4705 power-gpios) | FM tuner power |
| EXP 14 | (sa_sound_switch power_io) | jack-detect power |
| TLMM 108 | sgm_po_en | 1 only in high power mode |
| TLMM 69 | sgm_bal_en | 1 only in high power mode |
| TLMM 25 | hp_bal_mute | output mute, pulsed around every mode change |
| TLMM 19 | bal_hpo_mute | output mute, pulsed around every mode change |

Jack detect (`hiby,sa_sound_switch`): balance on TLMM 60, 3.5 mm on TLMM 65 (active low).
Speaker PA AW883xx at 8-0035. USB-C AW35615 at 7-0022 (`i2c_gpio`, TLMM 56/83).

### 2.2 Output targets

The machine driver's ALSA enum "Output Select" (`output_select_text` in `machine_dlkm.ko`) gives
the target ids the platform driver uses: 0 None, 1 Lineout, 2 Headset (3.5 mm PO), 3 Balance
(4.4 mm PO), 4 Spdif, 5 Coax, 6 Iis, 7 BalanceLo, 8 Speaker, 9 Headset635.
`hiby_target_poweron` powers hardware for targets 2, 3 and 8 only. For any other target it just
records the number. Line-out modes therefore get no DAC power-up from this driver (observation;
whether LO works on this unit was not tested).

### 2.3 The two CS43198s

- `cs43198_write_reg_save` and `cs43198_write_reg_bypass` take an address offset and send to
  `client->addr + offset`. Every write path (`init_reg_val`, volume, filter, DRE, raw
  `reg_val`/`write_reg_val`) writes offset 0 (0x30) and, when the current target is 3 (Balance),
  also offset 3 (0x33).
- 0x30 gets `cs43198_reg_po` (22 entries). In balanced mode 0x33 gets `cs43198_reg_bal`
  (38 entries). The balanced table differs at 0x01000C (0x02 vs 0x00), at 0x090004 (0x0E vs 0x02),
  and adds 16 writes to undocumented 0x18xxxx registers. GUESS: 0x33 runs inverted (the
  differential half), and 0x18xxxx is per-chip trim.
- Volume: `_plat_set_volume` maps level 0..100 through `cs43198_volume_db` (0.1 dB units,
  -127.0 dB at 0, then -88.0 dB at 1, 0.5 dB steps near the top, 0.0 dB at 100). It adds the gain
  offset, clamps to at most 0 dB, and writes the same value to PCM Vol A/B (0x090001/0x090002) and
  DSD Vol (0x070001/0x070002). The same value always goes to both channels, so there is no
  hardware L/R balance path.
- A +3 dB "low voltage" branch exists in `_plat_set_volume`, but `current_amp_voltage_mode` is
  set to 1 in probe and never changed, so that branch is dead.

## 3. Attribute table

Columns: accepted values (from the strncmp lists in `set_*`), what it does on the M500, who writes
it on stock, whether MikuOS uses it, how MikuOS could drive it. "No-op" means the store succeeds
and read-back returns the value, but no hardware changes.

Read-back caveat: probe pre-loads the strings `gain=low`, `lo_gain=high`,
`bal_po_lo_switch=bal_po`, `timbre=monitor`, and an empty `digital_filter`. The effective gain
offset starts at 0 dB, which is what "high" does. So `gain` reads "low" while acting like "high"
until something writes it.

### 3.1 Nodes that change hardware

| Attribute | Values | What it does (evidence) | Stock writer | MikuOS today | How MikuOS can drive it |
|---|---|---|---|---|---|
| `high_power_mode` | `hpower_enable`, `hpower_disable` | `plat_set_high_power_mode`: returns early if unchanged. Otherwise sets volume to 0, mutes (hp_bal_mute, bal_hpo_mute = 1), then on enable sets dc_en=1, waits 100 ms, sets amp_po_en=1, amp_bal_en=(target==Balance), sgm_po_en, sgm_bal_en, po_sel, po_hpo_sel, bal_hpo_sel all 1. On disable it sets all of them to 0. agnd_fm_sel stays 0. Then unmutes and restores the volume. Target power-on repeats the same set. GUESS: low power drives the headphones from the CS43198's own output stage, and high power switches in an external amp stage on a boosted rail. Digital volume is identical in both modes, so the same level index is louder in high power. | init: `on property:vendor.audio.hiby.high_power=*` (init.hiby.audio.rc). The property is set by stock Settings (system_app, "Low Power / High Power" list) and by system_server at boot from the Global row `vendor.audio.hiby.high_power` (default `hpower_disable`). | Writes Global rows and `setParameters` (neither reaches hardware: boot restore is gated on Build.MODEL, the HAL ignores the key). `HibyDacBridge.set(vendor.audio.hiby.high_power)` needs `IAudioService.setProperties`, which is missing on v1.00, so it returns UNAVAILABLE. | sysbridge (system_app) sets `vendor.audio.hiby.high_power`; the stock trigger does the write. For persistence, see 6.2. |
| `dre_mode` | `dremode_enable`, `dremode_disable` | `plat_set_dre_mode_enable` then `update_dre_function`: mute, `cs43198_dre_function_enable`, unmute. On both chips in balanced mode: unlock hidden registers (0x010010 = 0x99), write 0x0C0001 = 1 (enable) or 0 (disable), and on enable also 0x0C0056 = 0x2F, then relock (0x010010 = 0). Re-applied on every target power-on. GUESS: Cirrus dynamic range enhancement (signal-dependent analog gain switching). | init: `vendor.audio.hiby.dre_mode` trigger. Set by system_server at boot (default `dremode_disable`) and by stock Settings. Stock `AudioSettings.onCreate` calls `setDreMode(true)` unconditionally, so opening HiBy's audio settings screen turns DRE on. | Same as high_power: Global row plus HibyDacBridge (unavailable). Not reaching hardware. | sysbridge sets `vendor.audio.hiby.dre_mode`. |
| `digital_filter` | sa accepts any string. The plat driver acts on `fast_rolloff_low_latency`, `fast_rolloff_phase_compensated`, `slow_rolloff_low_latency`, `slow_rolloff_phase_compensated`, `nos` | `plat_set_digital_filter` calls `cs43198_codec_digital_filter_set`, which writes reg 0x090000 (PCM filter option) with mask 0xC0: fast/LL = 0x00, fast/phase-comp = 0x40, slow/LL = 0x80, slow/phase-comp = 0xC0. **`nos` computes 0x20, which the 0xC0 mask drops**, so it lands on bits 7:6 = 00, identical to fast/LL. NOS is not actually reachable through this node. The value persists in `user_filter_setting` and is re-applied at each `init_reg_val`. Skipped if `user_mqa_source` is set, which nothing on the M500 sets. | init: `vendor.audio.hiby.digital_filter` trigger. On v1.00 the property is set only by system_server at boot from the Global row `vendor.audio.hiby.digital_filter` (default fast_rolloff_low_latency). HiBy's newer Settings/services (jadx copy in the archive) write `vendor.audio.hiby.hw.digital_filter` instead, which no v1.00 rc reads. | Global rows, HAL params, HibyDacBridge (unavailable). Not reaching hardware. MikuOS also offers "NOS", which is the same as fast/LL. | sysbridge sets `vendor.audio.hiby.digital_filter`. Drop NOS from the UI, or implement it via 3.3. |
| `gain` | `low`, `middle`, `high` | `plat_set_gain`: `plat_vol_gain` = -24 (low), -12 (middle), 0 (high or anything else) in half-dB units, so -12 / -6 / 0 dB. Applied as a digital offset in `_plat_set_volume` for the 3.5 mm and 4.4 mm PO targets only (not line out, not speaker), then the volume work re-runs. It is not an analog gain change. | Nothing on stock v1.00 writes it (no rc trigger, no app). It stays at 0 dB. | Labels "Low (0 dB)" / "High (+6 dB)" are wrong. Writes Global rows and HAL params only, so nothing reaches the node. `build_mikuos_super.sh` puts `vendor.audio.hiby.hw.gain=high` in Global, which has no consumer. | Needs a new vendor rc trigger (6.2), then sysbridge sets the property. Real use: `low` gives -12 dB of digital headroom for sensitive IEMs. It does not lower the analog noise floor. |

### 3.2 Nodes that only re-run volume, or do nothing

| Attribute | Values | M500 effect (evidence) | Stock writer | MikuOS today | Drive it? |
|---|---|---|---|---|---|
| `gain_lock` | any (plat acts on `yes`/`no`) | Stores the flag and, if it changed, re-applies the current gain string. No lock behaviour. | none | not used | no value |
| `pregain` | integer | `plat_set_pregain` prints and requeues the volume work. The value is not stored or used. No effect. | none | not used | no |
| `dsd_compensate` | integer | Requeues the volume work only. No effect. | none on M500 | Writes a Global row only | no |
| `lrbalance` | integer | `plat_set_lrbalance` is a `printk` only. No hardware balance (see 2.3). | none on M500 (HiBy Settings has the UI for other models) | Writes Global rows and su echo (no effect either way) | Do balance in software |
| `turbo` | `on`, `off` | `plat_set_turbo` is a `printk` only | none on M500 | Reads `vendor.audio.hiby.hw.audio_turbo` prop for its audit UI | no |
| `timbre` | `default`, `monitor`, `warm`, `tube` | `plat_set_timbre` is an empty stub (`codec_timbre_set` in the codec is also print-only and never called) | none | not used | no |
| `mqa_source` | `yes`, `no` | Empty stub | none | not used | no |
| `lo_gain` | `low`, `middle`, `high` | Empty stub | none | not used | no |
| `bal_po_lo_switch` | `bal_po`, `bal_lo` | Empty stub. PO/LO is chosen by "Output Select", not this node | HiBy services.jar (newer build) sets `vendor.audio.hiby.hw.bal_po_lo_switch`, no consumer | su echo (no effect) | no |
| `dsd_digital_filter` | any | Empty stub | none | not used | no |
| `po_lo_switch` | `headset`, `lineout` | NULL ops slot | none | su echo (no effect) | no |
| `mute_enable` | any | NULL slot | none | not used | Use `sound-plat/mute_port` instead (5.1) |
| `charge_mode_state` | any | NULL slot | none | not used | no |
| `power_on_state` | any | NULL slot | none | not used | no |
| `ccb_reset_default_value` | any | NULL slot | none | not used | no |
| `R2R_mode` | `pcm`, `dsd`, `auto` | NULL slot (R2R DAC models) | none | not used | no |
| `tube_tumbre_type` | `tube_frist`, `tube_second` | NULL slot (tube models) | none | not used | no |
| `balpo_po_a_ab` | `zoom_a`, `zoom_ab` | NULL slot (Class A/AB models) | HiBy services.jar (newer build) sets `vendor.audio.hiby.hw.balpo_po_a_ab`, no consumer | not used | no |
| `balpo_po_t_n` | `transistor_t`, `transistor_n` | NULL slot | none | not used | no |
| `power_p_pplus` | `power_p`, `power_pplus` | NULL slot | none | not used | no |
| `hyper_mode` | `hyper_enable`, `hyper_disable` | NULL slot | none | not used | no |
| `dac_dsd_gain` | `dsd_gain_on`, `dsd_gain_off` | NULL slot | none | su echo (no effect) | no |
| `dac_output_type` | `dac_one`, `dac_two` | NULL slot | none | su echo (no effect) | no |
| `dsd_filter` | `wide_bandwith`, `narrow_bandwidth`, `dsd_low`, `dsd_middle`, `dsd_high` | NULL slot | none | not used | no |
| `digital_output_type` | `spidf/iis`, `analog` | NULL slot (S/PDIF and I2S models) | none | not used | no |
| `vendor_func` | any | NULL slot. Read returns empty | none | not used | no |
| `dac_type` | (read) | NULL slot. Read returns empty. **The store returns 0 bytes written**, so a writer that loops until all bytes are written (init `write`, `echo`) can spin forever. Never write it. | none | not used | never |

### 3.3 Related nodes outside sa_sound_setting

| Node | Mode | Behaviour (evidence) | Stock writer |
|---|---|---|---|
| `soc:hiby,sound-plat/volume` | 0200 | `%d`, clamped to 100, sets the L/R level and queues the ramped volume work (steps of 1 or 5). This is the master DAC/speaker attenuation | init trigger `vendor.audio.hw.set.volume`. In normal use the PAL sets "Plat Left/Right Playback Volume" (`libar-pal.so`) |
| `soc:hiby,sound-plat/mute` | 0200 | The string `speaker on` sets `current_mute_speaker`, which forces AW883xx volume to 1023 (fully attenuated). Any other string clears it. Affects the speaker only | init trigger `vendor.audio.hw.set.mute`. system_server sets it at boot from Global `speaker_mute_status` |
| `soc:hiby,sound-plat/mute_port` | 0200 | `%s %d`: drives the hp_bal_mute / bal_hpo_mute GPIOs directly | none |
| `soc:hiby,sound-plat/output`, `delay_val`, `turbo` | 0200 | `printk` only | init trigger for output |
| `soc:hiby,sound-plat/amp_mode`, `amp_level` | 0644 | Store parses and discards | none |
| `0-0030/reg_val` | 0200 | `"w <reg> <val>"` (hex) writes through `write_reg_save` (mask 0xFF) to 0x30, and to 0x33 when the target is Balance. `"r ..."` reads each shadow register back from the chip into the kernel log | none |
| `0-0030/write_reg_val` | 0200 | `"<reg> <val>"` (`%x %hhx`): same write path | none |
| `0-0030/write_lr_flag` | 0200 | `left`/`right`, affects log text only | none |
| ALSA "ES9028Q2M Digital Filter", "Mute Output", "Left/Right Playback Volume", "ES9028Q2M Soft Mute" (codec) | | All are print-only stubs | |
| ALSA "Force DSD Mode" (machine) | | Calls `hiby_output_force_dsd`, which returns 0 and does nothing | PAL `pal_force_dsd_mode` |

Raw register access can do what the node cannot: real NOS (reg 0x090000 bit 5, keeping bits 7:6
for the filter and bit 1 as in the init value 0x02), de-emphasis and HPF bits, and per-channel
volume (0x090001/0x090002), though the volume work overwrites per-channel volume on the next
change. The bit assignments follow the Cirrus CS4313x/CS43198 register map and the shadow-table
values. They are datasheet-based, not measured. A write updates the shadow table, so it survives
target switches. In single-ended mode only the 0x30 table is updated, so a later switch to
Balance would not carry the change to 0x33.

## 4. Who may touch what (SELinux, v1.00)

- No genfscon entry labels `sa_sound_setting`, `soc:hiby,sound-plat` or `0-0030`. They are plain
  `sysfs`.
- Writers of plain `sysfs` files: `init` (`base_typeattr_519` includes sysfs) and `vendor_init`
  (`base_typeattr_572` = sysfs_type minus usermodehelper). So a `write` in any rc file works.
  No app domain (`platform_app`, `system_app`, `priv_app`) has read or write. The "unreadable from
  adb shell" observation fits: shell has only dir search on `sysfs`.
- `vendor.audio.*` and `persist.vendor.audio.*` map to `vendor_audio_prop`. Setters in HiBy's
  plat policy: `system_app`, `system_server`, `hal_audio`, `hal_health_server`, `bluetooth`
  (system_ext), `vendor_init`, `vendor_qti_init_shell`. `platform_app` cannot set it.
- `/odm/etc/selinux/precompiled_sepolicy` exists, so editing CIL files alone does nothing until
  the precompiled policy is invalidated. Avoid this route. The property-trigger route needs no
  policy change.

## 5. What MikuOS did before 0.2.0 (code read 2026-10-10)

| Path | Where | Reaches hardware? |
|---|---|---|
| `Settings.Global` rows `vendor.audio.hiby.{high_power,dre_mode,digital_filter}` | `MikuDirectAudio.ensureBestAudio`, `CirrusLogicManager` (player, hardware-settings, settings) | No. Only `initM500AudioSettings` reads them, and it is gated on `Build.MODEL` being `M500_MIKU` or `M500` (v1.00 smali). MikuOS sets the model to `m500_mikuOS-v*` (build script lines 778-799, 917). |
| `Settings.Global` rows `vendor.audio.hiby.hw.*`, `vendor.audio.hiby.gain` | same, plus build script line 1144 | No consumer in v1.00. |
| `AudioManager.setParameters("vendor.audio.hiby.hw.*=...")`, `routing=...;vendor.audio.hiby.hw.output_mode=...`, `vendor.audio.dual_output` etc. | all CirrusLogicManager copies, `MikuDirectAudio.pushToHal` | No. The vendor HAL and PAL contain no `hiby` keys. `routing=` may still move AOSP routing. |
| `HibyDacBridge.set` via `IAudioService.setProperties` | player `profiles/HibyDacBridge.kt` | No on v1.00: the method is absent from the image's `framework.jar`/`services.jar`. It exists only in the archive's `vendor_software` jars (a different build). Expect `Result.UNAVAILABLE`. |
| `RootShell` / `su -c echo > sysfs`, `setprop` | hardware-settings, mikuos-settings, mikuos-systemui, `PocketLockReceiver` | No `su` on MikuOS. |
| sysfs reads for the audit UI | `CirrusLogicManager.readSysfs` | Denied (platform_app). The UI falls back to Global rows, which reflect intent, not hardware. Reads of `out_mode` and `lr_balance` would fail anyway: no such nodes exist. |

Net effect: the hardware sits on driver defaults: low power, DRE off, fast/low-latency filter,
gain offset 0 dB. Also note what the enforcer is set up to do. `ensureBestAudio` defaults
`highPower` to true. Once any working path is wired up, every MikuOS user gets high power on at
boot unless they opted out. See risks.

## 6. How MikuOS can drive the live knobs

### 6.1 Immediate, using the existing stock triggers

Add an action to `com.miku.sysbridge`, for example `com.miku.sysbridge.DAC_PROP` with
extras key/value. Keep a strict whitelist:

- `vendor.audio.hiby.high_power` in {`hpower_enable`, `hpower_disable`}
- `vendor.audio.hiby.dre_mode` in {`dremode_enable`, `dremode_disable`}
- `vendor.audio.hiby.digital_filter` in the four real filter names

It calls `SystemProperties.set`. That is allowed because sysbridge is `system_app`, the same
path its USB DAC code already uses. The stock `init.hiby.audio.rc` then writes the node. Point
`HibyDacBridge` at the broadcast instead of `IAudioService.setProperties`. Read-back: `getprop`
from any app works (`vendor_audio_prop` is readable by `platform_app`), but it only proves the
property changed, not the node.

### 6.2 Gain, and persistence across reboot

Ship one more vendor rc beside `miku_led.rc` (same `dfput` + `label vendor_file` pattern). The
`write` runs as `vendor_init`, which may write plain sysfs:

```
on property:persist.vendor.audio.miku.gain=*
    write /sys/devices/platform/sa_sound_setting/gain ${persist.vendor.audio.miku.gain}
on property:persist.vendor.audio.miku.high_power=*
    write /sys/devices/platform/sa_sound_setting/high_power_mode ${persist.vendor.audio.miku.high_power}
on property:persist.vendor.audio.miku.dre_mode=*
    write /sys/devices/platform/sa_sound_setting/dre_mode ${persist.vendor.audio.miku.dre_mode}
on property:persist.vendor.audio.miku.digital_filter=*
    write /sys/devices/platform/sa_sound_setting/digital_filter ${persist.vendor.audio.miku.digital_filter}
```

`persist.vendor.audio.*` is `vendor_audio_prop`, so sysbridge may set it. Persistent properties
are replayed when they load at boot, so the triggers fire again on every boot. This replaces
HiBy's model-gated boot restore without touching `ro.product.model`. The kernel validates the
enumerated values itself (strncmp lists), but keep the sysbridge whitelist anyway. Never add a
trigger for `dac_type` (3.2).

Optional, needs care: a trigger for `0-0030/write_reg_val` to get real NOS
(e.g. `090000 22` for fast/LL+NOS with the init HPF bit). Restrict it to that one register and to
the five computed values. It must be re-sent after switching between 3.5 mm and 4.4 mm (see the
shadow-table note in 3.3).

### 6.3 Not worth wiring

The 3.2 nodes. Do L/R balance, "timbre" and similar in the player's DSP. Remove or relabel the
"turbo", "dsd gain compensation", "NOS" and "+6 dB" UI items, which describe things this hardware
does not do.

## 7. Risks

- **High power on sensitive IEMs.** Switching keeps the same digital level and puts a
  higher-output stage in the path. The driver ramps volume to 0, switches and restores the same
  index, so the result is a step up in loudness at the same slider position. Defaulting to high
  power (as `ensureBestAudio` would) is a hearing and driver risk for IEM users. Default to off,
  and drop the volume before enabling it. 100 ms of boost settling is in the driver. Do not toggle
  repeatedly in a loop.
- **Gain is digital only.** `gain=high` (0 dB) is already the effective default, so the
  "make IEMs louder" premise was wrong. `low` costs nothing but headroom.
- **Raw register writes** (`reg_val`, `write_reg_val`) bypass all checks. The headphone output
  control register (0x080000 = 0x31 in both tables), the power-down register (0x020000) and the
  hidden 0x0C/0x18 pages can produce full-scale output, DC or loud pops, or leave the chip in an
  undefined state until the next target power-on. Whitelist single registers and values only.
- **`dac_type` write hang** (store returns 0). Writing it from init could wedge the property
  service thread.
- **`IAudioService.setProperties` in the newer HiBy framework** sets any property system_server
  may set, with no permission check. On firmware that has it, any app with a raw binder
  transaction can switch high power on. Not present in v1.00.
- Opening stock HiBy Settings' audio page forces DRE on (`setDreMode(true)` in `onCreate`), if
  that app is ever reinstated.
- Archive caution: `m500-system-archive/audio_configs/init.hiby.audio.rc` and
  `extracted_fs/vendor/etc/init/hw/init.hiby.audio.rc` say
  `vendor.audio.hiby.hw.digital_filter`. Both stock images (`extracted_1.00/vendor.img` and
  `firmware/super.img`) say `vendor.audio.hiby.digital_filter`. Treat the archive copies as
  edited. The jadx/smali trees under `decompiled_vendor_software/` are also from a different
  services/framework build than `extracted_1.00/system.img`.

## 8. Other underused hardware noticed

- **Second CS43198 at 0x33**: already used in balanced mode by the driver. Its separate shadow
  table means per-chip tuning (e.g. matching the two chips) is possible through raw writes. GUESS
  value.
- **SGM31324 RGB LED driver (2-0030)**: `/sys/class/leds/sgm31324-leds/led_pattern` takes 0..10
  (stock map: 1 idle, 2 low, 3 standard, 4 high, 5 DSD, 6/7 charging, 8 MQA, 9 MQA Studio, 10 MQB),
  and `write_pattern` takes a raw 10-byte register pattern (hex string, like the DT `regs`), so
  custom colours and breathing are possible. Stock `init.hiby.led.rc` already maps
  `vendor.audio.hiby.hw.sample_quality` to patterns. sysbridge (system_app, `vendor_audio_prop`)
  could set it per track. The build script comment that only init may set `vendor_audio_prop` is
  out of date.
- **AW883xx smart PA (8-0035)**: sysfs `spk_temp`, `cali_re`, `cali_f0`, `re_range`, `monitor`,
  `fade_en`/`fade_step`, `dbg_prof` (profile select). Possible uses: show speaker temperature,
  run Re/F0 calibration, change the fade length for speaker pops, pick a louder or cleaner
  profile. Needs an rc trigger (plain sysfs, same rules as above).
- **AW35615 USB-C/PD (7-0022)**: sysfs `pdo_set`, `port_type`, `pwr_role`, `data_role`,
  `typec_state`, `src_current`/`sink_current`, `vconn_source`. The DT limits PD to 5 V/2 A sink
  and 5 V/1 A source. Role and source-current control could power hungry USB DACs better.
  Raising the sink PDO voltage is a charger-damage risk unless the SGM41513/MP2731 input limits are
  checked.
- **CDSP / HVX**: `libcdsprpc.so`, `libsysmon_cdsp_skel.so`, FastCV and dspCV skels are on vendor,
  and `vendor.qti.cdsprpc-service.rc` runs. EQ, convolution or resampling could be offloaded to the
  compute DSP through FastRPC (unsigned PD) to save CPU and battery during playback.
- **sa_earpods_adc2** (`earpods_adc_sw`): inline-remote ADC switch for wired headset buttons.
- **gpio_keys_hiby / ring_keys**: `disabled_keys` (init trigger
  `vendor.audio.hw.gpiokey_state_update`) and the rotary volume knob. Hold-lock and knob reversal
  (`vendor.audio.hw.ring_vol_reverse`) are reachable through `vendor_audio_prop`, so sysbridge can
  set them too.
