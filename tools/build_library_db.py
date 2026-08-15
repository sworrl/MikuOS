#!/usr/bin/env python3
"""
Build the M500 MIKU master music-library database from:
  - meta.txt     : MediaStore tags (path,title,artist,album,duration,mime,track,size)
  - headers.txt  : "<path>\\t<base64 of first 64 bytes>" per FLAC (STREAMINFO)

Emits, into <outdir> (default: repo library/):
  - library.db    SQLite (queryable, robust)
  - library.csv   spreadsheet-friendly, everything at a glance
  - library.json  compact, for the web UI
Run via tools/sync-library.sh; this file only does the parse+build.
"""
import base64, csv, json, re, sqlite3, sys, os

def parse_meta(path):
    rows = {}
    pat = re.compile(
        r'_data=(?P<data>.*?), title=(?P<title>.*?), artist=(?P<artist>.*?), '
        r'album=(?P<album>.*?), duration=(?P<duration>.*?), mime_type=(?P<mime>.*?), '
        r'track=(?P<track>.*?), _size=(?P<size>\d+)\s*$')
    for line in open(path, encoding='utf-8', errors='ignore'):
        m = pat.search(line)
        if not m:
            continue
        d = m.groupdict()
        def nz(x): return None if x in ('null', '', None) else x
        rows[d['data']] = {
            'path': d['data'],
            'title': nz(d['title']) or os.path.basename(d['data']),
            'artist': nz(d['artist']),
            'album': nz(d['album']),
            'durationMs': int(d['duration']) if d['duration'].isdigit() else 0,
            'mime': nz(d['mime']),
            'track': int(d['track']) if (d['track'] or '').isdigit() else None,
            'size': int(d['size']),
        }
    return rows

def parse_flac_header(b64):
    """Return (sampleRate, bits, channels, totalSamples) from a FLAC header, or None."""
    try:
        raw = base64.b64decode(b64)
    except Exception:
        return None
    i = raw.find(b'fLaC')
    if i < 0 or len(raw) < i + 8 + 18:
        return None
    s = raw[i + 8:i + 8 + 34]           # STREAMINFO body
    sr = (s[10] << 12) | (s[11] << 4) | (s[12] >> 4)
    ch = ((s[12] >> 1) & 7) + 1
    bits = (((s[12] & 1) << 4) | (s[13] >> 4)) + 1
    ts = ((s[13] & 0xF) << 32) | (s[14] << 24) | (s[15] << 16) | (s[16] << 8) | s[17]
    if not (8000 <= sr <= 768000) or not (4 <= bits <= 32):
        return None
    return sr, bits, ch, ts

def parse_headers(path):
    out = {}
    if not os.path.exists(path):
        return out
    for line in open(path, encoding='utf-8', errors='ignore'):
        if line.startswith('###'):
            continue
        if '\t' not in line:
            continue
        p, b64 = line.rstrip('\n').split('\t', 1)
        r = parse_flac_header(b64)
        if r:
            out[p] = r
    return out

def load_prev(outdir):
    """path -> (sampleRate, bits, channels) from the last build, for reuse."""
    prev = {}
    pj = os.path.join(outdir, 'library.json')
    if os.path.exists(pj):
        try:
            for t in json.load(open(pj, encoding='utf-8'))['tracks']:
                prev[t['path']] = (t.get('sampleRate', 0), t.get('bits', 0), t.get('channels', 0))
        except Exception:
            pass
    return prev

def build(meta_txt, headers_txt, outdir):
    os.makedirs(outdir, exist_ok=True)
    meta = parse_meta(meta_txt)
    hdr = parse_headers(headers_txt)
    prev = load_prev(outdir)   # reuse formats for files not freshly header-scanned
    recs = []
    for p, m in meta.items():
        h = hdr.get(p)
        pv = prev.get(p)
        if h:
            sr, bits, ch, ts = h[0], h[1], h[2], h[3]
        elif pv:
            sr, bits, ch, ts = pv[0], pv[1], pv[2], 0   # unchanged file, reuse
            h = True                                    # treat as analyzed
        else:
            sr = bits = ch = ts = 0
        dur = (ts / sr) if (ts and sr) else (m['durationMs'] / 1000.0)
        kbps = round(m['size'] * 8 / dur / 1000) if dur else 0
        hires = 1 if (bits >= 24 or sr > 48000) else 0
        analyzed = 1 if h else 0
        # HiBy Music badge (sample-rate gate): HR >=88.2kHz lossless; SQ = lossless
        # <88.2kHz (any bit depth); Lossy = mp3/aac/etc. studioSQ marks the good
        # 24-bit SQ tracks (bit-perfect, often the true master ceiling — no HR exists).
        mime = (m['mime'] or '').lower()
        if any(x in mime for x in ('mpeg', 'mp3', 'aac', 'wma', 'ogg', 'opus')):
            badge = 'Lossy'
        elif not h:
            badge = '?'
        elif sr >= 88200:
            badge = 'HR'
        else:
            badge = 'SQ'
        studio_sq = 1 if (badge == 'SQ' and bits >= 24) else 0
        recs.append({**m,
                     'sampleRate': sr, 'bits': bits, 'channels': ch,
                     'durationSec': round(dur, 1), 'sizeMB': round(m['size'] / 1e6, 2),
                     'bitrateKbps': kbps, 'hires': hires, 'analyzed': analyzed,
                     'badge': badge, 'studioSQ': studio_sq,
                     'fmt': (f'{sr/1000:g}kHz/{bits}bit' if h else (m['mime'] or '?'))})
    recs.sort(key=lambda r: ((r['artist'] or '~').lower(),
                             (r['album'] or '~').lower(),
                             r['track'] or 0, (r['title'] or '').lower()))
    # SQLite
    db = os.path.join(outdir, 'library.db')
    if os.path.exists(db):
        os.remove(db)
    con = sqlite3.connect(db)
    cols = ['path', 'title', 'artist', 'album', 'track', 'sampleRate', 'bits',
            'channels', 'durationSec', 'size', 'sizeMB', 'bitrateKbps', 'mime',
            'hires', 'analyzed', 'badge', 'studioSQ', 'fmt']
    con.execute('CREATE TABLE tracks (%s)' % ','.join(
        c + (' INTEGER' if c in ('track', 'sampleRate', 'bits', 'channels', 'size',
                                 'bitrateKbps', 'hires', 'analyzed', 'studioSQ') else
             ' REAL' if c in ('durationSec', 'sizeMB') else ' TEXT') for c in cols))
    con.executemany('INSERT INTO tracks VALUES (%s)' % ','.join('?' * len(cols)),
                    [[r.get(c) for c in cols] for r in recs])
    con.execute('CREATE INDEX idx_artist ON tracks(artist)')
    con.execute('CREATE INDEX idx_hires ON tracks(hires)')
    con.commit(); con.close()
    # CSV
    with open(os.path.join(outdir, 'library.csv'), 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction='ignore')
        w.writeheader()
        for r in recs:
            w.writerow(r)
    # JSON (compact for the UI) + summary
    tot = len(recs)
    an = sum(r['analyzed'] for r in recs)
    hr = sum(r['hires'] for r in recs)
    nonhr = [r for r in recs if r['analyzed'] and not r['hires']]
    summary = {
        'total': tot, 'analyzed': an, 'hires': hr,
        'nonHires': len(nonhr),
        'badgeHR': sum(1 for r in recs if r['badge'] == 'HR'),
        'badgeSQ': sum(1 for r in recs if r['badge'] == 'SQ'),
        'studioSQ': sum(1 for r in recs if r['studioSQ']),
        'sizeTotalGB': round(sum(r['size'] for r in recs) / 1e9, 2),
        'sizeHiresGB': round(sum(r['size'] for r in recs if r['hires']) / 1e9, 2),
        'sizeNonHiresGB': round(sum(r['size'] for r in nonhr) / 1e9, 2),
        'sizeSQGB': round(sum(r['size'] for r in recs if r['badge'] == 'SQ') / 1e9, 2),
    }
    payload = {'summary': summary, 'tracks': recs}
    with open(os.path.join(outdir, 'library.json'), 'w', encoding='utf-8') as f:
        json.dump(payload, f, ensure_ascii=False)
    # JS data file so library.html loads offline over file:// (fetch is blocked there)
    with open(os.path.join(outdir, 'library.js'), 'w', encoding='utf-8') as f:
        f.write('window.LIB=')
        json.dump(payload, f, ensure_ascii=False)
        f.write(';')
    print('tracks: %d  analyzed: %d  hi-res: %d  non-hires: %d  (%.1f GB total, %.1f GB non-hires)'
          % (tot, an, hr, len(nonhr), summary['sizeTotalGB'], summary['sizeNonHiresGB']))
    return summary

if __name__ == '__main__':
    a = sys.argv
    meta = a[1] if len(a) > 1 else 'meta.txt'
    headers = a[2] if len(a) > 2 else 'headers.txt'
    outdir = a[3] if len(a) > 3 else os.path.join(os.path.dirname(__file__), '..', 'library')
    build(meta, headers, outdir)
