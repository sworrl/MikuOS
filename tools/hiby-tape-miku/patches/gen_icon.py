#!/usr/bin/env python3
"""Generate the Miku Tape launcher icon set (PIL only, no external assets).

Draws a Miku-teal compact cassette on a dark teal-charcoal rounded square,
pink label stripe, white hubs, and a small pink "01". Rendered at 4x and
downsampled with LANCZOS so edges stay clean at every density.

Usage: gen_icon.py <decoded_apk_dir> [preview.png]
Writes res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_app.png (the manifest's
android:icon / roundIcon) and also refreshes the unused ic_launcher*.webp so
nothing HiBy-shaped is left in the APK.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

TEAL = (0x39, 0xC5, 0xBB)
TEAL_DARK = (0x27, 0x8F, 0x88)
TEAL_DEEP = (0x14, 0x3F, 0x42)
PINK = (0xFF, 0x22, 0x77)
PINK_DARK = (0xC8, 0x14, 0x5A)
CHAR_TOP = (0x1C, 0x3C, 0x41)
CHAR_BOT = (0x0A, 0x1A, 0x1D)
LABEL = (0xF6, 0xFC, 0xFB)
WINDOW = (0x0E, 0x22, 0x25)
WHITE = (0xFF, 0xFF, 0xFF)

S = 4          # supersample factor
BASE = 1024    # master size (logical px)


def px(v):
    return int(round(v * S))


def find_font(size):
    for cand in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    ):
        if os.path.exists(cand):
            return ImageFont.truetype(cand, size)
    return None


def vertical_gradient(size, top, bottom):
    w, h = size
    grad = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        grad.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return grad.resize((w, h))


def render_master():
    W = H = px(BASE)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    # --- background: rounded square, dark teal-charcoal gradient -------------
    bg = vertical_gradient((W, H), CHAR_TOP, CHAR_BOT).convert("RGBA")
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, H - 1], radius=px(225), fill=255)
    img.paste(bg, (0, 0), mask)

    # soft teal glow behind the cassette
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([px(140), px(300), px(884), px(760)], fill=TEAL + (70,))
    glow = glow.filter(ImageFilter.GaussianBlur(px(60)))
    img.alpha_composite(glow)

    d = ImageDraw.Draw(img)

    # --- cassette shell ------------------------------------------------------
    shell = [px(112), px(292), px(912), px(732)]
    # drop shadow
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [shell[0], shell[1] + px(18), shell[2], shell[3] + px(18)], radius=px(44), fill=(0, 0, 0, 120))
    sh = sh.filter(ImageFilter.GaussianBlur(px(14)))
    img.alpha_composite(sh)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(shell, radius=px(44), fill=TEAL + (255,), outline=TEAL_DARK + (255,), width=px(6))
    # darker lower band (bottom edge of the shell)
    d.rounded_rectangle([shell[0] + px(6), px(660), shell[2] - px(6), shell[3] - px(6)],
                        radius=px(30), fill=TEAL_DARK + (255,))
    d.rectangle([shell[0] + px(6), px(660), shell[2] - px(6), px(690)], fill=TEAL + (255,))

    # --- label -----------------------------------------------------------------
    label = [px(152), px(332), px(872), px(624)]
    d.rounded_rectangle(label, radius=px(26), fill=LABEL + (255,))
    # pink header stripe + thin teal pinstripe under it
    d.rounded_rectangle([label[0], label[1], label[2], px(384)], radius=px(26), fill=PINK + (255,))
    d.rectangle([label[0], px(366), label[2], px(384)], fill=PINK + (255,))
    d.rectangle([label[0], px(384), label[2], px(392)], fill=TEAL_DARK + (255,))

    # --- window + hubs ---------------------------------------------------------
    win = [px(342), px(418), px(682), px(586)]
    d.rounded_rectangle(win, radius=px(40), fill=WINDOW + (255,))
    cy = px(502)
    for cx, pancake in ((px(432), px(78)), (px(592), px(58))):
        # tape pancake (asymmetric: more tape on the left reel)
        d.ellipse([cx - pancake, cy - pancake, cx + pancake, cy + pancake], fill=(0x22, 0x28, 0x2A, 255))
        # hub ring
        r = px(48)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=WHITE + (255,))
        r2 = px(30)
        d.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], fill=WINDOW + (255,))
        # six teeth
        for k in range(6):
            import math
            a = math.radians(k * 60)
            x0 = cx + math.cos(a) * px(28)
            y0 = cy + math.sin(a) * px(28)
            x1 = cx + math.cos(a) * px(44)
            y1 = cy + math.sin(a) * px(44)
            d.line([x0, y0, x1, y1], fill=WHITE + (255,), width=px(9))
        r3 = px(9)
        d.ellipse([cx - r3, cy - r3, cx + r3, cy + r3], fill=WHITE + (255,))

    # --- "01" mark on the label (Miku's shoulder tattoo) -------------------
    font = find_font(px(74))
    if font:
        d.text((px(720), px(560)), "01", font=font, fill=PINK + (255,), anchor="ls")
        f2 = find_font(px(34))
        d.text((px(176), px(560)), "MIKU", font=f2, fill=TEAL_DEEP + (255,), anchor="ls")

    # --- capstan / pinch-roller holes along the bottom edge ------------------
    for x in (200, 300, 512, 724, 824):
        rr = px(13) if x != 512 else px(17)
        d.ellipse([px(x) - rr, px(704) - rr, px(x) + rr, px(704) + rr], fill=WINDOW + (255,))
    # corner screws
    for x, y in ((146, 322), (878, 322), (146, 700), (878, 700)):
        rr = px(11)
        d.ellipse([px(x) - rr, px(y) - rr, px(x) + rr, px(y) + rr], fill=TEAL_DEEP + (255,))

    return img.resize((BASE, BASE), Image.LANCZOS)


DENSITIES = {
    "mdpi": 128,
    "hdpi": 192,
    "xhdpi": 256,
    "xxhdpi": 384,   # stock ic_app.png is 384 px in xxhdpi
    "xxxhdpi": 512,
}


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    root = sys.argv[1]
    master = render_master()
    if len(sys.argv) > 2:
        master.save(sys.argv[2])
    for dens, size in DENSITIES.items():
        ddir = os.path.join(root, "res", f"mipmap-{dens}")
        os.makedirs(ddir, exist_ok=True)
        im = master.resize((size, size), Image.LANCZOS)
        im.save(os.path.join(ddir, "ic_app.png"), optimize=True)
        # The unused Android-Studio default adaptive icons: overwrite the
        # bitmap fallbacks too so nothing off-brand remains.
        for name in ("ic_launcher.webp", "ic_launcher_round.webp"):
            p = os.path.join(ddir, name)
            if os.path.exists(p):
                im.save(p, "WEBP", quality=92, method=6)
        print(f"  icon: mipmap-{dens}/ic_app.png {size}px")


if __name__ == "__main__":
    main()
