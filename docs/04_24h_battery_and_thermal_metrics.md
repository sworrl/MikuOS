# HiBy M500 × Hatsune Miku 4G — First 24 Hours Metrics Report

**Window:** device active since **2026‑08‑13 14:14** (first app setup) → pulled **2026‑08‑14 14:33 MDT** (~24 h).
All figures pulled read‑only from the device (`dumpsys`, `/sys`, `/proc`, MediaStore) over the FT‑BENCH network. Where a counter resets on charge, its window is noted.

---

## 1. Hardware & platform
| | |
|---|---|
| Model | `M500_MIKU_4G` (HiBy) |
| OS | Android **14** (SDK 34), build `eng.HiBy.20260615` |
| SoC | Qualcomm **Bengal** (Snapdragon 4‑class), **6 cores @ 1.9 GHz**, governor `performance` |
| RAM | **3.6 GB** (3,745 MB total; 2.1 GB available) |
| Storage | **50 GB** data partition — **11 GB used / 39 GB free (23%)** |
| Display | **720×1280**, 320 dpi (override 270) — ~small DAP panel |
| DAC / audio | Dual **Cirrus Logic CS43198**, DTA bit‑perfect (see audio guide) |
| Cellular | 4G/LTE with active SIM (Google Fi / Tycho) |

## 2. Battery & thermals
| | |
|---|---|
| Battery capacity | **3,100 mAh** (nominal) |
| Level at pull | **53%**, health **Good**, 3.886 V, **30.0 °C**, Li‑ion, discharging |
| Drain this charge cycle (~4.6 h since 09:58) | **1,287 mAh** — screen 362, mobile‑radio 71, cpu 30, wifi 22, bluetooth 10.5 |
| Thermals | Cool throughout: CPU ~40 °C, GPU 39 °C, display 40 °C, battery 30 °C |
| Uptime at pull | 6 h 41 m (≥1 reboot in the 24 h) |

## 3. Usage — app time & sessions (24 h)
`FS` = media/foreground‑service time (playing or paused‑with‑notification); `visible` = on‑screen.

| App | FS (playing) | On‑screen | Launches |
|---|---|---|---|
| **Spotify** | **9 h 17 m** | 44 m | 56 |
| **HiByMusic** | **4 h 18 m** | 54 m | 32 |
| FM Radio (`com.caf.fmradio`) | **57 m** | 2 m | 5 |
| Launcher (home) | — | 4 h 19 m | 166 |
| Settings | — | 1 h 09 m | 108 |
| HiBy Update | — | 58 m | 18 |
| Play Store | 9 m | 13 m | 50 |
| Google Fi (Tycho) | 11 m | 4 m | 5 |

**Total audio‑app playback‑service ≈ 14 h 32 m** (Spotify + HiByMusic + FM) across **93 app launches**.
Actual **DAC audio‑active** time this charge cycle only: Spotify 58 m 52 s, HiByMusic 2 h 09 m (batterystats resets per charge, so 24 h total isn't retained).

## 4. Spotify streaming deep‑dive
| Metric | Value |
|---|---|
| **Downloaded (24 h)** | **6,415 MB (6.4 GB)** · uploaded 68.5 MB |
| Average bitrate over 9 h 17 m | **≈ 1,536 kbps** (≈1,300 kbps audio) |
| **Tier (inferred)** | **LOSSLESS (FLAC 16‑bit/44.1kHz)** — 4.8× a 320 kbps lossy day |
| By network | FT‑BENCH 4,647 MB (72%) · HawtDawg WiFi 1,743 MB (27%) · LTE 24.7 MB (<1%) |

> Spotify Lossless caps at 16/44.1 — so despite any on‑screen hint, it is **not** 96/32; that resolution only comes from local HiByMusic FLAC.

## 5. Device‑wide data consumers (24 h, ~18 GB total download)
| UID / app | Downloaded | Note |
|---|---|---|
| Spotify | 6,415 MB | lossless streaming |
| system (uid 1000) | 5,965 MB | OTA/FOTA + GMS + media scan |
| **shell/adb (uid 2000)** | 3,938 MB | **our tooling** — dozens of widget installs/pulls over WiFi/USB |
| uid 10046 | 749 MB | |
| uid 10162 | 470 MB | |
| HiByMusic | 63.8 MB | local playback — artwork/metadata only |

## 6. Music library composition (on‑device scan)
Analyzed **2,720 of 3,978 tracks (68%)** — **100% FLAC**:
- **Hi‑res: 48%** (1,293 tracks > CD quality)
- 44.1/16 CD ×1,384 · 48/24 ×486 · 44.1/24 ×479 · **96/24 ×226** · **192/24 ×94** · 48/16 ×43 · **176.4/24 ×8**
- Analyzed runtime **200.9 h** → full library ≈ **294 hours (~12 days) of music**

## 7. Connectivity & Bluetooth
- WiFi: `🔬🧪 FT‑BENCH 📡`, IP `10.7.7.3/28` (bench, adb‑over‑wifi live)
- LTE SIM active (barely used for data: 24.7 MB)
- Bluetooth: paired **"Miku San"**, max 5 audio devices; ~37 m BT active this cycle

## 8. Read of the first 24 hours
A heavy shakedown day: ~14.5 h of audio‑app playback with Spotify (lossless) carrying ~2/3 and local HiByMusic ~1/3, plus an hour of FM radio. 166 launcher hits and 108 Settings launches = lots of exploring/configuring (the audio‑settings dig). Ran cool (~40 °C) on the performance governor. The library is a serious all‑FLAC collection (~294 h, 48% hi‑res). Note ~10 GB of the 18 GB device download is system + our adb tooling, not user streaming.

*Pulled by the mod/bench toolchain; batterystats‑windowed figures reset on charge.*
