#!/usr/bin/env python3
"""Check a built MikuSplashOverlay against the stock SystemUI it targets.

  check_overlay.py MikuSplashOverlay.apk [stock SystemUI.apk]

For every PNG in the overlay: the same res path must exist in stock SystemUI, with the same
pixel size and the same alpha/no-alpha. Also reports stock frames of each replaced animation
that the overlay does not cover (those would play HiBy frames mid-loop).
"""
import io, os, re, sys, zipfile
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_STOCK = os.path.normpath(os.path.join(
    HERE, "../../../m500-system-archive/extracted_fs/system_ext/priv-app/SystemUI/SystemUI.apk"))


def info(z, n):
    im = Image.open(io.BytesIO(z.read(n)))
    alpha = im.mode in ("RGBA", "LA") or "transparency" in im.info
    return im.size, alpha


def main():
    ovl = zipfile.ZipFile(sys.argv[1])
    stock = zipfile.ZipFile(sys.argv[2] if len(sys.argv) > 2 else DEFAULT_STOCK)
    snames = set(stock.namelist())
    bad, prefixes, ok = 0, set(), 0
    for n in sorted(ovl.namelist()):
        if not n.endswith(".png"):
            continue
        if n not in snames:
            print("NOT IN STOCK:", n); bad += 1; continue
        (o_sz, o_a), (s_sz, s_a) = info(ovl, n), info(stock, n)
        if o_sz != s_sz:
            print(f"SIZE {n}: overlay {o_sz} stock {s_sz}"); bad += 1
        if s_a and not o_a:
            print(f"ALPHA {n}: stock has alpha, overlay does not"); bad += 1
        m = re.match(r"res/drawable-hdpi-v4/([a-z]+)\d+\.png$", n)
        if m:
            prefixes.add(m.group(1))
        ok += 1
    onames = set(ovl.namelist())
    for p in sorted(prefixes):
        for n in sorted(snames):
            if re.match(rf"res/drawable-[a-z]+-v4/{p}\d+\.png$", n) and n not in onames:
                print("STOCK FRAME NOT COVERED:", n); bad += 1
    print(f"{ok} overlay PNGs checked, {bad} problem(s)")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
