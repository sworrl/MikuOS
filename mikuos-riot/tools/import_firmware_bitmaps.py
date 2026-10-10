#!/usr/bin/env python3
"""
Imports the bitmaps recovered from the Rio Riot 1.25 firmware into the skin's assets.

Source: mikuos/art/rio-riot/extracted/bitmaps/ (see mikuos/docs/rio-riot-firmware.md).

  boot_logo_rio_riot.png  240x55, high confidence  -> assets/riot/logo_rioriot.png (as is)
  usb_connected.png       43x20, high confidence   -> assets/riot/icons/usb_connected.png
  battery_gauge_strip.png 279x9, medium            -> assets/riot/icons/battery_*.png

The battery strip is several 9 px gauges back to back whose row phase drifts from one image
to the next, so it cannot be cut as is. Each gauge was read at the phase where it lines up
and the geometry below is what those reads agree on: "E", a 27 x 9 box with a 2 px terminal
nub, "F"; fills 2 px inside the box, 5 rows tall, 23 px when full; the LOW cell's lettering.
Unsolved and stray pixels were dropped. Fill widths measured off the strip: 23, 18, 11 and 5 px.

The first cell of the strip is the charging gauge. Read with the column stream re-phased by 6
pixels, it is the same E [box] F with six 3 x 5 capitals inside the box: C H A R G E. Most of
the middle-column pixels of those letters land on cipher words the codebook did not solve, so
the letters are drawn here from the clean outer columns.

Ink is black, everything else (white, transparent, the gray "unsolved" marker) is clear.

Usage: python3 -I tools/import_firmware_bitmaps.py
"""
import os
import shutil

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "..", "..", "mikuos", "art", "rio-riot", "extracted", "bitmaps"))
OUT = os.path.join(HERE, "..", "src", "main", "assets", "riot")

E = ["###", "#..", "#..", "###", "#..", "#..", "###"]
F = ["###", "#..", "#..", "###", "#..", "#..", "#.."]
# LOW, as read off the firmware cell (rows 2..6 inside the box, starting 5 px in).
LOW = [
    "#.....##...#...#",
    "#....#..#..#.#.#",
    "#....#..#..#.#.#",
    "#....#..#..#.#.#",
    "####..##....#.#.",
]

# CHARGE, 3 x 5 capitals with 1 px gaps, rows 2..6, starting 2 px inside the box.
CHARGE = [
    ".##.#.#..#..##...##.###",
    "#...#.#.#.#.#.#.#...#..",
    "#...###.###.##..#.#.##.",
    "#...#.#.#.#.#.#.#.#.#..",
    ".##.#.#.#.#.#.#..##.###",
]

W, H = 40, 9
BOX_X, BOX_W = 6, 27


def gauge(fill=None, low=False, charge=False):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ink = (0, 0, 0, 255)

    def put(x, y):
        img.putpixel((x, y), ink)

    for r, row in enumerate(E):
        for c, p in enumerate(row):
            if p == "#":
                put(c, 1 + r)
    for x in range(BOX_X, BOX_X + BOX_W):
        put(x, 0)
        put(x, H - 1)
    for y in range(H):
        put(BOX_X, y)
        put(BOX_X + BOX_W - 1, y)
    nub = BOX_X + BOX_W - 1
    for x in range(nub, nub + 3):
        put(x, 2)
        put(x, 6)
    for y in range(2, 7):
        put(nub + 2, y)
    for r, row in enumerate(F):
        for c, p in enumerate(row):
            if p == "#":
                put(37 + c, 1 + r)
    if fill:
        for x in range(BOX_X + 2, BOX_X + 2 + fill):
            for y in range(2, 7):
                put(x, y)
    if low:
        for r, row in enumerate(LOW):
            for c, p in enumerate(row):
                if p == "#":
                    put(BOX_X + 1 + 5 + c, 2 + r)
    if charge:
        for r, row in enumerate(CHARGE):
            for c, p in enumerate(row):
                if p == "#":
                    put(BOX_X + 2 + c, 2 + r)
    return img


def main():
    icons = os.path.join(OUT, "icons")
    os.makedirs(icons, exist_ok=True)
    shutil.copyfile(os.path.join(SRC, "boot_logo_rio_riot.png"), os.path.join(OUT, "logo_rioriot.png"))
    shutil.copyfile(os.path.join(SRC, "usb_connected.png"), os.path.join(icons, "usb_connected.png"))
    gauge(fill=23).save(os.path.join(icons, "battery_100.png"))
    gauge(fill=18).save(os.path.join(icons, "battery_75.png"))
    gauge(fill=11).save(os.path.join(icons, "battery_50.png"))
    gauge(fill=5).save(os.path.join(icons, "battery_25.png"))
    gauge(low=True).save(os.path.join(icons, "battery_low.png"))
    gauge(charge=True).save(os.path.join(icons, "battery_charging.png"))
    print("imported logo, usb_connected, battery_100/75/50/25/low/charging")


if __name__ == "__main__":
    main()
