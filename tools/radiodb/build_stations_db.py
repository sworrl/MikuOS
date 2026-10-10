#!/usr/bin/env python3
"""Normalise the FCC pipe-delimited station lists into one compact SQLite file.

Source: the FCC's own AM/FM query "list=4" text output, which is US federal public-domain
record data and includes the Canadian and Mexican stations coordinated under the border
agreements. Nothing here is scraped or copyrighted; logos are deliberately NOT included and are
fetched per-device at runtime instead.
"""
import re, sqlite3, sys, os

def dms(d, m, s, hemi):
    try:
        v = abs(float(d)) + float(m) / 60.0 + float(s) / 3600.0
    except (TypeError, ValueError):
        return None
    if hemi in ("S", "W"):
        v = -v
    return round(v, 6)

def num(x):
    if x is None: return None
    t = re.sub(r"[^0-9.\-]", "", x)
    if t in ("", "-", ".", "-."): return None
    try: return float(t)
    except ValueError: return None

def clean(x):
    return (x or "").strip() or None

rows = []
for path, kind in (("fm.txt", "FM"), ("FX.txt", "FX"), ("FL.txt", "FL"), ("am.txt", "AM")):
    if not os.path.exists(path):
        print(f"  (skip {path}, not present)"); continue
    n = 0
    for line in open(path, errors="replace"):
        f = line.rstrip("\n").split("|")
        if len(f) < 30: continue
        call = clean(f[1])
        if not call or call == "-": continue
        freq = num(f[2])
        if freq is None: continue
        # FM/FX/FL are MHz, AM is kHz; store kHz throughout so one integer sorts the band.
        khz = int(round(freq * 1000)) if kind != "AM" else int(round(freq))
        lat = dms(f[20], f[21], f[22], clean(f[19]))
        lon = dms(f[24], f[25], f[26], clean(f[23]))
        # Facility id sits at a fixed offset from the end: the line ends with
        # |<facility_id>|<uuid>|<uuid>| so after split() that is f[-4], with f[-1] the empty
        # string after the final pipe. Scanning backwards for "a short number" instead picked
        # up antenna heights and dated only 4% of the set.
        fac = None
        if len(f) >= 4:
            c = clean(f[-4])
            if c and c.isdigit():
                fac = int(c)
        rows.append((
            call, kind, khz, clean(f[7]), clean(f[9]), clean(f[10]), clean(f[11]), clean(f[12]),
            clean(f[27]), lat, lon, num(f[14]), num(f[16]), num(f[31]), fac,
        ))
        n += 1
    print(f"  {path}: {n} parsed")

db = "stations.sqlite"
if os.path.exists(db): os.remove(db)
con = sqlite3.connect(db)
con.executescript("""
PRAGMA page_size=4096;
CREATE TABLE station(
  call TEXT NOT NULL,
  service TEXT NOT NULL,        -- FM full power, FX translator, FL LPFM, AM
  khz INTEGER NOT NULL,         -- kHz for every service, so one column sorts the dial
  class TEXT, status TEXT,
  city TEXT, state TEXT, country TEXT,
  licensee TEXT,
  lat REAL, lon REAL,           -- transmitter site, WGS84
  erp_kw REAL,                  -- effective radiated power
  haat_m REAL,                  -- height above average terrain
  rcamsl_m REAL,                -- antenna height above mean sea level, for terrain work
  facility_id INTEGER
);
""")
con.executemany("INSERT INTO station VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", rows)
con.executescript("""
CREATE INDEX idx_khz  ON station(khz);
CREATE INDEX idx_geo  ON station(lat, lon);
CREATE INDEX idx_call ON station(call);
CREATE INDEX idx_fac  ON station(facility_id);
""")
con.commit()
print(f"\ntotal {len(rows)} stations")
for r in con.execute("SELECT country, service, COUNT(*) FROM station GROUP BY 1,2 ORDER BY 3 DESC LIMIT 12"):
    print(f"  {r[0] or '??'} {r[1]}: {r[2]}")
print(f"  with coordinates: {con.execute('SELECT COUNT(*) FROM station WHERE lat IS NOT NULL').fetchone()[0]}")
con.execute("VACUUM"); con.close()
print(f"  {db}: {os.path.getsize(db)/1048576:.1f} MB")

# ---------------------------------------------------------------- history join
# CDBS facility.dat carries the date each call sign took effect, which is the closest thing in
# the public record to "how long has this station been on the air under this name". It is not a
# founding date and is not presented as one.
import datetime
con = sqlite3.connect(db)
con.execute("ALTER TABLE station ADD COLUMN callsign_since TEXT")
con.execute("ALTER TABLE station ADD COLUMN licence_expires TEXT")
con.execute("ALTER TABLE station ADD COLUMN zip TEXT")

def iso(d):
    d = (d or "").strip()
    if not d or d.count("/") != 2: return None
    m, dd, y = d.split("/")
    try: return f"{int(y):04d}-{int(m):02d}-{int(dd):02d}"
    except ValueError: return None

# Join on CALL SIGN, not the id column. The FCC query output's numeric id is an LMS-era
# identifier (WCLG-FM reads 187048 there) while facility.dat is CDBS and uses the legacy
# facility id (WCLG-FM is 6553). They do not correspond, and joining them dated 2% of the set.
hist = {}
for line in open("facility.dat", errors="replace"):
    f = line.rstrip("\n").split("|")
    if len(f) < 23: continue
    call = (f[5] or "").strip().upper()
    if not call: continue
    svc = (f[10] or "").strip().upper()
    hist[(call, svc)] = (iso(f[21]), iso(f[15]), (f[17] or "").strip() or None)

n = 0
for (call, svc), (since, exp, zp) in hist.items():
    # CDBS services: FM, AM, FX (translator), FL (LPFM) line up with ours.
    cur = con.execute(
        "UPDATE station SET callsign_since=?, licence_expires=?, zip=? "
        "WHERE call=? AND (service=? OR ?='')",
        (since, exp, zp, call, svc, svc))
    n += cur.rowcount
con.commit()
have = con.execute("SELECT COUNT(*) FROM station WHERE callsign_since IS NOT NULL").fetchone()[0]
oldest = con.execute(
    "SELECT call, city, state, callsign_since FROM station "
    "WHERE callsign_since IS NOT NULL ORDER BY callsign_since LIMIT 3").fetchall()
print(f"\nhistory: {len(hist)} facility records, {have} stations dated")
for o in oldest: print(f"  oldest: {o[0]} {o[1]}, {o[2]} since {o[3]}")
con.execute("VACUUM"); con.commit(); con.close()
print(f"  {db}: {os.path.getsize(db)/1048576:.1f} MB")

# ---------------------------------------------------------------- formats (optional)
# --formats adds format/genre/format_source from Wikipedia infoboxes (add_formats.py). It is
# opt-in because it is the one step that talks to a non-government source and needs network
# for several minutes on a cold cache; the government-data build above stays offline.
if "--formats" in sys.argv:
    import subprocess
    subprocess.run([sys.executable, "-I",
                    os.path.join(os.path.dirname(os.path.abspath(__file__)), "add_formats.py"),
                    db], check=True)
