#!/usr/bin/env python3
"""Render a MikuOS status announcement in one of the house voices.

    say.py "Earphones unplugged." --voice mirai --out /tmp/x.ogg
    say.py --event iem_removed_35mm --voice cyber --out /tmp/x.wav
    say.py --list

Pipeline, all offline once fetch_models.sh has run:

    text -> Kokoro-82M (ONNX, Apache-2.0) with a blended voice style
         -> Praat "Change gender" (PSOLA): pitch median, pitch range, formant shift
         -> [cyber only] pitch contour quantized to a pentatonic scale
         -> ffmpeg: high-pass, presence/air EQ, light chorus, de-ess, light compression
         -> trim silence, loudness to -16 LUFS integrated, true peak <= -1 dBTP
         -> 48 kHz mono Ogg Opus (or Vorbis, or WAV, by extension / --codec)

None of the three voices is any stock Kokoro voice: each is a weighted blend of several
style vectors, then reshaped. Nothing here is, imitates or is trained on Hatsune Miku or
any other commercial voicebank.

If this is run with a Python that lacks the dependencies, it re-executes itself under the
venv that fetch_models.sh created in the cache directory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
CACHE = Path(os.environ.get("MIKU_VOICE_CACHE", HERE / ".cache")).resolve()
EVENTS = HERE / "events.json"
OUT_SR = 48000
TARGET_LUFS = -16.0
TARGET_TP = -1.5          # dBTP before encoding; leaves margin for Opus overshoot
MAX_TP_SHIPPED = -1.0     # dBTP of the decoded file, checked after encoding

# ── The house voices ────────────────────────────────────────────────────────
# blend   : Kokoro style vectors and weights (normalized). af_* = US English female,
#           jf_alpha = Japanese female, which lifts pitch and brightness; kept a minority
#           share because at full weight its English is accented enough to hurt intelligibility.
# speed   : Kokoro speaking rate.
# shape   : Praat Change gender -> formant shift ratio, new pitch median (Hz), pitch range factor.
# quantize: snap the pitch contour to a scale (the "vocaloid" step), cyber only.
# fx      : ffmpeg filter chain applied at 48 kHz after shaping, before loudness.
# lexicon : optional (regex, respelling) pairs for this voice only, applied after LEXICON.
#           A respelling written as /.../ is fed to Kokoro as IPA phonemes.
# takes   : optional {written text: take number}. Each take is a different Praat seed;
#           bump it to re-roll one line without touching the rest. Default take is 0.
VARIANTS: dict[str, dict] = {
    "mirai": {
        "title": "Mirai",
        "character": "bright, cheerful, quick",
        "blend": {"af_heart": 0.45, "af_bella": 0.35, "jf_alpha": 0.20},
        "speed": 1.05,
        "shape": {"formant": 1.08, "median": 285.0, "range": 1.20},
        "quantize": None,
        "fx": ("highpass=f=120,"
               "equalizer=f=280:t=q:w=1.0:g=-1.5,"
               "equalizer=f=3400:t=q:w=1.4:g=2.5,"
               "highshelf=f=8000:g=2.5,"
               "chorus=0.9:0.9:22|31:0.10|0.07:0.30|0.21:1.2|1.6,"
               "deesser=i=0.35,"
               "acompressor=threshold=-20dB:ratio=2.5:attack=5:release=90:makeup=1"),
    },
    "hoshi": {
        "title": "Hoshi",
        "character": "soft, calm, unhurried",
        "blend": {"af_aoede": 0.40, "af_kore": 0.30, "af_nicole": 0.15, "jf_alpha": 0.15},
        "speed": 0.94,
        "shape": {"formant": 1.06, "median": 250.0, "range": 0.85},
        "quantize": None,
        "fx": ("highpass=f=100,"
               "equalizer=f=220:t=q:w=1.0:g=1.0,"
               "equalizer=f=4500:t=q:w=1.5:g=-1.0,"
               "highshelf=f=9000:g=1.0,"
               "deesser=i=0.5,"
               "aecho=0.9:0.9:38|67:0.10|0.06,"
               "acompressor=threshold=-22dB:ratio=2:attack=8:release=120:makeup=1"),
    },
    "cyber": {
        "title": "Cyber",
        "character": "synthetic, tuned, vocaloid-ish sheen",
        "blend": {"af_bella": 0.45, "af_nova": 0.25, "jf_alpha": 0.30},
        "speed": 1.0,
        "shape": {"formant": 1.10, "median": 300.0, "range": 0.70},
        # A major pentatonic (semitones above A). Snapping a spoken contour to a sparse
        # scale gives the stepped, sung-robot pitch that reads as "synth voice".
        "quantize": {"root_hz": 220.0, "scale": [0, 2, 4, 7, 9]},
        "fx": ("highpass=f=130,"
               "equalizer=f=1800:t=q:w=1.2:g=1.5,"
               "highshelf=f=6500:g=3.0,"
               "chorus=0.8:0.85:12|19|27:0.22|0.16|0.12:0.6|0.9|1.3:2|2.4|1.8,"
               "flanger=delay=1:depth=1.5:regen=-20:width=55:speed=0.3,"
               "aexciter=amount=1.2:drive=5:blend=0:freq=5500,"
               "deesser=i=0.4,"
               "acompressor=threshold=-20dB:ratio=3:attack=4:release=80:makeup=1"),
        # The scale snapping smears short vowels and acronyms. Each of these was misheard by
        # the Whisper check as written and heard correctly after the respelling.
        "lexicon": [
            (r"\bIEMs\b", "eye ee emms"),      # was "IAMs" / "I am"
            (r"\bmode\b", "mohd"),             # was "mood"
            (r"^Say cheese!$", "Sayy cheese!"),  # was "Say Cheezer"
            (r"^Two\.$", "two"),                 # was "To"; heard as "Two" without the stop
            (r"^Miss\.$", "Miss \u2014"),        # was "Mess up"; the dash cuts the vowel Kokoro adds
        ],
        # Re-rolled takes, picked by the Whisper check.
        "takes": {
            "USB DAC mode is on.": 1,   # take 0 heard "USB dock mode"
            "FM radio on.": 1,          # take 0 heard "FM Radio 1"
        },
    },
}


# What the synthesizer should hear when the written form misleads espeak-ng's G2P.
# The written text (events.json, manifest) stays as people read it.
LEXICON = [
    (r"\bMikuOS\b", "Meekoo OS"),   # espeak says "MICK-oo"
    (r"\bMiku\b", "Meekoo"),
    (r"\bDACs?\b", "dack"),         # spelled out "D-A-C" it was misheard as "DSC"
]


def spoken(text: str, v: dict | None = None) -> str:
    """The text Kokoro reads: shared LEXICON first, then the voice's own respellings."""
    import re
    for pat, rep in LEXICON + list((v or {}).get("lexicon", [])):
        text = re.sub(pat, rep, text)
    return text


def take_seed(voice: str, text: str) -> int:
    """Praat's PSOLA step uses its random generator, so every render of a line is a slightly
    different take. Seeding it from (voice, text, take) makes builds repeatable, and bumping
    a line's take number in the voice's "takes" picks another one when a take comes out
    muddy."""
    take = VARIANTS[voice].get("takes", {}).get(text, 0)
    h = hashlib.sha256(f"{voice}|{text}|{take}".encode()).hexdigest()
    return int(h[:8], 16) % 2_000_000_000


# ── Environment ─────────────────────────────────────────────────────────────
def _ensure_venv() -> None:
    try:
        import kokoro_onnx, parselmouth, pyloudnorm, soundfile  # noqa: F401
    except ImportError:
        py = CACHE / "venv" / "bin" / "python"
        if py.exists() and Path(sys.prefix).resolve() != (CACHE / "venv").resolve():
            os.execv(str(py), [str(py), "-I", *sys.argv])
        sys.exit(f"Dependencies missing. Run {HERE / 'fetch_models.sh'} first "
                 f"(cache: {CACHE}).")


def _espeak_data_dir() -> str:
    """espeak-ng copies its data path into a 160-byte buffer and silently falls back to a
    compiled-in CI path when it does not fit, then exit()s the whole process on the missing
    phontab. phonemizer resolve()s symlinks, so a link is not enough: copy the data to a
    short path when the venv lives somewhere deep."""
    import espeakng_loader
    src = espeakng_loader.get_data_path()
    if len(src) < 120:
        return src
    dst = Path(tempfile.gettempdir()) / f"miku-voice-{os.getuid()}" / "espeak-ng-data"
    if not (dst / "phontab").exists() or (dst / "phontab").stat().st_size != Path(src, "phontab").stat().st_size:
        shutil.rmtree(dst, ignore_errors=True)
        shutil.copytree(src, dst)
    return str(dst)


_KOKORO = None


def kokoro():
    global _KOKORO
    if _KOKORO is None:
        from kokoro_onnx import Kokoro
        from kokoro_onnx.config import EspeakConfig
        m = CACHE / "models" / "kokoro"
        if not (m / "kokoro-v1.0.onnx").exists():
            sys.exit(f"Kokoro model missing in {m}. Run {HERE / 'fetch_models.sh'}.")
        _KOKORO = Kokoro(str(m / "kokoro-v1.0.onnx"), str(m / "voices-v1.0.bin"),
                         espeak_config=EspeakConfig(data_path=_espeak_data_dir()))
    return _KOKORO


# ── Stages ──────────────────────────────────────────────────────────────────
def synth(text: str, v: dict):
    """Kokoro with the variant's blended style. Cached on disk by (text, blend, speed)."""
    import numpy as np
    import soundfile as sf
    text = spoken(text, v)
    key = hashlib.sha256(json.dumps([text, v["blend"], v["speed"], "kokoro-v1.0"],
                                    sort_keys=True).encode()).hexdigest()[:20]
    cached = CACHE / "tts" / f"{key}.wav"
    if cached.exists():
        a, sr = sf.read(cached, dtype="float32")
        return a, sr
    k = kokoro()
    total = sum(v["blend"].values())
    style = sum(k.get_voice_style(name) * (w / total) for name, w in v["blend"].items())
    # A respelling written as /.../ is IPA and goes to Kokoro as phonemes, past espeak-ng.
    phonemes = len(text) > 2 and text[0] == text[-1] == "/"
    a, sr = k.create(text[1:-1] if phonemes else text, voice=style.astype(np.float32),
                     speed=v["speed"], lang="en-us", is_phonemes=phonemes)
    cached.parent.mkdir(parents=True, exist_ok=True)
    sf.write(cached, a, sr, subtype="FLOAT")
    return a, sr


def shape(audio, sr: int, v: dict, seed: int | None = None):
    """Pitch median/range and formant shift with Praat PSOLA; optional scale quantization."""
    import numpy as np
    import parselmouth
    from parselmouth.praat import call, run
    if seed is not None:
        run(f"random_initializeWithSeedUnsafelyButPredictably ({seed})")
    snd = parselmouth.Sound(audio.astype(np.float64), sampling_frequency=sr)
    s = v["shape"]
    snd = call(snd, "Change gender", 75, 600, s["formant"], s["median"], s["range"], 1.0)
    q = v.get("quantize")
    if q:
        manip = call(snd, "To Manipulation", 0.01, 75, 600)
        tier = call(manip, "Extract pitch tier")
        n = call(tier, "Get number of points")
        new = call("Create PitchTier", "q", snd.xmin, snd.xmax)
        steps = sorted(q["scale"])
        for i in range(1, n + 1):
            t = call(tier, "Get time from index", i)
            f = call(tier, "Get value at index", i)
            semis = 12 * np.log2(f / q["root_hz"])
            octave, within = divmod(semis, 12)
            cands = [st + 12 * octave for st in steps] + [steps[0] + 12 * (octave + 1)]
            snapped = min(cands, key=lambda c: abs(c - semis))
            call(new, "Add point", t, q["root_hz"] * 2 ** (snapped / 12))
        call([new, manip], "Replace pitch tier")
        snd = call(manip, "Get resynthesis (overlap-add)")
    return snd.values[0].astype(np.float32), int(snd.sampling_frequency)


def _ffmpeg(args: list[str], stdin: bytes | None = None) -> bytes:
    r = subprocess.run(["ffmpeg", "-v", "error", "-nostdin", *args], input=stdin,
                       capture_output=True)
    if r.returncode != 0:
        sys.exit("ffmpeg failed: " + r.stderr.decode(errors="replace"))
    return r.stdout


def fx(audio, sr: int, chain: str):
    """Resample to 48 kHz, run the variant's chain, trim leading/trailing silence."""
    import numpy as np
    trim = ("silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.02,"
            "areverse,silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.06,"
            "areverse")
    graph = f"aresample={OUT_SR}:resampler=soxr:precision=28,{chain},{trim}"
    raw = _ffmpeg(["-f", "f32le", "-ar", str(sr), "-ac", "1", "-i", "pipe:0",
                   "-af", graph, "-f", "f32le", "-ar", str(OUT_SR), "-ac", "1", "pipe:1"],
                  stdin=audio.astype(np.float32).tobytes())
    return np.frombuffer(raw, np.float32).copy()


def true_peak_db(a) -> float:
    import numpy as np
    n = len(a)
    if n == 0:
        return -120.0
    spec = np.fft.rfft(a)
    up = np.fft.irfft(spec, 4 * n) * 4          # 4x oversampled reconstruction
    return 20 * np.log10(max(np.max(np.abs(up)), 1e-9))


def loudness(a, sr: int = OUT_SR) -> float:
    import numpy as np
    import pyloudnorm
    # BS.1770 gating needs >= 400 ms; pad very short clips with silence for the measurement.
    pad = np.zeros(max(0, int(0.45 * sr) - len(a)), np.float32)
    return pyloudnorm.Meter(sr).integrated_loudness(np.concatenate([a, pad]).astype(np.float64))


def _limit(a, ceiling_db: float):
    """Lookahead peak limiter for the odd plosive burst Kokoro leaves in ("unPlugged")."""
    import numpy as np
    lim = 10 ** (ceiling_db / 20)
    raw = _ffmpeg(["-f", "f32le", "-ar", str(OUT_SR), "-ac", "1", "-i", "pipe:0", "-af",
                   f"alimiter=limit={lim:.4f}:attack=3:release=60:level=disabled:asc=1",
                   "-f", "f32le", "pipe:1"], stdin=a.astype(np.float32).tobytes())
    return np.frombuffer(raw, np.float32).copy()


def normalize(a):
    """Fade the edges, gain to TARGET_LUFS, and if that pushes true peak past TARGET_TP,
    limit the few offending peaks rather than turning the whole clip down. Two passes,
    then a final trim in whichever direction the true-peak ceiling still allows."""
    import numpy as np
    # 15 ms fade in / 40 ms fade out and a little air either side, so players never click.
    fi, fo = int(0.015 * OUT_SR), int(0.04 * OUT_SR)
    a = a.copy()
    a[:fi] *= np.linspace(0, 1, fi, dtype=np.float32)
    a[-fo:] *= np.linspace(1, 0, fo, dtype=np.float32)
    a = np.concatenate([np.zeros(int(0.03 * OUT_SR), np.float32), a,
                        np.zeros(int(0.08 * OUT_SR), np.float32)])
    for _ in range(2):
        a = a * (10 ** ((TARGET_LUFS - loudness(a)) / 20))
        if true_peak_db(a) <= TARGET_TP:
            return a
        a = _limit(a, TARGET_TP - 1.0)
    over = true_peak_db(a) - TARGET_TP
    return a * (10 ** (-max(over, 0.0) / 20))


def encode(a, out: Path, codec: str | None = None) -> None:
    import numpy as np
    out.parent.mkdir(parents=True, exist_ok=True)
    codec = codec or {".wav": "wav", ".opus": "opus", ".oga": "vorbis"}.get(out.suffix, "opus")
    enc = {
        "wav": ["-c:a", "pcm_s16le", "-f", "wav"],
        # Opus in Ogg: Android 10+ plays it from MediaPlayer and SoundPool. 32 kb/s VBR
        # mono is transparent for synthetic speech; voice mode favours intelligibility.
        "opus": ["-c:a", "libopus", "-b:a", "32k", "-vbr", "on", "-application", "voip",
                 "-frame_duration", "20", "-f", "ogg"],
        "vorbis": ["-c:a", "libvorbis", "-q:a", "2", "-f", "ogg"],
    }[codec]
    _ffmpeg(["-y", "-f", "f32le", "-ar", str(OUT_SR), "-ac", "1", "-i", "pipe:0",
             "-map_metadata", "-1", *enc, str(out)], stdin=a.astype(np.float32).tobytes())


def render(text: str, voice: str, out: Path, codec: str | None = None) -> dict:
    v = VARIANTS[voice]
    a, sr = synth(text, v)
    a, sr = shape(a, sr, v, take_seed(voice, text))
    a = fx(a, sr, v["fx"])
    a = normalize(a)
    encode(a, out, codec)
    if out.suffix != ".wav" and codec != "wav":
        # Lossy codecs overshoot: Opus can add a dB of true peak on a sharp consonant.
        # Measure what the device will actually decode and pull the gain down if needed.
        for _ in range(3):
            tp = true_peak_db(decode(out))
            if tp <= MAX_TP_SHIPPED:
                break
            a = a * (10 ** ((MAX_TP_SHIPPED - 0.3 - tp) / 20))
            encode(a, out, codec)
    return {"duration": round(len(a) / OUT_SR, 3),
            "lufs": round(loudness(a), 1), "true_peak_dbtp": round(true_peak_db(a), 2)}


def decode(path: Path, sr: int = OUT_SR):
    import numpy as np
    raw = _ffmpeg(["-i", str(path), "-f", "f32le", "-ac", "1", "-ar", str(sr), "pipe:1"])
    return np.frombuffer(raw, np.float32).copy()


# ── CLI ─────────────────────────────────────────────────────────────────────
def load_events() -> dict:
    return json.loads(EVENTS.read_text())["events"]


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("text", nargs="?", help="what to say")
    p.add_argument("--event", help="event id from events.json (uses its first phrase)")
    p.add_argument("--alt", type=int, default=0, help="which phrase of the event (0-based)")
    p.add_argument("--voice", default="mirai", choices=sorted(VARIANTS))
    p.add_argument("--out", type=Path, help=".ogg (Opus), .wav, .opus or .oga (Vorbis)")
    p.add_argument("--codec", choices=["opus", "vorbis", "wav"], help="override the extension")
    p.add_argument("--list", action="store_true", help="list voices and events")
    p.add_argument("--play", action="store_true", help="play the result with ffplay")
    args = p.parse_args()

    if args.list:
        for k, v in VARIANTS.items():
            print(f"voice  {k:6s} {v['character']}")
        for k, e in load_events().items():
            print(f"event  {k:28s} {e['phrases'][0]}")
        return
    if args.event:
        ev = load_events().get(args.event) or sys.exit(f"unknown event {args.event!r}")
        text = ev["phrases"][min(args.alt, len(ev["phrases"]) - 1)]
    elif args.text:
        text = args.text
    else:
        p.error("give text or --event")
    _ensure_venv()
    out = args.out or Path(tempfile.gettempdir()) / f"miku-say-{args.voice}.ogg"
    info = render(text, args.voice, out, args.codec)
    print(f"{out}  {info['duration']:.2f}s  {info['lufs']} LUFS  {info['true_peak_dbtp']} dBTP  "
          f"[{args.voice}] {text}")
    if args.play:
        subprocess.run(["ffplay", "-v", "error", "-nodisp", "-autoexit", str(out)])


if __name__ == "__main__":
    if "--list" not in sys.argv:
        _ensure_venv()
    main()
