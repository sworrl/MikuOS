#!/usr/bin/env python3
"""Generate release.json for the MikuOS web installer.

Hashes every image (whole-file SHA-256 plus per-chunk SHA-256 for anything the installer
streams in <= 64 MiB sparse chunks) and writes the manifest the browser consumes. Optionally
copies/links the images into a release directory with their canonical names so the whole
directory can be uploaded as-is to Cloudflare R2 / a static host.

Typical use from the repo root:

    python3 tools/web-installer/make_release_manifest.py \
        --version 2026.08.29 \
        --base-url https://cdn.example.com/mikuos/2026.08.29/ \
        --release-dir /tmp/mikuos-release-2026.08.29 \
        --with-rooted --with-stock \
        --output tools/web-installer/release.json

Defaults for the image locations mirror the repo's proven flash scripts
(mikuos/build/flash_mikuos_keepdata.sh, enable_root.sh, tools/unbrick_factory.sh):

    boot / init_boot / dtbo / vendor_boot   m500-system-archive/firmware/extracted_1.00/
    vbmeta_disabled, vbmeta_system_disabled mikuos/out/
    mikuos_system_bundle                    mikuos/out/mikuos_system_bundle.img
    init_boot_rooted (--with-rooted)        m500-system-archive/firmware/magisk_patched_init_boot.img
    stock_super, vbmeta(_system)_stock      m500-system-archive/firmware/super.img + extracted_1.00/vbmeta*.img

Every path can be overridden with --img KEY=PATH.
"""
import argparse
import hashlib
import json
import os
import shutil
import sys
import time

BLOCK = 4096
MAX_PAYLOAD = 64 * 1024 * 1024           # hard cap per fastboot payload (sparse headers included)
DEFAULT_CHUNK = 63 * 1024 * 1024         # data bytes per chunk (== js/config.js DEFAULT_CHUNK_BYTES)
RAW_SINGLE_PAYLOAD_LIMIT = 128 * 1024 * 1024  # == js/config.js RAW_SINGLE_PAYLOAD_LIMIT
EXPECTED_SUPER_SIZE = 5371461632         # fastboot getvar partition-size:super on M500_MIKU_4G

# key -> (canonical release filename, required?)
IMAGE_KEYS = {
    "boot": ("boot.img", True),
    "init_boot": ("init_boot.img", True),
    "dtbo": ("dtbo.img", True),
    "vendor_boot": ("vendor_boot.img", True),
    "vbmeta_disabled": ("vbmeta_disabled.img", True),
    "vbmeta_system_disabled": ("vbmeta_system_disabled.img", True),
    "mikuos_system_bundle": ("mikuos_system_bundle.img", True),
    "init_boot_rooted": ("init_boot_rooted.img", False),
    "stock_super": ("stock_super.img", False),
    "vbmeta_stock": ("vbmeta_stock.img", False),
    "vbmeta_system_stock": ("vbmeta_system_stock.img", False),
    "userdata_formatted": ("userdata_formatted.img", False),
}


def repo_root() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", ".."))


def default_paths(root: str) -> dict:
    fw = os.path.join(root, "m500-system-archive", "firmware")
    fw1 = os.path.join(fw, "extracted_1.00")
    out = os.path.join(root, "mikuos", "out")
    return {
        "boot": os.path.join(fw1, "boot.img"),
        "init_boot": os.path.join(fw1, "init_boot.img"),
        "dtbo": os.path.join(fw1, "dtbo.img"),
        "vendor_boot": os.path.join(fw1, "vendor_boot.img"),
        "vbmeta_disabled": os.path.join(out, "vbmeta_disabled.img"),
        "vbmeta_system_disabled": os.path.join(out, "vbmeta_system_disabled.img"),
        "mikuos_system_bundle": os.path.join(out, "mikuos_system_bundle.img"),
        "init_boot_rooted": os.path.join(fw, "magisk_patched_init_boot.img"),
        "stock_super": os.path.join(fw, "super.img"),
        "vbmeta_stock": os.path.join(fw1, "vbmeta.img"),
        "vbmeta_system_stock": os.path.join(fw1, "vbmeta_system.img"),
        "userdata_formatted": os.path.join(out, "userdata_formatted.img"),
    }


def hash_file(path: str, chunk_size: int, want_chunks: bool):
    """Return (whole_sha256_hex, [chunk_sha256_hex, ...] or None). Single pass, streaming."""
    whole = hashlib.sha256()
    chunks = [] if want_chunks else None
    size = os.path.getsize(path)
    done = 0
    t0 = time.time()
    with open(path, "rb") as f:
        while True:
            buf = f.read(chunk_size)
            if not buf:
                break
            whole.update(buf)
            if chunks is not None:
                chunks.append(hashlib.sha256(buf).hexdigest())
            done += len(buf)
            if size > 256 * 1024 * 1024:
                pct = done * 100 // size
                sys.stderr.write(f"\r    hashing {os.path.basename(path)}: {pct:3d}%")
    if size > 256 * 1024 * 1024:
        sys.stderr.write(f"\r    hashing {os.path.basename(path)}: done in {time.time() - t0:.0f}s\n")
    return whole.hexdigest(), chunks


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", required=True, help="release version string shown in the installer")
    ap.add_argument("--name", default="MikuOS")
    ap.add_argument("--base-url", default="", help="absolute URL prefix the image files will be served from (trailing slash). Empty = same directory as release.json")
    ap.add_argument("--notes-url", default="")
    ap.add_argument("--output", "-o", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "release.json"))
    ap.add_argument("--release-dir", help="copy (or --link) every image into this directory under its canonical name")
    ap.add_argument("--link", action="store_true", help="hard-link instead of copy into --release-dir (same filesystem only)")
    ap.add_argument("--with-rooted", action="store_true", help="include init_boot_rooted (enables the Root button)")
    ap.add_argument("--with-stock", action="store_true", help="include stock_super + vbmeta_stock + vbmeta_system_stock (enables Rollback to stock). Mind HiBy's copyright before hosting these publicly.")
    ap.add_argument("--with-userdata", action="store_true", help="include userdata_formatted.img (flashed after erase userdata on clean installs)")
    ap.add_argument("--img", action="append", default=[], metavar="KEY=PATH", help="override an image path (repeatable)")
    ap.add_argument("--chunk-mib", type=int, default=DEFAULT_CHUNK // (1024 * 1024), help=f"data MiB per streamed chunk (default {DEFAULT_CHUNK // (1024 * 1024)}; must be < 64)")
    ap.add_argument("--allow-wrong-super-size", action="store_true", help="do not fail when mikuos_system_bundle is not exactly the M500 super size")
    args = ap.parse_args()

    chunk_size = args.chunk_mib * 1024 * 1024
    if chunk_size % BLOCK or chunk_size <= 0 or chunk_size > DEFAULT_CHUNK:
        print(f"error: --chunk-mib must be 1..{DEFAULT_CHUNK // (1024 * 1024)} (64 MiB payload cap minus header room)", file=sys.stderr)
        return 2

    paths = default_paths(repo_root())
    for ov in args.img:
        if "=" not in ov:
            print(f"error: --img expects KEY=PATH, got {ov}", file=sys.stderr)
            return 2
        k, p = ov.split("=", 1)
        if k not in IMAGE_KEYS:
            print(f"error: unknown image key {k}; known: {', '.join(IMAGE_KEYS)}", file=sys.stderr)
            return 2
        paths[k] = p

    selected = [k for k, (_, req) in IMAGE_KEYS.items() if req]
    if args.with_rooted:
        selected.append("init_boot_rooted")
    if args.with_stock:
        selected += ["stock_super", "vbmeta_stock", "vbmeta_system_stock"]
    if args.with_userdata:
        selected.append("userdata_formatted")

    missing = [f"{k}: {paths[k]}" for k in selected if not os.path.isfile(paths[k])]
    if missing:
        print("error: missing image files:\n  " + "\n  ".join(missing), file=sys.stderr)
        return 1

    if args.release_dir:
        os.makedirs(args.release_dir, exist_ok=True)

    images = {}
    for key in selected:
        src = paths[key]
        fname = IMAGE_KEYS[key][0]
        size = os.path.getsize(src)
        print(f"[{key}] {src} ({size} bytes)")
        if key == "mikuos_system_bundle" and size != EXPECTED_SUPER_SIZE and not args.allow_wrong_super_size:
            print(f"error: {src} is {size} bytes; the M500 super partition is exactly {EXPECTED_SUPER_SIZE}. "
                  f"Rebuild with build_mikuos_super.sh or pass --allow-wrong-super-size.", file=sys.stderr)
            return 1
        streamed = size > RAW_SINGLE_PAYLOAD_LIMIT
        if streamed and size % BLOCK:
            print(f"error: {src} is streamed in sparse chunks but its size is not a multiple of {BLOCK}", file=sys.stderr)
            return 1
        whole, chunks = hash_file(src, chunk_size, streamed)
        entry = {"file": fname, "url": fname, "size": size, "sha256": whole}
        if chunks is not None:
            entry["chunks"] = chunks
            print(f"    {len(chunks)} chunks of <= {chunk_size} bytes")
        images[key] = entry
        if args.release_dir:
            dst = os.path.join(args.release_dir, fname)
            if os.path.exists(dst):
                os.remove(dst)
            if args.link:
                os.link(src, dst)
            else:
                shutil.copyfile(src, dst)
            print(f"    -> {dst}")

    manifest = {
        "schema": 1,
        "name": args.name,
        "version": args.version,
        "build_date": time.strftime("%Y-%m-%d"),
        "chunk_size": chunk_size,
        "super_partition_size": EXPECTED_SUPER_SIZE,
        "images": images,
    }
    if args.base_url:
        manifest["base_url"] = args.base_url
    if args.notes_url:
        manifest["notes_url"] = args.notes_url

    with open(args.output, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print(f"wrote {args.output}")
    if args.release_dir:
        with open(os.path.join(args.release_dir, "release.json"), "w") as f:
            json.dump(manifest, f, indent=2)
            f.write("\n")
        print(f"wrote {os.path.join(args.release_dir, 'release.json')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
