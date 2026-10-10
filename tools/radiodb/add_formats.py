#!/usr/bin/env python3
"""Add a music-format column to the station catalogue, from English Wikipedia infoboxes.

    python3 -I add_formats.py [path/to/stations.sqlite]

The FCC record says where a station is and how loud it is, never what it plays. Wikidata has a
format property (P415) but only ~1,700 US stations carry it. Wikipedia, on the other hand, has
an article for nearly every full-power US and Canadian station, titled by call sign, and the
"Infobox radio station" in each one has a `format` field that editors keep reasonably current.
That field is what this script reads. It is CC BY-SA text, so every row keeps the title of the
article it came from in `format_source`.

Adds three columns to `station`: `format` (the infobox text, markup stripped, <=80 chars),
`genre` (one normalised bucket for filtering and colouring) and `format_source`.

Everything fetched is cached in .cache/ next to this script, so a rerun after an interruption
picks up where it stopped and a rerun after a parser change costs no network at all.

Python standard library only.
"""
import gzip, json, os, re, sqlite3, sys, time, urllib.error, urllib.parse, urllib.request
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DB = os.path.join(HERE, "..", "..", "mikuos", "data", "stations.sqlite")
CACHE = os.path.join(HERE, ".cache", "wikipedia_formats.json.gz")
API = "https://en.wikipedia.org/w/api.php"
UA = "MikuOS-radiodb/1.0 (https://github.com/sworrl/MikuOS)"
BATCH = 50          # the API's per-request title limit for normal accounts
PAUSE = 0.15        # between requests; Wikipedia asks for serial, polite clients

# ------------------------------------------------------------------------------------ fetching

def api(params):
    """One GET against the MediaWiki API, retrying 429/5xx and maxlag with backoff."""
    params = dict(params, format="json", formatversion="2", maxlag="5")
    url = API + "?" + urllib.parse.urlencode(params)
    delay = 2.0
    for attempt in range(8):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Encoding": "gzip"})
            with urllib.request.urlopen(req, timeout=60) as r:
                body = r.read()
                if r.headers.get("Content-Encoding") == "gzip":
                    body = gzip.decompress(body)
            data = json.loads(body)
            if data.get("error", {}).get("code") == "maxlag":
                time.sleep(delay); delay = min(delay * 2, 60); continue
            time.sleep(PAUSE)
            return data
        except urllib.error.HTTPError as e:
            if e.code == 429 or e.code >= 500:
                wait = float(e.headers.get("Retry-After") or delay)
                print(f"    HTTP {e.code}, backing off {wait:.0f}s", flush=True)
                time.sleep(wait); delay = min(delay * 2, 120); continue
            raise
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            print(f"    {e}, retrying in {delay:.0f}s", flush=True)
            time.sleep(delay); delay = min(delay * 2, 120)
    raise RuntimeError("Wikipedia API kept failing; rerun later, the cache keeps what we have")

def fetch_content(titles, lead_only=True):
    """Return {requested title: (final title or None, fragment, wikitext)} for up to 50 titles.

    Follows redirects, because a call-sign title is very often a redirect: a translator's call
    points at the station it relays, a network repeater's call points at the network."""
    p = {"action": "query", "prop": "revisions", "rvprop": "content", "rvslots": "main",
         "redirects": "1", "titles": "|".join(titles)}
    if lead_only:
        p["rvsection"] = "0"
    norm, redir, text = {}, {}, {}
    missing = set()
    cont = {}
    while True:
        d = api(dict(p, **cont))
        q = d.get("query", {})
        for n in q.get("normalized", []):
            norm[n["from"]] = n["to"]
        for r in q.get("redirects", []):
            redir[r["from"]] = (r["to"], r.get("tofragment"))
        for pg in q.get("pages", []):
            if pg.get("missing") or pg.get("invalid"):
                missing.add(pg["title"]); continue
            revs = pg.get("revisions")
            if revs:   # a big batch can come back across several continuation responses
                text[pg["title"]] = revs[0]["slots"]["main"].get("content", "")
        if "continue" not in d:
            break
        cont = d["continue"]
    out = {}
    for t in titles:
        cur, frag = norm.get(t, t), None
        for _ in range(5):          # follow a short redirect chain, never loop
            if cur not in redir: break
            cur, f = redir[cur]
            frag = f or frag
        if cur in missing or cur not in text:
            out[t] = (None, None, "")
        else:
            out[t] = (cur, frag, text[cur])
    return out

# ------------------------------------------------------------------------------- wikitext parse

def templates(text):
    """Yield (start, end) of every top-level {{...}} in text, matching nested braces."""
    i, n = 0, len(text)
    while True:
        i = text.find("{{", i)
        if i < 0: return
        depth, j = 0, i
        while j < n - 1:
            two = text[j:j + 2]
            if two == "{{": depth += 1; j += 2; continue
            if two == "}}":
                depth -= 1; j += 2
                if depth == 0: break
                continue
            j += 1
        if depth != 0: return
        yield i, j
        i = j

def split_top(body):
    """Split template body on '|' that is not inside a nested template or wikilink."""
    parts, cur, depth_t, depth_l, i = [], [], 0, 0, 0
    while i < len(body):
        two = body[i:i + 2]
        if two == "{{": depth_t += 1; cur.append(two); i += 2; continue
        if two == "}}": depth_t -= 1; cur.append(two); i += 2; continue
        if two == "[[": depth_l += 1; cur.append(two); i += 2; continue
        if two == "]]": depth_l -= 1; cur.append(two); i += 2; continue
        c = body[i]
        if c == "|" and depth_t == 0 and depth_l == 0:
            parts.append("".join(cur)); cur = []
        else:
            cur.append(c)
        i += 1
    parts.append("".join(cur))
    return parts

def infoboxes(text):
    """[(kind, {field: raw value})] for each infobox in the lead. kind is 'station' for a radio
    station infobox, otherwise the template name (e.g. 'infobox radio network')."""
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    out = []
    for a, b in templates(text):
        parts = split_top(text[a + 2:b - 2])
        name = re.sub(r"[\s_]+", " ", parts[0]).strip().lower()
        if not name.startswith("infobox"): continue
        fields = {}
        for p in parts[1:]:
            if "=" in p:
                k, v = p.split("=", 1)
                fields[k.strip().lower()] = v.strip()
        kind = "station" if is_station(name) else name
        out.append((kind, fields))
    return out

def is_station(kind):
    # "Infobox radio station dual" covers two stations in one article (name1/frequency1, ...)
    return kind in ("station", "infobox radio", "infobox radio stations") or \
        kind.startswith("infobox radio station")

LIST_TEMPLATES = {"ubl", "unbulleted list", "plainlist", "plain list", "flatlist", "flat list",
                  "hlist", "bulleted list", "bull list", "ublist", "unbulleted"}
KEEP_TEMPLATES = {"nowrap", "nobr", "small", "big", "nowrap begin", "longitem", "lang", "lang-es",
                  "lang-fr", "transl", "abbr", "sic", "frequency", "radio relay", "nbsp", "spaces",
                  "nobold", "noitalic", "smaller", "resize", "tooltip", "plain"}

def render_template(body):
    parts = [p.strip() for p in split_top(body)]
    name = parts[0].lower().replace("_", " ").strip()
    args = [p for p in parts[1:] if p and not re.match(r"^\w[\w ]*=", p)]
    if name in LIST_TEMPLATES:
        items = []
        for a in args:     # {{plainlist|\n* a\n* b}} puts the whole list in one argument
            items += [x.strip() for x in re.split(r"(?:^|\n)\s*[*#]+", a) if x.strip()]
        return ", ".join(items)
    if name in ("nbsp", "spaces"): return " "
    if name in ("lang",) and len(args) >= 2: return args[-1]
    if name in ("abbr", "tooltip") and args: return args[0]
    if name in KEEP_TEMPLATES or name.startswith("lang-"):
        return " ".join(args)
    return ""        # citations, {{HD Radio}}, dates, efn notes: none of it is format text

def strip_markup(s):
    s = re.sub(r"<!--.*?-->", "", s, flags=re.S)
    s = re.sub(r"<ref[^>]*/\s*>", "", s, flags=re.I)
    s = re.sub(r"<ref[^>]*>.*?</ref\s*>", "", s, flags=re.I | re.S)
    s = re.sub(r"<br\s*/?\s*>", ", ", s, flags=re.I)
    s = re.sub(r"\[\[(?:File|Image):[^\]]*\]\]", "", s, flags=re.I)
    # wikilinks before templates: a piped link inside {{ubl|...}} would otherwise split it
    s = re.sub(r"\[\[[^\[\]|]*\|([^\[\]]*)\]\]", r"\1", s)
    s = re.sub(r"\[\[([^\[\]]*)\]\]", r"\1", s)
    for _ in range(10):  # innermost templates first, so nesting resolves outward
        t = re.sub(r"\{\{([^{}]*)\}\}", lambda m: render_template(m.group(1)), s)
        if t == s: break
        s = t
    s = re.sub(r"\{\{|\}\}", "", s)
    s = re.sub(r"\[https?://\S+\s+([^\]]*)\]", r"\1", s)
    s = re.sub(r"\[https?://\S+\]", "", s)
    s = re.sub(r"<[^>]+>", "", s)
    s = re.sub(r"'{2,}", "", s)
    s = s.replace("&nbsp;", " ").replace("&amp;", "&").replace(" ", " ")
    s = re.sub(r"(?:^|\n)\s*[*#]+\s*", ", ", s)
    s = re.sub(r"\s+", " ", s)
    s = re.sub(r"\s*,\s*(?:,\s*)+", ", ", s)
    s = re.sub(r"\s+([,;:)])", r"\1", s)
    return s.strip(" ,;:-")

def shorten(s, n=80):
    if len(s) <= n: return s
    cut = s[:n]
    k = max(cut.rfind(", "), cut.rfind("; "), cut.rfind(" / "))
    if k < 20: k = cut.rfind(" ")
    return cut[:k].rstrip(" ,;/") if k > 0 else cut

def format_of(fields):
    v = shorten(strip_markup(fields.get("format") or fields.get("format1") or ""))
    if re.search(r"[|=\[\]{}]", v):    # an unclosed link in the article swallowed the infobox
        return None
    return v or None

# ----------------------------------------------------------------------------------- matching

def norm_call(c):
    c = re.sub(r"\s*\((?:AM|FM)\)$", "", c.strip().upper())
    return re.sub(r"-(?:FM|AM)$", "", c)

def ca_call(call):
    """FCC data spells Canadian calls inconsistently (CBEEFM, CHRI-FM1, CBON23, CIGV-2);
    Wikipedia uses CBEE-FM, CHRI-FM-1, CBON-FM-23."""
    m = re.match(r"^([A-Z]{3,4})FM$", call)
    if m: return m.group(1) + "-FM"
    m = re.match(r"^([A-Z]{4})-?FM-?(\d+)$", call)
    if m: return f"{m.group(1)}-FM-{m.group(2)}"
    m = re.match(r"^([A-Z]{4})-?(\d+)$", call)
    if m: return f"{m.group(1)}-FM-{m.group(2)}"
    return call

def variants(call, service, country):
    if country == "CA" and service != "AM":
        call = ca_call(call)
    if service == "FX":
        return [call]
    if service == "AM":
        return [call, call + " (AM)"] if "-" not in call else [call]
    if call.endswith("-FM"):
        base = call[:-3]
        return [call, base, base + " (FM)"]
    if "-" in call:            # -LP, Canadian -FM-2 rebroadcasters: the title is the call
        return [call]
    return [call, call + "-FM", call + " (FM)"]

NUM = re.compile(r"\d+(?:\.\d+)?")

def freq_numbers(fields):
    # numbered keys are the dual-station infobox
    v = " ".join(x for k, x in fields.items() if re.match(r"^frequency\d?$", k))
    v = re.sub(r"<ref[^>]*/\s*>|<ref[^>]*>.*?</ref\s*>", "", v, flags=re.I | re.S)
    return [float(x) for x in NUM.findall(v.replace(",", ""))], v.lower()

def freq_match(fields, service, khzs):
    nums, _ = freq_numbers(fields)
    for k in khzs:
        want = k / 1000.0 if service != "AM" else float(k)
        if any(abs(x - want) < 0.001 for x in nums):
            return True
    return False

def band_ok(fields, service):
    nums, raw = freq_numbers(fields)
    if service == "AM":
        return "khz" in raw or any(530 <= x <= 1710 for x in nums)
    return "mhz" in raw or any(87.5 <= x <= 108.0 for x in nums)

def name_match(fields, call, service):
    want = norm_call(call)
    keys = ("name", "callsign", "call_sign", "call_letters", "call", "station_name")
    for key in [k + n for k in keys for n in ("", "1", "2")]:
        v = strip_markup(fields.get(key, "")).upper()
        if v and norm_call(v) == want:
            return band_ok(fields, service)
    return False

RELAY_FIELD = re.compile(r"translat|repeat|rebroad|booster|relay")

def relayed_calls(fields):
    """Calls listed in an infobox's translator/repeater/rebroadcaster fields, minus any that
    relay an HD subchannel: those carry a different programme from the main format."""
    out = set()
    for k, v in fields.items():
        if not RELAY_FIELD.search(k): continue
        for m in re.finditer(r"(?<![A-Z0-9])([KWC][A-Z0-9]{2,5}(?:-(?:FM|LP|AM))?(?:-\d+)?)(?![A-Z0-9])", v):
            seg_a = max(v.rfind("{{", 0, m.start()), v.rfind("<br", 0, m.start()),
                        v.rfind("\n", 0, m.start()), m.start() - 40)
            ends = [x for x in (v.find("{{", m.end()), v.find("<br", m.end()),
                                v.find("\n", m.end())) if x >= 0]
            seg_b = min(ends + [m.end() + 40])
            if re.search(r"HD\s*\d", v[seg_a:seg_b]): continue
            out.add(m.group(1))
    return out

NETWORK_KIND = re.compile(r"radio|broadcast|television|network")

GENERIC_NETWORK = re.compile(r"^(radio|radio network|network|broadcast(ing)? network|"
                             r"public broadcasting|television|tv)$", re.I)

def network_format(fields):
    for key in ("format", "network_type", "genre", "programming", "type"):
        v = shorten(strip_markup(fields.get(key, "")))
        if key == "type" and re.search(r"televi|\btv\b", v, re.I): continue
        if v and not GENERIC_NETWORK.match(v):
            return v
    aff = strip_markup(fields.get("affiliations", "") + " " + fields.get("network", ""))
    if re.search(r"\bNPR\b|National Public Radio", aff):
        return "Public radio"
    return None

def CALL_TOKEN_IN(call, text):
    return re.search(r"(?<![A-Za-z0-9])" + re.escape(call) + r"(?![A-Za-z0-9])", text) is not None

CALL_TOKEN = re.compile(r"(?<![A-Za-z0-9])([KWC][A-Z0-9]{2,5}(?:-(?:FM|LP|AM))?(?:-\d+)?)(?![A-Za-z0-9])")

# ------------------------------------------------------------------------------------- genres

# Two tiers. The first is checked in table order and wins outright wherever it appears in the
# text: a station described as "adult contemporary Christian" is a Christian station to anyone
# scanning the dial. The second tier is positional: the keyword that appears EARLIEST in the
# format text wins, because infoboxes list the primary format first ("News/talk/sports" is a
# talk station, "Sports/talk" is a sports station). Ties at the same position go to the longer
# keyword, which is how "classic rock" beats "rock".
DOMINANT = [
    ("Gospel",     [r"gospel"]),
    ("Christian",  [r"christian", r"\bccm\b", r"worship", r"praise", r"inspirational"]),
    ("Religious",  [r"religio", r"catholic", r"bible", r"islam", r"sermon", r"teaching",
                    r"ministr", r"evangel", r"church", r"jewish"]),
    ("Spanish",    [r"spanish", r"regional mexican", r"mexican", r"tejano", r"ranchera",
                    r"\blatin", r"tropical", r"banda", r"norte[ñn]o", r"salsa", r"reggaet",
                    r"hispanic", r"\bespa[ñn]ol"]),
    ("College",    [r"college", r"student", r"campus", r"high school", r"\bschool"]),
    ("Children's", [r"children", r"\bkids\b", r"radio disney"]),
    ("Comedy",     [r"comedy"]),
]
POSITIONAL = [
    ("Classic Rock",       [r"classic rock"]),
    ("Classic Hits",       [r"classic hits", r"greatest hits", r"\b(?:19)?[5-9]0'?s hits"]),
    ("Oldies",             [r"oldies", r"adult standards", r"nostalgia", r"big band",
                            r"\bstandards"]),
    ("Variety",            [r"adult album alternative", r"\baaa\b", r"triple a", r"variety",
                            r"free ?-?form", r"eclectic", r"community", r"full[ -]service",
                            r"various", r"diversified",
                            r"adult hits"]),
    ("Alternative",        [r"alternative", r"modern rock", r"\bindie"]),
    ("Rock",               [r"rock", r"metal"]),
    ("Country",            [r"country", r"americana", r"bluegrass"]),
    ("Hot AC",             [r"hot adult", r"hot ac\b", r"adult top 40", r"modern adult"]),
    ("Top 40",             [r"contemporary hit", r"\bchr\b", r"top 40", r"top-40", r"\bpop\b",
                            r"rhythmic"]),
    ("Adult Contemporary", [r"rhythmic adult contemporary", r"adult contemporary", r"soft ac\b", r"\bac\b", r"soft adult",
                            r"easy listening", r"\blite\b", r"beautiful music"]),
    ("Urban",              [r"urban"]),
    ("Hip Hop",            [r"hip[ -]?hop", r"\brap\b"]),
    ("R&B",                [r"r&b", r"rhythm and blues", r"\bsoul\b", r"\brnb\b"]),
    ("Jazz",               [r"jazz"]),
    ("Classical",          [r"classical", r"fine arts"]),
    ("Dance",              [r"\bdance", r"\bedm\b", r"electronic"]),
    ("Public Radio",       [r"\bnpr\b", r"public radio", r"public broadcast", r"\bcbc\b",
                            r"radio-canada", r"pacifica", r"\bpublic\b"]),
    ("Sports",             [r"sports?\b", r"\bespn"]),
    ("News/Talk",          [r"\bnews", r"\btalk", r"conservative", r"information",
                            r"business"]),
]
DOMINANT_RE = [(g, [re.compile(k) for k in ks]) for g, ks in DOMINANT]
POSITIONAL_RE = [(g, [re.compile(k) for k in ks]) for g, ks in POSITIONAL]

def genre_of(fmt):
    if not fmt: return None
    t = fmt.lower()
    for g, ks in DOMINANT_RE:
        if any(k.search(t) for k in ks): return g
    best = None
    for g, ks in POSITIONAL_RE:
        for k in ks:
            m = k.search(t)
            if m:
                cand = (m.start(), -(m.end() - m.start()), g)
                if best is None or cand < best: best = cand
    return best[2] if best else "Other"

# ---------------------------------------------------------------------------------------- main

def load_cache():
    try:
        with gzip.open(CACHE, "rt") as f:
            c = json.load(f)
        for k in ("titles", "pages", "full", "links"): c.setdefault(k, {})
        return c
    except (OSError, ValueError):
        return {"titles": {}, "pages": {}, "full": {}, "links": {}}

def save_cache(c):
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    tmp = CACHE + ".tmp"
    with gzip.open(tmp, "wt", compresslevel=6) as f:
        json.dump(c, f, separators=(",", ":"))
    os.replace(tmp, CACHE)

def ensure_titles(cache, titles, label):
    todo = sorted({t for t in titles if t not in cache["titles"]})
    if not todo:
        print(f"  {label}: {len(set(titles))} titles, all cached", flush=True); return
    print(f"  {label}: {len(set(titles))} titles, fetching {len(todo)}", flush=True)
    t0 = time.time()
    for i in range(0, len(todo), BATCH):
        chunk = todo[i:i + BATCH]
        for req, (final, frag, text) in fetch_content(chunk).items():
            cache["titles"][req] = [final, frag]
            if final and final not in cache["pages"]:
                # Keep only the infoboxes. The lead prose is not used and would make the cache
                # ten times larger.
                cache["pages"][final] = [[k, f] for k, f in infoboxes(text)]
        done = min(i + BATCH, len(todo))
        if (i // BATCH) % 10 == 9 or done == len(todo):
            rate = done / max(time.time() - t0, 1e-6)
            print(f"    {done}/{len(todo)}  ({rate:.0f} titles/s)", flush=True)
            save_cache(cache)

def ensure_full(cache, pages):
    """Full text of redirect targets (networks, parent stations), reduced to the set of call
    signs they mention, so a redirect from a call sign can be confirmed against the target's
    station list instead of trusted blindly."""
    todo = sorted({p for p in pages if p not in cache["full"]})
    if not todo: return
    print(f"  redirect targets: fetching full text of {len(todo)}", flush=True)
    for i in range(0, len(todo), 10):   # full articles are big; keep responses modest
        chunk = todo[i:i + 10]
        got = fetch_content(chunk, lead_only=False)
        for t in chunk:
            final, _, text = got[t]
            cache["full"][t] = sorted(set(CALL_TOKEN.findall(text))) if final else []
    save_cache(cache)

def resolve_titles(cache, titles):
    """Where each wikilink target ends up after redirects (no content fetched)."""
    todo = sorted({t for t in titles if t not in cache["links"]})
    if todo:
        print(f"  resolving {len(todo)} network link targets", flush=True)
    for i in range(0, len(todo), BATCH):
        chunk = todo[i:i + BATCH]
        d = api({"action": "query", "redirects": "1", "titles": "|".join(chunk)})
        q = d.get("query", {})
        norm = {n["from"]: n["to"] for n in q.get("normalized", [])}
        redir = {r["from"]: r["to"] for r in q.get("redirects", [])}
        for t in chunk:
            cur = norm.get(t, t)
            for _ in range(5):
                if cur not in redir: break
                cur = redir[cur]
            cache["links"][t] = cur
    if todo: save_cache(cache)

def main():
    db = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DB)
    if not os.path.exists(db):
        sys.exit(f"no catalogue at {db}")
    con = sqlite3.connect(db)
    rows = con.execute(
        "SELECT call, service, country, khz FROM station WHERE country IN ('US','CA') "
        "AND service IN ('FM','FX','FL','AM')").fetchall()
    stations = defaultdict(set)          # (call, service, country) -> {khz, ...}
    for call, svc, ctry, khz in rows:
        if not re.match(r"^[KWC][A-Z0-9]{2,}", call or ""): continue   # skips NEW, numeric ids
        stations[(call, svc, ctry)].add(khz)
    print(f"{len(stations)} distinct US/CA call+service pairs from {db}", flush=True)

    cache = load_cache()
    result = {}                          # station key -> (format, source, how)
    reasons = Counter()

    def judge(key, title):
        """Decide whether the page `title` resolves to describes this station.
        Returns (format, source, how) or None."""
        call, svc, ctry = key
        khzs = stations[key]
        if ctry == "CA" and svc != "AM":
            call = ca_call(call)
        final, frag = cache["titles"].get(title, [None, None])
        if not final: return None
        boxes = cache["pages"].get(final, [])
        redirected = final != title
        for kind, f in boxes:
            if not is_station(kind): continue
            if freq_match(f, svc, khzs) or name_match(f, call, svc):
                return (format_of(f), final, "article")
            if call in relayed_calls(f):
                return (format_of(f), final, "relay field")
        station_boxes = [f for k, f in boxes if is_station(k)]
        if svc == "FX" and redirected and not frag and station_boxes:
            # A translator's call redirecting to a station article is an editor's statement
            # that it relays that station. The exception is an FM parent with HD subchannels:
            # translators very often carry HD2/HD3, a different format, so do not guess there.
            f = station_boxes[0]
            nums, raw = freq_numbers(f)
            is_am = "khz" in raw or any(530 <= x <= 1710 for x in nums)
            if is_am or not strip_markup(f.get("subchannels", "")):
                return (format_of(f), final, "translator redirect")
            reasons["FX redirect to FM parent with HD subchannels"] += 1
            return None
        if svc != "FX" and redirected and not frag and station_boxes:
            # A full-power or LPFM call redirecting to another station's article is usually a
            # satellite or repeater of it (WHRE -> WHRV). Confirm the article actually names
            # this call, and that it is not naming it as a former call sign or a sister
            # station: both get redirects too, and both run a different format.
            # Same band only: an old Canadian AM call redirecting to the FM it moved to is the
            # common cross-band case, and that AM is gone, not relaying anything.
            nums, raw = freq_numbers(station_boxes[0])
            target_am = "khz" in raw or any(530 <= x <= 1710 for x in nums)
            if call in cache["full"].get(final, []) and target_am == (svc == "AM"):
                own = " ".join(v for k, v in station_boxes[0].items()
                               if re.search(r"former|sister|meaning", k))
                if not CALL_TOKEN_IN(call, own):
                    return (format_of(station_boxes[0]), final, "repeater redirect")
            return None
        # Networks only. "WHO" redirects to the World Health Organization and a college LPFM
        # to its university, and both of those articles mention the call too.
        others = [f for k, f in boxes if not is_station(k) and NETWORK_KIND.search(k)]
        if redirected and others and not station_boxes:
            fmt = network_format(others[0])
            if svc == "FX" or call in cache["full"].get(final, []):
                return (fmt, final, "network redirect")
        return None

    def needs_full(key, title):
        """Article whose full text judge() would want for this station, if any."""
        final, frag = cache["titles"].get(title, [None, None])
        if not final or final == title or final in cache["full"]: return None
        bx = cache["pages"].get(final, [])
        if not bx: return None
        if not any(is_station(k) for k, _ in bx):
            return final if any(NETWORK_KIND.search(k) for k, _ in bx) else None
        if key[1] != "FX" and not frag: return final
        return None

    # Pass over title variants in order; a station stops at the first page that matches it.
    main_keys = [k for k in stations if k[1] != "FX"]
    var = {k: variants(*k) for k in stations}
    depth = max(len(v) for v in var.values())
    for i in range(depth):
        pending = [k for k in main_keys if k not in result and len(var[k]) > i]
        if not pending: continue
        print(f"\nvariant pass {i + 1}: {len(pending)} stations unresolved", flush=True)
        ensure_titles(cache, [var[k][i] for k in pending], f"pass {i + 1}")
        for k in pending:
            r = judge(k, var[k][i])
            if r: result[k] = r
        # Only the redirects that did not match on their own need the target's full text.
        need = {needs_full(k, var[k][i]) for k in pending if k not in result} - {None}
        ensure_full(cache, need)
        for k in pending:
            if k in result: continue
            r = judge(k, var[k][i])
            if r: result[k] = r
        print(f"  resolved so far: {len(result)}", flush=True)

    # Translators. First, for free: every accepted article whose infobox lists translators
    # hands its format to them. Then fetch each remaining translator's own call, which on
    # Wikipedia is almost always a redirect to the station or network it relays.
    print("\ntranslators", flush=True)
    relay_map, conflict = {}, set()
    for k, (fmt, src, how) in list(result.items()):
        if how != "article": continue
        for kind, f in cache["pages"].get(src, []):
            if not is_station(kind) or not (freq_match(f, k[1], stations[k]) or
                                         name_match(f, k[0], k[1])): continue
            for c in relayed_calls(f):
                if c in relay_map and relay_map[c][0] != fmt: conflict.add(c)
                relay_map.setdefault(c, (fmt, src))
    fx_keys = [k for k in stations if k[1] == "FX"]
    n_relay = 0
    for k in fx_keys:
        if k[0] in relay_map and k[0] not in conflict:
            fmt, src = relay_map[k[0]]
            result[k] = (fmt, src, "parent's translator field"); n_relay += 1
    print(f"  {n_relay} translators named in a parent station's infobox", flush=True)
    pending = [k for k in fx_keys if k not in result]
    ensure_titles(cache, [var[k][0] for k in pending], "translator calls")
    for k in pending:
        r = judge(k, var[k][0])
        if r: result[k] = r

    # Networks. Most network infoboxes say only "network_type = Radio network", so a call that
    # redirects to American Family Radio or Moody Radio arrives with no format. The member
    # stations that do have their own article name the network in their infobox's network or
    # affiliations field and carry a format; if at least three of them do and one format is at
    # least half of them, the network gets that format. Still infobox data, one hop removed.
    blank = {src for fmt, src, how in result.values() if how == "network redirect" and not fmt}
    if blank:
        print("\nnetworks without a format of their own", flush=True)
        member = []
        for k, (fmt, src, how) in result.items():
            if how != "article" or not fmt: continue
            for kind, f in cache["pages"].get(src, []):
                if not is_station(kind): continue
                raw = f.get("network", "") + " " + f.get("affiliations", "")
                for t in re.findall(r"\[\[([^\]|#]+)", raw):
                    t = re.sub(r"[\s_]+", " ", t).strip()
                    if t: member.append((t[0].upper() + t[1:], fmt))
                break
        resolve_titles(cache, [t for t, _ in member])
        votes = defaultdict(Counter)
        for t, fmt in member:
            votes[cache["links"].get(t, t)][fmt] += 1
        net_fmt = {}
        for net in blank:
            v = votes.get(net)
            if not v: continue
            top, n = v.most_common(1)[0]
            if sum(v.values()) >= 3 and n * 2 >= sum(v.values()):
                net_fmt[net] = top
                print(f"  {net}: {top} ({n} of {sum(v.values())} member articles)")
        for k, (fmt, src, how) in list(result.items()):
            if how == "network redirect" and not fmt and src in net_fmt:
                result[k] = (net_fmt[src], src, "network members")
    save_cache(cache)

    # ---------------------------------------------------------------------------- write
    cols = {r[1] for r in con.execute("PRAGMA table_info(station)")}
    for c in ("format", "genre", "format_source"):
        if c not in cols:
            con.execute(f"ALTER TABLE station ADD COLUMN {c} TEXT")
    con.execute("UPDATE station SET format=NULL, genre=NULL, format_source=NULL")
    upd = []
    for (call, svc, ctry), (fmt, src, how) in result.items():
        if fmt:
            upd.append((fmt, genre_of(fmt), src, call, svc, ctry))
    con.executemany("UPDATE station SET format=?, genre=?, format_source=? "
                    "WHERE call=? AND service=? AND country=?", upd)
    con.execute("CREATE INDEX IF NOT EXISTS idx_genre ON station(genre)")
    con.commit()

    hows = Counter(how for fmt, src, how in result.values() if fmt)
    nofmt = sum(1 for fmt, _, _ in result.values() if not fmt)
    print(f"\nmatched {len(result)} call signs to an article; {nofmt} of those articles have "
          f"no format field")
    print("  matched by: " + ", ".join(f"{h} {n}" for h, n in hows.most_common()))
    for r, n in reasons.items(): print(f"  skipped: {r}: {n}")
    print("\ncoverage (rows)")
    print(f"  {'':8}{'stations':>9}{'format':>8}{'%':>6}")
    for ctry, svc, total, have in con.execute(
            "SELECT country, service, COUNT(*), COUNT(format) FROM station "
            "WHERE country IN ('US','CA') AND service IN ('FM','FX','FL','AM') "
            "GROUP BY 1,2 ORDER BY 1 DESC, 3 DESC"):
        print(f"  {ctry} {svc:5}{total:>9}{have:>8}{100.0 * have / total:>6.1f}")
    print("\ngenres")
    for g, n in con.execute("SELECT genre, COUNT(*) FROM station WHERE genre IS NOT NULL "
                            "GROUP BY 1 ORDER BY 2 DESC"):
        print(f"  {g:20}{n:>6}")
    con.execute("VACUUM"); con.close()
    print(f"\n  {db}: {os.path.getsize(db) / 1048576:.1f} MB")

if __name__ == "__main__":
    main()
