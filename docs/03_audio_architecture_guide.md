# HiBy M500 × Hatsune Miku 4G — Definitive Audio Guide

A working reference for the M500 MIKU's (mostly undocumented) audio settings, what
each one actually does, and how to drive them — plus how our custom-music setup
(formats, bit-perfect playback, the on-device library) fits in.

Compiled 2026-08-14 from **on-device probing** of this exact unit + manufacturer/
reviewer research. Where the menu wording and the internal setting key differ, both
are given. Anything not 100% confirmed on-device is marked *(verify)*.

---

## 1. The hardware

| | |
|---|---|
| DAC | **Dual Cirrus Logic CS43198** (differential/mono-per-channel), PCM up to 768kHz/32-bit, native DSD512 |
| Amp | Four **SGM8261** op-amps |
| Outputs | 3.5mm single-ended (~123 mW) + 4.4mm balanced (~449 mW) |
| SoC | Qualcomm **Bengal/Khaje** class (Snapdragon 4-series), Android 14 |
| Bit-perfect | HiBy **DTA (Direct Transport Audio)** — bypasses Android's resampler so the DAC gets untouched data |

**DTA is why bit-perfect works.** When HiByMusic plays a local file it opens a
`DIRECT` audio output straight to the DAC (we can see it in the audio pipeline as an
`AudioOut_xD, type 1 (DIRECT)` thread clocking the file's real sample rate). Apps
that go through Android's mixer (Spotify, YouTube) are resampled to the mixer's fixed
48kHz/32-bit float and are **not** bit-perfect. `direct_support_app_list` currently
lists only `com.hiby.music`.

---

## 2. Where the settings live (and how to drive them)

Every HiBy audio toggle is stored in the Android **`global`** settings namespace under
the `vendor.audio.hiby.` prefix. Read/verify from a shell (or adb):

```bash
settings list global | grep vendor.audio.hiby
```

**This unit's current values (2026-08-14):**

| Key (`vendor.audio.hiby.…`) | Current value | Menu name |
|---|---|---|
| `digital_filter` | `fast_rolloff_low_latency` | Digital Filter (DAC roll-off) |
| `hw.digital_filter` | `nos` | Oversampling / NOS mode |
| `dre_mode` | `dremode_disable` | DRE (Dynamic Range Enhancement) |
| `high_power` | `hpower_enable` | Output Mode / Gain (High) |
| `hw.bal_po_lo_switch` | `bal_po` | Output routing (balanced phone-out) |
| `hw.balpo_po_a_ab` | `zoom_ab` | Amp bias (Class AB) |
| `hw.iisspdif` | `spdif` | Digital out (I²S/SPDIF) |
| `cpu_tuner` | `performance` | CPU governor for audio |

**Changing them programmatically** — the shell holds `WRITE_SETTINGS`, so this
returns success:

```bash
settings put global vendor.audio.hiby.digital_filter slow_rolloff_low_latency
```

⚠️ *Verify:* a write succeeds and reads back, but whether the audio HAL re-reads the
value **live** vs. only at boot/output-restart isn't yet confirmed on-device (didn't
test audible changes during listening). If a change doesn't "take," toggle it once in
the on-screen menu, or restart playback. Always change from the **menu** when unsure;
the keys above are for scripting/automation once live-apply is confirmed.

> Practical upshot: because these are plain settings keys, a future "audiophile
> preset" button in our widget/app is feasible (one tap → set filter + gain + DRE for
> a given headphone). Pending the live-apply check.

---

## 3. Digital Filter (the DAC roll-off) — 5 options

The CS43198 offers five reconstruction filters. They change the **shape of the
low-pass filter** just below 22kHz — an almost inaudible tweak for most people; it
alters pre/post-ringing and the last sliver of treble, **not** tone or detail
wholesale. Current: `fast_rolloff_low_latency`.

Likely key values *(verify exact strings against the menu)* and what they do:

| Value | Menu wording | Character |
|---|---|---|
| `fast_rolloff_low_latency` | Fast roll-off, minimum phase | Steep cut, no pre-ringing (all ringing after the transient). Tight, immediate. **Good default.** |
| `fast_rolloff_phase_compensated` | Fast roll-off, linear phase | Steep cut, symmetric ringing. The "measures best" textbook filter. |
| `slow_rolloff_low_latency` | Slow roll-off, minimum phase | Gentle cut, minimal ringing, slightly softer/"analog" top end. |
| `slow_rolloff_phase_compensated` | Slow roll-off, linear phase | Gentle cut, symmetric ringing. |
| `nos` *(also `hw.digital_filter`)* | NOS (non-oversampling) | No digital reconstruction filter at all. Most "raw/analog," some rolled-off/soft highs; measures worst, some love it. |

**Recommendation:** leave it on **Fast roll-off / low-latency** (current). If you find
cymbals/sibilance fatiguing, try **Slow roll-off, minimum phase** or **NOS**. This is
a taste knob — there is no "wrong" one, and differences are subtle. `hw.digital_filter`
is a separate hardware NOS toggle; when it's `nos` the hardware runs non-oversampling
regardless — treat the two as one decision.

---

## 4. DRE — Dynamic Range Enhancement — currently OFF

A **CS43198 feature** that squeezes a bit more dynamic range out of the DAC. Trade-off:
- **On:** slightly better measured dynamic range; can sound a touch fuller on
  loud/compressed masters.
- **Off (current):** flatter on paper but often **more natural**, and — importantly on
  this unit — **it's what stopped the stutter on 192kHz/32-bit playback.** DRE's extra
  DSP was choking on the highest-res files.

**Recommendation:** leave **DRE off** (`dremode_disable`). You lose almost nothing and
you keep hi-res playback glitch-free. Only try turning it on for heavily-compressed pop
if you want a hair more body, and turn it back off for hi-res.

---

## 5. Output Mode / Gain — High vs Low — currently HIGH

`high_power = hpower_enable` → **High gain.** Gain sets how much voltage swing is
available; it is **not** volume and **not** quality.

- **Low gain:** for **sensitive IEMs** (most Miku-branded IEMs, anything that gets loud
  at low volume). Lower noise floor, finer volume steps, less hiss.
- **High gain (current):** for **harder-to-drive headphones** (higher impedance /
  low sensitivity) that need more voltage to open up.

**Recommendation for "the Mikus":** if you're on **Miku IEMs**, switch to **Low gain**
— you'll get a blacker background and better low-volume control, and the M500 has
plenty of power for IEMs on low. Keep **High** only for full-size/harder cans.
Use the **balanced 4.4mm** output when your gear supports it (≈449 mW vs ≈123 mW on
3.5mm, and often lower noise).

```bash
# Low gain:
settings put global vendor.audio.hiby.high_power hpower_disable   # (verify value)
```

---

## 6. Output routing & amp bias

- `hw.bal_po_lo_switch = bal_po` — **balanced phone-out**. Options are balanced
  phone-out / single-ended phone-out / **line-out** (LO). Use **line-out** only when
  feeding an external amp or dock (fixed level, bypasses the internal amp/volume).
  For headphones/IEMs leave it on phone-out.
- `hw.balpo_po_a_ab = zoom_ab` — internal amp bias, currently **Class AB**. The M500's
  amp is Class-AB (SGM8261 op-amps); unlike the pricier R5/R6, the M500 isn't marketed
  with a user Class-A switch, so treat this as fixed unless a menu toggle exists. *(verify)*
- `hw.iisspdif = spdif` — digital output format on the data pin (I²S vs SPDIF). Only
  relevant if using a digital/coax out. Leave as-is for headphone listening.

---

## 7. Recommended starting point (this unit / IEM listening)

| Setting | Value | Why |
|---|---|---|
| Digital filter | Fast roll-off, low-latency (or Slow if treble is hot) | Clean default; taste knob |
| DRE | **Off** | Natural + keeps 192/32 glitch-free |
| Gain | **Low** for IEMs / High for headphones | Noise floor + control |
| Output | **Balanced 4.4mm** if supported | More power, lower noise |
| Routing | Phone-out (Line-out only for external amp) | — |
| CPU tuner | performance | Lowest audio latency/jitter |

---

## 8. Custom music — formats & bit-perfect

**What's actually in the library (from our on-device scan of the files themselves):**
a mix of **FLAC 44.1kHz/16-bit** (CD), **FLAC 44.1kHz/24-bit** (hi-res, e.g. the
Anthrax *Among the Living* masters at ~1700 kbps), and **48kHz/24-bit**. Bit depth and
sample rate are read straight from each file's header — the playback pipeline can't
report true bit depth because it hands everything to the DAC as 32-bit **float**.

Guidelines for adding/curating tracks:
- **Prefer FLAC/WAV/ALAC** (lossless). For hi-res, **24-bit** and **88.2/96kHz** (or
  higher) are the real upgrade; 44.1/16 is CD quality.
- Sample **rate** is the honest "is this hi-res" tell (44.1/48 = standard, 96/192 =
  hi-res). Bit **depth** matters less audibly than people think; 24-bit mainly buys
  headroom/noise-floor, not "more detail."
- Play through **HiByMusic** to get **DTA bit-perfect** to the DAC. Other apps get
  resampled to 48kHz.
- In HiByMusic, **MSEB** (tone-tilt "sound tuning") and **PEQ / graphic EQ** are the
  per-taste tone controls — leave them flat for reference, or use MSEB's "Temperature/
  Note thickness" sliders for gentle warmth.
- NIN note: the current Add Violence tracks scan at **48kHz** — the 96kHz/24-bit
  Definitive Edition masters would clock the DAC at 96kHz, so there's a genuine hi-res
  upgrade available for those.

**The on-device library (built by our widget mod):**
- SQLite at `…/com.hiby.widget/files/library.db` (internal) — the widget reads it to
  show the true `96kHz · 24bit` on the now-playing pill.
- Human/other-app readable JSON snapshot at **`/sdcard/MikuLibrary/library.json`**
  (`path,title,artist,album,durationMs,sampleRate,bits,bitrate,channels,mime`).
- Scans MediaStore incrementally (40 tracks/tick) via `MediaMetadataRetriever`
  (`METADATA_KEY_SAMPLERATE` / `METADATA_KEY_BITS_PER_SAMPLE`), resumable, ~3969 tracks.

---

## 9. adb cheat-sheet

```bash
# Read all HiBy audio settings
adb shell settings list global | grep vendor.audio.hiby

# Change one (menu is safer until live-apply is confirmed)
adb shell settings put global vendor.audio.hiby.<key> <value>

# Dump the music library formats
adb shell cat /sdcard/MikuLibrary/library.json | python3 -m json.tool
```

---

## Sources
- [HiBy Digital M500 × Hatsune Miku 4G Review — Headfonics](https://headfonics.com/hiby-digital-m500-x-hatsune-miku-4g-review/) (DAC, gain, op-amps, output power)
- [HiBy M500 Hatsune Miku Edition Review — Headfonia](https://www.headfonia.com/hiby-m500-hatsune-miku-edition-review/3/)
- [HiBy Digital M500 DAP Review — Androidbrick](https://androidbrick.com/hiby-digital-m500-dap-review/) (dual CS43198, 5 filters, DTA)
- [Understanding the Seven DAC Digital Filter Types — WiiM FAQ](https://faq.wiimhome.com/en/support/solutions/articles/72000635240)
- [Digital Filters – In general — Ferrum](https://ferrum.audio/digital-filters-in-general/)
- [How to pick the best filter setting for your DAC — Addicted To Audio](https://addictedtoaudio.com.au/blogs/how-to/how-to-pick-the-best-filter-setting-for-your-dac)
- [HiBy R5 (Gen 2): A Class-A Act — HiBy](https://store.hiby.com/blogs/press/hiby-r5-a-class) (Class A vs AB)
- Prism Sound glossary — *Dynamic Range Enhancement*
- On-device probe of this unit: `settings list global`, `dumpsys media.audio_flinger`, `getprop`
