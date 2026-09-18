#!/usr/bin/env python3
"""Apply the Miku Tape rebrand to an apktool-decoded HiBy Tape tree.

Usage: patch_resources.py <decoded_apk_dir>

What it does (all idempotent):
  1. Strings: "HiBy Tape" -> "Miku Tape" (app_name), "HiBy" -> "Miku" (title),
     HiBy slogan -> MikuOS tagline, in every res/values*/strings.xml.
     Format specifiers (%s, %1$d ...) are never touched: only literal
     "HiBy" substrings are replaced.
  2. Layouts: default placeholder texts "HiBy Music"/"HiBy" on the cassette
     label become "Miku Music"/"Miku"; the artist line gets Miku pink.
  3. Colors: pure-green LED/point shapes in the VU/amp layout -> Miku teal.
  4. Artwork: luminance-preserving teal tint of the opaque deck (tape_bg) and
     the reel hubs (tape_wheel); the layout-switch glyph (tape_switch) goes
     Miku pink. The translucent glass film (tape_front*) and the masks are
     left alone so album art shows through untinted.
  5. apktool rebuild fix: values-v34/colors.xml references framework colors
     that apktool resolves to *private* names (the APK was built against
     SDK 36). Prefix them with '@*android:' so aapt2 links them to the very
     same resource ids the stock binary carries.
"""
import glob
import os
import re
import sys

from PIL import Image

TEAL = (0x39, 0xC5, 0xBB)
PINK = (0xFF, 0x22, 0x77)


def sub_file(path, pairs, count_out):
    with open(path, encoding="utf-8") as f:
        s = f.read()
    orig = s
    for pat, rep in pairs:
        s, n = re.subn(pat, rep, s)
        count_out[0] += n
    if s != orig:
        with open(path, "w", encoding="utf-8") as f:
            f.write(s)
        return True
    return False


def patch_strings(root):
    n = [0]
    for path in glob.glob(os.path.join(root, "res", "values*", "strings.xml")):
        sub_file(path, [
            (r'(<string name="app_name">)HiBy Tape(</string>)', r'\1Miku Tape\2'),
            (r'(<string name="title">)HiBy(</string>)', r'\1Miku\2'),
            (r'(<string name="artist">)Make music more musical(</string>)', r'\1Powered by MikuOS\2'),
            # catch-all for any other literal HiBy (never inside a % specifier)
            (r'HiBy Music', 'Miku Music'),
            (r'HiBy', 'Miku'),
        ], n)
    print(f"  strings: {n[0]} replacements")


def patch_layouts(root):
    n = [0]
    for path in glob.glob(os.path.join(root, "res", "layout*", "negative_one_screen*.xml")):
        sub_file(path, [
            (r'app:text="HiBy Music"', 'app:text="Miku Music"'),
            (r'app:text="HiBy"', 'app:text="Miku"'),
            (r'android:text="HiBy Music"', 'android:text="Miku Music"'),
            (r'android:text="HiBy"', 'android:text="Miku"'),
            # artist line on the cassette label in Miku pink (album stays grey)
            (r'(android:id="@id/tvSongArtist2"[^>]*app:textColor=")#cccccccc(")', r'\1#e6ff2277\2'),
        ], n)
    print(f"  layouts: {n[0]} replacements")


def patch_colors(root):
    """The amp/VU skin's lit LED dot (#ee00ee00, pure green) -> Miku teal with
    the same alpha. Its disabled twin is translucent black and stays as is."""
    n = [0]
    p = os.path.join(root, "res", "drawable", "ns_shape_green_point.xml")
    if os.path.exists(p):
        sub_file(p, [(r'android:color="#ee00ee00"', 'android:color="#ee39c5bb"')], n)
    print(f"  colors: {n[0]} replacements")


def fix_v34_private_refs(root):
    """apktool decodes SDK-36 framework color ids to private framework names;
    aapt2 refuses '@android:' refs to private symbols but accepts '@*android:'
    and links them to the identical ids the stock APK contains."""
    n = [0]
    for path in glob.glob(os.path.join(root, "res", "values-v3*", "colors.xml")):
        sub_file(path, [(r'@android:color/', '@*android:color/')], n)
    print(f"  v3x private framework refs: {n[0]} rewritten")


# ---------------------------------------------------------------------------
# artwork tinting

def tint_luminance(im, color, strength):
    """Recolour a grey image toward `color` keeping luminance. strength 0..1.
    Alpha is preserved untouched."""
    im = im.convert("RGBA")
    r, g, b, a = im.split()
    lum = im.convert("L")
    unit = [c / max(color) for c in color]  # brightest channel keeps its luminance
    chans = []
    for u in unit:
        k = (1.0 - strength) + strength * u
        chans.append(lum.point(lambda v, k=k: int(min(255, v * k))))
    return Image.merge("RGBA", (*chans, a))


def colorize_alpha(im, color):
    """Flat-fill a glyph with `color`, keeping only its alpha."""
    im = im.convert("RGBA")
    a = im.split()[3]
    out = Image.new("RGBA", im.size, color + (0,))
    out.putalpha(a)
    return out


def patch_artwork(root):
    ddir = os.path.join(root, "res", "drawable-xxxhdpi")
    jobs = [
        # (file, function, description)
        ("tape_bg.png", lambda im: tint_luminance(im, TEAL, 0.65), "deck -> deep teal-charcoal"),
        ("tape_wheel.png", lambda im: tint_luminance(im, TEAL, 0.80), "reel hubs -> Miku teal"),
        ("tape_switch.png", lambda im: colorize_alpha(im, PINK), "layout-switch glyph -> Miku pink"),
    ]
    for name, fn, desc in jobs:
        p = os.path.join(ddir, name)
        if not os.path.exists(p):
            print(f"  artwork: {name} missing, skipped")
            continue
        im = Image.open(p)
        out = fn(im)
        out.save(p, optimize=True)
        print(f"  artwork: {name}: {desc}")


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    root = sys.argv[1]
    if not os.path.isdir(os.path.join(root, "res")):
        sys.exit(f"not a decoded apk tree: {root}")
    patch_strings(root)
    patch_layouts(root)
    patch_colors(root)
    fix_v34_private_refs(root)
    patch_artwork(root)
    # final guard: nothing user-visible still says HiBy
    left = []
    for path in glob.glob(os.path.join(root, "res", "**", "*.xml"), recursive=True):
        with open(path, encoding="utf-8", errors="ignore") as f:
            for i, line in enumerate(f, 1):
                if "HiBy" in line and "com.hiby" not in line:
                    left.append(f"{os.path.relpath(path, root)}:{i}")
    if left:
        print("  WARNING: 'HiBy' still present in: " + ", ".join(left))
    else:
        print("  no user-visible 'HiBy' left in res/")


if __name__ == "__main__":
    main()
