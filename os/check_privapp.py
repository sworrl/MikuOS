#!/usr/bin/env python3
"""
Fail the build, not the boot, when a priv-app asks for a privileged permission the allowlist
does not grant.

This device runs with ro.control_privapp_permissions=enforce and makes no exception for
platform-signed apps, so a single privileged permission missing from
privapp-permissions-mikuos.xml stops system_server at boot. That is a bootloop on a device
that is otherwise fine. This compares, for one APK:
  requested permissions        (aapt2 dump permissions <apk>)
  privileged in this framework (protectionLevel has "privileged", from the image's framework-res)
  granted by the allowlist     (<privapp-permissions package=...> in the XML)

Usage: check_privapp.py <aapt2> <apk> <framework-res.apk> <privapp.xml>
"""
import re
import subprocess
import sys
import xml.etree.ElementTree as ET


def run(*a):
    return subprocess.run(a, capture_output=True, text=True, check=True).stdout


def main():
    aapt2, apk, fwres, xml = sys.argv[1:5]
    perms = run(aapt2, "dump", "permissions", apk)
    pkg = re.search(r"^package: (\S+)", perms, re.M).group(1)
    requested = set(re.findall(r"uses-permission: name='([^']+)'", perms))

    # framework-res declares every android.permission.*; its protectionLevel is a flags int
    # in the binary manifest. 0x10 is the "privileged" flag (PROTECTION_FLAG_PRIVILEGED).
    tree = run(aapt2, "dump", "xmltree", "--file", "AndroidManifest.xml", fwres)
    privileged = set()
    for block in tree.split("E: permission ")[1:]:
        name = re.search(r'android:name\(0x[0-9a-f]+\)="([^"]+)"', block)
        level = re.search(r"android:protectionLevel\(0x[0-9a-f]+\)=(?:\(type 0x11\))?0x([0-9a-f]+)", block)
        if name and level and int(level.group(1), 16) & 0x10:
            privileged.add(name.group(1))

    allowed = set()
    for p in ET.parse(xml).getroot().iter("privapp-permissions"):
        if p.get("package") == pkg:
            allowed |= {e.get("name") for e in p.iter("permission")}

    missing = sorted((requested & privileged) - allowed)
    if missing:
        print(f"  !! {pkg}: privileged permissions not in the allowlist (would stop boot):")
        for m in missing:
            print(f"       {m}")
        sys.exit(1)
    print(f"  -> {pkg}: all {len(requested & privileged)} privileged permissions are allowlisted")


if __name__ == "__main__":
    main()
