#!/usr/bin/env python3
"""Prepare Android Auto for bundling into a MikuOS image, without bricking the boot.

WHY THIS EXISTS

Android Auto's phone side (com.google.android.projection.gearhead) is Google proprietary
and is not in AOSP. HiBy licensed a media-player GMS set for this DAP, which does not
include it, so "it's Android 14" does not get you Android Auto. Since Android 10 the app
also refuses to run unless it is a PRIVILEGED SYSTEM app, which is the error you get when
you sideload it: it wants to have shipped with the OS.

So bundling it means putting it in a priv-app directory in the image. That is where the
danger is. This device builds with ro.control_privapp_permissions=enforce, which means a
privileged app requesting ONE privileged permission that is not in the allowlist stops the
device booting - PackageManagerService throws during scan. Android Auto requests a lot of
permissions, and hand-writing that list is how you get a brick.

So this generates the allowlist from the APK and the framework, mechanically:

  1. read every uses-permission out of the real gearhead manifest,
  2. read every permission the THIS BUILD's framework-res.apk marks privileged
     (protectionLevel & 0x10), which is the only authority that matters,
  3. intersect, and emit exactly those.

Permissions the framework does not define, or defines as non-privileged, are deliberately
left out: the allowlist only governs privileged ones, and padding it with the rest makes it
unreviewable.

It also refuses to proceed if the APK is not what it claims to be. Re-signing gearhead
breaks its GMS handshake, so it must be installed exactly as Google shipped it, and this
prints the signer so a human can confirm before anything is written to an image.

USAGE
    python3 tools/androidauto/prepare_android_auto.py --apk /path/to/gearhead.apk \
        --system-img mikuos/out/system.img

Writes mikuos/build/permissions/privapp-permissions-androidauto.xml and prints exactly what
the build step needs to inject. It does NOT modify any image; that is the build's job.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

GEARHEAD = "com.google.android.projection.gearhead"
PROTECTION_FLAG_PRIVILEGED = 0x10


def tool(name: str) -> str:
    """Find a build tool, preferring the SDK copy over whatever is on PATH."""
    for root in (os.path.expanduser("~/Android/Sdk/build-tools"),
                 os.path.expanduser("~/Android/Sdk/cmdline-tools/latest/bin")):
        if os.path.isdir(root):
            for dirpath, _, files in os.walk(root):
                if name in files:
                    return os.path.join(dirpath, name)
    found = shutil.which(name)
    if not found:
        sys.exit(f"error: {name} not found; install Android build-tools")
    return found


def xmltree(apk: str, path: str = "AndroidManifest.xml") -> str:
    out = subprocess.run([tool("aapt2"), "dump", "xmltree", "--file", path, apk],
                         capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"error: could not read {path} from {apk}:\n{out.stderr.strip()}")
    return out.stdout


def framework_privileged(system_img: str) -> set:
    """Every permission THIS build's framework marks privileged. The only authority."""
    with tempfile.TemporaryDirectory() as td:
        dst = os.path.join(td, "framework-res.apk")
        subprocess.run(["debugfs", "-R", f"dump system/framework/framework-res.apk {dst}",
                        system_img], capture_output=True, text=True)
        if not os.path.isfile(dst) or os.path.getsize(dst) == 0:
            sys.exit(f"error: could not extract system/framework/framework-res.apk from {system_img}")
        priv, name, lvl, inperm = set(), None, None, False
        for line in xmltree(dst).splitlines():
            s = line.strip()
            if s.startswith("E: "):
                if inperm and name and lvl is not None and (lvl & PROTECTION_FLAG_PRIVILEGED):
                    priv.add(name)
                inperm = s.startswith("E: permission ") or s.startswith("E: permission(")
                name, lvl = None, None
                continue
            if not inperm:
                continue
            m = re.search(r'android:name\(0x[0-9a-f]+\)="([^"]+)"', s)
            if m:
                name = m.group(1)
            m = re.search(r'android:protectionLevel\(0x[0-9a-f]+\)=(0x[0-9a-f]+)', s)
            if m:
                lvl = int(m.group(1), 16)
        if inperm and name and lvl is not None and (lvl & PROTECTION_FLAG_PRIVILEGED):
            priv.add(name)
        return priv


def apk_facts(apk: str):
    """Package name, version, and every uses-permission the APK declares."""
    tree = xmltree(apk)
    pkg = re.search(r'A: package="([^"]+)"', tree)
    ver = re.search(r'android:versionName\(0x[0-9a-f]+\)="([^"]+)"', tree)
    code = re.search(r'android:versionCode\(0x[0-9a-f]+\)=(\d+)', tree)
    perms, inuses = set(), False
    for line in tree.splitlines():
        s = line.strip()
        if s.startswith("E: "):
            inuses = s.startswith("E: uses-permission")
            continue
        if not inuses:
            continue
        m = re.search(r'android:name\(0x[0-9a-f]+\)="([^"]+)"', s)
        if m:
            perms.add(m.group(1))
    return (pkg.group(1) if pkg else None,
            ver.group(1) if ver else "?",
            code.group(1) if code else "?",
            perms)


def signer(apk: str) -> str:
    """Who signed it. Gearhead must stay Google-signed; re-signing breaks its GMS handshake."""
    aps = tool("apksigner")
    out = subprocess.run([aps, "verify", "--print-certs", apk], capture_output=True, text=True)
    for line in (out.stdout or "").splitlines():
        if "certificate SHA-256 digest" in line:
            return line.split(":")[-1].strip()
    return "(could not read; apksigner said: " + (out.stderr or "").strip()[:120] + ")"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apk", required=True, help="the official Android Auto APK, unmodified")
    ap.add_argument("--system-img", required=True,
                    help="the built system.img, to read the framework's permission table from")
    ap.add_argument("--out", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..",
        "mikuos", "build", "permissions", "privapp-permissions-androidauto.xml"))
    ap.add_argument("--allow-any-package", action="store_true",
                    help="skip the package-name check (for inspecting a different APK)")
    args = ap.parse_args()

    if not os.path.isfile(args.apk):
        sys.exit(f"error: no such APK: {args.apk}")

    pkg, ver, code, perms = apk_facts(args.apk)
    size_mb = os.path.getsize(args.apk) / 1048576
    sha = hashlib.sha256(open(args.apk, "rb").read()).hexdigest()

    print(f"APK        {args.apk}")
    print(f"  package  {pkg}")
    print(f"  version  {ver} (code {code})")
    print(f"  size     {size_mb:.1f} MB")
    print(f"  sha256   {sha}")
    print(f"  signer   {signer(args.apk)}")
    print(f"  requests {len(perms)} permissions")

    if pkg != GEARHEAD and not args.allow_any_package:
        sys.exit(f"\nerror: expected {GEARHEAD}, got {pkg}. "
                 f"Pass --allow-any-package only if you know why.")

    priv = framework_privileged(args.system_img)
    print(f"\nframework defines {len(priv)} privileged permissions")

    need = sorted(perms & priv)
    unknown = sorted(p for p in perms
                     if p.startswith("android.permission.") and p not in priv)
    print(f"  of which this APK requests {len(need)} -> these MUST be allowlisted")
    print(f"  (it also requests {len(unknown)} android.permission.* the framework does not "
          f"mark privileged; those need no entry)")

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n')
        f.write("<!-- GENERATED by tools/androidauto/prepare_android_auto.py - do not hand-edit.\n")
        f.write(f"     Source APK {os.path.basename(args.apk)} version {ver} (code {code})\n")
        f.write(f"     sha256 {sha}\n")
        f.write("     Every entry is a permission this APK requests AND this build's\n")
        f.write("     framework-res.apk marks privileged (protectionLevel & 0x10). The device\n")
        f.write("     builds with ro.control_privapp_permissions=enforce, so a missing entry\n")
        f.write("     here is not a warning, it is a device that does not boot. Regenerate this\n")
        f.write("     file whenever the APK or the framework changes. -->\n")
        f.write("<permissions>\n")
        f.write(f'    <privapp-permissions package="{pkg}">\n')
        for p in need:
            f.write(f'        <permission name="{p}"/>\n')
        f.write("    </privapp-permissions>\n")
        f.write("</permissions>\n")
    print(f"\nwrote {os.path.abspath(args.out)}")

    print("\nNEXT, and none of it is done by this script:")
    print("  1. inject the APK UNMODIFIED to /system_ext/priv-app/AndroidAuto/AndroidAuto.apk")
    print("     (system_ext has the headroom; do NOT re-sign it)")
    print("  2. inject this XML to /system_ext/etc/permissions/")
    print("  3. bump MIKUOS_VERSION so PackageManager re-reads manifests")
    print("  4. flash, and watch for PackageManagerService refusing the package on first boot")
    return 0


if __name__ == "__main__":
    sys.exit(main())
