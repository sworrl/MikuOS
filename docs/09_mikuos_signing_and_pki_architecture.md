# MikuOS Signing & PKI Architecture Reference

**Author**: Falcon Technix / MikuOS Core Engineering  
**Scope**: HiBy M500 High-Resolution Digital Audio Player (`M500_MIKU_4G`)  
**Security Domain**: AOSP Custom ROM, System Application Signing, Verified Boot (AVB 2.0)

---

## 1. Executive Summary & Problem Statement

Stock HiBy M500 firmware was authored against standard Android Open Source Project (AOSP) public test keys. This presents two primary architectural and security challenges:
1. **Security Exposure**: Any third-party APK signed with public AOSP test keys (`CN=Android, emailAddress=android@android.com`) automatically inherits system permissions (`WRITE_SECURE_SETTINGS`, `STATUS_BAR_SERVICE`, `MODIFY_AUDIO_ROUTING`) and can join `android.uid.system`.
2. **Fragmentation & Development Friction**: Different apps and modules previously targeted ad-hoc keystores (`platform.jks`, `mikuos-production.jks`), causing signature mismatch failures (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`) when sideloading development builds over the running OS.

This document details the unified signing architecture implemented across all APKs, system partitions, and boot containers.

---

## 2. Key Hierarchy & Cryptographic Roots

All keys reside in `mikuos/signing/` (gitignored, mode 0600) and are generated via `mikuos/signing/generate_mikuos_keys.sh`.

### Key Specifications:
- **Algorithm**: RSA 4096-bit
- **Digest Algorithm**: SHA-256
- **Validity Period**: ~30 years (10,958 days)
- **Subject**: `C=US, O=Falcon Technix, CN=Justin Earl, emailAddress=certs@falcontechnix.com`

### Role Mapping (1:1 Bijective AOSP Replacement):

| Role | Target System Components | Formats |
| :--- | :--- | :--- |
| **`platform`** | `framework-res.apk`, `SystemUI.apk`, `Settings.apk`, `Launcher3.apk`, `MikuMusic.apk`, `M500HardwareSettings.apk`, System Overlays | `.pk8`, `.x509.pem`, `.key`, `mikuos-platform.jks` |
| **`releasekey`**| User-facing system apps (e.g. `Gallery2`, `ExactCalculator`), OTA updates, recovery packages | `.pk8`, `.x509.pem`, `.key`, `mikuos-releasekey.jks` |
| **`media`** | `MediaProvider`, `DownloadProvider`, `MtpService`, `SoundPicker` | `.pk8`, `.x509.pem`, `.key`, `mikuos-media.jks` |
| **`shared`** | `ContactsProvider`, `UserDictionaryProvider`, `BlockedNumberProvider`, `LatinIME` (`android.uid.shared`) | `.pk8`, `.x509.pem`, `.key`, `mikuos-shared.jks` |
| **`networkstack`** | `NetworkStack.apk`, `CaptivePortalLogin.apk` (`com.android.networkstack`) | `.pk8`, `.x509.pem`, `.key`, `mikuos-networkstack.jks` |
| **`avb`** | Android Verified Boot 2.0 container (`vbmeta.img`, `vbmeta_system.img`) and dm-verity hashtrees | `.key`, `.pem`, `avb_custom_key.bin` |

---

## 3. Unified APK Signing in Gradle (`miku-player-kotlin`)

All modules in `miku-player-kotlin` (`app`, `mikuos-launcher`, `mikuos-settings`, `mikuos-systemui`, `hardware-settings`) utilize dynamic keystore resolution without hardcoded passwords:

```kotlin
// Automatically resolves ../keystore.properties, keystore.properties, or local.properties
val signingProps = Properties().apply {
    val candidates = listOf(
        rootProject.file("../keystore.properties"),
        rootProject.file("keystore.properties"),
        rootProject.file("local.properties")
    )
    for (f in candidates) {
        if (f.exists()) {
            f.inputStream().use { load(it) }
            break
        }
    }
}
val platformStorePath: String? = signingProps.getProperty("platform.storeFile")
val platformStoreFile = platformStorePath?.let { path: String ->
    listOf(rootProject.file("../$path"), rootProject.file(path), file(path)).firstOrNull { it.exists() }
}
val platformStorePass: String? = signingProps.getProperty("platform.storePassword")
val platformKeyAlias: String = signingProps.getProperty("platform.keyAlias", "platform")
val platformKeyPass: String? = signingProps.getProperty("platform.keyPassword")
val hasPlatformSigning = platformStoreFile != null && platformStorePass != null && platformKeyPass != null

signingConfigs {
    if (hasPlatformSigning) {
        create("platform") {
            storeFile = platformStoreFile
            storePassword = platformStorePass
            keyAlias = platformKeyAlias
            keyPassword = platformKeyPass
            enableV1Signing = false // Preserves 4096-byte mmap alignment for native .so
            enableV2Signing = true
            enableV3Signing = true
            enableV4Signing = true
        }
    }
}
```

### Key Properties:
- **Zero Hardcoded Secrets**: Passwords are read exclusively from gitignored `keystore.properties`.
- **Contributor Graceful Fallback**: If keystore files are not present, debug builds automatically fall back to standard Android debug keystores rather than halting the build.
- **Sideload Compatibility**: APKs compiled via `./gradlew assembleDebug` or `./gradlew assembleRelease` match the running OS platform key, allowing seamless `adb install -r`.

---

## 4. Standalone APK Signing CLI Tool (`tools/sign_apk.sh`)

For ad-hoc APKs, vendor APKs, or custom system overlays, `tools/sign_apk.sh` provides automated alignment and signing:

```sh
# Sign with default platform key
./tools/sign_apk.sh my_custom_app.apk

# Sign with specific role
./tools/sign_apk.sh --role media DownloadProvider.apk

# Sign and write to custom output
./tools/sign_apk.sh --platform -o signed/MikuLauncher.apk unsigned/MikuLauncher.apk

# Verify signature
./tools/sign_apk.sh --verify-only signed/MikuLauncher.apk
```

### Safety Features:
- **Zip Alignment**: Performs 4-byte boundary and 4096-byte page alignment for uncompressed `.so` libraries (`zipalign -p 4`).
- **SELinux Xattr Preservation**: Retains `security.selinux` extended attributes when signing existing rootfs APKs.
- **V1 Exclusion**: Omits v1 JAR signing on system apps to prevent zip entry shift that disrupts `extractNativeLibs=false` mmap execution.

---

## 5. OS Rootfs Partition Re-signing (`mikuos/build/resign_system.sh`)

When building `mikuos_super.img`, partition images (`system.img`, `system_ext.img`, `product.img`, `vendor.img`) are mounted and processed:

1. **Fingerprint Scan**: `resign_system.sh` inspects every APK's SHA-256 cert fingerprint.
2. **Bijective Replacement**: Maps AOSP test keys to the corresponding Falcon Technix key.
3. **In-place Re-sign**: Uses `apksigner` with `--v1-signing-enabled false --v2-signing-enabled true --v3-signing-enabled true`.
4. **SELinux Context Restoration**: Preserves POSIX file modes and `security.selinux` labels.
5. **SELinux MAC Policy Patching (`patch_mac_permissions.sh`)**: Updates `plat_mac_permissions.xml` and `vendor_mac_permissions.xml` by replacing old cert DER hex with our new cert DER hex. This ensures `system_server` assigns `seinfo="platform"` and the `platform_app` SELinux domain correctly.

---

## 6. Android Verified Boot (AVB 2.0) & vbmeta (`mikuos/signing/sign_avb.sh`)

MikuOS supports dual AVB configurations:

### A. Development Mode (`./mikuos/signing/sign_avb.sh dev`)
- Generates `vbmeta_disabled.img` and `vbmeta_system_disabled.img` with flags `0x03` (`HASHTREE_DISABLED | VERIFICATION_DISABLED`).
- Permissive for rooting (Magisk / KernelSU), experimental kernels, and fastboot live modifications on unlocked bootloaders (`ro.boot.verifiedbootstate=orange`).

### B. Production Release Mode (`./mikuos/signing/sign_avb.sh release`)
- Uses `tools/avbtool.py` and `mikuos/signing/avb.key` (RSA-4096).
- Builds `vbmeta_system_signed.img` containing dm-verity hashtrees for `system`, `system_ext`, and `product`.
- Builds top-level `vbmeta_signed.img` containing hash descriptors for `boot`, `init_boot`, `vendor_boot`, `dtbo`, and hashtrees for `vendor`, `odm`, `dlkm`.
- Generates `avb_custom_key.bin` via `extract_public_key` for flashing to bootloader custom root-of-trust partitions (`fastboot flash avb_custom_key avb_custom_key.bin`).

---

## 7. Verification & Diagnostic Tool (`tools/verify_signatures.sh`)

To audit the signature state of all components at any time, run:

```sh
./tools/verify_signatures.sh
```

This verifies:
- All 6 private/public key pairs in `mikuos/signing/`.
- All compiled release APKs across `miku-player-kotlin`.
- Custom overlay APKs.
- `vbmeta` flags and algorithm integrity.
