#!/usr/bin/env python3
"""
Builds the Riot skin's font sheets and icons into src/main/assets/riot/.

Everything the LCD draws comes from these files, so the look can be replaced as data:
drop in a different sheet + JSON (for example glyphs recovered from the original firmware)
and nothing in the Kotlin changes.

FONTS. large/medium/small are rasterized from Liberation Sans (SIL Open Font License 1.1,
Reserved Font Name "Liberation") with FreeType's monochrome renderer, then cropped to ink and
given a fixed 1 px letter gap, the way LCD firmware fonts are spaced. The output is a modified
version under the OFL, renamed "Riot Sans" as the license requires; see assets/riot/FONTS.txt.
"tiny" is hand-drawn below on a 5 px grid.

ICONS. Hand-drawn below as '#'/'.' rows. The logo is NOT made here: it is a single file,
assets/riot/logo_rioriot.png, so it can be swapped or removed on its own.

Sheet format (both fonts and icons): PNG, black ink on transparent. Font JSON:
  {"name", "height", "ascent", "space", "glyphs": {"A": {"x", "w", "ox", "adv"}, ...}}
x/w locate the glyph in the one-row sheet (full height), ox shifts it right when drawn,
adv is the pen advance. Optional "bold": true marks a sheet that is already bold.

Usage: python3 -I tools/make_riot_assets.py   (needs Pillow and the Liberation fonts)
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "src", "main", "assets", "riot")
LIB = "/usr/share/fonts/truetype/liberation/"

CHARS = [chr(c) for c in range(32, 127)] + [chr(c) for c in range(0xA0, 0x100)] + list("•–—‘’“”…™")


def rasterize(ttf, px, name, tabular_digits=False):
    font = ImageFont.truetype(ttf, px)
    ascent, descent = font.getmetrics()
    height = ascent + descent
    cells = []
    for ch in CHARS:
        img = Image.new("L", (px * 3, height), 0)
        d = ImageDraw.Draw(img)
        d.fontmode = "1"
        d.text((px, 0), ch, font=font, fill=255)
        bbox = img.getbbox()
        if bbox is None:
            cells.append((ch, None, 0, 0))
            continue
        x0, _, x1, _ = bbox
        glyph = img.crop((x0, 0, x1, height))
        cells.append((ch, glyph, x1 - x0, 0))
    space = max(2, round(px * 0.28))
    digit_w = max(c[2] for c in cells if c[0].isdigit())
    sheet_w = sum((c[2] or 1) + 1 for c in cells)
    sheet = Image.new("RGBA", (sheet_w, height), (0, 0, 0, 0))
    meta = {}
    x = 0
    for ch, glyph, w, _ in cells:
        if glyph is None:
            if ch in (" ", " "):
                meta[ch] = {"x": x, "w": 0, "ox": 0, "adv": space}
            x += 2
            continue
        ink = Image.new("RGBA", glyph.size, (0, 0, 0, 255))
        sheet.paste(ink, (x, 0), glyph)
        ox, adv = 0, w + 1
        if tabular_digits and ch.isdigit():
            ox = (digit_w - w) // 2
            adv = digit_w + 2
        meta[ch] = {"x": x, "w": w, "ox": ox, "adv": adv}
        x += w + 1
    sheet.save(os.path.join(OUT, f"font_{name}.png"))
    with open(os.path.join(OUT, f"font_{name}.json"), "w") as f:
        json.dump({"name": name, "height": height, "ascent": ascent, "space": space, "glyphs": meta},
                  f, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    print(f"font_{name}: {px}px height={height} ascent={ascent} glyphs={len(meta)} sheet={sheet_w}x{height}")


# A 5-row label face for the little tags: RND, TUNED, -01:05, the dial numbers, E LOW F.
TINY = {
    "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#", "##", ".#", ".#", ".#"],
    "2": ["###", "..#", "###", "#..", "###"], "3": ["###", "..#", ".##", "..#", "###"],
    "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "###", "..#", "###"],
    "6": ["###", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."],
    "8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "###"],
    "A": [".#.", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."],
    "C": [".##", "#..", "#..", "#..", ".##"], "D": ["##.", "#.#", "#.#", "#.#", "##."],
    "E": ["###", "#..", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#..", "#.."],
    "G": [".##", "#..", "#.#", "#.#", ".##"], "H": ["#.#", "#.#", "###", "#.#", "#.#"],
    "I": ["###", ".#.", ".#.", ".#.", "###"], "J": ["..#", "..#", "..#", "#.#", ".#."],
    "K": ["#.#", "#.#", "##.", "#.#", "#.#"], "L": ["#..", "#..", "#..", "#..", "###"],
    "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"], "N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
    "O": [".#.", "#.#", "#.#", "#.#", ".#."], "P": ["##.", "#.#", "##.", "#..", "#.."],
    "Q": [".#.", "#.#", "#.#", "#.#", ".##"], "R": ["##.", "#.#", "##.", "#.#", "#.#"],
    "S": [".##", "#..", ".#.", "..#", "##."], "T": ["###", ".#.", ".#.", ".#.", ".#."],
    "U": ["#.#", "#.#", "#.#", "#.#", "###"], "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
    "W": ["#...#", "#...#", "#.#.#", "##.##", "#...#"], "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
    "Y": ["#.#", "#.#", ".#.", ".#.", ".#."], "Z": ["###", "..#", ".#.", "#..", "###"],
    "-": ["..", "..", "##", "..", ".."], "+": ["...", ".#.", "###", ".#.", "..."],
    ":": [".", "#", ".", "#", "."], ".": [".", ".", ".", ".", "#"], "/": ["..#", "..#", ".#.", "#..", "#.."],
}


def tiny():
    height = 5
    order = sorted(TINY)
    sheet_w = sum(len(TINY[c][0]) + 1 for c in order)
    sheet = Image.new("RGBA", (sheet_w, height), (0, 0, 0, 0))
    meta = {}
    x = 0
    for c in order:
        rows = TINY[c]
        w = len(rows[0])
        for r, line in enumerate(rows):
            for cx, p in enumerate(line):
                if p == "#":
                    sheet.putpixel((x + cx, r), (0, 0, 0, 255))
        meta[c] = {"x": x, "w": w, "ox": 0, "adv": w + 1}
        x += w + 1
    meta[" "] = {"x": 0, "w": 0, "ox": 0, "adv": 2}
    sheet.save(os.path.join(OUT, "font_tiny.png"))
    with open(os.path.join(OUT, "font_tiny.json"), "w") as f:
        json.dump({"name": "tiny", "height": height, "ascent": height, "space": 2, "glyphs": meta},
                  f, separators=(",", ":"), sort_keys=True)
    print("font_tiny:", len(meta), "glyphs")


ICONS = {
    # Speaker with two sound arcs, left of the volume bar.
    "speaker": ["...#.......", "..##....#..", "###.#.#..#.", "#...#..#.#.", "#...#..#.#.",
                "#...#..#.#.", "###.#.#..#.", "..##....#..", "...#......."],
    "check": ["......#", ".....##", "#...##.", "##.##..", ".###...", "..#...."],
    "usb": ["......#......", ".....#.....##", "#############", "....#......##", ".....##......"],
    "pointer": ["#####", ".###.", "..#.."],
    "lock": [".###.", "#...#", "#...#", "#####", "##.##", "##.##", "#####"],
}


def shape_icons():
    # Big transport glyphs, same box as the play triangle on Now Playing (13 x 15).
    play = [("#" * (min(r, 14 - r) + 1)).ljust(8, ".") for r in range(15)]
    pause = ["####.####"] * 15
    stop = ["#############"] * 13
    ICONS["play"] = play
    ICONS["pause"] = pause
    ICONS["stop"] = stop


def icons():
    shape_icons()
    os.makedirs(os.path.join(OUT, "icons"), exist_ok=True)
    for name, rows in ICONS.items():
        w = max(len(r) for r in rows)
        img = Image.new("RGBA", (w, len(rows)), (0, 0, 0, 0))
        for y, line in enumerate(rows):
            for x, p in enumerate(line):
                if p == "#":
                    img.putpixel((x, y), (0, 0, 0, 255))
        img.save(os.path.join(OUT, "icons", f"{name}.png"))
    print("icons:", ", ".join(sorted(ICONS)))


def main():
    os.makedirs(OUT, exist_ok=True)
    reg = LIB + "LiberationSans-Regular.ttf"
    if not os.path.exists(reg):
        sys.exit("Liberation Sans not found at " + LIB)
    rasterize(reg, 19, "large", tabular_digits=True)
    rasterize(reg, 11, "medium")
    rasterize(reg, 10, "small")
    tiny()
    icons()


if __name__ == "__main__":
    main()
