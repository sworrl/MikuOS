#!/usr/bin/env python3
"""Generate the Miku projectM preset library.

These replace the old second renderer (the GLES2 "Miku Shaders" engine). Same look, one engine:
everything is a real MilkDrop .milk preset that projectM plays, so there is no parallel visualiser
with its own preset list, its own settings and its own toggle.

DELIBERATELY NO HLSL warp/comp blocks. Classic per_frame/per_pixel presets are the part of the
format projectM's GLES path handles without question; a hundred hand-written shader blocks would be
a hundred chances to ship a preset that renders black on this device and nothing else.

Families differ in MOTION and RENDER MATH, not hue. Variants inside a family change symmetry,
speed, wave mode, decay and what the audio drives, so two presets from the same family do not look
like the same preset twice.
"""
import os, sys, math

OUT = sys.argv[1] if len(sys.argv) > 1 else "miku-player-kotlin/app/src/main/assets/miku_presets"

# Miku identity palette: teal, bright teal, pink, magenta, white-ish, purple.
PALETTES = [
    ("Teal",     (0.22, 0.77, 0.73), (0.55, 0.93, 0.90)),
    ("Bloom",    (1.00, 0.37, 0.64), (1.00, 0.70, 0.83)),
    ("Duet",     (0.22, 0.77, 0.73), (1.00, 0.37, 0.64)),
    ("Neon",     (0.00, 0.90, 0.80), (0.70, 0.53, 1.00)),
    ("Frost",    (0.62, 0.95, 1.00), (0.90, 0.98, 1.00)),
    ("Midnight", (0.12, 0.30, 0.55), (0.40, 0.85, 0.95)),
]

BASE = {
    "fRating": 5.0, "fGammaAdj": 1.8, "fDecay": 0.97,
    "fVideoEchoZoom": 1.0, "fVideoEchoAlpha": 0.0, "nVideoEchoOrientation": 0,
    "nWaveMode": 0, "bAdditiveWaves": 1, "bWaveDots": 0, "bWaveThick": 1,
    "bModWaveAlphaByVolume": 1, "bMaximizeWaveColor": 1, "bTexWrap": 1,
    "bDarkenCenter": 0, "bRedBlueStereo": 0, "bBrighten": 0, "bDarken": 0,
    "bSolarize": 0, "bInvert": 0,
    "fWaveAlpha": 0.8, "fWaveScale": 1.0, "fWaveSmoothing": 0.75, "fWaveParam": 0.0,
    "fModWaveAlphaStart": 0.71, "fModWaveAlphaEnd": 1.3,
    "fWarpAnimSpeed": 1.0, "fWarpScale": 1.0, "fZoomExponent": 1.0, "fShader": 0.0,
    "zoom": 1.0, "rot": 0.0, "cx": 0.5, "cy": 0.5, "dx": 0.0, "dy": 0.0,
    "warp": 0.01, "sx": 1.0, "sy": 1.0,
    "wave_r": 0.5, "wave_g": 0.5, "wave_b": 0.5, "wave_x": 0.5, "wave_y": 0.5,
    "ob_size": 0.005, "ob_r": 0.0, "ob_g": 0.0, "ob_b": 0.0, "ob_a": 0.0,
    "ib_size": 0.01, "ib_r": 0.25, "ib_g": 0.25, "ib_b": 0.25, "ib_a": 0.0,
    "nMotionVectorsX": 0.0, "nMotionVectorsY": 0.0,
    "mv_dx": 0.0, "mv_dy": 0.0, "mv_l": 0.0, "mv_r": 1.0, "mv_g": 1.0, "mv_b": 1.0, "mv_a": 0.0,
}

def header(over):
    d = dict(BASE); d.update(over)
    # Version 1 EXPLICITLY: a classic per_frame/per_pixel preset with no HLSL warp/comp blocks.
    # Absent, projectM has to infer it; stated, there is nothing to infer and no chance of it
    # looking for shader sections that were never written.
    out = ["[preset00]", "MILKDROP_PRESET_VERSION=1"]
    for k, v in d.items():
        out.append(f"{k}={v:.6f}" if isinstance(v, float) else f"{k}={v}")
    for i in range(4):
        out.append(f"wavecode_{i}_enabled=0")
    for i in range(4):
        out.append(f"shapecode_{i}_enabled=0")
    return out

def shape(idx, **kw):
    d = dict(enabled=1, sides=4, additive=1, thickOutline=0, textured=0,
             x=0.5, y=0.5, rad=0.3, ang=0.0, tex_ang=0.0, tex_zoom=1.0,
             r=1.0, g=1.0, b=1.0, a=0.5, r2=0.0, g2=0.0, b2=0.0, a2=0.0,
             border_r=1.0, border_g=1.0, border_b=1.0, border_a=0.0)
    d.update(kw)
    return [f"shapecode_{idx}_{k}=" + (f"{v:.6f}" if isinstance(v, float) else f"{v}") for k, v in d.items()]

def numbered(prefix, lines):
    return [f"{prefix}_{i+1}={l}" for i, l in enumerate(lines)]

def write(name, lines):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".milk"), "w", newline="\r\n") as f:
        f.write("\n".join(lines) + "\n")

presets = []

def add(family, variant, pal_i, over, per_frame, per_pixel, shapes=(), waves=()):
    pname, c1, c2 = PALETTES[pal_i % len(PALETTES)]
    head = header(over)
    # Colour is set from the palette in per_frame so every family reads as Miku, not as a random hue.
    col = [
        f"mk1r = {c1[0]:.3f}; mk1g = {c1[1]:.3f}; mk1b = {c1[2]:.3f};",
        f"mk2r = {c2[0]:.3f}; mk2g = {c2[1]:.3f}; mk2b = {c2[2]:.3f};",
        "mix = 0.5 + 0.5*sin(time*0.37) * 0.6 + bass_att*0.25;",
        "mix = min(1, max(0, mix));",
        "wave_r = mk1r + (mk2r - mk1r)*mix;",
        "wave_g = mk1g + (mk2g - mk1g)*mix;",
        "wave_b = mk1b + (mk2b - mk1b)*mix;",
    ]
    body = head + numbered("per_frame", col + list(per_frame))
    if per_pixel:
        body += numbered("per_pixel", list(per_pixel))
    for i, sh in enumerate(shapes):
        body += shape(i, **sh)
    for i, w in enumerate(waves):
        body += w
    title = f"Miku - {family} {variant} ({pname})"
    write(title, body)
    presets.append(title)

# ----------------------------------------------------------------- 1. Negi Rain
# Vertical streaks falling past the camera, speed on the beat.
for i in range(8):
    speed = 0.012 + 0.004 * i
    add("Negi Rain", f"{i+1:02d}", i,
        {"fDecay": 0.94 + 0.005 * (i % 4), "nWaveMode": 2 if i % 2 else 7,
         "fWaveScale": 0.6 + 0.12 * i, "bTexWrap": 1, "fVideoEchoAlpha": 0.18 if i % 3 == 0 else 0.0,
         "fVideoEchoZoom": 1.004, "zoom": 1.0, "warp": 0.02 + 0.01 * (i % 3)},
        [f"dy = {speed:.4f} + bass*{0.010 + 0.003*i:.4f};",
         "dx = 0.0006*sin(time*0.6);",
         f"rot = {0.004*((i%3)-1):.4f};",
         "decay = 0.93 + 0.05*treb_att;",
         "wave_a = 0.7 + 0.3*mid;"],
        [f"zoom = 1 + 0.02*sin(rad*{6+i} - time*1.4)*bass_att;",
         f"dy = dy + 0.010*(1 - abs(sin(x*{3.0+0.7*i:.2f}*3.1416)));"])

# ----------------------------------------------------------------- 2. Twintail Flow
# Two counter-rotating spirals offset from centre.
for i in range(8):
    add("Twintail Flow", f"{i+1:02d}", i + 1,
        {"fDecay": 0.965, "nWaveMode": 1 if i % 2 else 4, "fWaveScale": 1.2 + 0.2 * i,
         "fWarpAnimSpeed": 1.2 + 0.25 * i, "warp": 0.35 + 0.08 * i, "zoom": 0.995},
        [f"rot = {0.02 + 0.006*i:.4f}*sin(time*0.42) + mid_att*0.02;",
         "cx = 0.5 + 0.13*sin(time*0.31);",
         "cy = 0.5 + 0.09*cos(time*0.27);",
         "decay = 0.955 + 0.03*bass_att;",
         "wave_a = 0.55 + 0.45*treb;"],
        [f"ang = ang + 0.10*sin(rad*{4+i} + time)*bass_att;",
         "rad = rad*(1 - 0.02*sin(time*0.7));",
         f"zoom = 1 + 0.03*cos(ang*{2+(i%4)}) * (0.4 + bass_att);"])

# ----------------------------------------------------------------- 3. Hatsune Bloom
# Radial petal bloom, driven by shapes on the beat.
for i in range(8):
    sides = 5 + (i % 6)
    add("Hatsune Bloom", f"{i+1:02d}", i + 2,
        {"fDecay": 0.975, "nWaveMode": 6, "bAdditiveWaves": 1, "fWaveScale": 0.8,
         "zoom": 1.004, "warp": 0.08, "bDarkenCenter": 1 if i % 2 else 0},
        [f"q1 = 0.3 + bass_att*0.7;",
         f"rot = {0.003*(i-4):.4f};",
         "decay = 0.97;",
         "wave_a = 0.4 + 0.6*bass;"],
        [f"rad = rad + 0.03*sin(ang*{sides} + time*1.1)*q1;",
         "zoom = 1 + 0.015*q1;"],
        shapes=[dict(sides=sides, rad=0.18, a=0.35, additive=1,
                     r=0.2, g=0.85, b=0.8, r2=1.0, g2=0.4, b2=0.7, a2=0.0),
                dict(sides=sides, rad=0.32, a=0.18, additive=1, ang=0.4,
                     r=1.0, g=0.4, b=0.7, r2=0.2, g2=0.85, b2=0.8, a2=0.0)])

# ----------------------------------------------------------------- 4. Vocaloid Circuit
# Orthogonal traces on a grid, treble-lit.
for i in range(8):
    grid = 6 + 2 * (i % 5)
    add("Vocaloid Circuit", f"{i+1:02d}", (i + 3),
        {"fDecay": 0.90 + 0.01 * (i % 5), "nWaveMode": 3, "bTexWrap": 0,
         "fVideoEchoAlpha": 0.35, "fVideoEchoZoom": 0.998, "nVideoEchoOrientation": i % 4,
         "warp": 0.0, "zoom": 1.0, "fWaveScale": 1.6},
        ["decay = 0.89 + 0.09*treb_att;",
         f"dx = {0.002*((i%3)-1):.4f};",
         f"dy = {0.002*(((i+1)%3)-1):.4f};",
         "wave_a = 0.3 + 0.7*treb;"],
        [f"dx = dx + 0.004*(above(sin(y*{grid}*3.1416), 0.94));",
         f"dy = dy + 0.004*(above(sin(x*{grid}*3.1416), 0.94));",
         "zoom = 1.0;"])

# ----------------------------------------------------------------- 5. Miku Vortex
# Classic inward tunnel with a breathing rotation.
for i in range(8):
    add("Miku Vortex", f"{i+1:02d}", i,
        {"fDecay": 0.98, "nWaveMode": 0, "fWaveScale": 1.0, "bDarkenCenter": 1,
         "warp": 0.12 + 0.05 * i, "zoom": 1.02 + 0.006 * i, "fZoomExponent": 1.0 + 0.08 * (i % 4)},
        [f"zoom = {1.018 + 0.004*i:.4f} + bass_att*0.02;",
         f"rot = {0.008 + 0.004*i:.4f}*sin(time*0.5);",
         "decay = 0.975 + 0.02*mid_att;",
         "wave_a = 0.6 + 0.4*bass_att;"],
        ["zoom = zoom + 0.01*sin(rad*8 - time*2)*bass_att;",
         f"ang = ang + {0.02 + 0.01*(i%4):.4f}*rad;"])

# ----------------------------------------------------------------- 6. Leek Spin
# One ribbon orbiting the frame, high echo for the trail.
for i in range(8):
    add("Leek Spin", f"{i+1:02d}", i + 1,
        {"fDecay": 0.93, "nWaveMode": 5, "bWaveThick": 1, "fWaveScale": 0.5 + 0.15 * i,
         "fVideoEchoAlpha": 0.45, "fVideoEchoZoom": 1.01, "warp": 0.02, "zoom": 0.998},
        [f"wave_x = 0.5 + 0.33*sin(time*{0.7 + 0.15*i:.2f});",
         f"wave_y = 0.5 + 0.33*cos(time*{0.9 + 0.13*i:.2f});",
         "wave_a = 0.85;",
         "decay = 0.92 + 0.06*bass_att;",
         f"rot = {0.01*((i%5)-2):.4f};"],
        ["zoom = 1 - 0.004*rad;"])

# ----------------------------------------------------------------- 7. Crystal Chorus
# Kaleidoscope facets, mid-driven.
for i in range(8):
    facets = 3 + (i % 8)
    add("Crystal Chorus", f"{i+1:02d}", i + 4,
        {"fDecay": 0.985, "nWaveMode": 7, "fWaveScale": 1.1, "bTexWrap": 0,
         "warp": 0.22, "zoom": 1.0, "fGammaAdj": 2.1},
        [f"q1 = {facets};",
         "decay = 0.98 + 0.015*mid_att;",
         "rot = 0.004*sin(time*0.23);",
         "wave_a = 0.5 + 0.5*mid;"],
        [f"ang = int(ang*{facets}/6.2832)*6.2832/{facets};",
         "rad = rad + 0.02*sin(rad*12 - time)*mid_att;",
         "zoom = 1 + 0.01*cos(rad*10);"])

# ----------------------------------------------------------------- 8. Neon Stage
# Horizontal spectrum bars sweeping across the stage.
for i in range(8):
    add("Neon Stage", f"{i+1:02d}", (i + 5),
        {"fDecay": 0.88, "nWaveMode": 3, "bWaveDots": 1 if i % 3 == 0 else 0,
         "fWaveScale": 2.0 + 0.3 * i, "bTexWrap": 0, "warp": 0.0, "zoom": 1.0,
         "fVideoEchoAlpha": 0.25, "nVideoEchoOrientation": 1},
        ["decay = 0.86 + 0.12*bass_att;",
         f"dy = {-0.004 - 0.002*(i%4):.4f};",
         "wave_a = 0.9;",
         "wave_y = 0.5;"],
        [f"dx = 0.006*sin(y*{8 + 2*i}*3.1416 + time*2);",
         "zoom = 1.0;"])

# ----------------------------------------------------------------- 9. Tidal Teal
# Slow fluid warp, no hard edges.
for i in range(8):
    add("Tidal Teal", f"{i+1:02d}", i,
        {"fDecay": 0.99, "nWaveMode": 4, "fWaveScale": 0.9, "warp": 0.55 + 0.1 * i,
         "fWarpAnimSpeed": 0.4 + 0.12 * i, "zoom": 1.0, "fGammaAdj": 1.6},
        ["decay = 0.988;",
         "cx = 0.5 + 0.06*sin(time*0.17);",
         "cy = 0.5 + 0.06*cos(time*0.21);",
         "wave_a = 0.35 + 0.35*bass;",
         f"rot = {0.002*((i%5)-2):.4f};"],
        [f"dx = 0.004*sin(y*{2+i}*3.1416 + time*0.7);",
         f"dy = 0.004*cos(x*{2+i}*3.1416 - time*0.6);",
         "zoom = 1 + 0.004*sin(rad*4 - time*0.5);"])

# ----------------------------------------------------------------- 10. Star Aria
# Starfield bursting outward on the beat.
for i in range(8):
    add("Star Aria", f"{i+1:02d}", i + 2,
        {"fDecay": 0.955, "nWaveMode": 2, "bWaveDots": 1, "fWaveScale": 0.35 + 0.1 * i,
         "bDarkenCenter": 1, "warp": 0.01, "zoom": 0.985 - 0.004 * i,
         "fVideoEchoAlpha": 0.3, "fVideoEchoZoom": 0.995},
        [f"zoom = {0.982 - 0.003*i:.4f} - bass_att*0.02;",
         "decay = 0.95;",
         "rot = 0.001*sin(time*0.13);",
         "wave_a = 0.8 + 0.2*treb;"],
        ["zoom = zoom - 0.01*bass_att*(1-rad);",
         f"ang = ang + 0.005*sin(time*0.4)*{1+(i%4)};"])

print(f"{len(presets)} Miku presets written to {OUT}")
