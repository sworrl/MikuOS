# Miku Remote — phone-as-Bluetooth-remote PWA

A tiny installable web page that controls **Miku Music on the HiBy M500** over **Bluetooth LE**.
Nothing to install on the phone: open the page in Chrome/Edge, tap *Connect*, pick **Miku M500**,
type the 6-digit code shown on the M500, done.

The M500 side is `miku-player-kotlin/app/src/main/java/com/miku/player/remote/` — a GATT
*peripheral* (`MikuRemoteGattService`) that is only advertised while **Settings → Phone Remote**
is on. The M500's Settings card shows a QR code pointing at wherever you host this folder, with the
current pairing code pre-filled in the URL fragment (`#code=123456`).

## Files

| file            | purpose                                                             |
|-----------------|---------------------------------------------------------------------|
| `index.html`    | UI (inline CSS, Miku teal `#39C5BB` / pink `#FF5FA2`)                |
| `app.js`        | Web Bluetooth client: connect → pair/auth → notifications → commands |
| `manifest.json` | PWA manifest (installable, standalone)                              |
| `sw.js`         | app-shell cache so the page opens offline                           |
| `icon.svg`      | icon                                                                |

## Hosting

Web Bluetooth only works from a **secure context**: `https://` (or `http://localhost` for
development). Any static host works — no build step, no server code.

- **GitHub Pages**: push this folder to a repo (or a `docs/` subfolder), enable Pages, use the
  `https://<user>.github.io/<repo>/` URL.
- **Cloudflare Pages**: `wrangler pages deploy tools/remote-pwa --project-name miku-remote`
  (or connect the repo and set the build output directory to `tools/remote-pwa`).
- **Local dev**: `python3 -m http.server 8080` inside this folder and open `http://localhost:8080/`
  on the *same machine* (a phone hitting your laptop's LAN IP is **not** a secure context —
  use `adb reverse tcp:8080 tcp:8080` on an Android phone to make it `localhost` there).

Then on the M500: **Settings → Phone Remote → Change URL** and paste the hosted URL — the QR code
updates instantly. The default placeholder baked into the app is
`https://miku-remote.pages.dev/` (`MikuRemotePreferences.DEFAULT_PWA_URL`); change it there if you
settle on a permanent home.

## Browser support (Web Bluetooth)

| platform                     | works?                                                     |
|------------------------------|------------------------------------------------------------|
| Android — Chrome, Edge, Brave, Samsung Internet | yes                                     |
| Windows / macOS / Linux / ChromeOS — Chrome, Edge | yes                                    |
| iOS / iPadOS — Safari, Chrome, Edge (all WebKit) | **no** Web Bluetooth. The third-party *Bluefy* browser works. |
| Firefox (any platform)       | no                                                         |

Linux desktop Chrome may need `chrome://flags/#enable-web-bluetooth-new-permissions-backend`
for the "reconnect without chooser" path; the plain chooser flow works without flags.

## Pairing / security model

1. The M500 shows a random **6-digit code** (single-use; regenerated after every successful
   pairing, after 5 wrong attempts — which also locks pairing for 60 s — or on "New code").
2. The page writes `pair:<code>:<label>` to the *pair* characteristic. The M500 replies (notify)
   with `ok:<token>` — a 32-hex secret stored only in this phone's `localStorage`; the M500 keeps
   only its SHA-256.
3. Every later session writes `auth:<token>` and gets `ok:auth`. Until then, the control and
   now-playing characteristics refuse the connection (`GATT_WRITE_NOT_PERMITTED`, `{"auth":false}`).
4. **Forget** on the M500 revokes the token and drops the phone if it's connected; *Options →
   Forget this M500* on the phone clears its token (and sends `unpair` if connected).

Authorization is per-BLE-connection and evaporates on disconnect; nothing is ever advertised
while the Settings toggle is off.

## GATT protocol (mirrors `MikuRemoteProtocol.kt`)

Service `39c5bb00-4d49-4b55-9d31-3f8a6e7c2a01` (advertised; local name **Miku M500**).

| characteristic | UUID (`39c5bbXX-4d49-4b55-9d31-3f8a6e7c2a01`) | props           | payload |
|----------------|------|-----------------|---------|
| now-playing    | `01` | READ, NOTIFY    | `{"id","title","artist","album","pos","dur","playing","liked","quality","shuffle","repeat","vol","art":"none"}` |
| command        | `02` | WRITE, WRITE_NR | `play` `pause` `toggle` `next` `prev` `seek:<ms>` `like` `vol:<0-100>` `volup` `voldown` `mute` `shuffle[:on\|off]` `repeat[:off\|all\|one]` `refresh` |
| volume         | `03` | READ, NOTIFY    | `{"vol":0-100,"muted":bool}` |
| pair           | `04` | READ, WRITE, NOTIFY | see above; READ → `authorized` / `unauthorized` |
| status         | `05` | READ            | `{"name","model","app","battery","charging","auth"}` |

Notifies are capped at MTU−3 bytes; when the now-playing JSON doesn't fit, the M500 notifies
`{"r":1}` and the page does a (long) read instead. Position notifies are throttled to 1/s while
playing; state changes (track/play/pause/like/shuffle/repeat) push immediately (120 ms debounce).
There is no artwork transport over BLE — the page shows a placeholder disc; `art` is always `"none"`.

## Lock-screen controls (optional)

*Options → Lock-screen controls* uses the Media Session API so the phone's lock screen shows the
M500's track and routes its play/pause/next keys to the M500. Browsers only surface media
controls for a page that is actually playing audio, so this plays an inaudible 1-second WAV loop
while enabled. Off by default.
