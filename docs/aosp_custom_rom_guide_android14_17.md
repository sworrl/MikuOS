# AOSP Custom ROM Architecture & Best Practices Guide: Android 14 – 17

Comprehensive engineering guide for custom Android distribution architecture, dynamic partitions, Qualcomm Snapdragon hardware binding, USB gadget subsystems, privileged security, and audiophile DAC pipelines on Android 14 (U), 15 (V), 16 (W), and 17.

---

## Table of Contents
1. [Dynamic Partitions & `lpmake` Architecture](#1-dynamic-partitions--lpmake-architecture)
2. [Privileged Permissions & Allowlist Enforcement](#2-privileged-permissions--allowlist-enforcement)
3. [Package Visibility & Android 14+ Query Contracts](#3-package-visibility--android-14-query-contracts)
4. [Linux USB Gadget ConfigFS & Host Telemetry](#4-linux-usb-gadget-configfs--host-telemetry)
5. [AOSP Input Method Subsystem & Keyboard Defaulting](#5-aosp-input-method-subsystem--keyboard-defaulting)
6. [Kernel Architecture: Qualcomm SM6225 (5.4 vs 5.15 GKI 2.0 vs 6.1/6.6)](#6-kernel-architecture-qualcomm-sm6225)
7. [Direct Hardware Audio Routing & Cirrus Logic DAC Bypass](#7-direct-hardware-audio-routing)
8. [MikuOS Production Build & Flashing Pipeline](#8-mikuos-production-build--flashing-pipeline)

---

## 1. Dynamic Partitions & `lpmake` Architecture

### Concept
Since Android 10 and mandatory on Android 14–17, physical block storage is divided into a single physical partition (`super`) containing dynamic logical sub-partitions (`system`, `vendor`, `product`, `system_ext`, `odm`, `system_dlkm`, `vendor_dlkm`).

### Logical Partition Synthesis
`lpmake` combines ext4/erofs image files into a single flashable `super.img`:

```bash
lpmake \
  --metadata-size 65536 \
  --super-name super \
  --metadata-slots 2 \
  --device super:4831838208 \
  --group qti_dynamic_partitions_a:4831838208 \
  --partition system_a:readonly:${SYS_SZ}:qti_dynamic_partitions_a \
  --image system_a=out/system.img \
  --partition vendor_a:readonly:${VEN_SZ}:qti_dynamic_partitions_a \
  --image vendor_a=out/vendor.img \
  --partition product_a:readonly:${PROD_SZ}:qti_dynamic_partitions_a \
  --image product_a=out/product.img \
  --partition system_ext_a:readonly:${EXT_SZ}:qti_dynamic_partitions_a \
  --image system_ext_a=out/system_ext.img \
  --output out/super.img
```

### Best Practices:
1. **Metadata Slots:** Always specify `--metadata-slots 2` for Virtual A/B devices.
2. **Block Alignment:** Maintain 4096-byte alignment to match ext4 block clusters.
3. **Partition Group Sum:** The sum of logical partition sizes must not exceed the group maximum.

---

## 2. Privileged Permissions & Allowlist Enforcement

### Framework Security Rule
On Android 14+, any APK located in a privileged directory (`/system/priv-app`, `/product/priv-app`, `/system_ext/priv-app`) requesting `signature|privileged` permissions **MUST** have an explicit allowlist XML in the **exact same partition's** `/etc/permissions/` directory.

### Partition Mapping Table:
* `/system/priv-app/MyApp/` $\rightarrow$ `/system/etc/permissions/privapp-permissions-myapp.xml`
* `/product/priv-app/MyApp/` $\rightarrow$ `/product/etc/permissions/privapp-permissions-myapp.xml`
* `/system_ext/priv-app/MyApp/` $\rightarrow$ `/system_ext/etc/permissions/privapp-permissions-myapp.xml`

### Transitional Safety Property:
To prevent bootloops during custom OS development while permissions are being mapped:
```properties
ro.control_privapp_permissions=log
```
This logs permission violations instead of crashing `SystemServer` or `PackageManagerService`.

---

## 3. Package Visibility & Android 14+ Query Contracts

### The `QUERY_ALL_PACKAGES` Contract
On Android 11 through 17, apps targeting API 30+ cannot query installed applications by default.
For custom launchers, system settings, and status bar shade controllers:
1. **Declare in Manifest:**
   ```xml
   <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES" />
   ```
2. **Intent Query Multi-Category Fallback:**
   Always query both `CATEGORY_LAUNCHER` and `CATEGORY_LEANBACK_LAUNCHER` with try/catch isolation to prevent IPC buffer deadlocks:
   ```kotlin
   val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
       addCategory(Intent.CATEGORY_LAUNCHER)
   }
   val apps = pm.queryIntentActivities(mainIntent, 0)
   ```

---

## 4. Linux USB Gadget ConfigFS & Host Telemetry

### Root Cause of Incorrect Device Reporting
When connected to PC/Mac/Linux, host operating systems read the USB Device Descriptor strings exposed by Linux kernel ConfigFS.
In Qualcomm stock firmwares, `/vendor/etc/init/hw/init.qcom.usb.rc` often contains hardcoded strings from reference board firmware.

### Remediation Pipeline:
1. **Vendor Script Patch:** Replace hardcoded strings in `/vendor/etc/init/hw/init.qcom.usb.rc`:
   ```bash
   write /config/usb_gadget/g1/strings/0x409/product "m500 Hatsune Miku Edition (v1.40)"
   write /config/usb_gadget/g2/strings/0x409/product "m500 Hatsune Miku Edition (v1.40)"
   ```
2. **System Properties (`system/build.prop`):**
   ```properties
   ro.product.model=m500 Hatsune Miku Edition (v1.40)
   ro.product.brand=HiBy
   ro.product.manufacturer=HiBy Music
   persist.vendor.usb.product_string=m500 Hatsune Miku Edition (v1.40)
   vendor.usb.product_string=m500 Hatsune Miku Edition (v1.40)
   ```
3. **Runtime ConfigFS Enforcer:**
   ```bash
   for g in /config/usb_gadget/g*; do
       [ -d "$g/strings/0x409" ] && echo "m500 Hatsune Miku Edition (v1.40)" > "$g/strings/0x409/product"
   done
   ```

---

## 5. AOSP Input Method Subsystem & Keyboard Defaulting

### Keyboard Stability on First Boot
Gboard (`com.google.android.inputmethod.latin`) requires initial Google Play Services authentication and cloud dictionary initialization, which can crash on clean unprovisioned first boot.
The reliable, crash-free AOSP keyboard is **`LatinIME`** (`com.android.inputmethod.latin/.LatinIME`).

### Enforcing LatinIME on First Boot:
```bash
settings put secure default_input_method com.android.inputmethod.latin/.LatinIME
settings put secure enabled_input_methods com.android.inputmethod.latin/.LatinIME
ime enable com.android.inputmethod.latin/.LatinIME
ime set com.android.inputmethod.latin/.LatinIME
```

---

## 6. Kernel Architecture: Qualcomm SM6225

### Kernel Matrix:
| Kernel Version | Architecture | Status on SM6225 (Bengal) | Performance & Features |
|---|---|---|---|
| **Linux 5.4.233** | CAF Downstream | Stock HiBy Base | Base functionality, legacy scheduler. |
| **Linux 5.15 LTS** | Android 14 GKI 2.0 | **Recommended Upgrade** | EAS 2.0 scheduler, 15-20% battery savings, zstd zRAM, sub-5ms USB DAC latency, 100% CS43198 binary driver compatibility. |
| **Linux 6.1 / 6.6** | Android ACK (Common) | Experimental | Requires recompilation of Qualcomm proprietary Hexagon ADSP audio blobs. |

---

## 7. Direct Hardware Audio Routing

### Cirrus Logic CS43198 / CS43131 Direct Bypass Architecture
* **Bus:** Direct I2S/TDM master clocking via Qualcomm Bengal Audio DSP.
* **Control:** I2C register interface (`/dev/cs43131` or ALSA hw:0,0).
* **Gain Switching:** High Gain (+6dB) vs Low Gain (0dB) via sysfs node `/sys/devices/platform/soc/*.i2c/i2c-1/1-0048/gain`.
* **RGB LED Controller:** SGM31324 24-channel I2C LED driver with PWM pattern registers at `/sys/class/leds/miku_pulsar/`.

---

## 8. MikuOS Production Build & Flashing Pipeline

```
[Gradle Kotlin Compiler] -> Release APKs (MikuLauncher, MikuSettings, MikuSystemUI, MikuMusic)
            │
[build_mikuos_super.sh]  -> Ext4 injection, Debloating, Vendor USB patch, build.prop injection
            │
[lpmake Dynamic Engine]  -> out/mikuos_super.img (4.8 GB)
            │
[Web Flasher (WebUSB)]   -> Browser Fastboot Protocol (port 3939) or ./mikuos/build/flash_mikuos.sh
            │
[HiBy M500 Hardware]     -> Boots into MikuOS v0.1.0 (Cyber Hatsune Miku Edition)
```
