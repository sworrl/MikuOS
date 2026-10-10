#!/usr/bin/env python3
"""Turn the picked candidates into drop-in replacements for HiBy's SystemUI frames.

  python3 build_frames.py            # uses picks.json, writes frames/ and the overlay res/

Every stock animation-list (anim_miku_*) keeps its XML, timing and frame names; only the frame
PNGs are replaced, so the RRO swaps them by resource name and nothing in SystemUI changes.
Each event gets ONE generated illustration; the frames are that illustration with a little
motion (bob, sway, shake, hop) and a pulsing neon rim, so the frame count matches stock exactly.

Stock geometry (SystemUI.apk, drawable-hdpi-v4): every frame is 240x240 RGBA, character
bottom-aligned on a transparent canvas. shutdown_bg is drawable-xhdpi-v4, 1440x2560, opaque.
"""
import json, math, os, shutil, sys
import numpy as np
from PIL import Image, ImageChops, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OVERLAY_RES = os.path.normpath(os.path.join(
    HERE, "../../../tools/custom_overlays/MikuSplashOverlay/res"))

# event -> (stock frame prefix, frame count, motion, rim colour)
EVENTS = {
    "headset_in":         ("listenmusic",     4, "bob",     (0x00, 0xE5, 0xFF)),
    "headset_out":        ("notlistenmusic", 23, "droop",   (0xB3, 0x88, 0xFF)),
    "charging":           ("pigeon",         10, "bob",     (0x39, 0xC5, 0xBB)),
    "low_battery":        ("cry",            12, "shake",   (0xFF, 0x5F, 0xA2)),
    "low_power_shutdown": ("tired",           4, "breathe", (0xFF, 0x5F, 0xA2)),
    "bye":                ("bye",            14, "sway",    (0x39, 0xC5, 0xBB)),
    "volume_warning":     ("dizzy",          19, "wobble",  (0xFF, 0x5F, 0xA2)),
    "volume_dial":        ("lift",           12, "hop",     (0x00, 0xE5, 0xFF)),
}
FRAME = 240          # stock hdpi frame size
SS = 3               # render at 3x then downsample, keeps edges clean
BG_SIZE = (1440, 2560)


def chroma_key(img):
    """Flat #00FF00 background -> alpha, with green spill pulled out of the edges."""
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    d = g - np.maximum(r, b)                       # green dominance; teal hair is ~10
    alpha = 1.0 - np.clip((d - 45.0) / 90.0, 0.0, 1.0)
    spill = d > 20.0
    g2 = np.where(spill, np.maximum(r, b) + 0.25 * np.clip(d - 20.0, 0, None) * alpha, g)
    out = np.dstack([r, np.minimum(g, g2), b, alpha * 255.0]).clip(0, 255).astype(np.uint8)
    im = Image.fromarray(out, "RGBA")
    # drop isolated specks the model left on the background
    m = im.getchannel("A").point(lambda v: 255 if v > 24 else 0).filter(ImageFilter.MinFilter(3))
    m = m.filter(ImageFilter.MaxFilter(5))
    im.putalpha(ImageChops.multiply(im.getchannel("A"), m))
    return im


def trim(im, thresh=10):
    box = im.getchannel("A").point(lambda v: 255 if v > thresh else 0).getbbox()
    return im.crop(box) if box else im


def fit(master, size, margin_side, margin_top, margin_bottom):
    """Scale the trimmed figure into a size x size canvas, bottom-centred."""
    w, h = master.size
    s = min((size - 2 * margin_side) / w, (size - margin_top - margin_bottom) / h)
    fig = master.resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(fig, ((size - fig.width) // 2, size - margin_bottom - fig.height))
    return canvas


def rim_glow(fig, color, strength):
    a = fig.getchannel("A")
    halo = a.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(4 * SS))
    halo = halo.point(lambda v: int(v * strength))
    layer = Image.new("RGBA", fig.size, color + (0,))
    layer.putalpha(halo)
    out = Image.new("RGBA", fig.size, (0, 0, 0, 0))
    out.alpha_composite(layer)
    out.alpha_composite(fig)
    return out


def pose(base, motion, p):
    """base: SSx canvas. p: phase 0..1. Returns transformed canvas (same size)."""
    W = base.width
    tau = 2 * math.pi
    dx = dy = 0.0
    ang = 0.0
    sy = 1.0
    if motion == "bob":
        dy = -4 * abs(math.sin(tau * p))
    elif motion == "droop":                          # slow sink and a small lean
        dy = 3 * math.sin(tau * p) + 1
        ang = 2.0 * math.sin(tau * p)
    elif motion == "shake":                          # sobbing tremble
        dx = 1.6 * math.sin(tau * 4 * p)
        dy = -1.5 * abs(math.sin(tau * 2 * p))
    elif motion == "breathe":
        sy = 1.0 + 0.025 * math.sin(tau * p)
    elif motion == "sway":                           # waving: lean side to side
        ang = 4.0 * math.sin(tau * p)
    elif motion == "wobble":                         # dizzy: wider lean and a small bounce
        ang = 6.0 * math.sin(tau * p)
        dy = -2 * abs(math.sin(tau * p))
    elif motion == "hop":
        dy = -10 * max(0.0, math.sin(tau * p)) ** 1.5
    out = base
    if sy != 1.0:                                     # vertical stretch anchored at the feet
        h = round(W * sy)
        st = base.resize((W, h), Image.LANCZOS)
        out = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        out.alpha_composite(st.crop((0, h - W, W, h)) if h > W else st, (0, max(0, W - h)))
    if ang:
        out = out.rotate(ang, resample=Image.BICUBIC, center=(W / 2, W * 0.97))
    if dx or dy:
        out = ImageChops.offset(out, round(dx * SS), round(dy * SS))
    return out


def build_event(name, cand_path, out_dir):
    prefix, count, motion, color = EVENTS[name]
    master = trim(chroma_key(Image.open(cand_path)))
    master.save(os.path.join(HERE, "masters", f"{name}.png"))
    S = FRAME * SS
    wide = master.width > master.height * 1.25
    base = fit(master, S, 10 * SS, (8 if wide else 14) * SS, 3 * SS)
    names = []
    for i in range(count):
        p = i / count
        glow = 0.35 + 0.30 * (0.5 + 0.5 * math.sin(2 * math.pi * p))
        fr = rim_glow(pose(base, motion, p), color, glow)
        fr = fr.resize((FRAME, FRAME), Image.LANCZOS)
        n = f"{prefix}{i + 1:02d}.png"
        fr.save(os.path.join(out_dir, n), optimize=True)
        names.append(n)
    return names


def build_bg(cand_path, out_dir):
    im = Image.open(cand_path).convert("RGB")
    tw, th = BG_SIZE
    s = max(tw / im.width, th / im.height)
    im = im.resize((math.ceil(im.width * s), math.ceil(im.height * s)), Image.LANCZOS)
    l, t = (im.width - tw) // 2, (im.height - th) // 2
    im = im.crop((l, t, l + tw, t + th))
    # keep the middle dark so the waving chibi (centred on top) stays readable
    yy, xx = np.mgrid[0:th, 0:tw]
    r = np.sqrt(((xx - tw / 2) / (tw * 0.42)) ** 2 + ((yy - th / 2) / (th * 0.30)) ** 2)
    k = np.clip(0.55 + 0.45 * r, 0.55, 1.0)
    # and a soft dark pad behind the wordmark so it reads over busy ribbons
    k = k * (1 - 0.75 * np.exp(-((xx - tw / 2) / (tw * 0.42)) ** 2 - ((yy - th * 0.84) / (th * 0.06)) ** 2))
    k = k[..., None]
    arr = (np.asarray(im).astype(np.float32) * k).clip(0, 255).astype(np.uint8)
    out = Image.fromarray(arr, "RGB")
    # MikuOS wordmark in the clear band below the waving chibi (drawn here, never by the model)
    sys.path.insert(0, os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                     "../splash")))
    from wordmark import draw_wordmark
    out = draw_wordmark(out, 0.84)
    out.save(os.path.join(out_dir, "shutdown_bg.png"), optimize=True)
    return ["shutdown_bg.png"]


def find_candidate(name, tag):
    for ext in (".png", ".jpg"):
        p = os.path.join(HERE, "candidates", f"{name}_{tag}{ext}")
        if os.path.exists(p):
            return p
    return None


def main():
    global HERE, OVERLAY_RES
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", default=HERE, help="dir holding candidates/ and picks.json")
    ap.add_argument("--overlay-res", default=OVERLAY_RES)
    a = ap.parse_args()
    HERE, OVERLAY_RES = os.path.abspath(a.work), os.path.abspath(a.overlay_res)
    picks = json.load(open(os.path.join(HERE, "picks.json")))
    hdpi = os.path.join(HERE, "frames", "drawable-hdpi")
    xhdpi = os.path.join(HERE, "frames", "drawable-xhdpi")
    for d in (hdpi, xhdpi, os.path.join(HERE, "masters")):
        os.makedirs(d, exist_ok=True)
    done, missing = [], []
    for name, tag in picks.items():
        if name.startswith("_") or name == "boot_splash":   # boot_splash: ../splash/make_boot.py
            continue
        cand = find_candidate(name, tag)
        if not cand:
            missing.append(f"{name}_{tag}")
            continue
        if name == "shutdown_bg":
            build_bg(cand, xhdpi)
        else:
            build_event(name, cand, hdpi)
        done.append(name)
    # mirror into the overlay source tree (only what was built)
    for sub, src in (("drawable-hdpi", hdpi), ("drawable-xhdpi", xhdpi)):
        files = sorted(f for f in os.listdir(src) if f.endswith(".png"))
        if files:
            dst = os.path.join(OVERLAY_RES, sub)
            os.makedirs(dst, exist_ok=True)
            for f in files:
                shutil.copy2(os.path.join(src, f), os.path.join(dst, f))
    print("built:", ", ".join(done) or "nothing")
    if missing:
        print("missing candidates:", ", ".join(missing), file=sys.stderr)


if __name__ == "__main__":
    main()
