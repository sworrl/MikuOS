"""MikuOS wordmark for the full-screen splash images, drawn with PIL so the model never renders text.

draw_wordmark(img, center_y_frac) draws "Miku" in teal and "OS" in pink, Orbitron, with a soft glow,
centred horizontally. Sizes scale with the image width, so the same call works at 720x1280 and
1440x2560. Font: Orbitron (SIL OFL), already shipped in the app module.
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.normpath(os.path.join(
    HERE, "../../../miku-player-kotlin/app/src/main/res/font/orbitron.ttf"))
TEAL = (0x39, 0xC5, 0xBB)
PINK = (0xFF, 0x5F, 0xA2)
BG = (0x0B, 0x14, 0x18)


def _font(px):
    f = ImageFont.truetype(FONT, px)
    try:
        f.set_variation_by_name("Bold")
    except Exception:
        pass
    return f


def wordmark_layer(size, center_y, alpha=1.0):
    """RGBA layer (size) with the wordmark centred at center_y px. alpha 0..1 fades it."""
    w, h = size
    font = _font(round(w * 0.135))
    parts = (("Miku", TEAL), ("OS", PINK))
    gap = round(w * 0.006)
    widths = [font.getbbox(t)[2] - font.getbbox(t)[0] for t, _ in parts]
    total = sum(widths) + gap
    top, bottom = font.getbbox("MikuOS")[1], font.getbbox("MikuOS")[3]
    x = (w - total) // 2
    y = round(center_y - (top + bottom) / 2)
    text = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(text)
    for (t, c), tw in zip(parts, widths):
        d.text((x - font.getbbox(t)[0], y), t, font=font, fill=c + (255,))
        x += tw + gap
    glow = text.filter(ImageFilter.GaussianBlur(w * 0.018))
    glow.putalpha(glow.getchannel("A").point(lambda v: int(v * 0.9)))
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    out.alpha_composite(glow)
    out.alpha_composite(text)
    if alpha < 1.0:
        out.putalpha(out.getchannel("A").point(lambda v: int(v * max(0.0, alpha))))
    return out


def draw_wordmark(img, center_y_frac=0.84, alpha=1.0):
    base = img.convert("RGBA")
    base.alpha_composite(wordmark_layer(base.size, round(base.height * center_y_frac), alpha))
    return base.convert("RGB")
