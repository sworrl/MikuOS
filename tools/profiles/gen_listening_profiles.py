#!/usr/bin/env python3
"""Build Miku Music's built-in listening profiles.

Reads catalog.json (the hand-checked list of headphones: brand, model, type, connection,
published impedance/sensitivity, and the AutoEq result to use), fetches each AutoEq
ParametricEQ.txt (cached under cache/), applies the gain/High Power rule, and writes
miku-player-kotlin/app/src/main/assets/listening_profiles.json.

    python3 tools/profiles/gen_listening_profiles.py            # use cache, fetch what is missing
    python3 tools/profiles/gen_listening_profiles.py --refresh  # re-download every AutoEq file
    python3 tools/profiles/gen_listening_profiles.py --offline  # cache only, never touch the network

Nothing here invents numbers. A model without an AutoEq result ships flat with EQ off and says
"no measurement". A model without a sensitivity spec gets the type/impedance fallback and says so.

THE RULE (keep in step with ProfileRules.kt in the app):
  sensitivity in dB SPL per volt; from dB/mW: dB/V = dB/mW + 10*log10(1000/Z)
  V needed for 110 dB SPL peaks = 10 ** ((110 - dB/V) / 20)
    < 0.5 V        -> Low gain,  High Power off
    0.5 to < 1.5 V -> High gain, High Power off
    >= 1.5 V       -> High gain, High Power on
  no sensitivity: IEM/earbud/TWS -> Low/off; else impedance >= 150 -> High/on, >= 50 -> High/off, else Low/off
  Bluetooth-only hardware: no DAC settings (the M500's DAC is not in that path), EQ only.
  Filter: fast_rolloff_phase_compensated. DRE: on (the app's best-audio default).

AutoEq (https://github.com/jaakkopasanen/AutoEq) is MIT licensed. The measurements behind its
results belong to their measurers (oratory1990, crinacle, Rtings, Innerfidelity, ...); each
profile records which one it used and the exact file URL.
"""
import argparse
import datetime
import hashlib
import json
import math
import os
import re
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
CATALOG = os.path.join(HERE, "catalog.json")
CACHE = os.path.join(HERE, "cache", "autoeq")
OUT = os.path.join(REPO, "miku-player-kotlin", "app", "src", "main", "assets", "listening_profiles.json")

FILTER_DEFAULT = "fast_rolloff_phase_compensated"
FILTER_RE = re.compile(
    r"Filter\s+\d+:\s+ON\s+(PK|LSC|HSC|LS|HS|LSQ|HSQ)\s+Fc\s+([\d.]+)\s*Hz\s+Gain\s+(-?[\d.]+)\s*dB\s+Q\s+([\d.]+)",
    re.I,
)
PREAMP_RE = re.compile(r"Preamp:\s*(-?[\d.]+)\s*dB", re.I)

ATTRIBUTION = (
    "EQ curves: AutoEq, Copyright (c) 2018-2022 Jaakko Pasanen, MIT license, github.com/jaakkopasanen/AutoEq, "
    "from measurements by the source named on each profile. Specs from the makers' published data. "
    "Profiles without a measurement ship flat."
)


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def fetch(url, refresh, offline):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, hashlib.sha1(url.encode()).hexdigest()[:16] + ".txt")
    if os.path.exists(path) and not refresh:
        with open(path, encoding="utf-8") as f:
            return f.read()
    if offline:
        return None
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "miku-profiles-gen"})
            with urllib.request.urlopen(req, timeout=30) as r:
                text = r.read().decode("utf-8", "replace")
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
            return text
        except Exception as e:  # network hiccup or 404; report and move on
            last = e
            time.sleep(1 + attempt)
    print(f"  ! fetch failed {url}: {last}", file=sys.stderr)
    return None


def parse_peq(text):
    if not text:
        return None
    m = PREAMP_RE.search(text)
    bands = [
        {"type": {"LS": "LSC", "LSQ": "LSC", "HS": "HSC", "HSQ": "HSC"}.get(t.upper(), t.upper()),
         "fc": float(fc), "gain": float(g), "q": float(q)}
        for t, fc, g, q in FILTER_RE.findall(text)
    ]
    if not bands:
        return None
    return {"preamp": float(m.group(1)) if m else 0.0, "bands": bands}


def db_per_volt(hw):
    s, unit, z = hw.get("sensitivity"), (hw.get("sensitivityUnit") or "").lower(), hw.get("impedanceOhm")
    if s is None:
        return None
    if unit == "db/v":
        return s
    if unit == "db/mw" and z:
        return s + 10 * math.log10(1000.0 / z)
    return None


def drive(hw):
    dbv = db_per_volt(hw)
    if dbv is not None:
        v = 10 ** ((110.0 - dbv) / 20.0)
        if v < 0.5:
            return "low", False, v
        if v < 1.5:
            return "high", False, v
        return "high", True, v
    if hw["type"] in ("iem", "earbud", "tws"):
        return "low", False, None
    z = hw.get("impedanceOhm")
    if z is None:
        return "high", False, None
    if z >= 150:
        return "high", True, None
    if z >= 50:
        return "high", False, None
    return "low", False, None


def is_wired(conn):
    return conn in ("wired", "wired-3.5", "wired-4.4", "wired+bluetooth")


def rationale(hw):
    if not is_wired(hw["connection"]):
        return "Bluetooth: the M500's DAC is not in this signal path, so only the EQ applies."
    gain, hp, v = drive(hw)
    setting = f"{gain} gain and High Power {'on' if hp else 'off'}."
    if v is not None:
        return f"Needs about {v:.2f} V to reach 110 dB SPL peaks: {setting}"
    return f"No sensitivity spec. Going by type and impedance: {setting}"


def build(entry, refresh, offline):
    hw = {
        "brand": entry["brand"],
        "model": entry["model"],
        "type": entry["type"],
        "connection": entry["connection"],
    }
    for k in ("impedanceOhm", "sensitivity", "sensitivityUnit", "discontinued"):
        if entry.get(k) is not None:
            hw[k] = entry[k]

    eq = None
    url = entry.get("autoeqPath")
    if url:
        eq = parse_peq(fetch(url, refresh, offline))
    rec = {}
    if eq and any(abs(b["gain"]) > 1e-9 for b in eq["bands"]):
        rec["eqEnabled"] = True
        rec["eq"] = eq
    else:
        rec["eqEnabled"] = False
        rec["eq"] = {"preamp": 0.0, "bands": []}
    if is_wired(hw["connection"]):
        gain, hp, _ = drive(hw)
        rec.update({"digitalFilter": FILTER_DEFAULT, "gain": gain, "highPower": hp, "dre": True})

    source = {"rationale": rationale(hw)}
    if eq:
        src = entry.get("autoeqSource") or "AutoEq"
        source["eq"] = f"AutoEq, measured by {src}"
        source["eqUrl"] = url
    if entry.get("specSource"):
        source["spec"] = entry["specSource"]
    # The catalog's "notes" are research notes for whoever maintains this list (spec conflicts,
    # which retailer page a number came from). They stay in catalog.json and are not shipped.

    return {
        "id": slug(f"{entry['brand']} {entry['model']}"),
        "name": entry.get("name") or (entry["model"] if entry["model"].lower().startswith(entry["brand"].lower())
                                      else f"{entry['brand']} {entry['model']}"),
        "builtIn": True,
        "hardware": hw,
        "recommended": rec,
        "overrides": {},
        "autoSwitch": [],
        "source": source,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh", action="store_true")
    ap.add_argument("--offline", action="store_true")
    ap.add_argument("--catalog", default=CATALOG)
    ap.add_argument("--out", default=OUT)
    a = ap.parse_args()

    with open(a.catalog, encoding="utf-8") as f:
        catalog = json.load(f)
    profiles, seen = [], set()
    for entry in catalog:
        p = build(entry, a.refresh, a.offline)
        if p["id"] in seen:
            print(f"  ! duplicate id {p['id']}, skipped", file=sys.stderr)
            continue
        seen.add(p["id"])
        profiles.append(p)
        print(f"{p['id']:40s} eq={'yes' if p['recommended']['eqEnabled'] else 'no ':3s} "
              f"gain={p['recommended'].get('gain', '-'):4s} hp={p['recommended'].get('highPower', '-')}")

    out = {
        "version": 1,
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "generator": "tools/profiles/gen_listening_profiles.py",
        "attribution": ATTRIBUTION,
        # MIT asks for its notice to travel with copies of substantial portions; the curves are.
        "autoeqLicense": open(os.path.join(HERE, "AutoEq-LICENSE.txt"), encoding="utf-8").read(),
        "profiles": profiles,
    }
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
        f.write("\n")

    by_brand = {}
    for p in profiles:
        b = by_brand.setdefault(p["hardware"]["brand"], [0, 0])
        b[0] += 1
        b[1] += 1 if p["recommended"]["eqEnabled"] else 0
    for b, (n, e) in sorted(by_brand.items()):
        print(f"{b}: {n} profiles, {e} with AutoEq EQ, {n - e} flat")
    print(f"wrote {a.out}")


if __name__ == "__main__":
    main()
