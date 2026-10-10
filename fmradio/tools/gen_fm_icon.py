#!/usr/bin/env python3
"""Miku FM launcher icon generator.

One shape list drives everything: the VectorDrawable XMLs that ship in
fmradio/src/main/res, an SVG twin for rendering, the legacy PNG mipmaps and the
preview sheets. Run:  python3 gen_fm_icon.py [--write-res]
"""
import io, math, os, sys
import cairo
import gi
gi.require_version("Rsvg", "2.0")
from gi.repository import Rsvg
from PIL import Image, ImageDraw

RES = "/home/reaver/Documents/GitHub/m500/miku-player-kotlin/fmradio/src/main/res"
OUT = "/home/reaver/mikuos-scratch/fm-icon"

TEAL = "#39C5BB"
TEAL_DK = "#2A9D95"
TEAL_LT = "#7FE3DA"
PINK = "#FF5FA2"
DARK = "#0B1418"


def argb(c, a=1.0):
    """#RRGGBB -> #AARRGGBB for VectorDrawable."""
    return "#%02X%s" % (round(a * 255), c[1:].upper())


# ---------------------------------------------------------------------------
# Shapes. Coordinates are in the 108x108 adaptive-icon canvas. Everything that
# matters sits inside the 66 dp safe circle centred on 54,54.
# Keys: d, fill, fill_alpha, stroke, width, cap, join, grad (x1,y1,x2,y2,c1,c2),
# evenodd
# ---------------------------------------------------------------------------

BG = [
    dict(d="M0,0h108v108h-108z", grad=(54, 0, 54, 108, "#17474D", DARK)),
    # faint scanlines, same panel texture as the other MikuOS adaptive icons
    dict(d="M18,32h72M18,44h72M18,56h72M18,68h72M18,80h72",
         stroke=TEAL, stroke_alpha=0.08, width=1),
]

# Twin tails: teal hair hanging off the radio's top corners, tied with pink.
TAIL_L = ("M37,45 C32,38.5 23,38.5 20,46 C17.5,52.5 18.5,63 21.5,71 "
          "C23,75 25,78.5 28,81 C26.8,76.5 27,71.5 28.2,67 C29.6,61 31.4,56 33.4,51.5 "
          "C34.4,49 35.6,47 37,45 Z")
TAIL_R = ("M71,45 C76,38.5 85,38.5 88,46 C90.5,52.5 89.5,63 86.5,71 "
          "C85,75 83,78.5 80,81 C81.2,76.5 81,71.5 79.8,67 C78.4,61 76.6,56 74.6,51.5 "
          "C73.6,49 72.4,47 71,45 Z")
# a lighter strand inside each tail for some volume
STRAND_L = "M29,43.5 C24.5,45 22.5,51 22.8,58 C23,65 24.5,71 26.5,76"
STRAND_R = "M79,43.5 C83.5,45 85.5,51 85.2,58 C85,65 83.5,71 81.5,76"

BODY = "M38,46h32a6,6 0,0 1,6 6v18a6,6 0,0 1,-6 6h-32a6,6 0,0 1,-6 -6v-18a6,6 0,0 1,6 -6z"
HANDLE = "M44,46v-5a3,3 0,0 1,3 -3h14a3,3 0,0 1,3 3v5"
ANTENNA = "M64,46L71,29"
ANT_TIP = "M71,29m-2.6,0a2.6,2.6 0,1 0,5.2 0a2.6,2.6 0,1 0,-5.2 0z"
WAVES = "M66.8,25.6a5,5 0,0 0,0 6.8M63.6,22.6a9.5,9.5 0,0 0,0 12.8M75.2,25.6a5,5 0,0 1,0 6.8M78.4,22.6a9.5,9.5 0,0 1,0 12.8"
SPK_RING = "M45,61m-8,0a8,8 0,1 0,16 0a8,8 0,1 0,-16 0z"
SPK_CORE = "M45,61m-3.2,0a3.2,3.2 0,1 0,6.4 0a3.2,3.2 0,1 0,-6.4 0z"
DISPLAY = "M57.5,51h12a2,2 0,0 1,2 2v8a2,2 0,0 1,-2 2h-12a2,2 0,0 1,-2 -2v-8a2,2 0,0 1,2 -2z"
TICKS = "M58,59.5v2M60,60.3v1.2M62,59.5v2M64,60.3v1.2M66,59.5v2M68,60.3v1.2M69.4,59.5v2"
NEEDLE = "M64.6,52.6v9"
KNOB_L = "M59,69m-2.3,0a2.3,2.3 0,1 0,4.6 0a2.3,2.3 0,1 0,-4.6 0z"
KNOB_R = "M68,69m-2.3,0a2.3,2.3 0,1 0,4.6 0a2.3,2.3 0,1 0,-4.6 0z"
TIE_L = "M34.5,44m-3.4,0a3.4,3.4 0,1 0,6.8 0a3.4,3.4 0,1 0,-6.8 0z"
TIE_R = "M73.5,44m-3.4,0a3.4,3.4 0,1 0,6.8 0a3.4,3.4 0,1 0,-6.8 0z"

FG = [
    dict(d=TAIL_L, grad=(28, 40, 24, 81, TEAL_LT, "#1E9A92")),
    dict(d=TAIL_R, grad=(80, 40, 84, 81, TEAL_LT, "#1E9A92")),
    dict(d=STRAND_L, stroke=TEAL_DK, width=1.3, cap="round"),
    dict(d=STRAND_R, stroke=TEAL_DK, width=1.3, cap="round"),
    dict(d=HANDLE, stroke=TEAL, width=3.2, cap="round", join="round"),
    dict(d=ANTENNA, stroke="#C9D6D8", width=2.2, cap="round"),
    dict(d=WAVES, stroke=PINK, width=2, cap="round"),
    dict(d=BODY, grad=(54, 46, 54, 76, "#1E5359", "#123036"), stroke=TEAL, width=2.6),
    dict(d=SPK_RING, fill=DARK, stroke=PINK, width=2.4),
    dict(d=SPK_CORE, fill=PINK),
    dict(d=DISPLAY, fill=DARK, stroke=TEAL, width=1.2),
    dict(d=TICKS, stroke=TEAL, width=0.9),
    dict(d=NEEDLE, stroke=PINK, width=1.4, cap="round"),
    dict(d=KNOB_L, fill=TEAL),
    dict(d=KNOB_R, fill=TEAL),
    dict(d=ANT_TIP, fill=PINK),
    dict(d=TIE_L, fill=PINK),
    dict(d=TIE_R, fill=PINK),
]

# Monochrome (themed icons): one colour, the system uses alpha only. Dark fills
# are dropped so the speaker, display and knobs read as cut-outs.
W = "#FFFFFF"
MONO = [
    dict(d=TAIL_L, fill=W),
    dict(d=TAIL_R, fill=W),
    dict(d=HANDLE, stroke=W, width=3.2, cap="round", join="round"),
    dict(d=ANTENNA, stroke=W, width=2.2, cap="round"),
    dict(d=WAVES, stroke=W, width=2, cap="round"),
    dict(d=BODY, stroke=W, width=2.8),
    dict(d=SPK_RING, stroke=W, width=2.4),
    dict(d=SPK_CORE, fill=W),
    dict(d=DISPLAY, stroke=W, width=1.4),
    dict(d=NEEDLE, stroke=W, width=1.4, cap="round"),
    dict(d=KNOB_L, fill=W),
    dict(d=KNOB_R, fill=W),
    dict(d=ANT_TIP, fill=W),
    dict(d=TIE_L, fill=W),
    dict(d=TIE_R, fill=W),
]

# Status bar icon, 24x24. Solid radio with the speaker and display cut out,
# antenna, and the two tails. evenOdd makes the holes.
STAT = [
    dict(d=("M3.6,10.2 C1.6,10.6 0.8,13 1,15.2 C1.2,17 2,18.4 3.4,19.4 "
            "C3,17.6 3.1,15.6 3.6,14 Z"), fill=W),
    dict(d=("M20.4,10.2 C22.4,10.6 23.2,13 23,15.2 C22.8,17 22,18.4 20.6,19.4 "
            "C21,17.6 20.9,15.6 20.4,14 Z"), fill=W),
    dict(d=("M6,9h12a2,2 0,0 1,2 2v7a2,2 0,0 1,-2 2h-12a2,2 0,0 1,-2 -2v-7a2,2 0,0 1,2 -2z"
            "M8.5,11.6a2.9,2.9 0,1 0,0.01 0z"
            "M13,11.5h4.5v3h-4.5z"), fill=W, evenodd=True),
    dict(d="M8.5,13.6m-1.1,0a1.1,1.1 0,1 0,2.2 0a1.1,1.1 0,1 0,-2.2 0z", fill=W),
    dict(d="M14.5,9L18.5,3.2", stroke=W, width=1.6, cap="round"),
    dict(d="M18.6,3m-1.5,0a1.5,1.5 0,1 0,3 0a1.5,1.5 0,1 0,-3 0z", fill=W),
]


# Scale/offset applied to the foreground and monochrome layers so the art sits
# inside the safe circle: (scale about the centre, translateX, translateY).
FG_XFORM = (0.9, 0, 3)
XFORM = {id(FG): FG_XFORM, id(MONO): FG_XFORM}

# ---------------------------------------------------------------------------
# Emitters
# ---------------------------------------------------------------------------

def vd(shapes, size_dp, vp, comment="", xform=None):
    has_grad = any("grad" in s for s in shapes)
    out = ['<?xml version="1.0" encoding="utf-8"?>']
    if comment:
        out.append("<!-- %s -->" % comment)
    ns = ' xmlns:aapt="http://schemas.android.com/aapt"' if has_grad else ""
    out.append('<vector xmlns:android="http://schemas.android.com/apk/res/android"%s' % ns)
    out.append('    android:width="%ddp" android:height="%ddp"' % (size_dp, size_dp))
    out.append('    android:viewportWidth="%d" android:viewportHeight="%d">' % (vp, vp))
    ind = "    "
    if xform:
        sc, tx, ty = xform
        out.append('    <group android:pivotX="%g" android:pivotY="%g" android:scaleX="%g"'
                   ' android:scaleY="%g" android:translateX="%g" android:translateY="%g">'
                   % (vp / 2, vp / 2, sc, sc, tx, ty))
    for s in shapes:
        attrs = ['android:pathData="%s"' % s["d"]]
        if "fill" in s:
            attrs.append('android:fillColor="%s"' % argb(s["fill"], s.get("fill_alpha", 1)))
        if "stroke" in s:
            attrs.append('android:strokeColor="%s"' % argb(s["stroke"], s.get("stroke_alpha", 1)))
            attrs.append('android:strokeWidth="%g"' % s["width"])
            if "cap" in s:
                attrs.append('android:strokeLineCap="%s"' % s["cap"])
            if "join" in s:
                attrs.append('android:strokeLineJoin="%s"' % s["join"])
        if s.get("evenodd"):
            attrs.append('android:fillType="evenOdd"')
        a = "\n        ".join(attrs)
        if "grad" in s:
            x1, y1, x2, y2, c1, c2 = s["grad"]
            out.append("    <path\n        %s>" % a)
            out.append('        <aapt:attr name="android:fillColor">')
            out.append('            <gradient android:type="linear"')
            out.append('                android:startX="%g" android:startY="%g"' % (x1, y1))
            out.append('                android:endX="%g" android:endY="%g"' % (x2, y2))
            out.append('                android:startColor="%s" android:endColor="%s" />'
                       % (argb(c1), argb(c2)))
            out.append("        </aapt:attr>")
            out.append("    </path>")
        else:
            out.append("    <path\n        %s />" % a)
    if xform:
        out.append("    </group>")
    out.append("</vector>")
    return "\n".join(out) + "\n"


def svg(shapes, vp, xform=None):
    defs, body = [], []
    for i, s in enumerate(shapes):
        a = ['d="%s"' % s["d"]]
        if "grad" in s:
            x1, y1, x2, y2, c1, c2 = s["grad"]
            defs.append('<linearGradient id="g%d" gradientUnits="userSpaceOnUse" '
                        'x1="%g" y1="%g" x2="%g" y2="%g"><stop offset="0" stop-color="%s"/>'
                        '<stop offset="1" stop-color="%s"/></linearGradient>'
                        % (i, x1, y1, x2, y2, c1, c2))
            a.append('fill="url(#g%d)"' % i)
        elif "fill" in s:
            a.append('fill="%s" fill-opacity="%g"' % (s["fill"], s.get("fill_alpha", 1)))
        else:
            a.append('fill="none"')
        if "stroke" in s:
            a.append('stroke="%s" stroke-opacity="%g" stroke-width="%g"'
                     % (s["stroke"], s.get("stroke_alpha", 1), s["width"]))
            a.append('stroke-linecap="%s"' % s.get("cap", "butt"))
            a.append('stroke-linejoin="%s"' % s.get("join", "miter"))
        if s.get("evenodd"):
            a.append('fill-rule="evenodd"')
        body.append("<path %s/>" % " ".join(a))
    g = "".join(body)
    if xform:
        sc, tx, ty = xform
        g = ('<g transform="translate(%g %g) translate(%g %g) scale(%g) translate(%g %g)">%s</g>'
             % (tx, ty, vp / 2, vp / 2, sc, -vp / 2, -vp / 2, g))
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d">'
            '<defs>%s</defs>%s</svg>' % (vp, vp, vp, vp, "".join(defs), g))


def render(shapes, vp, px):
    """Render a shape list to a PIL RGBA image of px x px."""
    h = Rsvg.Handle.new_from_data(svg(shapes, vp, XFORM.get(id(shapes))).encode())
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, px, px)
    ctx = cairo.Context(surf)
    vpr = Rsvg.Rectangle()
    vpr.x, vpr.y, vpr.width, vpr.height = 0, 0, px, px
    h.render_document(ctx, vpr)
    buf = io.BytesIO()
    surf.write_to_png(buf)
    buf.seek(0)
    return Image.open(buf).convert("RGBA")


def mask(px, kind):
    """Launcher masks applied to the 72 dp visible area of a 108 dp canvas."""
    ss = 4
    m = Image.new("L", (px * ss, px * ss), 0)
    dr = ImageDraw.Draw(m)
    n = px * ss
    if kind == "circle":
        dr.ellipse((0, 0, n - 1, n - 1), fill=255)
    elif kind == "squircle":
        dr.rounded_rectangle((0, 0, n - 1, n - 1), radius=int(n * 0.30), fill=255)
    else:  # rounded square
        dr.rounded_rectangle((0, 0, n - 1, n - 1), radius=int(n * 0.16), fill=255)
    return m.resize((px, px), Image.LANCZOS)


def adaptive(px, kind, layers=None):
    """Composite bg+fg like the launcher: render 108 canvas at px*1.5, crop centre 72."""
    full = int(round(px * 108 / 72))
    layers = layers or [BG, FG]
    img = Image.new("RGBA", (full, full), (0, 0, 0, 0))
    for l in layers:
        img = Image.alpha_composite(img, render(l, 108, full))
    off = (full - px) // 2
    img = img.crop((off, off, off + px, off + px))
    out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask(px, kind))
    return out


def tint(img, color):
    r, g, b = int(color[1:3], 16), int(color[3:5], 16), int(color[5:7], 16)
    solid = Image.new("RGBA", img.size, (r, g, b, 255))
    solid.putalpha(img.getchannel("A"))
    return solid


def preview():
    sizes = [24, 32, 48, 72, 96, 144, 192]
    bgs = [("#F2F2F2", "light"), ("#202124", "dark"), ("#0B1418", "mikuos")]
    pad = 16
    W_ = pad + sum(s + pad for s in sizes) + 60
    rows = []
    for col, name in bgs:
        for kind in ("circle", "squircle"):
            rows.append((col, kind, [adaptive(s, kind) for s in sizes]))
    # themed (monochrome) row on light and dark, Material You style
    mono_rows = []
    for col, fgc, bgc in (("#F2F2F2", "#1F4D4A", "#C8EDE9"), ("#202124", "#C8EDE9", "#1F3B3A")):
        imgs = []
        for s in sizes:
            disc = adaptive(s, "circle", layers=[[dict(d="M0,0h108v108h-108z", fill=bgc)]])
            m = tint(adaptive(s, "circle", layers=[MONO]), fgc)
            imgs.append(Image.alpha_composite(disc, m))
        mono_rows.append((col, "themed", imgs))
    stat_rows = []
    for col, fgc in (("#F2F2F2", "#202124"), ("#202124", "#FFFFFF")):
        stat_rows.append((col, "status", [tint(render(STAT, 24, s), fgc) for s in sizes]))
    all_rows = rows + mono_rows + stat_rows
    H_ = pad + sum(max(sizes) + pad for _ in all_rows)
    sheet = Image.new("RGBA", (W_, H_), (255, 255, 255, 255))
    d = ImageDraw.Draw(sheet)
    y = pad
    for col, label, imgs in all_rows:
        d.rectangle((0, y - pad // 2, W_, y + max(sizes) + pad // 2), fill=col)
        x = pad
        for im in imgs:
            sheet.alpha_composite(im, (x, y + (max(sizes) - im.size[1]) // 2))
            x += im.size[0] + pad
        d.text((x, y + max(sizes) // 2), label, fill="#888888")
        y += max(sizes) + pad
    sheet.convert("RGB").save(os.path.join(OUT, "preview_sheet.png"))

    # big single renders
    adaptive(512, "circle").save(os.path.join(OUT, "icon_512_circle.png"))
    adaptive(512, "squircle").save(os.path.join(OUT, "icon_512_squircle.png"))
    full = Image.alpha_composite(render(BG, 108, 648), render(FG, 108, 648))
    dr = ImageDraw.Draw(full)
    c = 324
    r = 33 * 6
    dr.ellipse((c - r, c - r, c + r, c + r), outline="#FF0000")
    dr.rectangle((108, 108, 540, 540), outline="#FFFF00")
    full.save(os.path.join(OUT, "canvas_108_safezone.png"))

    # splash: icon on 0B1418, as Android 12 shows it (icon 160 dp inside 240 dp area)
    sp = Image.new("RGBA", (540, 960), DARK)
    ic = adaptive(240, "circle")
    sp.alpha_composite(ic, ((540 - 240) // 2, (960 - 240) // 2))
    sp.convert("RGB").save(os.path.join(OUT, "splash_mock.png"))


def write_res():
    hdr = "Miku FM launcher icon. Generated by fmradio/tools/gen_fm_icon.py, edit there."
    files = {
        "drawable/ic_launcher_fm_bg.xml": vd(BG, 108, 108, hdr),
        "drawable/ic_launcher_fm_fg.xml": vd(FG, 108, 108, hdr, FG_XFORM),
        "drawable/ic_launcher_fm_mono.xml": vd(MONO, 108, 108, hdr + " Themed-icon layer, alpha only.", FG_XFORM),
        "drawable/ic_stat_fm.xml": vd(STAT, 24, 24, "Status bar icon: plain white silhouette, the system tints it."),
    }
    adaptive_xml = ('<?xml version="1.0" encoding="utf-8"?>\n'
                    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                    '    <background android:drawable="@drawable/ic_launcher_fm_bg" />\n'
                    '    <foreground android:drawable="@drawable/ic_launcher_fm_fg" />\n'
                    '    <monochrome android:drawable="@drawable/ic_launcher_fm_mono" />\n'
                    '</adaptive-icon>\n')
    files["mipmap-anydpi-v26/ic_launcher.xml"] = adaptive_xml
    files["mipmap-anydpi-v26/ic_launcher_round.xml"] = adaptive_xml
    for rel, text in files.items():
        p = os.path.join(RES, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(text)
    for dpi, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        dd = os.path.join(RES, "mipmap-" + dpi)
        os.makedirs(dd, exist_ok=True)
        adaptive(px, "rounded").save(os.path.join(dd, "ic_launcher.png"), optimize=True)
        adaptive(px, "circle").save(os.path.join(dd, "ic_launcher_round.png"), optimize=True)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    preview()
    if "--write-res" in sys.argv:
        write_res()
    print("ok")
