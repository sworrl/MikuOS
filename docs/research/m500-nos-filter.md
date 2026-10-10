# The M500's NOS filter was broken through firmware 1.20. HiBy fixed it in 1.30.

The HiBy M500 lists a NOS (non-oversampling) digital filter. Through firmware 1.20, picking it did
nothing: you got the same sound as "Fast roll-off, low latency". The DAC chip has a real NOS mode,
and a one-byte mask in HiBy's driver kept it from ever being turned on. HiBy fixed the mask in
firmware 1.30. MikuOS is built on 1.20. From 0.3.0 it ships HiBy's own 1.30 build of the driver
(`cs43198_dlkm.ko`) when the build has the 1.30 parts, and falls back to the same fix as a
four-byte patch to the 1.20 driver when it only has 1.20.

Everything below can be checked by anyone with the stock v1.00 firmware.

## What the chip can do

The M500 uses Cirrus Logic CS43198 DACs. The datasheet (DS1156, "PCM Filter Option" register)
puts the filter controls in register `0x090000`:

| Bit | Field | What it does |
|---|---|---|
| 7 | FILTER_SLOW_FASTB | slow or fast roll-off |
| 6 | PHCOMP_LOWLATB | phase compensated or low latency |
| 5 | NOS | non-oversampling mode; when set, bits 7 and 6 are ignored |
| 4..3 | reserved | |
| 2 | PCM_WBF_EN | wideband flatness |
| 1 | HIGH_PASS | high-pass filter (on by default) |
| 0 | DEEMP_ON | de-emphasis |

So the chip has five filter responses: the four roll-off combinations, and NOS.

## What HiBy's driver does

The filter is set in `cs43198_dlkm.ko` (vendor_dlkm, `/lib/modules`), function
`cs43198_codec_digital_filter_set`. Disassembled from the stock module
(md5 `6ef92ff320d4b64f101eee7262260a2d`):

```
strcmp(name, "fast_rolloff_low_latency")        -> 0x00
strcmp(name, "fast_rolloff_phase_compensated")  -> 0x40
strcmp(name, "slow_rolloff_low_latency")        -> 0x80
strcmp(name, "slow_rolloff_phase_compensated") -> 0xC0
anything else ("nos")                           -> 0x20

1110: mov w2, #0x90000      ; register: PCM Filter Option
1114: mov w3, w19           ; value: 0x20 for NOS
1118: mov w4, #0xc0         ; mask: bits 7..6 only
111c: bl  update_bits       ; main DAC
...
1144: mov w4, #0xc0         ; same mask for the second DAC (4.4 mm balanced)
```

The driver picks the right value for NOS, `0x20`, which is bit 5. Then it writes it with mask
`0xC0`, which only lets bits 7 and 6 through. Bit 5 is thrown away, bits 7 and 6 are both 0, and
the chip lands on fast roll-off, low latency. Every time.

Same thing on the second DAC. The M500 really has two CS43198 chips: in 4.4 mm balanced mode the
driver writes every register to the one at I2C address 0x30 and to a second one at 0x33. Both get
the same mask.

## The fix

Change the mask from `0xC0` to `0xE0` at all four write sites: the two in
`cs43198_codec_digital_filter_set` (when you pick a filter) and the two in `cs43198_init_reg_val`
(which re-applies the saved filter every time the DAC powers up). One instruction each:

| .text offset | function | stock | patched |
|---|---|---|---|
| `0x0B6C` | init_reg_val, main DAC | `52801804` (`mov w4, #0xc0`) | `52801c04` (`mov w4, #0xe0`) |
| `0x0B9C` | init_reg_val, second DAC | `52801804` | `52801c04` |
| `0x1118` | filter_set, main DAC | `52801804` | `52801c04` |
| `0x1144` | filter_set, second DAC | `52801804` | `52801c04` |

Four bytes change in the whole module. The patched module's md5 is
`d325d31d42768304fcf506afea2113e3`. This is the same change HiBy made in 1.30 (see "Checked
firmware versions" below). The script is `mikuos/build/patch_cs43198_nos.py`. It refuses
to run on anything but the stock module and checks the result hash.

Switching back works too. The four roll-off values all have bit 5 clear, so picking one of them
writes a 0 into the NOS bit and turns NOS off. Bits 4 to 0 stay outside the mask, so high-pass,
de-emphasis and wideband flatness are untouched, as before.

## Why MikuOS couldn't reach any DAC setting either

Separate from the mask, MikuOS before 0.2.0 never reached the DAC settings at all. HiBy applies
the filter, DRE and high power through init triggers on `vendor.audio.hiby.*` properties. Those
are set at boot by a HiBy system service that only runs when the model name is "M500", and MikuOS
renames the device. Apps can't set those properties themselves (SELinux).

MikuOS 0.2.0 routes the settings through its system bridge app, which is allowed to set
`vendor_audio_prop`. It sets `persist.vendor.audio.miku.*`, and a small init file writes the
driver nodes on every change and again at every boot. Details: [hiby-audio-knobs.md](hiby-audio-knobs.md).

On MikuOS 0.3.0 (2026-10-10) that path was confirmed on hardware from the driver's own kernel
log. A filter change shows up as `cs43198_i2c_write_reg` lines for register `0x090000` on both
DACs, `addr= 0x30` and `addr= 0x33`. For example "Fast roll-off, phase compensated" writes
`0x42` (0x40 for the filter plus the high-pass bit). That is what the driver sent, not a read of
the chip's register, which needs root.

## What NOS does to the sound

Without oversampling there's no steep digital filter after the DAC, so no pre-ringing or
post-ringing on transients, a gentler top-end roll-off, and more ultrasonic images above the audio
band. People who like NOS describe it as more relaxed and natural. It measures worse on a scope.
That trade is the whole point of offering it.

Cirrus notes that NOS should be off when wideband flatness mode is used. MikuOS doesn't turn
wideband flatness on.

## Status

MikuOS 0.3.0 (2026-10-10):

- **HiBy's 1.30 driver** is what the image ships when the 1.30 parts are supplied.
  `os/adopt_hiby130.py` checks the exact hash of the file, its vermagic and every imported
  symbol's CRC against the 1.20 kernel before it swaps anything. `patch_cs43198_nos.py` is the
  fallback for a 1.20-only build.
- **NOS is selectable**, and the setting reaches the driver through the system bridge. The kernel
  log shows the driver writing the filter register on both DACs.
- **Not done yet:** a listening test, and a read of the chip's own register to show bit 5 set.
  Reading the register back needs root, which MikuOS does not use. This page will be updated with
  the listening test.

A note on version numbers: the firmware archive used for MikuOS labels its base package "v1.00",
but that package reports `ro.fota.version=1.20_20260228-1619`. Everything on this page called
"stock" is 1.20.

## Checked firmware versions

### Which versions these are

The archive's two HiBy packages carry different version numbers from the ones they have been filed under:

| Archive file | Archive label | What the image says |
|---|---|---|
| `mSHAY1Ex.zip` (full OTA) | v1.00 | vendor `ro.fota.version=1.20_20260228-1619`, `ro.build.version.subversion=1.20`, build `eng.HiBy.20260228.173244` |
| `mOGC5azx.zip` (incremental) | v1.20 | pre-build `eng.HiBy.20260228.173244`; resulting vendor `ro.fota.version=1.30_20260509-1120`, `ro.build.version.subversion=1.30` |

So "stock v1.00" elsewhere on this page means firmware 1.20, and the incremental is 1.20 to 1.30.

### How 1.30 was obtained

`mOGC5azx.zip` (payload v2, minor version 8) was applied to the 1.20 images with a local payload applier. The applier handles SOURCE_COPY, ZERO, REPLACE_BZ/XZ, BROTLI_BSDIFF (BSDF2), and PUFFDIFF (AOSP puffin puff/huff plus BSDF2), then recomputes the dm-verity hash tree and RS(255,253) FEC. Every source partition hash matched the manifest's old_partition_info. Every resulting partition matched new_partition_info: boot, dtbo, init_boot, odm, product, recovery, system, system_dlkm, system_ext, vbmeta, vbmeta_system, vendor, vendor_boot and vendor_dlkm. vendor_dlkm 1.30: sha256 `e9738198e11f988f232ea3b4ed1702a6d191b281d1afd2e762d1cf822eb35672`.

### Results

Offsets are `.text` offsets in `cs43198_dlkm.ko`.

| Version | cs43198_dlkm.ko md5 | hiby_m500_plat_dlkm.ko md5 | Mask at each `0x090000` write | NOS reaches chip |
|---|---|---|---|---|
| 1.20 (archive "v1.00") | `6ef92ff320d4b64f101eee7262260a2d` | `133aa6b488e4db0b9d9d962220473274` | `cs43198_init_reg_val`: `0x0B6C` 0xC0, `0x0B9C` 0xC0 (second DAC, only if output target is 3). `cs43198_codec_digital_filter_set`: `0x1118` 0xC0, `0x1144` 0xC0 (second DAC, only if output target is 3) | No |
| 1.30 | `12ded9dcbdf308f4d43ff56aaeca59e8` | `e367481fe7342c35bc571c86629499ff` | `cs43198_init_reg_val`: `0x0B6C` 0xE0, `0x0B90` 0xE0. `cs43198_codec_digital_filter_set`: `0x107C` 0xE0, `0x1098` 0xE0. `codec_set_mqa_source` restore path: `0x10FC` 0xE0, `0x1120` 0xE0 | Yes, unless the MQA source flag is set |
| 1.40G, 1.41 | not obtained | not obtained | not checked (no image, see below) | unknown |

Every masked write in 1.30 is `mov w4, #0xe0` = `52801c04`, the same value the MikuOS patch uses.

Evidence, 1.30 `cs43198_codec_digital_filter_set` (`0x0FCC`):

```
strcmp(name, "fast_rolloff_low_latency")        -> 0x00
strcmp(name, "fast_rolloff_phase_compensated")  -> 0x40
strcmp(name, "slow_rolloff_low_latency")        -> 0x80
strcmp(name, "slow_rolloff_phase_compensated") -> 0xC0
anything else ("nos")                           -> 0x20
1060: strb w19, user_filter_setting
1064: tbnz user_mqa_source, skip
1074: mov w2, #0x90000 ; 1078: mov w3, w19 ; 107c: mov w4, #0xe0 ; bl cs43198_write_reg_save   (DAC 0)
1090: mov w2, #0x90000 ; 1094: mov w3, w19 ; 1098: mov w4, #0xe0 ; bl cs43198_write_reg_save   (DAC +3)
```

Other 1.30 changes on the same path:

- The second DAC (`cs43198_reg_bal`) is now written whatever the output target is. In 1.20 those writes only ran when the target was 3 (balanced).
- `codec_set_mqa_source("yes")` writes a raw `0x02` to `0x090000` on DAC 0 through `cs43198_write_reg_bypass` (`0x1130`). It writes the second DAC too (`0x1158`) when the target is 3. `0x02` is high-pass on, fast roll-off, low latency, NOS off. Any other value restores `user_filter_setting` with mask 0xE0. In 1.20 this function only set the flag.
- `.rodata` of `cs43198_dlkm.ko` is identical between 1.20 and 1.30.

The plat module is the same in both versions. `plat_set_digital_filter` compares the name against the same five strings, `"nos"` included (`.rodata+0x42a`), and passes it to `cs43198_codec_digital_filter_set`. Its `.text` is byte-identical between 1.20 and 1.30; only the printk format changed.

The stock Settings filter list is the same in both versions (`res/values/arrays.xml`, `digital_filter_value_list_preference`): `fast_rolloff_low_latency`, `fast_rolloff_phase_compensated`, `slow_rolloff_low_latency`, `slow_rolloff_phase_compensated`, `nos`. 1.30 changes the property Settings sets from `vendor.audio.hiby.digital_filter` to `vendor.audio.hiby.hw.digital_filter`, and `init.hiby.audio.rc` triggers on the new name. Both write `/sys/devices/platform/sa_sound_setting/digital_filter`.

### What this means

- NOS did not reach the chip through firmware 1.20. HiBy changed the mask to 0xE0 in 1.30, built 2026-05-09, at every masked write to `0x090000`. On 1.30 stock, NOS should work unless MQA source mode is on.
- 1.40G and 1.41 were not checked, because no image of either has been obtained. HiBy publishes 1.40 only as a Baidu Pan link, which needs a logged-in account, and 1.41 only through the on-device updater. Rechecked 2026-10-10: `iotapi.abupdate.com` now resolves, but to 149.248.211.216, and the reply carries `blocked-by: NextDNS` with an empty body. That is this network's DNS filter, not the update server. The other updater hosts (`piotapi`, `uiotapi.abupdate.com`, `iotapi.adups.com`) get the same answer. The filter was not bypassed, so the update API was not queried.
- The MikuOS patch (`patch_cs43198_nos.py`) changes the mask to 0xE0 at all four masked writes to `0x090000` in the 1.20 module: `0x0B6C` and `0x0B9C` in `cs43198_init_reg_val`, and `0x1118` and `0x1144` in `cs43198_codec_digital_filter_set`. This covers the same sites HiBy changed in 1.30. The two `init_reg_val` sites matter because that function re-applies `user_filter_setting` every time `hiby_target_poweron` (plat module) runs: from probe, `plat_suspend`, `update_dre_function`, `hiby_lch_vol_put` and `hiby_plat_calib_process`. Without them, NOS could drop back to fast roll-off after the next DAC power-up, if that power-up resets the DAC registers. The patch does not copy HiBy's other 1.30 changes: the second DAC is still written only when the output target is 3, and there is no MQA source override.
