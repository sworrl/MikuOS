#!/usr/bin/env python3
"""Side-by-side review sheet: stock HiBy art vs both candidates vs the built frames.

  python3 contact_sheet.py [--stock-apk path/to/stock/SystemUI.apk]

Stock frames are read straight out of the stock SystemUI.apk (never copied into this folder),
and the sheet itself is gitignored, because both contain HiBy's art.
Rows: one per event. Columns: stock frame 1 | candidate a | candidate b | new frame 1 | new mid frame.
The picked candidate has a teal outline.
"""
import argparse, io, json, os, zipfile
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_APK = os.path.normpath(os.path.join(
    HERE, "../../../m500-system-archive/extracted_fs/system_ext/priv-app/SystemUI/SystemUI.apk"))
FRAMES = {"headset_in": "listenmusic", "headset_out": "notlistenmusic", "charging": "pigeon",
          "low_battery": "cry", "low_power_shutdown": "tired", "bye": "bye",
          "volume_warning": "dizzy", "volume_dial": "lift"}
COUNTS = {"listenmusic": 4, "notlistenmusic": 23, "pigeon": 10, "cry": 12, "tired": 4,
          "bye": 14, "dizzy": 19, "lift": 12}
CELL, PAD, LABEL = 240, 12, 22
BG, PANEL, TEAL = (12, 14, 20), (30, 34, 44), (57, 197, 187)


def font(sz):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
              "/usr/share/fonts/TTF/DejaVuSans.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


def tile(im, size):
    t = Image.new("RGBA", size, PANEL + (255,))
    if im is not None:
        im = im.convert("RGBA").copy()
        im.thumbnail(size, Image.LANCZOS)
        t.alpha_composite(im, ((size[0] - im.width) // 2, (size[1] - im.height) // 2))
    return t


def cand(name, tag):
    for ext in (".png", ".jpg"):
        p = os.path.join(HERE, "candidates", f"{name}_{tag}{ext}")
        if os.path.exists(p):
            return Image.open(p)
    return None


def opt(p):
    return Image.open(p) if os.path.exists(p) else None


def main():
    global HERE
    ap = argparse.ArgumentParser()
    ap.add_argument("--stock-apk", default=DEFAULT_APK)
    ap.add_argument("--work", default=HERE, help="dir holding candidates/, frames/, picks.json")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    HERE = os.path.abspath(a.work)
    a.out = a.out or os.path.join(HERE, "contact_sheet.png")
    z = zipfile.ZipFile(a.stock_apk)
    stock = lambda n: Image.open(io.BytesIO(z.read(n))) if n in z.namelist() else None
    picks = json.load(open(os.path.join(HERE, "picks.json")))
    f_big, f_small = font(18), font(14)
    cols = ["stock (HiBy)", "candidate a", "candidate b", "new frame 1", "new mid frame"]
    rows = list(FRAMES) + ["shutdown_bg"]
    rh = [CELL if r != "shutdown_bg" else 427 for r in rows]
    W = PAD + len(cols) * (CELL + PAD) + 200
    H = PAD + LABEL + sum(h + PAD for h in rh)
    sheet = Image.new("RGBA", (W, H), BG + (255,))
    d = ImageDraw.Draw(sheet)
    for i, c in enumerate(cols):
        d.text((200 + PAD + i * (CELL + PAD), PAD), c, fill=(200, 210, 220), font=f_small)
    y = PAD + LABEL
    for r, h in zip(rows, rh):
        d.text((PAD, y + h // 2 - 10), r, fill=TEAL, font=f_big)
        if r == "shutdown_bg":
            cells = [stock("res/drawable-xhdpi-v4/shutdown_bg.png"), cand(r, "a"), cand(r, "b"),
                     opt(os.path.join(HERE, "frames/drawable-xhdpi/shutdown_bg.png")), None]
        else:
            pre = FRAMES[r]
            mid = COUNTS[pre] // 2 + 1
            cells = [stock(f"res/drawable-hdpi-v4/{pre}01.png"), cand(r, "a"), cand(r, "b"),
                     opt(os.path.join(HERE, f"frames/drawable-hdpi/{pre}01.png")),
                     opt(os.path.join(HERE, f"frames/drawable-hdpi/{pre}{mid:02d}.png"))]
        for i, im in enumerate(cells):
            x = 200 + PAD + i * (CELL + PAD)
            sheet.alpha_composite(tile(im, (CELL, h)), (x, y))
            if im is None and i in (1, 2, 3):
                d.text((x + 10, y + 10), "not generated", fill=(120, 120, 130), font=f_small)
            if i in (1, 2) and picks.get(r) == "ab"[i - 1] and im is not None:
                d.rectangle((x - 3, y - 3, x + CELL + 2, y + h + 2), outline=TEAL, width=3)
        y += h + PAD
    sheet.convert("RGB").save(a.out, optimize=True)
    print("wrote", a.out)


if __name__ == "__main__":
    main()
