#!/usr/bin/env python3
"""Build the bundled NOAA Weather Radio (NWR) transmitter list for the FM app.

Source: https://www.weather.gov/source/nwr/JS/ccl-data.js -- the data file behind NWS's own
NWR station listing and coverage pages (weather.gov/nwr/station_listing,
weather.gov/nwr/stations?State=XX). It is a single JavaScript assignment
`var cclData = [...]` whose right-hand side is plain JSON, one object per transmitter with
callsign, freq, status, power, lat, lon, sitename, siteloc, sitestate, wfo and the counties
(with SAME codes) it covers. US federal data, public domain.

NWR is on 162.400-162.550 MHz. The phone's Si4705 tunes 64-108 MHz only, so this list is
reference data for a separate weather radio or ham handheld, not something the tuner can play.

Usage:
    python3 build_nwr.py                  # download, write the asset
    python3 build_nwr.py ccl-data.js      # build from an already-downloaded copy
    python3 build_nwr.py SRC OUT.json     # explicit output path
"""
import json, os, sys, urllib.request

URL = "https://www.weather.gov/source/nwr/JS/ccl-data.js"
UA = "MikuOS-radiodb/1.0 (https://github.com/sworrl/MikuOS)"
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.join(HERE, "..", "..", "miku-player-kotlin", "fmradio", "src", "main",
                           "assets", "nwr_transmitters.json")

# The seven NWR channels. WX numbering is the conventional weather-radio one.
WX = {"162.550": "WX1", "162.400": "WX2", "162.475": "WX3", "162.425": "WX4",
      "162.450": "WX5", "162.500": "WX6", "162.525": "WX7"}


def fetch(src):
    if src and os.path.exists(src):
        with open(src, encoding="utf-8", errors="replace") as f:
            return f.read()
    req = urllib.request.Request(src or URL, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8", errors="replace")


def parse(text):
    # Strip `var cclData = ` and the trailing `;`; what is left is a JSON array.
    a, b = text.find("["), text.rfind("]")
    if a < 0 or b < a:
        raise SystemExit("ccl-data.js: no JSON array found -- has NWS changed the format?")
    return json.loads(text[a:b + 1])


def num(x):
    try:
        return float(str(x).strip())
    except (TypeError, ValueError):
        return None


def clean(x):
    x = (x or "").strip()
    return x or None


def build(rows):
    out = []
    for r in rows:
        lat, lon = num(r.get("lat")), num(r.get("lon"))
        call = clean(r.get("callsign"))
        # Only rows with real coordinates; this also drops the "---No NWR Coverage---"
        # placeholder row the counties table uses.
        if not call or lat is None or lon is None or (lat == 0 and lon == 0):
            continue
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            continue
        freq = clean(r.get("freq"))
        mhz = num(freq)
        # Normalise to three decimals so "162.55" and "162.550" map the same.
        key = f"{mhz:.3f}" if mhz is not None else None
        watts = num(r.get("power"))
        wfo = clean(r.get("wfo"))
        if wfo and "|" in wfo:  # "Quad Cities|IA" -> "Quad Cities, IA"
            name, st = wfo.split("|", 1)
            wfo = f"{name.strip()}, {st.strip()}" if st.strip() else name.strip()
        rec = {
            "call": call,
            "mhz": round(mhz, 3) if mhz is not None else None,
            "wx": WX.get(key),
            "site": clean(r.get("sitename")),   # NWS "Site Name" (the service-area name)
            "city": clean(r.get("siteloc")),    # NWS "Site Location" (town or peak of the tower)
            "state": clean(r.get("sitestate")),
            "lat": round(lat, 5),
            "lon": round(lon, 5),
            "watts": int(watts) if watts else None,
            "wfo": wfo,
            "status": clean(r.get("status")),
        }
        out.append({k: v for k, v in rec.items() if v is not None})
    out.sort(key=lambda o: (o.get("state", ""), o["call"]))
    return out


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else None
    dst = os.path.abspath(sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUT)
    rows = parse(fetch(src))
    out = build(rows)
    if len(out) < 500:  # NWR has ~1,000 transmitters; far fewer means a broken download
        raise SystemExit(f"only {len(out)} transmitters parsed from {len(rows)} rows; refusing")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    tmp = dst + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, dst)
    print(f"{len(rows)} source rows -> {len(out)} transmitters, "
          f"{os.path.getsize(dst)} bytes -> {dst}")


if __name__ == "__main__":
    main()
