# MikuOS — Operating System Architecture & Core Subsystem Specification

**Device Target**: HiBy M500 Hatsune Miku Edition (`SM6225` / Qualcomm Snapdragon 680)  
**Base Platform**: Android 14 (AOSP / GKI Linux 5.15)  
**System Identity**: `MikuOS v0.1.0` (Platform Signed, Native Kotlin & Compose Architecture)

---

## 1. Core Operating System Architecture

MikuOS replaces stock vendor and AOSP system software with a native, pure Kotlin/Compose operating system suite built directly into the read-only dynamic partition (`super.img`):

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                   MIKUOS SYSTEM ARCHITECTURE                          │
├────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                        │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │                              MIKUOS CORE SYSTEM APKS                             │  │
│  ├─────────────────────────┬──────────────────────────┬─────────────────────────────┤  │
│  │   MikuSettings          │   MikuSystemUI           │   MikuLauncher              │  │
│  │   (com.android.settings)│   (com.android.systemui) │   (com.android.launcher3)   │  │
│  │   /system_ext/priv-app/ │   /system_ext/priv-app/  │   /system/priv-app/         │  │
│  ├─────────────────────────┴──────────────────────────┴─────────────────────────────┤  │
│  │   MikuMusic Audiophile Subsystem                                                 │  │
│  │   (com.miku.player) [v0.9.223+] /system/priv-app/MikuMusic                       │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
│                                           │                                            │
│                                           ▼                                            │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │                           AOSP SYSTEM FRAMEWORK & IPC                            │  │
│  │  • SettingsSearchIndexablesProvider  • SettingsSliceProvider  • BatteryUsageProvider│  │
│  │  • AudioFlinger Direct ALSA Routing  • InputManagerService (Physical Fn Switch)  │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
│                                           │                                            │
│                                           ▼                                            │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │                       QUALCOMM & CIRRUS HARDWARE ABSTRACTION                     │  │
│  │  • Cirrus Logic CS43198 MasterHIFI DAC (Low/High Gain, NOS, Fast/Slow Roll-Off) │  │
│  │  • SGM31324 Pulsar RGB LED Driver (BPM Breathing, Color Waveforms, PWM Matrix)  │  │
│  │  • ALSA Hardware Bypass (Direct 32-bit/768kHz PCM & Native DSD256 Pipeline)      │  │
│  └──────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                        │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Partition Layout & Placement Map

| Core Component | Package Namespace | Partition Path | UID / Privileges |
|---|---|---|---|
| **MikuSettings** | `com.android.settings` | `/system_ext/priv-app/Settings/Settings.apk` | `android.uid.system` (Platform Signed) |
| **MikuSystemUI** | `com.android.systemui` | `/system_ext/priv-app/SystemUI/SystemUI.apk` | `android.uid.system` (Platform Signed) |
| **MikuLauncher** | `com.miku.launcher` | `/system/priv-app/MikuLauncher/MikuLauncher.apk` | `android.uid.system` (Default Home) |
| **MikuMusic** | `com.miku.player` | `/system/priv-app/MikuMusic/MikuMusic.apk` | Privileged Audio Carrier |
| **Permissions** | `privapp-permissions-mikuos.xml` | `/system_ext/etc/permissions/` | Whitelisted Privileged Permissions |

---

## 3. Directory Layout in Repository

```text
/home/reaver/Documents/GitHub/m500/mikuos/
├── README.md                          # Master architecture guide
├── build/                             # ROM tools & repack engine
│   ├── repack_super.sh                # lpmake dynamic super.img builder
│   ├── keys/                          # Platform signing certificates
│   └── permissions/                   # privapp-permissions-mikuos.xml
└── packages/
    └── apps/
        ├── MikuSettings/              # com.android.settings (AOSP Provider Stubs + Hardware UI)
        ├── MikuSystemUI/              # com.android.systemui (Cyber Shade & Status HUD)
        ├── MikuLauncher/              # com.miku.launcher (Cyber Desktop & Dock)
        └── MikuMusic/                 # com.miku.player (Hi-Res Audiophile Player)
```
