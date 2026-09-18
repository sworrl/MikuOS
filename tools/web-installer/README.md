# MikuOS Web Installer (HiBy M500)

GrapheneOS-style browser installer: the user plugs the M500 into a PC, opens this page in
Chrome/Edge, and clicks **Install MikuOS** / **Enable root**. Everything runs client-side over
**WebUSB fastboot** - no adb, no fastboot binary, no drivers to install (WinUSB on Windows aside),
no backend.

```
tools/web-installer/
  index.html                  the wizard (Requirements -> Connect -> Choose -> Flash -> Done + recovery)
  css/style.css               Miku teal (#39C5BB) + neon pink theme
  js/config.js                device constants, guard rails, partition sequences  <-- TODO lives here
  js/flasher.js               flash engine: image sources, SHA-256, 64 MiB sparse chunking, plan, resume
  js/app.js                   UI controller
  js/vendor/fastboot.min.mjs  kdrag0n/fastboot.js 1.1.3 (MIT), unmodified; + LICENSE + NOTICE
  release.example.json        manifest format reference (placeholders)
  make_release_manifest.py    hashes mikuos/out + firmware images -> release.json (+ release dir)
  serve.py                    local dev server WITH Range support (python -m http.server lacks it)
```

No build step. Static files only.

## What it flashes (derived from the repo's proven scripts, not invented)

| Action | Sequence | Source script |
|---|---|---|
| Install / Update (keep data) - **default** | `boot_a/b`, `init_boot_a/b`, `dtbo_a/b`, `vendor_boot_a/b` (stock 1.00 firmware) -> `vbmeta_a/b`, `vbmeta_system_a/b` (flags=3 "disabled" images) -> `super` (MikuOS bundle, **<= 64 MiB sparse chunks, retried**) -> `set_active a` -> `reboot` | `mikuos/build/flash_mikuos_keepdata.sh` |
| Clean install (wipe) | same, then `erase misc`, `erase metadata`, `erase userdata` (+ optional `userdata_formatted` flash) -> `reboot` | `flash_mikuos_clean.sh` |
| Enable root | `init_boot_a/b` <- Magisk-patched init_boot -> `set_active a` -> `reboot` (no wipe) | `enable_root.sh` |
| Disable root | `init_boot_a/b` <- stock init_boot -> `set_active a` -> `reboot` | `disable_root.sh` |
| Rollback to stock | stock boot chain -> **stock signed** `vbmeta`/`vbmeta_system` -> stock `super` -> `set_active a` -> wipe -> `reboot` | `tools/unbrick_factory.sh` |

Install actions offer an "also enable root" checkbox that swaps `init_boot` for `init_boot_rooted`
in the same run (equivalent to `flash_mikuos_rooted.sh`).

### Device facts the engine is built around
* **super is 5,371,461,632 bytes exactly** (`getvar partition-size:super`). The installer refuses
  a bundle of any other size and refuses a device whose super differs.
* **The M500's USB gadget wedges on big bulk pushes.** Every payload is a self-contained sparse
  image <= 64 MiB (63 MiB data + headers, zero runs become FILL chunks), sent one at a time,
  each chunk retried up to 3 times with a 3 s pause. A 90 s no-progress watchdog detects a
  wedged gadget, closes the USB device and tells the user to power-cycle; **Reconnect & Resume**
  continues at the exact chunk. Small images (<= 128 MiB and <= `max-download-size`) go as one
  raw payload, exactly like plain `fastboot flash` in the scripts.
* **Never two fastboot streams**: a single lock serialises every command.
* **Fastboot does not charge**: step 1 requires a >= 50 % checkbox; step 2 shows
  `battery-voltage` (Qualcomm ABL) with a rough % hint and blocks below ~50 % unless the user
  confirms they read the on-device percentage.
* **Wipe** = `erase misc` + `erase metadata` + `erase userdata` (from the clean script; never a
  raw dd). See "wipe semantics" below.
* Bootloop / USB drop-off recovery is documented on the page (`#recovery`).

### Integrity
Every image in `release.json` carries a whole-file SHA-256; images bigger than 128 MiB also carry
one SHA-256 per 63 MiB chunk. The browser verifies with Web Crypto **before** each upload: small
images fully before the first byte, big images chunk by chunk as they stream (a bad chunk is
never sent). The pre-flight also `HEAD`s every URL and compares `Content-Length` with the manifest
so a wrong upload is caught before anything is written.

## TODO / placeholders (read before publishing)

1. **`js/config.js` -> `EXPECTED_PRODUCTS`** is a placeholder (`__TODO_FILL_FROM_fastboot_getvar_product__`).
   Run `fastboot getvar product` on a real M500 and put the exact string there. Until then the
   installer is locked (it prints the observed value in the log and the guard list) and only the
   clearly-labelled *Developer override* checkbox lets it proceed.
2. **Fastboot key combo** on the Requirements page says *Power + Volume Down* (from the older
   web-flasher README and `tools/root_device.sh`). The M500 has a rotary volume wheel, so verify
   on hardware and edit the text in `index.html`.
3. **Bootloader unlock** button sends `flashing:unlock` (the standard command the repo's rooting
   guide lists). Whether HiBy's ABL honours it and how it asks for confirmation is unverified.
4. **`init_boot_rooted`** = `m500-system-archive/firmware/magisk_patched_init_boot.img` (Magisk-patched
   stock init_boot; see `FIRMWARE_ARCHIVE_REPORT.md` section 3 for how it is made). Re-patch it
   whenever the Magisk version or the stock init_boot changes. Root button only appears when the
   manifest contains it (`--with-rooted`).
5. **Wipe semantics.** Memory note `m500-flash-hygiene` says a bare `erase userdata` once left
   /data raw and bootlooped, and that `fastboot -w` (which writes a freshly formatted userdata
   image) fixed it; the later `flash_mikuos_clean.sh` uses `erase metadata` + `erase userdata`
   and comments that first-stage mount formats them. The browser cannot run `mke2fs`, so the
   installer does the erase sequence and, **if** the manifest includes `userdata_formatted`
   (`--with-userdata`), flashes that image afterwards - exactly what `-w` does. To produce it,
   capture the file the fastboot CLI generates for `-w` (it is ~364 KB) or build one with
   `mke2fs -t ext4 -b 4096 -E android_sparse ...` for the userdata partition size. If clean
   installs boot fine with erase-only, ignore this.
6. **Rollback to stock** needs `stock_super` (the extracted 1.00 `super.img`, 4,831,838,208 bytes -
   smaller than the partition but known to boot) plus the original signed `vbmeta`/`vbmeta_system`.
   Those are HiBy's proprietary images; decide whether you may host them before using
   `--with-stock`. Same consideration applies, more weakly, to the stock boot-chain images that
   every install needs (they come from HiBy's public OTA).
7. `USB_VENDOR_ID/PRODUCT_ID` 18d1:d00d were observed on the real device; the browser chooser
   also accepts any fastboot-class interface, then the product guard decides.

## Generating a release

```bash
# from the repo root, after build_mikuos_super.sh produced mikuos/out/mikuos_system_bundle.img
python3 tools/web-installer/make_release_manifest.py \
    --version 2026.08.29 \
    --base-url https://releases.example.com/mikuos/2026.08.29/ \
    --release-dir /srv/mikuos-releases/2026.08.29 --link \
    --with-rooted \
    --output tools/web-installer/release.json
```

* Hashes are computed in one streaming pass (the 5 GB bundle takes ~30-60 s).
* `--release-dir` gathers every image under its canonical name (`boot.img`, `mikuos_system_bundle.img`,
  `init_boot_rooted.img`, ...) plus a copy of `release.json`; upload that directory as-is.
* `--img KEY=PATH` overrides any source path; `--with-stock`, `--with-userdata` add the optional images.
* `chunk_size` in the manifest **must** equal what the browser uses (default 63 MiB = 66,060,288 bytes);
  the generator and `js/config.js` share that default. Lower it with `--chunk-mib` only if a device
  reports a smaller `max-download-size`.

## Hosting

* **WebUSB requires a secure context**: HTTPS, or `http://localhost` for development.
* The page itself is tiny; host it on Cloudflare Pages / GitHub Pages / any static host.
* **Images need a host that supports HTTP Range requests and CORS** (if on another origin):
  Cloudflare R2 (add a CORS rule allowing `GET, HEAD`, header `Range`, exposing
  `Content-Length, Content-Range, Accept-Ranges`), Backblaze B2, S3, nginx, Caddy all work.
  GitHub Pages caps files at 100 MB and GitHub Releases at 2 GiB per asset, so the 5 GB bundle
  cannot live there; put the manifest's `base_url` on R2/B2 instead.
* Serve `release.json` with `Cache-Control: no-cache` (the page fetches it with `no-store`).
* Add `?manifest=https://.../release.json` to point the page at another manifest (e.g. a beta channel).

## Testing locally (no device needed for the UI, a device for flashing)

```bash
# 1. make a manifest that points at the local images
python3 tools/web-installer/make_release_manifest.py --version dev \
    --base-url http://localhost:8000/images/ --with-rooted \
    --output tools/web-installer/release.json

# 2. serve with Range support, exposing mikuos/out as /images/
python3 tools/web-installer/serve.py --images mikuos/out --port 8000
# stock boot-chain images live elsewhere: either --release-dir into one folder and --images that,
# or pick them as local files in the page's "Advanced" panel.

# 3. open http://localhost:8000/ in Chrome
```

`localhost` counts as a secure context, so WebUSB works over plain HTTP there. Alternatively use
the *Advanced: local files* panel on the Connect step to pick `release.json` and the images
straight from disk (sizes must match; hashes are still verified). On Linux add a udev rule for
`18d1:d00d` and make sure no `fastboot` CLI process is running - two clients wedge the gadget.

Sanity checks you can run without hardware:

```bash
node --check tools/web-installer/js/flasher.js      # (as ESM: copy to .mjs or use --input-type=module)
python3 -m py_compile tools/web-installer/make_release_manifest.py tools/web-installer/serve.py
```

## Recovery cheat-sheet (also on the page)

* Transfer stalls / device disappears: unplug, hold POWER ~10 s, re-enter fastboot, replug,
  **Reconnect & Resume**. Host-side USB resets do nothing; only the device power-cycle clears the gadget.
* Bootloop after a flash: run **Clean install** again and do not touch the device until the Miku
  boot animation. `set_active a` also resets slot A's boot-attempt counter.
* Blue LED + 2 s splash loop: flat battery, not a brick. Wall charger, then retry.
* Truly stuck: SM6225 EDL/9008 raw restore (see `m500-system-archive/M500_ROOTING_AND_UNBRICK_GUIDE.md`).

## Credits
* [fastboot.js](https://github.com/kdrag0n/fastboot.js) by Danny Lin - MIT, vendored unmodified in `js/vendor/`.
