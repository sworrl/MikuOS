#!/usr/bin/env python3
"""Blur named rectangles in a screenshot, leaving the rest of the image untouched.

Used to strip PII (SSIDs, BSSIDs, IP addresses, the user's town) out of the M500
screenshots that go in the public README, without flattening the whole panel to a
grey box. A heavy Gaussian over just the text keeps the layout, the colours and the
component shapes readable, which is the point of the screenshot.
"""
import sys
from PIL import Image, ImageFilter

def blur_regions(src, dst, boxes, radius=14):
    im = Image.open(src).convert("RGB")
    for (x0, y0, x1, y1) in boxes:
        x0, y0 = max(0, x0), max(0, y0)
        x1, y1 = min(im.width, x1), min(im.height, y1)
        if x1 <= x0 or y1 <= y0:
            continue
        region = im.crop((x0, y0, x1, y1))
        # Blur at 4x downscale first: a plain Gaussian at this radius still leaves
        # letter shapes guessable on high-contrast terminal-style text.
        w, h = region.size
        small = region.resize((max(1, w // 6), max(1, h // 6)), Image.BILINEAR)
        region = small.resize((w, h), Image.NEAREST).filter(ImageFilter.GaussianBlur(radius))
        im.paste(region, (x0, y0))
    im.save(dst)
    print(f"wrote {dst}  ({len(boxes)} regions)")

if __name__ == "__main__":
    print("import and call blur_regions()")
