#!/usr/bin/env python3
"""Build the MikuOS boot screen from the picked boot_splash candidate.

  python3 make_boot.py                     # uses ../hiby-splash/picks.json -> boot_splash_<letter>
  python3 make_boot.py --src some.png      # any 9:16 image

Writes, next to this script:
  boot_splash_master.png  1440x2560, cropped and graded art, no wordmark (the source for the rest)
  boot_splash.png         720x1280 still with the MikuOS wordmark (what the video ends on)
  bootanimation.mp4       720x1280, 30 fps, 12.5 s, H.264 Main, yuv420p, no audio track.
                          Same geometry and length as HiBy's /vendor/media/bootanimation_*.mp4.
                          build_mikuos_super.sh muxes the per-locale welcome voice into it.

The video fades in from black, pulls back slowly from 106% to 100%, and fades the wordmark in.
"""
import argparse, json, math, os, subprocess, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from wordmark import wordmark_layer, BG  # noqa: E402

GEN = os.path.normpath(os.path.join(HERE, "../hiby-splash"))
W, H, FPS, SECS = 720, 1280, 30, 12.5
MW, MH = 1440, 2560
WORDMARK_Y = 0.85


def find_src():
    picks = json.load(open(os.path.join(GEN, "picks.json")))
    tag = picks.get("boot_splash", "a")
    for ext in (".png", ".jpg"):
        p = os.path.join(GEN, "candidates", f"boot_splash_{tag}{ext}")
        if os.path.exists(p):
            return p
    sys.exit(f"no candidate boot_splash_{tag} (run ../hiby-splash/gen.py --only boot_splash)")


def master_from(src):
    im = Image.open(src).convert("RGB")
    s = max(MW / im.width, MH / im.height)
    im = im.resize((math.ceil(im.width * s), math.ceil(im.height * s)), Image.LANCZOS)
    l, t = (im.width - MW) // 2, (im.height - MH) // 2
    im = im.crop((l, t, l + MW, t + MH))
    # ease the bottom band toward the MikuOS background colour so the wordmark always reads
    a = np.asarray(im).astype(np.float32)
    y = np.linspace(0, 1, MH)[:, None, None]
    k = np.clip((y - 0.70) / 0.18, 0, 1) * 0.75
    a = a * (1 - k) + np.array(BG, np.float32) * k
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGB")


def ease(x):
    x = min(max(x, 0.0), 1.0)
    return 1 - (1 - x) ** 3


def frame(master, wm, t):
    s = 1.06 - 0.06 * ease(t / (SECS - 1.0))
    cw, ch = MW / s, MH / s
    box = ((MW - cw) / 2, (MH - ch) * 0.35, (MW + cw) / 2, (MH - ch) * 0.35 + ch)
    im = master.resize((W, H), Image.BICUBIC, box=box)
    fade = ease(t / 1.2)
    if fade < 1:
        im = Image.eval(im, lambda v: int(v * fade))
    wa = ease((t - 1.5) / 1.2)
    if wa > 0:
        layer = wm if wa >= 1 else wm.copy()
        if wa < 1:
            layer.putalpha(layer.getchannel("A").point(lambda v: int(v * wa)))
        im = im.convert("RGBA")
        im.alpha_composite(layer)
        im = im.convert("RGB")
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src")
    ap.add_argument("--out", default=HERE)
    a = ap.parse_args()
    src = a.src or find_src()
    master = master_from(src)
    master.save(os.path.join(a.out, "boot_splash_master.png"), optimize=True)
    wm = wordmark_layer((W, H), round(H * WORDMARK_Y))
    frame(master, wm, SECS).save(os.path.join(a.out, "boot_splash.png"), optimize=True)
    mp4 = os.path.join(a.out, "bootanimation.mp4")
    ff = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
         "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-profile:v", "main", "-pix_fmt", "yuv420p",
         "-preset", "slow", "-crf", "20", "-movflags", "+faststart", "-an", mp4],
        stdin=subprocess.PIPE)
    n = round(SECS * FPS)
    for i in range(n):
        ff.stdin.write(frame(master, wm, i / FPS).tobytes())
    ff.stdin.close()
    if ff.wait():
        sys.exit("ffmpeg failed")
    print(f"from {src}\nwrote boot_splash_master.png, boot_splash.png, bootanimation.mp4 ({n} frames)")


if __name__ == "__main__":
    main()
