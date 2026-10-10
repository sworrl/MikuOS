# MikuOS splash art

Art for the screens the M500 shows outside the launcher: the boot video, the shutdown backdrop, and the
SystemUI popups (headphones in and out, charging, low battery, shutdown, volume warning).

Screen: 720x1280, 320 dpi. Everything here is original art. No HiBy logo, no Crypton logo, no model-drawn text.
The MikuOS wordmark is drawn by `wordmark.py` with Orbitron (SIL OFL), the font the app already ships.

## What goes where

| Image | Size | Ends up in |
|---|---|---|
| `bootanimation.mp4` | 720x1280, 30 fps, 12.5 s, H.264 Main, no audio | `/vendor/media/bootanimation*.mp4` (the build muxes the welcome voice in per locale) |
| `boot_splash.png` | 720x1280 | Last frame of the boot video, kept as a still |
| `boot_splash_master.png` | 1440x2560 | Source for the two above |
| `shutdown_bg.png` | 1440x2560, no alpha | SystemUI `drawable-xhdpi/shutdown_bg` via MikuSplashOverlay |
| Popup frames | 240x240 RGBA, stock names and counts | SystemUI `drawable-hdpi/*` via MikuSplashOverlay |

The popup frames and the backdrop are built by `../hiby-splash/build_frames.py` into
`tools/custom_overlays/MikuSplashOverlay/res/`. See `mikuos/docs/hiby-splash-inventory.md` for every frame.

## Making it

```
cd mikuos/art/hiby-splash
python3 gen.py                      # 2 candidates per image, needs the Glassite key in gcloud
python3 gen.py --only boot_splash --n 3
# look at candidates/, set the letter per image in picks.json
./make_overlay.sh                   # popup frames + shutdown_bg + MikuSplashOverlay.apk
python3 ../splash/make_boot.py      # boot_splash_master.png, boot_splash.png, bootanimation.mp4
```

The boot video fades in from black, pulls back slowly from 106% to 100%, and fades the wordmark in at 1.5 s.

## Prompts

Model: `gemini-3-pro-image` over REST (`generateContent`, `responseModalities: IMAGE`).
The exact text lives in `../hiby-splash/gen.py`. Copies of the main ones:

Boot screen (9:16, 2K):

> Vertical 9:16 full-screen anime illustration for a music player boot screen. An original idol girl character inspired by classic virtual-singer designs: very long flowing teal twin-tails #39C5BB, bright teal eyes, small pink #FF5FA2 hair clips, dark grey and black sleeveless top with a teal collar ribbon, black arm warmers with teal trim, sleek over-ear headphones with soft teal glow resting on her head. Upper body, three-quarter view, gentle happy smile, eyes slightly closed as if enjoying music, one hand lightly touching an ear cup. She fills the upper 65 percent of the frame, her twin-tails sweep down and outward to both sides. Background: deep dark teal-black #0B1418 with a soft teal glow behind her, a few thin flowing light ribbons and small sparkles in teal and pink. The bottom 30 percent of the image is calm, dark, nearly empty background with no character parts. Clean modern anime illustration, crisp line art, cel shading with soft gradients, high detail. No text, no letters, no numbers, no logos, no watermark, no signature.

Shutdown backdrop (9:16, 2K):

> Portrait phone wallpaper, 9:16, for a music player shutdown screen. Very dark teal-black background #0B1418. Thin glowing light ribbons and soft audio waveform lines in teal #39C5BB sweep in from the edges and corners, a few accents of pink #FF5FA2, soft bokeh, faint hexagon grid. The central 60 percent of the image and the bottom 20 percent stay almost empty and dark. Elegant, minimal, high contrast. No characters, no people, no text, no letters, no numbers, no logos, no UI elements, no watermark.

Popup chibis (1:1, 1K): one shared style line plus one scene line per event.

> Chibi anime illustration of an original idol girl character inspired by classic virtual-singer designs (two-heads-tall super-deformed proportions, big sparkling teal eyes, very long teal twin-tails colored #39C5BB, dark grey and black sleeveless top with a teal collar ribbon, short black pleated skirt, black arm warmers with teal trim, small pink #FF5FA2 hair clips and accents). Clean modern anime look: crisp bold line art, cel shading with soft gradients, glossy highlights on hair and props, a thin rim light in teal #39C5BB and pink #FF5FA2 drawn ON the character only. Full body, centered, the whole figure fits inside the frame with a clear margin on every side, feet near the bottom edge. Background: perfectly flat solid pure chroma-key green #00FF00, uniform, no gradient, no floor, no cast shadow, no glow or particles spilling onto the background, nothing green on the character. No text, no letters, no numbers, no logos, no watermark, no signature, no speech bubbles with writing.

The green is keyed out to real alpha by `build_frames.py`.

## Boot logo partition

The M500 has a `splash` partition (`/dev/block/by-name/splash`, mmcblk0p16), but it is not in the
firmware set and MikuOS does not write it. Reading it needs root. Not touched here.
