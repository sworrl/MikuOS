#!/usr/bin/env python3
"""Generate the MikuOS replacements for HiBy's SystemUI popup art.

  python3 gen.py                      # every event, 2 candidates each
  python3 gen.py --only charging bye  # a subset
  python3 gen.py --n 1 --suffix c     # one more candidate, saved as <name>_c
  GEMINI_API_KEY=... python3 gen.py   # only used when gcloud has no Glassite key

Same approach as ACRE_MASTER/brand/photo/gen.py: gemini-3-pro-image over plain REST
(generateContent, responseModalities IMAGE, imageConfig aspectRatio/imageSize). The key is the
AI Studio key "Glassite", fetched from gcloud at run time so it never lands in a file.

The chibi art is drawn on a flat chroma green so build_frames.py can key it to real alpha
(the stock frames are RGBA and sit over a bordered panel). Writes candidates/<name>_<a|b>.png.
"""
import argparse, base64, json, os, subprocess, sys, time, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))

STYLE = (
    "Chibi anime illustration of an original idol girl character inspired by classic "
    "virtual-singer designs (two-heads-tall super-deformed proportions, big sparkling teal eyes, "
    "very long teal twin-tails colored #39C5BB, dark grey and black sleeveless top with a teal "
    "collar ribbon, short black pleated skirt, black arm warmers with teal trim, small pink "
    "#FF5FA2 hair clips and accents). Clean modern anime look: crisp bold line art, cel shading "
    "with soft gradients, glossy highlights on hair and props, a thin rim light in teal #39C5BB "
    "and pink #FF5FA2 drawn ON the character only. "
    "Full body, centered, the whole figure fits inside the frame with a clear margin on every side, "
    "feet near the bottom edge. Background: perfectly flat solid pure chroma-key green #00FF00, "
    "uniform, no gradient, no floor, no cast shadow, no glow or particles spilling onto the "
    "background, nothing green on the character. No text, no letters, no numbers, no logos, "
    "no watermark, no signature, no speech bubbles with writing."
)

PROMPTS = {
    "headset_in": (
        "The girl happily pushing a pair of glossy in-ear monitors into her ears, eyes closed in bliss, "
        "gentle smile. A short braided cable runs to a glowing teal 4.4mm balanced headphone plug she "
        "holds up near her chest, the plug tip shining with a cyan glow. Two small pink and teal music "
        "notes float right next to her head."),
    "headset_out": (
        "The girl has just pulled her in-ear monitors out: one earbud dangles from her hand on its cable, "
        "the unplugged headphone plug hangs loose at the end with a tiny dim spark. She looks "
        "surprised and a little pouty, eyebrows raised, one small grey faded music note drooping "
        "beside her."),
    "charging": (
        "The girl standing cheerfully, hugging a chunky glossy glass battery cell almost as big as her "
        "torso, the battery glowing teal inside with a bright lightning-bolt shape, a USB-C cable "
        "curling from it. She smiles with one eye closed. Small cyan sparkles around the battery."),
    "low_battery": (
        "The girl sitting on the ground crying comically, big anime tears streaming, mouth wide open in a "
        "wail, clutching a small empty glass battery cell with only a thin red sliver of charge left. "
        "Her twin-tails droop to the ground."),
    "low_power_shutdown": (
        "The girl lying flat on her stomach on the ground, completely drained and exhausted, eyes closed "
        "with a sleepy frown, cheek squished, twin-tails spread out flat around her, a tiny empty "
        "battery cell tipped over beside her hand, a small bubble of breath. Wide low composition."),
    "bye": (
        "The girl waving goodbye with one hand raised high, warm closed-eye smile, slight head tilt, the "
        "other hand on her hip, a few small teal and pink sparkles near the waving hand."),
    "volume_warning": (
        "The girl covering both ears with her hands, swirly spiral dizzy eyes, wobbly worried mouth, "
        "a sweat drop, big over-ear headphones around her neck blasting concentric pink sound-wave "
        "rings, a small glowing pink triangle warning shape (empty, no symbol inside) above her head."),
    "volume_dial": (
        "The girl jumping up in excitement with both arms raised, one fist pumped, mouth open in a happy "
        "shout, twin-tails flying upward, a couple of rising teal music notes next to her."),
}
# Full-screen backdrop for the shutdown/reboot screen; the waving chibi is drawn on top of it
# and ../splash/wordmark.py adds the MikuOS wordmark in the clear band near the bottom.
BG_PROMPT = (
    "Portrait phone wallpaper, 9:16, for a music player shutdown screen. Very dark teal-black "
    "background #0B1418. Thin glowing light ribbons and soft audio waveform lines in teal "
    "#39C5BB sweep in from the edges and corners, a few accents of pink #FF5FA2, soft bokeh, "
    "faint hexagon grid. The central 60 percent of the image and the bottom 20 percent stay "
    "almost empty and dark. Elegant, minimal, high contrast. No characters, no people, no text, "
    "no letters, no numbers, no logos, no UI elements, no watermark.")
# Full-screen boot screen (bootanimation video and its still). Wordmark goes in the bottom band.
BOOT_PROMPT = (
    "Vertical 9:16 full-screen anime illustration for a music player boot screen. An original "
    "idol girl character inspired by classic virtual-singer designs: very long flowing teal "
    "twin-tails #39C5BB, bright teal eyes, small pink #FF5FA2 hair clips, dark grey and black "
    "sleeveless top with a teal collar ribbon, black arm warmers with teal trim, sleek over-ear "
    "headphones with soft teal glow resting on her head. Upper body, three-quarter view, gentle "
    "happy smile, eyes slightly closed as if enjoying music, one hand lightly touching an ear cup. "
    "She fills the upper 65 percent of the frame, her twin-tails sweep down and outward to both "
    "sides. Background: deep dark teal-black #0B1418 with a soft teal glow behind her, a few thin "
    "flowing light ribbons and small sparkles in teal and pink. The bottom 30 percent of the "
    "image is calm, dark, nearly empty background with no character parts. Clean modern anime "
    "illustration, crisp line art, cel shading with soft gradients, high detail. No text, no "
    "letters, no numbers, no logos, no watermark, no signature.")

JOBS = {k: (STYLE + " Scene: " + v, "1:1", "1K") for k, v in PROMPTS.items()}
JOBS["shutdown_bg"] = (BG_PROMPT, "9:16", "2K")
JOBS["boot_splash"] = (BOOT_PROMPT, "9:16", "2K")

GCLOUD_PROJECT = "gen-lang-client-0814159993"
GCLOUD_KEY_NAME = "Glassite"


def key_from_gcloud():
    try:
        name = subprocess.check_output(
            ["gcloud", "services", "api-keys", "list", "--project", GCLOUD_PROJECT,
             f"--filter=displayName={GCLOUD_KEY_NAME}", "--format=value(name)"],
            text=True, stderr=subprocess.DEVNULL).strip().splitlines()[0]
        return subprocess.check_output(
            ["gcloud", "services", "api-keys", "get-key-string", name, "--format=value(keyString)"],
            text=True, stderr=subprocess.DEVNULL).strip()
    except (subprocess.CalledProcessError, IndexError, FileNotFoundError):
        return None


def generate(key, model, prompt, aspect, size):
    body = {
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "generationConfig": {"responseModalities": ["IMAGE"],
                             "imageConfig": {"aspectRatio": aspect, "imageSize": size}},
    }
    req = urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
        data=json.dumps(body).encode(),
        headers={"x-goog-api-key": key, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        d = json.load(r)
    for cand in d.get("candidates", []):
        for part in cand.get("content", {}).get("parts", []):
            if "inlineData" in part:
                return base64.b64decode(part["inlineData"]["data"]), part["inlineData"].get("mimeType", "")
    raise RuntimeError("no image in response: " + json.dumps(d)[:300])


def run_one(key, models, name, tag, out):
    prompt, aspect, size = JOBS[name]
    for model in models:
        t = time.time()
        try:
            data, mime = generate(key, model, prompt, aspect, size)
            dst = os.path.join(out, f"{name}_{tag}" + (".jpg" if "jpeg" in mime else ".png"))
            open(dst, "wb").write(data)
            return f"{name}_{tag}: {model} {mime} {len(data)//1024} KB {time.time()-t:.0f}s"
        except urllib.error.HTTPError as e:
            err = e.read().decode()[:200].replace(key, "<key>")
            print(f"{name}_{tag}: {model} HTTP {e.code}: {err}", file=sys.stderr)
        except Exception as e:
            print(f"{name}_{tag}: {model} failed: {str(e)[:200]}", file=sys.stderr)
    return f"{name}_{tag}: FAILED"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--n", type=int, default=2, help="candidates per image")
    ap.add_argument("--suffix", default="", help="first candidate letter (default a)")
    ap.add_argument("--model", default="gemini-3-pro-image")
    ap.add_argument("--fallback", default="gemini-3-pro-image-preview")
    ap.add_argument("--out", default=os.path.join(HERE, "candidates"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    # gcloud first, the shell often carries a stale GEMINI_API_KEY that Google rejects
    key = key_from_gcloud() or os.environ.get("GEMINI_API_KEY")
    if not key:
        sys.exit(f"no key: log in to gcloud (key '{GCLOUD_KEY_NAME}' in {GCLOUD_PROJECT}) "
                 "or set GEMINI_API_KEY")
    first = ord(a.suffix or "a")
    tasks = [(n, chr(first + i)) for n in (a.only or list(JOBS)) for i in range(a.n)]
    with ThreadPoolExecutor(max_workers=6) as ex:
        for line in ex.map(lambda t: run_one(key, (a.model, a.fallback), t[0], t[1], a.out), tasks):
            print(line, flush=True)


if __name__ == "__main__":
    main()
