# Architecture Directive: Pure Kotlin Target & Zero-Smali Production Policy

## 1. Executive Directive & Final Target State
The long-term target state for the **M500 x Hatsune Miku Software Suite** is **100% Pure Kotlin and Zero Smali in Production**.

All core applications, system utilities, audio routing bridges, Pulsar LED drivers, hardware switches, and UI widgets must ultimately reside in clean, maintainable, idiomatic Kotlin code (utilizing Jetpack Compose, Coroutines, Media3, and standard Android architecture components).

```
   ┌────────────────────────────────────────────────────────┐
   │                  FINAL TARGET STATE                    │
   │               100% Native Kotlin Stack                 │
   │  ┌──────────────────┐  ┌────────────────────────────┐  │
   │  │   Miku Music     │  │   M500 Hardware Settings   │  │
   │  │  (Media3 Player) │  │ (Dual CS43198 / Pulsar HAL)│  │
   │  └──────────────────┘  └────────────────────────────┘  │
   │  ┌──────────────────┐  ┌────────────────────────────┐  │
   │  │  Widgets & Deck  │  │  Platform-Signed Services  │  │
   │  │ (Compose Glance) │  │   (android.uid.system)     │  │
   │  └──────────────────┘  └────────────────────────────┘  │
   │                         ▲                              │
   │                         │  100% Kotlin / NDK JNI       │
   │                         ▼                              │
   │  ┌──────────────────────────────────────────────────┐  │
   │  │  Qualcomm SoC / Dual CS43198 DAC / SGM31324 LED  │  │
   │  └──────────────────────────────────────────────────┘  │
   └────────────────────────────────────────────────────────┘
```

---

## 2. The Smali Prototyping Protocol (Dev-Only Phase)

Smali decompilation and bytecode modification remain valuable **exploratory tools during development only**.

### Permitted Use Cases for Smali:
1. **Reverse-Engineering Vendor Logic**: Inspecting vendor audio routing (`init.hiby.audio.rc`, `services.jar`, `Settings.apk`) to discover hidden system properties, broadcast actions, and IPC protocols.
2. **Rapid Hypothesis Testing**: Patching vendor smali on a live debug unit to confirm hardware register behaviors before investing in a full Kotlin implementation.
3. **Resource Mapping**: Extracting layout IDs, string keys, and internal state machines.

### Transition Requirement:
* Smali patches are **temporary scratch artifacts**.
* As soon as a feature, hardware hook, or system setting is proven via smali, it must be **re-engineered directly in Kotlin** within `miku-player-kotlin` (`com.miku.player` / `com.m500.hardware`).
* Once the Kotlin implementation is validated on the target device, the temporary smali patch is retired and archived.

---

## 3. Implementation Guidelines for Native Kotlin Modules

1. **System & Hardware Privileges**:
   * Modules requiring direct hardware access (e.g., SGM31324 LED sysfs nodes, Cirrus Logic registers, global hardware locks) are configured with `android:sharedUserId="android.uid.system"` and signed with the platform release key (`platform.pk8` / `platform.x509.pem`).
   * This provides full native UID 1000 permissions in pure Kotlin without requiring external `su` root binary wrappers.

2. **Hardware Interfacing**:
   * File I/O for sysfs and kernel nodes is executed through pure Kotlin `FileOutputStream` / NIO streams wrapped in asynchronous IO Coroutines.
   * High-performance signal processing and visualizer rendering (libprojectM 4.2) are linked via standard Kotlin JNI / C++ bindings.

3. **Android Settings & System Integration**:
   * Official system menu expansions (such as the Fn function key options) are extended via clean Runtime Resource Overlays (RRO) compiled alongside the Kotlin codebase.

---

## 4. Lifecycle & Enforcement

| Component | Status | Production Target |
| :--- | :--- | :--- |
| **Miku Music Audio Player** | Active Kotlin Codebase (`com.miku.player`) | 100% Kotlin |
| **M500 Hardware & DAC Settings** | Active Kotlin Codebase (`com.m500.hardware`) | 100% Kotlin |
| **Pulsar RGB Lighting Engine** | Migrated to Kotlin Engine (`PulsarLight.kt`) | 100% Kotlin |
| **Pocket Lock & Fn Key Switch** | Migrated to Kotlin Architecture (`PocketLockManager.kt`) | 100% Kotlin |
| **Vendor Settings Menu Integration** | Declarative RRO (`com.m500.settings.overlay`) | Pure Overlay |
| **HiBy Music Smali Mod** | Deprecated / Archived | Retired |
