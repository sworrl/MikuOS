# MikuOS — Hardware & Software Security Review

**Device:** HiBy M500 (Hatsune Miku Edition) · **OS under review:** MikuOS v0.1.0
**Reviewer:** Falcon Technix · **Date:** 2026-08-20
**Status:** Living document — findings gathered during the MikuOS build-out.

---

## 1. Executive summary

MikuOS is a custom Android distribution for the HiBy M500 digital audio player, with
the Miku Music player as an integral component. This review covers the device
hardware, the OS software stack, and — its main focus — the **security posture**:
code signing, verified boot, SELinux, debug/ADB defaults, and secrets handling.

**Headline security findings (most to least severe):**

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| S1 | Platform & system apps signed with the **public AOSP test keys** — any 3rd-party APK signed with the same world-known key gains full system permissions | Critical | Fix built, pending reimage |
| S2 | **Verified boot disabled** (AVB vbmeta flags `0x03`, bootloader `orange`/unlocked) — no boot-chain integrity | High | Target: re-enable with own AVB key |
| S3 | **Debug-open build.prop** — `ro.secure=0`, `ro.adb.secure=0`, `ro.debuggable=1`, `service.adb.root=1`, adbd forced on TCP:5555 at every init stage | High | Acceptable for dev; must gate for release |
| S4 | Secrets in-tree — private key, VPN config, hardcoded keystore passwords | Medium | Secrets gitignored; passwords pending retirement |
| S5 | SELinux is Enforcing but ships **no custom policy** for MikuOS components; several features silently fail closed | Medium | Target: proper `.te`/`seapp` policy |

**Overall:** the device is currently in a **fully-open development posture** (unlocked,
unverified, debuggable, world-known keys). That is appropriate for iteration but is the
opposite of the stated end goal — a **secure, self-owned distribution**. The remediation
roadmap (§10) sequences the transition without bricking the daily-driver test unit.

---

## 2. Hardware profile

| Component | Detail |
|-----------|--------|
| Model | `M500_MIKU` (HiBy M500, Hatsune Miku Edition) |
| SoC | Qualcomm **SM6225** (Snapdragon 680 4G), platform `bengal` |
| RAM | ~3.7 GB (4 GB) |
| Data storage | ~50 GB `/data` (2% used at review) |
| DAC | Dual **Cirrus Logic CS43198** (see `03_audio_architecture_guide.md`) |
| Amp / codec bus | Awinic `aw883xx` smart amp; Qualcomm `bolero_cdc` codec bus |
| USB-C PD | Awinic `aw35615` |
| Partition scheme | A/B slots (`boot_a/b`, `init_boot_a/b`, `vendor_boot_a/b`); dynamic `super` |

## 3. Software / OS profile

| Item | Detail |
|------|--------|
| Android release | **14** (SDK 34), build `UKQ1.241213.001` |
| Vendor fingerprint | `HiBy/M500_MIKU/M500_MIKU:14/UKQ1.241213.001/eng.HiBy.20260228.173244:user/release-keys` (an **eng** build) |
| Kernel | `5.15.153-android13-8-gca6de2449164-dirty` — Android-13 **GKI**, built 2026-02-04 |
| MikuOS packages | `com.miku.launcher`, `com.miku.player`, `com.miku.settings`, `com.miku.systemui` |
| Root | Magisk v27.0 (patched `init_boot`); rooted and non-rooted flash variants exist |

---

## 4. Security review — code signing (S1)

**The core risk.** The stock HiBy firmware signs `framework-res` and every platform
app with the **public AOSP test keys** (platform cert SHA-256 `c8a2e9bc…`, subject
`CN=Android … android@android.com`, an MD5/2048-bit key from 2008 that is published in
AOSP). Because the platform signature is world-known, **any APK anywhere signed with
that key is granted `signature`/`signatureOrSystem` permissions and can join
`android.uid.system`** on this device.

Current signing of our own apps (verified on-device):

| App | Signer | Key |
|-----|--------|-----|
| `com.miku.launcher`, `com.miku.settings` | `c8a2e9bc…` | **AOSP public test platform key** |
| `com.miku.player`, `com.miku.systemui` | `dfe220d2…` | custom `mikuos-production.jks` (4096-bit — good) |
| device `framework-res` / `com.android.systemui` | `c8a2e9bc…` | AOSP public test platform key |

**Fix (built, validated, not yet applied):** a full custom 1:1 replacement key set was
generated under Falcon Technix ownership.

- Location: `mikuos/signing/` (gitignored). Generator: `generate_mikuos_keys.sh`.
- Keys: 4096-bit RSA / SHA-256, `CN=Justin Earl, O=Falcon Technix, OU=MikuOS <Role>, C=US, emailAddress=certs@falcontechnix.com`, ~30-yr validity. New platform fp `d24e8b0a…`.
- Roles map 1:1 to the five AOSP test keys (platform, releasekey, media, shared, networkstack) — a **bijection**, so every `sharedUserId` group and `framework-res` stay internally consistent.
- Re-sign pipeline: `mikuos/build/resign_system.sh` (dry-run default; `APPLY=1` to apply). Validated dry-run over the real filesystem: **171 APKs re-keyed** (124 platform incl. `framework-res`, 34 releasekey, 5 media, 5 shared, 3 networkstack); **14 real Google/Qualcomm/HiBy keys left untouched.**
- Safe against AOT: re-signing changes the APK signing block / `META-INF`, not `classes.dex`, so `oat/*.odex` remain valid.

**Delivery constraint:** `framework-res` + all platform apps must change key together, so
the re-key ships only in a **full reimage** — a piecemeal push of a re-signed app over a
differently-signed installed one fails with a signature mismatch (→ uninstall → data
loss). Module Gradle signing is therefore deliberately kept on the current keys so
day-to-day `adb install -r` keeps working until the reimage.

## 5. Security review — verified boot / AVB (S2)

Current: `ro.boot.verifiedbootstate=orange`, `ro.boot.flash.locked=0`; the build flashes
**AVB-disabled** `vbmeta` (flags `0x03` = verification + verity off, via
`make_vbmeta_disabled.py`). There is **no boot-chain integrity** — any modified
boot/system image boots without complaint.

Target (**secure boot, stated goal**): re-enable AVB signed with a **Falcon-Technix-owned
AVB key** (separate from the APK platform key), embed the public key in `vbmeta`, and —
only once the image is trusted and stable — lock the bootloader so `verifiedbootstate`
goes `green`. This is feasible precisely because we build the images; it requires
`avbtool` (add key, make `vbmeta` with proper descriptors) rather than the current
disable-shim. **Tension to resolve:** secure boot is incompatible with `ro.secure=0` and
the AVB-disable shim — it belongs to a **release variant**, not the dev variant (§10).

## 6. Security review — SELinux (S3/S5)

SELinux is **Enforcing** (good). But MikuOS ships **no custom policy** — no `.te`,
`file_contexts`, or `seapp_contexts` additions for its own components. Consequences:

- Features that need privileged access fail closed and are swallowed by
  `catch (_: Throwable) {}`, so they look like they work while doing nothing.
- The **FM tuner** is the clearest example (§7).
- The debug-open posture (`ro.secure=0`) partly masks this today; under a locked release
  build these gaps become hard failures.

Target: author a proper MikuOS sepolicy module so components run in correctly-labeled
domains under enforcing SELinux, instead of relying on the open dev posture.

## 7. FM tuner — SELinux package-name gate

The custom FM tuner produces silence **not** because of `/dev/radio0` permissions (init
does `chmod 0777`), but because SELinux domain assignment is **keyed on the package name**:

- `system_ext_seapp_contexts:12` → `name=com.caf.fmradio … domain=vendor_fm_app`
- `system_ext_sepolicy.cil:774` → `allow vendor_fm_app vendor_fm_radio_device (chr_file …)`

So tuner access requires the package name to be literally `com.caf.fmradio` **and**
platform-signed. `com.miku.player` matches no rule → denied → silence behind fake UI.
**Fix:** ship the FM UI as its own `com.caf.fmradio` APK, platform-signed, injected to
`/system_ext/app/FM2/`. No sepolicy rebuild required.

## 8. Ingress / file-sync

Current: `tools/m500-sync.sh` — an rsync pipeline, USB (~45 MB/s via adb port-forward)
or 5 GHz Wi-Fi (~18.5 MB/s via `rsync://…:8730`).

Target (**stated goal**): the **non-rooted** MikuOS variant must also get fast ingress
(CIFS/SMB or equivalent). Open question for design: the fast path must not depend on
`su`. Options to evaluate — an app-hosted rsync/SMB service running as a normal app,
`MANAGE_EXTERNAL_STORAGE` + a user-space server, or a `system_ext` service granted the
needed perms via our sepolicy. To be specified during the ingress work.

## 9. Kernel review

Running kernel is **byte-identical to the stock `boot.img`** on **both** A/B slots — an
out-of-session kernel upgrade **did not stick** (every full/recovery flash reflashes
stock `boot.img` to both slots). This is a **GKI 5.15 android13** setup: the vendor
modules (`bolero_cdc`, `audio_prm`, `adsp_loader`, `aw883xx`, …) are **KMI-locked** to
this kernel, and that module set is the audio/DAC/DSP stack. **Conclusion:**
`5.15.153-android13-8` is the correct and effectively only safe kernel; a wholesale
upgrade would break audio. "Better" is limited to the same GKI branch at a newer sublevel
(if HiBy ships one) or a config-level `boot.img` rebuild. Any custom kernel must ship
**inside the reimage** so a later full-flash cannot silently revert it.

## 10. Remediation roadmap

Two build variants resolve the dev-vs-secure tension:

- **`mikuos-dev`** — current posture (unlocked, AVB-off, `ro.secure=0`, root, adb-open).
  For iteration and piecemeal flashing.
- **`mikuos-secure`** (release / non-rooted) — custom platform key, AVB on with our key,
  SELinux enforcing + custom policy, `ro.secure=1`, adb gated, bootloader lockable.

| Priority | Item | Notes |
|----------|------|-------|
| P0 | Integrate `resign_system.sh` into `build_mikuos_super.sh`; test build; verify `framework-res` signature; flash | Removes AOSP test key (S1). Brick-risk → verify before flash |
| P1 | Author MikuOS sepolicy (domains, `seapp_contexts`, FM tuner) | S5, §7 |
| P1 | Re-key AVB with Falcon Technix key; produce `mikuos-secure` `vbmeta` | S2 |
| P2 | Split dev vs secure build variants; gate `ro.secure`/adb per variant | S3 |
| P2 | Non-root fast ingress (CIFS/SMB/app-service) | §8 |
| P2 | Retire hardcoded keystore passwords from module `build.gradle.kts` | S4 |
| P3 | Delete dead `mikuos/packages/apps/` duplicate tree | build-safety |
| P3 | Ship FM as platform-signed `com.caf.fmradio` | §7 |

## 11. Secrets & PII (S4)

Now gitignored (verified none git-tracked): `*.key`, `*.jks`, `*.pk8`, `*.pem`, `*.p12`,
`keystore.properties`, `mikuos/signing/`. Items still to address:

- `miku_m500_private.key`, `miku_san_split_tunnel.conf` — loose at repo root; move out of tree.
- Hardcoded keystore passwords in module `build.gradle.kts` (and their committed
  `mikuos/packages/apps` copies) — retire on cutover to the new key.
- A repo-wide PII scrub is scheduled (personal contact details, device serials, telemetry/GPS captures).

---

*This document is maintained under `docs/`. Sibling references:
`03_audio_architecture_guide.md`, `05_fn_switch_system_mod_spec.md`,
`MIKUOS_MASTER_ROADMAP.md`.*
