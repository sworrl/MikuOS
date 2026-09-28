# Full source OS and signing: where we are, what is left, what it costs

Status as of 2026-09-28. This document exists because the distinction it describes was lost once
already, and the difference matters for whether MikuOS can ever be distributed as a finished image.

---

## 1. What we have today, stated plainly

MikuOS is **not** built from source. `mikuos/build/build_mikuos_super.sh` reads HiBy's stock
partitions out of `m500-system-archive/firmware/extracted_1.00`, re-signs them to your platform key,
injects our applications and configs, and repacks the super image.

The re-key is real work. It replaces the public AOSP test keys, which every Android developer
already holds, with a key set only you have, across the framework, the system apps and the APEX
modules. That is the entire security model and it is worth having.

It is also not the same thing as building the OS. Re-signing changes the signature on someone
else's binary. The binary is still theirs, which is why we cannot host a finished image.

## 2. What already exists toward a source build

More than you would expect, which is the encouraging part.

| Thing | State |
|---|---|
| AOSP 14 tree | Synced at `/mnt/aosp-src` |
| Device tree | `device/hiby/m500` exists: `AndroidProducts.mk`, `aosp_m500.mk`, `BoardConfig.mk`, `device.mk`, `permissions/`, `prebuilts/` |
| Lunch target | `aosp_m500` is defined |
| The known blocker | Addressed. `device.mk` explicitly re-adds `hwservicemanager` and the six HIDL services the vendor's `compatibility_matrix.xml` marks `optional="false"` and that Android 14 dropped |
| Output | **None.** `out/target/product/` is empty. This tree has never produced an image |

That last row is the whole gap. The setup was done and the build was never run, because the machine
could not run it.

## 3. What a build machine needs

Google's own guidance for an AOSP 14 build, plus what this tree specifically will want.

| Part | Minimum | Comfortable | Why |
|---|---|---|---|
| RAM | 64 GB | 128 GB | AOSP's documented floor is 64 GB. Soong and the Java steps are what eat it. The current machine has 15 GB and gets its Gradle daemon OOM-killed building a single APK |
| CPU | 16 cores | 32 threads | Build time scales almost linearly. A 7950X class part is the sweet spot for cost per core |
| Disk | 1 TB NVMe | 2 TB NVMe | The tree is around 250 GB, `out/` is 100 to 150 GB per target, and ccache wants 50 to 100 GB. Spinning rust roughly doubles build time |
| OS | Ubuntu LTS | Ubuntu LTS | AOSP is tested there. Other distros work and cost you a day of toolchain archaeology |
| Swap | 32 GB | 32 GB | Covers the link steps that spike |

Expect two to six hours for a first clean build on that hardware, and five to thirty minutes for
incrementals once ccache is warm.

## 4. The plan

Phases, in dependency order. The timings assume evenings and weekends, not full time, and the wide
ranges on phases 3 and 4 are honest rather than padded.

### Phase 0: the machine
Blocked on hardware. Nothing else can start.

### Phase 1: make `aosp_m500` compile
Get `lunch aosp_m500-userdebug && m` to produce images. This is mostly grinding through missing
makefile variables and BoardConfig mismatches. Failures are loud and specific.

**Estimate: 1 to 2 weekends.** Low risk. A build that will not compile always tells you why.

### Phase 2: make it boot
Flash the built `system`, `system_ext` and `product` over the stock `vendor` and see how far it
gets. The HIDL shim list in `device.mk` is the groundwork for exactly this, but groundwork is not
proof.

This is where a GSI already failed once. A device build has a much better chance because we control
the framework side, but expect `vendor` to demand something the built framework does not provide,
and expect to read a lot of `vintf` output.

**Estimate: 2 to 6 weeks.** Medium to high risk. This is the phase that could stall.

### Phase 3: make it sound right
The M500's entire value is the vendor audio stack: HIDL `audio@7.0`, the dual CS43198 path, and
HiBy's DIRECT output. Getting AOSP 14 to talk to a vendor HAL written for HiBy's framework is the
real engineering, and "it boots" is a long way from "it is bit perfect".

**Estimate: 2 to 8 weeks.** Highest risk in the project. A plausible bad outcome is that it boots,
plays audio, and sounds worse than what we ship today.

### Phase 4: reimplement what HiBy gave us for free
Several MikuOS features currently ride on **HiBy's** framework modifications, not AOSP's. Those
disappear in a source build and have to be rebuilt against the HAL directly:

- `Settings.Global button_lock`, which is what makes the root-free Fn pocket lock work
- The `vendor.audio.hiby.*` property surface for filter, DRE, gain and high power
- The per-jack volume raise-lock behavior the volume wheel works around
- HiBy's voice prompt and LED hooks

**Estimate: 3 to 6 weeks.** Medium risk, well understood, just work.

### Phase 5: signing, which is the easy part
Set `PRODUCT_DEFAULT_DEV_CERTIFICATE` to the Falcon key set and the whole build comes out signed by
you, with no re-key pass at all. Then AVB with your own keys so verified boot chains to your
certificate instead of being disabled.

**Estimate: 1 weekend.** Low risk. This is a solved problem in AOSP and it is strictly simpler than
the re-key pipeline we run today.

### Phase 6: a hostable release
Publish `boot`, `system`, `system_ext` and `product`, all built from Apache-2.0 source plus our own
GPL-3.0 applications. The user keeps their own `vendor`, `vendor_boot`, `dtbo` and `odm`, which we
never modify and therefore never distribute.

That split is the GrapheneOS model and it is what makes their images hostable.

**Estimate: 1 weekend** once phases 1 to 5 land.

## 5. Total, and the honest version

Roughly **three to five months** of evenings if phases 2 and 3 go well, and open-ended if they do
not. Phase 3 is the one that decides the project.

There is a real outcome where the answer is "AOSP boots on the M500 but the audio is worse, so we
keep shipping the re-keyed stock image". That would not be wasted work, since phase 5 is portable,
but it should be said out loud before the machine is bought.

## 6. The cheaper path that runs in parallel

Asking HiBy for permission to redistribute a modified image costs one email and could deliver a
hostable one-click installer this month instead of next quarter. It does not compete with the
source build, it just removes the urgency.

The two together are the sensible order: ask now, build the machine anyway, and treat the source OS
as the long game it is.

## 7. What to do next, regardless

Independent of the build machine, the patch helper is worth building: a small local tool that takes
the user's own stock firmware, applies our payload and hands off to the web installer for flashing.
It is useful under every outcome above, including the one where HiBy says yes, because users on
different stock versions need the patch applied to their own base anyway.
