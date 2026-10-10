#!/usr/bin/env python3
"""Render the app sound catalog (app_sounds.json): voice lines in every house voice and
synthesized sound effects, plus the index apps read at runtime.

    build_apps.py                         everything
    build_apps.py --apps camera           one app
    build_apps.py --apps camera --verify  and Whisper-check the voice lines
    build_apps.py --index-only            just rewrite sounds_index.json

Output:

    mikuos/data/voice/<voice>/app/<app>/<id>.ogg   voice lines (Opus, -16 LUFS)
    mikuos/data/sfx/<app>/<id>.ogg                 effects (Opus; loops are Vorbis + ANDROID_LOOP)
    mikuos/data/voice/manifest.json                "apps" section added next to the status events
    mikuos/data/sfx/manifest.json
    mikuos/data/sounds_index.json                  flat index of everything, see write_index()
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import say  # noqa: E402

CATALOG = say.HERE / "app_sounds.json"
DATA = say.HERE.parent.parent / "mikuos" / "data"


def write_index(data: Path = DATA) -> Path:
    """One flat, typed file for the apps. Two homogeneous arrays so a Kotlin data class per
    array maps it directly (org.json or kotlinx.serialization). Paths are relative to the
    directory holding the index; durations are integer milliseconds."""
    vm = json.loads((data / "voice" / "manifest.json").read_text()) \
        if (data / "voice" / "manifest.json").exists() else {}
    sm = json.loads((data / "sfx" / "manifest.json").read_text()) \
        if (data / "sfx" / "manifest.json").exists() else {}
    voices = list(say.VARIANTS)
    voice_rows = []

    def add(app, vid, phrases, category=None, priority=None):
        for alt, p in enumerate(phrases):
            voice_rows.append({
                "app": app, "id": vid, "alt": alt, "text": p["text"],
                "category": category, "priority": priority,
                "files": {v: "voice/" + p["files"][v]["path"] for v in voices if v in p["files"]},
                "duration_ms": {v: int(p["files"][v]["duration"] * 1000) for v in voices if v in p["files"]},
            })

    for eid, e in vm.get("events", {}).items():
        add("status", eid, e["phrases"], e.get("category"), e.get("priority"))
    for app, lines in vm.get("apps", {}).items():
        for vid, e in lines.items():
            add(app, vid, e["phrases"])
    sfx_rows = [{"app": app, "id": sid, "file": "sfx/" + s["path"],
                 "duration_ms": int(s["duration"] * 1000), "loop": bool(s.get("loop"))}
                for app, sounds in sm.get("apps", {}).items() for sid, s in sounds.items()]
    index = {"version": 1, "voices": voices, "default_voice": voices[0],
             "voice": voice_rows, "sfx": sfx_rows}
    out = data / "sounds_index.json"
    out.write_text(json.dumps(index, separators=(",", ":"), ensure_ascii=False) + "\n")
    return out


def compose(parts: list[Path], spacing: float, out: Path) -> None:
    """Lay finished clips on a fixed grid (part k starts at k * spacing s, each keeping its
    own 30 ms lead-in) and re-encode. Each part is already at target loudness, so the sum
    is left alone apart from the post-encode true-peak check in say.render's style."""
    import numpy as np
    clips = [say.decode(p) for p in parts]
    step = int(spacing * say.OUT_SR)
    buf = np.zeros(step * (len(clips) - 1) + len(clips[-1]), np.float32)
    for k, c in enumerate(clips):
        buf[k * step:k * step + len(c)] += c
    say.encode(buf, out)
    for _ in range(3):
        tp = say.true_peak_db(say.decode(out))
        if tp <= say.MAX_TP_SHIPPED:
            break
        buf = buf * (10 ** ((say.MAX_TP_SHIPPED - 0.3 - tp) / 20))
        say.encode(buf, out)


def main() -> None:
    import sfx
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--apps", nargs="*", help="subset of apps (default: all)")
    ap.add_argument("--voices", nargs="*", default=list(say.VARIANTS))
    ap.add_argument("--no-voice", action="store_true", help="effects only")
    ap.add_argument("--no-sfx", action="store_true", help="voice lines only")
    ap.add_argument("--verify", action="store_true", help="Whisper round-trip the voice lines")
    ap.add_argument("--index-only", action="store_true")
    args = ap.parse_args()
    if args.index_only:
        print(write_index())
        return

    cat = json.loads(CATALOG.read_text())["apps"]
    apps = args.apps or list(cat)
    unknown = [a for a in apps if a not in cat]
    if unknown:
        sys.exit(f"unknown apps: {unknown}")
    verifier = None
    if args.verify and not args.no_voice:
        import build_all
        verifier = build_all.Verifier()

    vpath, spath = DATA / "voice" / "manifest.json", DATA / "sfx" / "manifest.json"
    vm = json.loads(vpath.read_text()) if vpath.exists() else {}
    sm = json.loads(spath.read_text()) if spath.exists() else {}
    sm.setdefault("format", {"container": "ogg", "codec": "opus (loops: vorbis + ANDROID_LOOP)",
                             "sample_rate": sfx.SR, "channels": 1,
                             "loudness": "max momentary LUFS for one-shots, integrated for loops"})
    v_apps, s_apps = vm.setdefault("apps", {}), sm.setdefault("apps", {})
    for gone in [a for a in list(v_apps) if a not in cat]:
        del v_apps[gone]
    for gone in [a for a in list(s_apps) if a not in cat]:
        del s_apps[gone]

    t0, n, problems = time.time(), 0, []
    for app in apps:
        spec = cat[app]
        if not args.no_voice:
            lines = {}
            old = v_apps.get(app, {})
            # Composed lines (e.g. a timed countdown) are built from other lines, so go last.
            items = sorted(spec.get("voice", {}).items(), key=lambda kv: "compose" in kv[1])
            for vid, e in items:
                prev = {p["text"]: p for p in old.get(vid, {}).get("phrases", [])}
                phrases = []
                if "compose" in e:
                    files = dict(prev.get(e["text"], {}).get("files", {}))
                    for voice in args.voices:
                        rel = f"{voice}/app/{app}/{vid}.ogg"
                        out = DATA / "voice" / rel
                        parts = [DATA / "voice" / f"{voice}/app/{app}/{c}.ogg" for c in e["compose"]]
                        compose(parts, e.get("spacing", 1.0), out)
                        a = say.decode(out)
                        files[voice] = {"path": rel, "duration": round(len(a) / say.OUT_SR, 2),
                                        "lufs": round(float(say.loudness(a)), 1),
                                        "true_peak_dbtp": round(float(say.true_peak_db(a)), 2),
                                        "bytes": out.stat().st_size}
                        n += 1
                        print(f"[{n:4d}] voice/{rel:44s} {files[voice]['duration']:4.2f}s (composed)", flush=True)
                    lines[vid] = {"phrases": [{"text": e["text"], "files": files}],
                                  **({"note": e["note"]} if "note" in e else {})}
                    continue
                for i, text in enumerate(e["phrases"]):
                    stem = vid if i == 0 else f"{vid}_alt{i}"
                    files = dict(prev.get(text, {}).get("files", {}))
                    for voice in args.voices:
                        rel = f"{voice}/app/{app}/{stem}.ogg"
                        out = DATA / "voice" / rel
                        say.render(text, voice, out)
                        a = say.decode(out)
                        rec = {"path": rel, "duration": round(len(a) / say.OUT_SR, 2),
                               "lufs": round(float(say.loudness(a)), 1),
                               "true_peak_dbtp": round(float(say.true_peak_db(a)), 2),
                               "bytes": out.stat().st_size}
                        if verifier:
                            wer, heard = verifier.check(out, text)
                            rec["asr_wer"] = round(float(wer), 2)
                            if wer > 0:
                                problems.append(f"voice/{rel}: heard {heard!r} for {text!r}")
                        files[voice] = rec
                        n += 1
                        print(f"[{n:4d}] voice/{rel:44s} {rec['duration']:4.2f}s "
                              f"{rec['lufs']:6.1f} LUFS" + (f"  WER {rec['asr_wer']:.2f}" if verifier else ""),
                              flush=True)
                    phrases.append({"text": text, "files": files})
                lines[vid] = {"phrases": phrases, **({"note": e["note"]} if "note" in e else {})}
            if lines:
                v_apps[app] = lines
            else:
                v_apps.pop(app, None)
        if not args.no_sfx:
            sounds = {}
            for sid, e in spec.get("sfx", {}).items():
                rel = f"{app}/{sid}.ogg"
                out = DATA / "sfx" / rel
                info = sfx.render(e["recipe"], out, e.get("lufs", -20.0), e.get("loop", False))
                sounds[sid] = {"path": rel, "recipe": e["recipe"], "loop": e.get("loop", False),
                               **info, "bytes": out.stat().st_size,
                               **({"note": e["note"]} if "note" in e else {})}
                n += 1
                print(f"[{n:4d}] sfx/{rel:46s} {info['duration']:6.2f}s {info['lufs']:6.1f} LUFS "
                      f"{info['true_peak_dbtp']:6.2f} dBTP {sounds[sid]['bytes'] / 1024:6.1f} KB", flush=True)
            if sounds:
                s_apps[app] = sounds
            else:
                s_apps.pop(app, None)

    # On a full build, remove app files nothing in the catalog owns any more.
    if not args.apps and not args.no_voice and not args.no_sfx and set(args.voices) == set(say.VARIANTS):
        owned = {"voice/" + f["path"] for lines in v_apps.values() for e in lines.values()
                 for p in e["phrases"] for f in p["files"].values()}
        owned |= {"sfx/" + s["path"] for sounds in s_apps.values() for s in sounds.values()}
        for f in list((DATA / "voice").glob("*/app/*/*.ogg")) + list((DATA / "sfx").glob("*/*.ogg")):
            if str(f.relative_to(DATA)) not in owned:
                f.unlink()
                print(f"removed stale {f.relative_to(DATA)}")

    vpath.parent.mkdir(parents=True, exist_ok=True)
    spath.parent.mkdir(parents=True, exist_ok=True)
    vpath.write_text(json.dumps(vm, indent=1, ensure_ascii=False) + "\n")
    spath.write_text(json.dumps(sm, indent=1, ensure_ascii=False) + "\n")
    idx = write_index()
    total = sum(f.stat().st_size for f in DATA.glob("voice/**/*.ogg")) + \
        sum(f.stat().st_size for f in DATA.glob("sfx/**/*.ogg"))
    print(f"\n{n} files rendered in {time.time() - t0:.0f}s. voice + sfx now {total / 1024 / 1024:.2f} MB; "
          f"index {idx} ({idx.stat().st_size / 1024:.0f} KB)")
    if problems:
        print("\nCheck these:")
        for p in problems:
            print("  " + p)


if __name__ == "__main__":
    say._ensure_venv()
    main()
