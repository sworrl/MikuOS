#!/usr/bin/env python3
"""Render every event in events.json in every house voice, plus a manifest.

    build_all.py                      everything -> mikuos/data/voice/
    build_all.py --voices cyber       one voice
    build_all.py --events battery_low_5 alarm
    build_all.py --verify             also transcribe each clip with Whisper and flag misreads

Output layout (all names are res/raw-safe: lowercase, digits, underscores):

    mikuos/data/voice/<voice>/<event_id>.ogg         phrases[0]
    mikuos/data/voice/<voice>/<event_id>_alt1.ogg    phrases[1], and so on
    mikuos/data/voice/manifest.json

Each file is measured again after encoding (decoded back, BS.1770 integrated loudness and
4x-oversampled true peak), and those are the numbers the manifest records.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import say  # noqa: E402

REPO = say.HERE.parent.parent
DEFAULT_OUT = REPO / "mikuos" / "data" / "voice"


decode = say.decode


class Verifier:
    """Whisper round-trip: does a stranger's ear hear the words we meant?"""

    def __init__(self):
        try:
            from faster_whisper import WhisperModel
        except ImportError:
            sys.exit("--verify needs faster-whisper: run fetch_models.sh --with-verify")
        self.m = WhisperModel("base.en", device="cpu", compute_type="int8",
                              download_root=str(say.CACHE / "models" / "whisper"))

    @staticmethod
    def words(s: str) -> list[str]:
        s = s.lower().replace("wi-fi", "wifi").replace("%", " percent").replace("d.a.c.", "dac")
        s = s.replace("miku os", "mikuos")
        # "Battery's" and "Batteries" sound the same: fold both to "batterys".
        s = re.sub(r"ies\b", "ys", s.replace("'", ""))
        nums = {"1": "one", "2": "two", "3": "three", "5": "five", "10": "ten", "20": "twenty"}
        # "IEM's" vs "IEMs", "Timer's" vs "Timers": apostrophes are spelling, not hearing.
        return [nums.get(w, w) for w in re.findall(r"[a-z0-9]+", s.replace("'", ""))]

    def check(self, path: Path, text: str) -> tuple[float, str]:
        segs, _ = self.m.transcribe(decode(path, 16000), beam_size=5, language="en")
        heard = " ".join(s.text.strip() for s in segs)
        ref, hyp = self.words(text), self.words(heard)
        # word error rate by edit distance
        d = list(range(len(hyp) + 1))
        for i, r in enumerate(ref, 1):
            prev, d[0] = d[0], i
            for j, h in enumerate(hyp, 1):
                prev, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, prev + (r != h))
        return d[-1] / max(len(ref), 1), heard


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--voices", nargs="*", default=list(say.VARIANTS))
    ap.add_argument("--events", nargs="*", help="subset of event ids (default: all)")
    ap.add_argument("--codec", choices=["opus", "vorbis"], default="opus")
    ap.add_argument("--verify", action="store_true", help="Whisper round-trip every clip")
    args = ap.parse_args()

    events = say.load_events()
    ids = args.events or list(events)
    unknown = [i for i in ids if i not in events]
    if unknown:
        sys.exit(f"unknown events: {unknown}")
    verifier = Verifier() if args.verify else None
    import pyloudnorm  # noqa: F401  (fail early, before an hour of rendering)

    manifest_path = args.out / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    manifest.update({
        "generator": {
            "tool": "tools/voice/build_all.py",
            "engine": "Kokoro-82M v1.0 (ONNX), Apache-2.0",
            "post": "Praat PSOLA reshaping + ffmpeg EQ/chorus + BS.1770 loudness",
        },
        "format": {
            "container": "ogg", "codec": args.codec, "sample_rate": say.OUT_SR, "channels": 1,
            "target_lufs": say.TARGET_LUFS, "max_true_peak_dbtp": -1.0,
        },
        "voices": {k: {"title": v["title"], "character": v["character"]}
                   for k, v in say.VARIANTS.items()},
    })
    out_events = manifest.setdefault("events", {})
    for gone in [e for e in out_events if e not in events]:
        del out_events[gone]

    t0, n, problems = time.time(), 0, []
    for eid in ids:
        ev = events[eid]
        entry = out_events.setdefault(eid, {})
        entry.update({"category": ev["category"], "priority": ev["priority"]})
        old = {p["text"]: p for p in entry.get("phrases", [])}
        phrases = []
        for i, text in enumerate(ev["phrases"]):
            stem = eid if i == 0 else f"{eid}_alt{i}"
            files = dict(old.get(text, {}).get("files", {}))
            for voice in args.voices:
                rel = f"{voice}/{stem}.ogg"
                out = args.out / rel
                say.render(text, voice, out, args.codec)
                a = decode(out)
                rec = {"path": rel, "duration": round(len(a) / say.OUT_SR, 2),
                       "lufs": round(float(say.loudness(a)), 1),
                       "true_peak_dbtp": round(float(say.true_peak_db(a)), 2),
                       "bytes": out.stat().st_size}
                if rec["true_peak_dbtp"] > say.MAX_TP_SHIPPED:
                    problems.append(f"{rel}: true peak {rec['true_peak_dbtp']} dBTP")
                if verifier:
                    wer, heard = verifier.check(out, text)
                    rec["asr_wer"] = round(float(wer), 2)
                    if wer > 0:
                        problems.append(f"{rel}: heard {heard!r} for {text!r} (WER {wer:.2f})")
                files[voice] = rec
                n += 1
                print(f"[{n:4d}] {rel:42s} {rec['duration']:4.2f}s {rec['lufs']:6.1f} LUFS "
                      f"{rec['true_peak_dbtp']:6.2f} dBTP {rec['bytes'] / 1024:5.1f} KB"
                      + (f"  WER {rec['asr_wer']:.2f}" if verifier else ""), flush=True)
            phrases.append({"text": text, "files": files})
        entry["phrases"] = phrases

    # On a full build, drop files no phrase owns any more (renamed events, removed alternates).
    owned = {f["path"] for e in out_events.values() for p in e["phrases"] for f in p["files"].values()}
    if not args.events and set(args.voices) == set(say.VARIANTS):
        for f in args.out.glob("*/*.ogg"):
            if f"{f.parent.name}/{f.name}" not in owned:
                f.unlink()
                print(f"removed stale {f.parent.name}/{f.name}")

    total = sum(f.stat().st_size for f in args.out.glob("*/*.ogg"))
    manifest["totals"] = {"files": len(owned), "bytes": total}
    manifest_path.write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n")
    if args.out == DEFAULT_OUT:
        import build_apps
        build_apps.write_index()
    print(f"\n{n} clips rendered in {time.time() - t0:.0f}s; {len(owned)} files, "
          f"{total / 1024 / 1024:.2f} MB in {args.out}")
    if problems:
        print("\nCheck these:")
        for p in problems:
            print("  " + p)


if __name__ == "__main__":
    say._ensure_venv()
    main()
