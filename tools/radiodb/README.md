# Broadcast station catalogue

A single SQLite file with every broadcast station the public record knows about in North
America, built so the FM tuner can say what is on a frequency, what should be receivable from
where you are standing, and where the transmitter actually is.

```
tools/radiodb/fetch_sources.sh        pull the raw government files
tools/radiodb/build_stations_db.py    normalise them into stations.sqlite
tools/radiodb/add_formats.py          add format/genre from Wikipedia (optional, network)
mikuos/data/stations.sqlite           the built catalogue the image injects
```

## What is in it

47,826 stations, **every one with transmitter coordinates**, 7.9 MB (9.5 MB with formats).

| Country | FM | Translators | LPFM | AM |
|---|---|---|---|---|
| US | 12,037 | 9,005 | 2,775 | 8,031 |
| Mexico | 156 | | | 5,328 |
| Canada | 874 | | | 1,607 |
| Brazil | | | | 2,445 |
| Others (EC, CO, AR, CI…) | | | | ~2,900 |

Per station: call sign, service, frequency in kHz, class, licence status, city, state, country,
licensee, transmitter latitude and longitude, ERP in kW, HAAT in metres, antenna height above
mean sea level, and for 25,037 of them the date the call sign took effect.

Translators and LPFM matter as much as full-power stations for what you can actually hear. In
many towns a 1xx.x FM translator relays a local AM station, and it is real radio.

## Sources, and why these

Everything is government public-record data, which is what makes it safe to bake into an image
that gets published.

- **FM, FX, FL, AM** — the FCC's own query output in `list=4` pipe-delimited form. US federal
  public domain. It already contains the Canadian and Mexican stations coordinated under the
  border agreements, which is why there is no separate ISED or IFT source here. ISED's TAFL
  download covers the fixed service only, not broadcast.
- **facility.dat** — the CDBS facility table, for `callsign_eff_date`. That is the date the
  current call sign took effect, which is the closest thing the public record offers to "how
  long has this station been on the air". It is **not** a founding date and is not presented as
  one in the UI.

### Coverage gaps, stated plainly

Canadian and Mexican **FM** coverage is border stations only — 874 and 156 against national
totals nearer 1,300 and 1,800. Their AM coverage is good because AM skywave forces wider
coordination. Filling the FM gap needs CRTC and IFT sources that are not a single download;
until someone does that, the catalogue under-reports inland CA and MX FM and should say so
rather than look complete.

Stations outside the FCC's facility table — most non-US ones — have no `callsign_since`. 22,789
of 47,826 are undated for that reason.

## Formats, from Wikipedia

The FCC record says where a station is and how loud, never what it plays. `add_formats.py`
fills three columns for US and Canadian FM, translators, LPFM and AM:

- `format` — the `format` field of the article's "Infobox radio station", markup stripped and
  cut to 80 characters: "Classic rock", "News/talk/sports", "Public radio, News/Talk, Classical".
- `genre` — one of 27 fixed buckets (Rock, Classic Rock, Country, Top 40, Hot AC, Christian,
  News/Talk, Public Radio, Spanish, … Other) for filtering and colouring. Religious, Spanish,
  college, children's and comedy win wherever they appear in the text; for the rest the
  keyword that appears *first* wins, because infoboxes list the primary format first.
- `format_source` — the title of the Wikipedia article the format came from.

**Source and licence.** English Wikipedia, CC BY-SA 4.0. That is not public domain like the
FCC data, which is why every row keeps `format_source`: anything that shows a format can credit
the article it came from. Wikidata's format property (P415) was the obvious first choice and
only ~1,700 US stations have it; Wikipedia has an article for nearly every full-power station.

**How a station is matched.** Articles are titled by call sign, but not consistently: WDVE,
WCLG-FM, KDKA (AM), WKEL (FM), and the bare call is often a disambiguation page or a different
station. The script tries the call, then the call with or without -FM, then "(FM)"/"(AM)", and
accepts a page only when its radio-station infobox has our frequency or our call sign in the
right band, or lists our call in its translator/repeater fields. A same-named article about
something else never gets through: "WHO" redirects to the World Health Organization, which
mentions WHO plenty and has no radio infobox.

Redirects are used, carefully. A full-power repeater's call redirecting to its parent (WHRE →
WHRV) is accepted when the parent's full article names that call and not as a former call or a
sister station. A call redirecting to a network (WYFU → Bible Broadcasting Network, WVPM → West
Virginia Public Broadcasting) takes the network infobox's format; most network infoboxes say
only "Radio network", so for those the format is the majority format of member-station articles
that name the network (K-Love: "Contemporary Christian", 95 of 177).

**Translators** inherit the format of the station they relay, two ways: the parent's infobox
`translator` field names them (an AM news/talk station that lists its FM translator makes that translator read "News/talk/sports"),
or the translator's own call redirects to the parent on Wikipedia. Two caveats, stated plainly:

- A translator relaying an **HD2/HD3 subchannel** carries a different format from the main
  station. Those are skipped, not guessed: when the infobox marks the relay as HD it is dropped,
  and a translator that only redirects to an FM parent with HD subchannels is left blank (866).
- The translator tables most articles keep further down the page are not read (the script
  fetches the lead section only), so a translator named only there gets its format through the
  redirect route or not at all.

**Coverage**, by row, from the run on 9 October 2026:

| | Stations | With format | |
|---|---|---|---|
| US FM | 12,037 | 10,042 | 83% |
| US translators | 9,005 | 6,372 | 71% |
| US AM | 8,031 | 7,808 | 97% |
| US LPFM | 2,775 | 737 | 27% |
| Canada FM | 874 | 488 | 56% |
| Canada AM | 1,607 | 449 | 28% |

The misses, counted by call sign: no article under any variant (~1,950); a redirect to a
"List of K-Love stations"-style list with no infobox (~410); a page that could not be confirmed
as this station (~1,600: disambiguation pages, networks whose article does not name the call,
former-call redirects); and a confirmed match whose infobox or network has no format (~870). Canadian AM is low because much of that list is stations that moved to FM; their old
call now redirects to the FM, and a cross-band redirect is deliberately not accepted. LPFM is
low because most LPFMs have no article. Formats are as current as Wikipedia, which lags real
flips by weeks to months.

It caches everything it fetches in `tools/radiodb/.cache/` (git-ignored, ~4 MB), so a rerun
costs no network and an interrupted run resumes. A cold run is about 25,000 titles in batches of
50 and takes 10–15 minutes.

## Logos are deliberately absent

Station logos are trademarks. This firmware is published on GitHub and on
mikuos.falcontechnix.com, so shipping tens of thousands of other people's marks inside the image
is redistribution, and ~22,000 logos would be hundreds of megabytes besides.

Instead the device fetches a logo when it first needs one and caches it locally. Same thing on
screen, no marks travelling in the image.

## Two gotchas, both of which cost time

**The id column in the FCC query output is not the CDBS facility id.** WCLG-FM reads `187048`
there and is `6553` in `facility.dat`; they are LMS-era and legacy identifiers respectively and
do not correspond. Join the two sources on **call sign**. Joining on the id dated 2% of the set
and looked plausible while doing it.

**`du` is aliased to `dust` on this machine**, so `du -h` in a pipeline prints a help page
instead of a size. Use `/usr/bin/du`, or `ls -l` and divide.

## Refreshing

```bash
tools/radiodb/fetch_sources.sh /tmp/radiodb
cd /tmp/radiodb && python3 -I /path/to/build_stations_db.py --formats
cp stations.sqlite mikuos/data/
```

`--formats` runs `add_formats.py` on the fresh file at the end. Leave it off for an offline,
government-data-only build; `python3 -I tools/radiodb/add_formats.py [stations.sqlite]` adds the
columns to an existing catalogue at any time (default: `mikuos/data/stations.sqlite`).

The FCC files update daily; the catalogue does not need to. `stations.sqlite` is not committed
to the public repos — it is a build artifact, reproducible from the two scripts above, and
keeping a 7.9 MB binary out of git history is worth the one command.

## NOAA Weather Radio transmitters

`tools/radiodb/build_nwr.py` writes
`miku-player-kotlin/fmradio/src/main/assets/nwr_transmitters.json`: 1,035 NWR transmitters
(every one with coordinates, ~180 KB minified), each with call sign, frequency, WX channel
(WX1 162.550 … WX7 162.525), site name, site location, state, lat/lon, power in watts,
forecast office and status (NORMAL / DEGRADED / OUT OF SERVICE — out-of-service sites are kept
and labelled, not dropped). The FM app uses it to list the nearest weather-radio stations.

Source: <https://www.weather.gov/source/nwr/JS/ccl-data.js>, the data file behind NWS's own
station listing (weather.gov/nwr/station_listing). It is `var cclData = [...]` with a JSON
right-hand side; the script strips the assignment and parses it. US federal data, public domain.
`site` is NWS's "Site Name" (service area, usually a city or county) and `city` its "Site Location"
(where the tower is, e.g. Harmony Grove).

**This is reference data only.** NWR broadcasts at 162.400–162.550 MHz; the Si4705 tunes
64–108 MHz, so the phone cannot receive it. The list is for pointing a weather radio or ham
handheld at the right channel.

```bash
python3 -I tools/radiodb/build_nwr.py            # download and rebuild
python3 -I tools/radiodb/build_nwr.py ccl-data.js  # from a saved copy
```
