# Rio Riot research notes

Research for the "Riot mode" skin. The Rio Riot was SonicBlue's 20 GB hard drive jukebox, shown at CES in January 2002 (it won a CES Innovations award) and on sale in the US in late February / March 2002 for $399.95.

The best source by far is the original SonicBlue PDF, "SONIC|blue RioRiot digital user's guide" (40 pages, First Edition December 2001, part number 75550191-001, authors Tony McHatton and Richard Key). It is on the Internet Archive: https://archive.org/details/manualsbase-id-50037 (same file at https://archive.org/details/manualsonline-id-84cc33a1-2826-1d94-9db5-b83719cf51e8). Its screen drawings match the real firmware closely. The second best source is a 3-minute TechTV "TechLive" segment from 2002 that shows a real unit booting, playing, opening the menu, and tuning FM: https://archive.org/details/g4tv.com-video5034

Page numbers below ("p18") are the manual's printed page numbers, which equal the PDF page numbers.

Confidence tags: **[manual]** = read or seen in the user guide. **[video]** = seen in the TechTV footage. **[press]** = review or spec sheet. **[forum]** = user posts. **[uncertain]** = not verified (see the "Unverified details" list at the end).

## 1. Hardware

| Item | Value | Source |
|---|---|---|
| Storage | 20 GB HDD, "400 albums" / "5,000 songs" at 128 kbps | [manual] p5 |
| Size | 145 x 100 x 30 mm max (5.4 x 3.6 x 1.4 in per a US review) | [press] https://av.watch.impress.co.jp/docs/20020624/sonic.htm ; Bloomberg excerpt https://www.bloomberg.com/news/articles/2002-03-27/rio-riot-big-music-for-big-pockets |
| Weight | about 250 g (about 10 oz) | [press] https://www.phileweb.com/sp/news/d-av/200206/24/5040.html |
| Body | dark slate blue-gray (looks matte black in some photos), "hourglass" shape with flared ends, small "Rio" wordmark printed top right of the face | [manual] p6 ; [video] ; PC World via CNN excerpt https://edition.cnn.com/2002/TECH/ptech/03/29/rio.riot.idg/index.html |
| Display | 240 x 160 pixel monochrome graphic LCD, 3:2, backlit | [press] Wikipedia https://en.wikipedia.org/wiki/Rio_Riot ; AV Watch ("240x160 dots") |
| LCD look | very pale mint / gray-green background, dark gray-green pixels. A green glow shows along the bezel edge in the boot shot. | [video] |
| Contrast | slider 0 to 14 | [manual] p31 |
| Backlight color | no text source states it. Video suggests a green / yellow-green tint. **[uncertain]** | [video] |
| Backlight timer | Always Off, 1 second, 2 seconds, 5 seconds, Always On | [manual] p31 |
| Battery | built-in Li-ion, "at least 10 hours per charge at 50% volume", first charge 5+ hours, large cylindrical cell inside | [manual] p5, p8 ; [forum] https://forums.anandtech.com/threads/rio-sonicblue-rioriot-20gb-portable-mp3-player-jukebox-134-99.1119577/ |
| Charging | AC adapter into a "Charger Port" on the bottom. Usable while charging. | [manual] p8 |
| USB | USB 1.1 (slow). The USB cable plugs into the combined "USB/Headphone Port". | [manual] p12 ; Wikipedia |
| Line out | Japanese spec lists line out (20 Hz to 20 kHz) separately from headphone (40 Hz to 20 kHz), but the US manual shows no line-out jack. **[uncertain]** | AV Watch, phileweb |
| SNR | 89 dB | [press] AV Watch |
| FM tuner | 88 to 108 MHz dial (drawn on screen), 0.1 MHz steps, hold Forward/Backward to seek, 8 presets. Japan model had no tuner. | [manual] p27, p28 ; [video] |
| Recording | none. No record key, no recording chapter. | [manual] |
| Remote | none in the US box (accessories list: headphones, carrying case, AC adapter, USB cable, CDs, optional car cassette adapter) | [manual] p7 |
| Formats | MP3 up to 320 kbps, WMA up to 192 kbps, ID3 and WMA tags | [manual] p5 |
| PC software | RealJukebox (Win 98/ME/2000/XP), iTunes (Mac OS 9.0.4+). Device name in RealJukebox: "Rio Riot Digital Audio Player". | [manual] p9 to p16 |
| Firmware | manual's Information screen shows "Firmware Version: 1.0". Last known update is "RioRiot_125_firmware.exe" (so 1.25) in https://archive.org/details/rio-audio-collection . PC flasher is "RioFlasher" ("Upgrade Now"); Mac uses iTunes "Rio Settings" > "Upgrade Firmware". | [manual] p32, p34 |
| Price | $399.95 launch, 44,800 yen in Japan (June 28, 2002), liquidated for about $50 to $135 in 2003 | [video] price card ; AV Watch ; anandtech thread |

### Physical controls

From the "Tour of the Player" photo on [manual] p6, p7 and the [video]:

- **Left of the screen**: a round four-way cluster. Play/Pause on top, Backward on the left, Forward on the right, Stop on the bottom. The manual calls these the "four button playback control".
- **Top left corner**: a single small round **Menu** button.
- **Right of the screen**: the **Scroll** wheel, a disc set in a crescent-shaped slot so only part of its face shows, with a ring of small dimples around the rim. You rub it up or down with your right thumb. A small round **Select** button sits above the wheel and a small round **Back** button below it. Select is a separate button, the wheel does not press in.
- One owner said the "jog dial doesn't let you go all the way around" and the device felt two-handed [forum, search excerpt of http://m.empegbbs.com/ubbthreads.php/topics/56502/ ].
- **Volume + / -**: two buttons on an edge (p7 drawing).
- **On - Lock - Off** slide switch. In Lock mode "LOCK" appears on the LCD [manual] p7. The FAQ calls it "Hold".
- **Reset** pinhole on the back.
- Button legend symbols in the manual: Menu = three horizontal lines in a circle, Select = a dot in a ring, Scroll = a dotted arc, Back = an up arrow in a circle bent to the left.

There is no EQ, Radio, Record, or Repeat key. Volume never takes a menu.

## 2. Firmware UI

### General look

- Everything is drawn in a clean sans serif (Helvetica / Arial style in the manual drawings, and the real firmware matches), proportional, mixed case. No pixel-art "computer" font, no all-caps menus.
- Three type sizes appear: **large** (about 15 to 16 px tall on the 240 x 160 panel) for the Now Playing title, the elapsed time, and the FM frequency; **medium** (about 11 to 13 px rows) for lists, menu items, and the bold section labels; **small** (about 9 to 10 px) for the remaining-time readout, the detail screen, and dialogs. Sizes are estimated by scaling the p18 and p27 drawings to 240 px wide, so treat them as close, not exact.
- Highlight style: the selected list row is a **dark, fully rounded pill** (stadium shape) with light text, spanning almost the full list width.
- Lists have a **vertical scroll bar** at the right: a thin rail with a small rectangular thumb (Now Playing, FM) or a round-ended trough (browse lists).
- A full-width **horizontal rule** separates the header band from the list.
- Settings dialogs are rounded rectangles with a bold title and a rule under it, values in small rounded boxes, and **Done** / **Cancel** buttons stacked at the bottom right as gray tabs (rounded on the left, running off the right edge). An editable value "will blink to indicate that it is selected" [manual] p19.

### Boot / splash [video] [manual] p6

1. Screen lights to blank pale green.
2. The "Rio riot" logo appears, filling most of the width, centered a little above the middle.
3. Under it, a small status line at the bottom left changes as the player starts. Legible frames read "Hard Disk Setup". Earlier frames show a longer line that looks like "Battery Manager Setup" and then another "... Setup" line. **[uncertain]** on the earlier wording.
4. Then Now Playing.

Logo shape, for redrawing: a heavy, rounded geometric sans "Rio" with a dot on the i and a short flat bar (macron) over the o ("Riō"), all solid dark. Right after it, lower and smaller, "riot" in lowercase, slanted forward, drawn as **outlines only** (hollow letters with a single thin stroke), squarish with rounded corners. A tiny "TM" sits at the top right of "riot". No tagline on the LCD. The same logo shows on the LCD in the p6 product photo.

### Now Playing [manual] p18 drawing, confirmed by [video]

Top to bottom on the 240 x 160 screen:

1. **Title line** (large font): the current track title, clipped at the right edge (no ellipsis seen). In the video the line reads like "2 (Angel Alarm) - Do..." so it may include more than the bare title. **[uncertain]**
2. **Status line**:
   - big elapsed time "02:42" (MM:SS with a leading zero; "00:00" at start)
   - right of it, stacked small: remaining time "-01:05" on top, and a small inverse tag under it showing the play mode ("RND" for random in the manual drawing)
   - a speaker icon with sound waves
   - a **volume bar** of 10 tall, round-ended vertical segments, solid for the current level, hollow outlines for the rest
   - a big solid **play-state triangle** at the right (play shown; pause/stop glyphs not shown) **[uncertain]**
3. **Section line**: bold "Upcoming tracks:" in the manual ("Upcoming Tracks" in the real firmware, capital T, colon unclear). At the right of that line: a USB plug icon (connected) in the drawing, and a **battery gauge**: "E" left of a battery outline, "F" right of it, with the word "LOW" inside the outline when low.
4. Horizontal rule.
5. **Queue list** (medium font, about 5 rows visible): already played tracks get a check mark in front, the current track is the dark pill, upcoming tracks follow. In the real firmware rows read "Artist - Title". A thin scroll bar on the right.

There is **no progress bar** and no bitrate or track number on the main screen.

Press **Back** while playing: the queue area is replaced by a detail block (small font): "Artist:", "Album:", "Codec: MP3", "Bitrate: 160000 kbps" (sic, the drawing really says that), "Length: 2:55", "File Size: 2458426 bytes".

### Menu overlay [manual] p18, p39 ; [video]

- Pressing **Menu** dims the whole Now Playing screen to a pale gray ghost and **slides menu bars in from the right**.
- The menu is a stack of tabs hugging the right edge: a header tab with the menu name in bold ("Main Menu"), then one tab per item. Each tab is a box rounded on the left and open on the right (runs off the screen edge).
- The **highlighted item is bold and sticks out further left** than the others (it is shifted left about half a character width and has a white fill). Unhighlighted items are indented and plain.
- Submenus stack the same way, with the parent shown as a breadcrumb tab above ("Play Music" above "Albums").
- Back steps out one level at a time. Menu exits.

### Menu tree (exact wording and order, [manual] p39 plus chapter pages)

- **Main Menu**
  - **Play Music**
    - **Rio DJ**
      - **Entertain Me!** (dialog: "Play a mix of music that lasts about [15 minutes]", range 15 minutes to 8 hours or "Everything")
      - **Play All**
      - **Top Tunes** (10 to 250 tracks)
      - **New Music** (1 day to 1 year)
      - **Memory Lane** (1 day to 1 year)
      - **Sounds Of...** ("1940's" to the '00s, or a year 1950 to 2010) (the body text writes "Sounds of...")
      - **Random Play** (15 minutes to 8 hours)
      - each ends with **Done** / **Cancel**
    - **Albums** (letter column, then list)
    - **Artists**
    - **Genre** (header like "5 Genres on Player", pick one, Done)
    - **Songs**
    - **Favorites** (40 most played): **Albums**, **Artists**, **Songs**
    - **Playlists**
  - **Radio** (reads **Player** while you are in radio mode, to go back)
  - **Equalizer**
    - **Bass/Treble** (breadcrumb shows "Bass Treble")
  - **Organize**
    - **My Playlists**: **Create**, **Edit** (Add Tracks, Delete Tracks), **Delete**, **Rename**
    - **Delete...**: **an Album**, **an Artist**, **a Song**, **Everything!** (reads as "Delete... an Album"). Confirm with "Delete File" or "Delete All".
    - In radio mode Organize instead shows **Select Preset**, **Set Preset**, **Clear Preset** [manual] p28
  - **Preferences**
    - **Play Options** (dialog "Track Play Options": Repeat [All / Track / Off], Random [On / Off])
    - **Contrast** (vertical slider 0 to 14, knob shows the value, e.g. "+11", live preview)
    - **Backlight** (dialog "Backlight on: [2 seconds]": Always Off, 1 second, 2 seconds, 5 seconds, Always On)
    - **Power Saver** (dialog titled "Power Saving": "Player automatically turns off [5 minutes] after inactivity": 1 minute, 2 minutes, 5 minutes, 15 minutes, Never)
    - **Time / Date** (dialog "Set Time / Date:": "Date: [January] [01] [2001]", "Time: [05] [50] [AM]", 12-hour clock)
    - **Information**
    - **"The" Filter** (dialog: "Turn "The" Filter [Off]")

### Browse lists [manual] p20, p21, p26

- Breadcrumb tabs at the top ("Play Music", then "Albums").
- Left: a tall rounded column with the alphabet, about 8 letters visible at once (A to H), the chosen letter circled with a gray oval. The column scrolls (J to Q in another drawing).
- Right: a rounded panel with a bold header like `9 Albums Match "B"` (or `2 Artists Match "D"`, `5 Songs Match "F"`, `1 Song Matches: "N"`), a rule, a bold first row **Play All Albums/Tracks** (or **Play All Tracks**), then items each starting with a small bullet "•", the selection as a dark pill, scroll trough at the right.

### Playlist name entry [manual] p23

"Playlist Name: Timmy's Birthday S_" with an underscore cursor. Below, a 7-column by 6-row character grid read down the columns: a to f, g to l, m to r, s to x, y z ( ) ! @, # $ % ^ & *, / ? | - \ space. A rounded **Lowercase** toggle at top right (the matrix with numbers is the uppercase one), **Done** and **Cancel** at bottom right. Leaving asks "You have created the playlist: [name]. Do you want to save the changes or exit without saving?" with **Save**. A running count "There are # tracks in [name]." shows top right while adding.

### Radio / "FM Tuner" [manual] p27 drawing, confirmed by [video]

1. **Dial scale** across the top: a ruler with tick marks and labels 88, 92, 96, 100, 104, 108, and a small solid down-pointing triangle above the current frequency.
2. **Frequency line**: big "105.1", then a small inverse tag "TUNED", then the speaker icon and the same 10-segment volume bar, then big "FM" with small "TUNER" under it.
3. Bold "Radio Presets:" (battery gauge at the right in the video).
4. Rule.
5. Preset list: "Preset 1 – 106.3 FM" ... "Preset 8", about 5 rows visible, frequencies right-aligned ("Preset 5 –   92.3 FM"), an unset slot reads "Preset 5 – empty". Selected preset is the dark pill. Scroll bar at the right.

Behavior: Forward/Backward tune 0.1 MHz, hold to seek. Scroll to a preset and **hold Select** until "empty" is replaced by the station to save. Or MENU > Organize > Set Preset. Overwriting asks "Overwrite Preset?" with **Save**. Scroll to a preset + Select to play it.

### Equalizer [manual] p29

Dialog "Bass/Treble": two vertical sliders labeled "Bass" and "Treble", a "dB" label with scale "+6", "0", "-6", the knob shows the current value (e.g. "+4"). Select a slider, scroll to move it, Select again, then Done / Cancel. **There are no EQ presets** (no Rock, Jazz, Classical).

### Information [manual] p32

Header "Rio Riot" left and the clock "5:52 AM" right, then:
"Firmware Version: 1.0", "Total Storage: 20 Gbytes", "Free Storage: 19.25 Gbytes", "Supports: MP3 and WMA", "14 Albums and 51 tracks in use", "(room for approx. 4889 more tracks)", and a **Done** button.

### Other states

- Lock: "LOCK" appears on the LCD [manual] p7. Exact placement unknown.
- Sleep: after several minutes stopped or paused the player sleeps; Play/Pause wakes it [manual] p6.
- No key click sounds are mentioned anywhere.
- PC World reported freezes when navigating menus too fast [press, excerpt].

## 3. Trademarks and naming

History:

- Rio started as a Diamond Multimedia brand (Rio PMP300, 1998). Diamond merged with S3 in 1999 and the company became SonicBlue. The Riot manual itself says "Rio is a registered trademark of RioPort, Inc. ... and is used under license" [manual] p2.
- SonicBlue filed Chapter 11 on March 21, 2003. The Rio business went to D&M Holdings (Denon/Marantz) in 2003.
- D&M stopped making players in August 2005, licensed the player software to SigmaTel, and kept the Rio brand and trademarks (per https://en.wikipedia.org/wiki/Rio_Audio ). I did not check current USPTO records.

Project decision (the user's call, recorded here):

- The Riot has been out of production for about 20 years. The user decided the skin and the app label may say **"Rio Riot"** and **"Riot mode"**.
- A 1-bit "Rio riot" logo may appear only where the original showed it (boot/splash, and the locked screen). First it was redrawn by us as pixel art; once the firmware bitmaps were recovered, the user's direction was to use the firmware's own boot logo instead.
- Each logo lives in **one replaceable drawable file**, with no logo pixels in code, so it can be swapped quickly if anyone ever asks.
- The About/Exit screen shows: "A fan tribute. Not affiliated with or endorsed by SonicBlue, D&M Holdings, or Rio."
- Fonts are OFL or our own bitmap font. No copied font files, no copied images.

I am not a lawyer and this is not legal advice. A discontinued product does not by itself mean its marks are abandoned, so the one-file logo swap is the right safety valve.

## 4. References

Primary

- Rio Riot User's Guide PDF (original SonicBlue file), Internet Archive: https://archive.org/details/manualsbase-id-50037
- Same guide, ManualsLib: https://www.manualslib.com/manual/141199/Rio-Rio-Riot.html
- Same guide, ManualsDir (with index): https://www.manualsdir.com/manuals/198058/rio-audio-rio-riot.html
- TechTV TechLive segment "Sonicblue Rio Riot" (2002), real unit booting, playing, menu, FM: https://archive.org/details/g4tv.com-video5034
- Rio firmware and utility collection (contains RioRiot_125_firmware.exe): https://archive.org/details/rio-audio-collection

Specs and reviews

- Wikipedia, Rio Riot: https://en.wikipedia.org/wiki/Rio_Riot
- Wikipedia, Rio Audio: https://en.wikipedia.org/wiki/Rio_Audio
- AV Watch, Japanese launch spec sheet (June 24, 2002): https://av.watch.impress.co.jp/docs/20020624/sonic.htm
- PhileWeb, Japanese launch (June 24, 2002): https://www.phileweb.com/sp/news/d-av/200206/24/5040.html
- Macworld news (resolution quoted in search excerpt): https://www.macworld.com/article/152262/sonic.html
- PC World review via CNN, March 29, 2002: https://edition.cnn.com/2002/TECH/ptech/03/29/rio.riot.idg/index.html
- Bloomberg / BusinessWeek review: https://www.bloomberg.com/news/articles/2002-03-27/rio-riot-big-music-for-big-pockets
- Glenn Fleishman quoting Walt Mossberg (Feb 28, 2002): https://glog.glennf.com/blog/2002/02/28/slower_older_worse
- SF Chronicle iPod review comparing the Riot: https://www.sfgate.com/business/article/REVIEW-iPod-s-on-the-prize-Apple-s-portable-2789924.php
- Slashdot CES 2002 story: https://news.slashdot.org/story/02/01/13/1951259/rio-riot-and-lyra-personal-jukebox

Forums

- empeg BBS, "Rio Riot: New handheld juke?": http://m.empegbbs.com/ubbthreads.php/topics/56502/
- empeg BBS, "Rio Riot Feedback": https://empegbbs.com/ubbthreads.php/ubb/printthread/Board/1/main/13037/type/thread
- AnandTech forums, 2003 owner notes: https://forums.anandtech.com/threads/rio-sonicblue-rioriot-20gb-portable-mp3-player-jukebox-134-99.1119577/

Reference images and the PDF were downloaded to a scratch folder outside the repo for viewing only. Nothing from them goes into the repo.

## 5. Homage design notes

- **Canvas**: draw the LCD at a logical 240 x 160 (3:2), integer-scale with nearest-neighbor, bezel around it.
- **Palette**: two inks plus a dim tone. Background pale mint / gray-green, ink dark gray-green, and a "ghost" tone for the dimmed screen behind the menu. Keep the tint in one token (green is the best guess, blue is the fallback if a photo proves it). Use a duller, unlit variant when the backlight times out.
- **Fonts**: draw our own proportional sans bitmap fonts in three sizes (about 16, 12, and 9 px), Helvetica-like proportions, mixed case, plus bold weights of the medium and small sizes. No copied font files.
- **Shapes**: dark rounded pills for selection, left-rounded tabs for menu items and Done / Cancel, rounded panels for dialogs and browse lists, thin rail scroll bars, round-ended volume segments.
- **Motion**: menu tabs slide in from the right over a dimmed screen. Highlighted tab shifts left and goes bold. Editable values blink.
- **Logo**: one drawable, redrawn 1-bit, splash and About only.
- **Input mapping**: m500 wheel or dpad up/down to Scroll, center to Select, plus Menu, Back, and the four playback keys. Volume stays on the hardware keys.

## Unverified details (ask the user or check a real unit)

| Detail | Most likely value | Why |
|---|---|---|
| Backlight color | green / yellow-green | green glow on the bezel and mint LCD in the TechTV footage, no text source |
| Unlit LCD color | pale gray-green with dark gray-green ink | video |
| Exact font sizes | about 16 px large, 12 px list rows, 9 to 10 px small | scaled from manual drawings |
| Title line content | track title, possibly "track# artist - title" | video frame reads "2 (Angel Alarm) - Do..." |
| "Upcoming tracks:" wording | "Upcoming Tracks" in real firmware | manual drawing vs. video |
| Pause and stop glyphs | standard two bars / solid square in the same spot as the play triangle | only play is shown |
| Play-mode tag values | "RND" for random, probably "RPT"-style tags for repeat | only "RND" is shown |
| Battery gauge levels | segmented fill inside the outline between "E" and "F", "LOW" text when low | only the LOW state is drawn |
| USB icon | shows only when connected | drawn on p18, not seen in the video |
| Boot status lines | something like "Battery Manager Setup", then another "... Setup", then "Hard Disk Setup" | blurry video frames |
| Boot logo placement | centered, slightly above middle, status text bottom left | video |
| Lock indicator | the word "LOCK" somewhere on screen, likely replacing the play-state area or as a popup | manual says only that "LOCK" appears |
| Menu slide speed | quick, a few frames | video too coarse to time |
| Wheel feel | limited travel thumb dial, no detents known | forum post plus photo |
| Line out | probably not on the US unit | Japanese spec only |
| Truncation | clipped text, no ellipsis | video |
| Sounds | none | nothing mentions key clicks |
| Factory defaults | Backlight "Always Off", Power Saver "2 minutes", "The" Filter "Off" | the guide's steps say "scroll to Always Off" etc., which reads like the current value. Riot mode ships Backlight "5 seconds" so the panel visibly lights on first use. |
| "Radio Presets" colon | no colon on the real screen | the video frame shows none; the guide's drawing has one |
| Repeat tag wording | "RPT" for All, "RPT 1" for Track | invented; only "RND" is ever shown |
| Name entry: Back key | rubs out the last character | not described |
| Uppercase matrix symbols | ". , ' : _" plus digits | the guide only says it "includes numbers" |
| Album and track list headers | "N Tracks on [album]", "N Albums by [artist]" | invented in the style of "9 Albums Match "B"" and "5 Genres on Player" |

## Riot mode as built (mikuos-riot, com.miku.riot)

What the module does with the facts above. Plain notes for whoever touches it next.

**Screen.** The LCD is a 240 x 160 buffer of four gray levels (clear, light, dark, ink), drawn at a whole-number scale with nearest-neighbor filtering. Riot mode runs in landscape (`sensorLandscape`), so on the M500's 1280 x 720 panel the LCD is 3x, 720 x 480, in the middle of the body. The body follows a photo of a real Riot held in landscape: the round four-way pad (Play/Pause top, Stop bottom, Backward and Forward on the sides) on the left with the small silver button above it, Select, the thumb wheel and Back stacked on the right, "Rio" printed top right. Nothing else is on the face. Volume and the On / Lock switch were on the real unit's edges, and the M500's own volume keys stand in for Volume. The silver button is the Riot's Menu key, and holding it for 1.2 seconds leaves Riot mode. A faint grid between LCD pixels gives the dot-matrix texture. (The first build stacked a portrait body under the screen. That layout is gone.)

**Haptics.** Every wheel detent is a short tick (22 ms, at most one every 45 ms so a fast spin clicks instead of buzzing), a button press is a firmer 35 ms pulse, and the hold that leaves Riot mode is 60 ms. They follow Settings > Sound > Touch feedback. The M500's haptics HAL has no prebaked effects (`EFFECT_TICK` falls back to a soft 50 ms buzz), so these are one-shot pulses. See [m500-haptics.md](m500-haptics.md).

**Palette.** Lit: pale mint (#CFE2C6) with dark gray-green ink. Unlit (backlight timed out or Always Off): duller gray-green (#9AA493). Contrast 0 to 14 moves the ink from faint to full, live, like the original slider. All four levels are computed in `lcdPalette()` in RiotDevice.kt; change the two colors there if the real backlight turns out different.

**Swappable look.** Nothing on the LCD is baked into code:
- Fonts are `assets/riot/font_<name>.png` (one row of glyphs, black ink on transparent) plus `font_<name>.json`: `{"height", "ascent", "space", "glyphs": {"A": {"x", "w", "ox", "adv"}}}`. x and w find the glyph in the sheet (full height), ox shifts it when drawn, adv is the pen advance. Optional `"bold": true`, and optional `font_medium_bold` / `font_small_bold` sheets; without them bold is a 1 px smear, which is how many LCD firmwares did it. Faces used: large (title, clock, frequency), medium (lists, tabs), small (pages, dialogs), tiny (tags, dial numbers, battery).
- Icons are `assets/riot/icons/<name>.png`. Hand-drawn: play, pause, stop, speaker, check, usb (the small one beside the gauge), pointer, lock. From the 1.25 firmware: usb_connected (the USB screen picture, used as recovered) and battery_100/75/50/25/low (rebuilt from the recovered gauge strip, whose row phase drifts between images; geometry and the LOW lettering are as read off it, the scrambled CHARGING cell is not used).
- The logo is one file, `assets/riot/logo_rioriot.png`: the firmware's own 240 x 55 boot logo, used as recovered (it replaced the pixel-art redraw made before the firmware bitmaps turned up). Delete it and the boot and locked screens draw without it.
- `tools/make_riot_assets.py` regenerates the fonts and hand-drawn icons; `tools/import_firmware_bitmaps.py` re-imports the firmware bitmaps from `mikuos/art/rio-riot/extracted/bitmaps/`. No font strips were found in the firmware, so the fonts stay rebuilt; if real glyphs turn up later, replacing the sheets is a pure data change.
- The USB screen shows while the M500 is plugged into a computer in file transfer mode (MTP or PTP). Any key goes back to Now Playing. Its caption, "USB Connected", is a guess.

**Fonts and license.** large/medium/small are "Riot Sans": Liberation Sans Regular rasterized by FreeType in monochrome, cropped to ink and respaced with a 1 px gap. That is a Modified Version under the SIL OFL 1.1, renamed because "Liberation" and "Arimo" are Reserved Font Names; the notice and full license ship in `assets/riot/FONTS.txt`. The tiny face and the small icons are hand-drawn for this project. No font file from SonicBlue is in the repo; the only original images are the firmware bitmaps listed above.

**Data.** Library pages read MediaStore (the ids are the same ids Miku Music plays). Picking music hands the ids to Miku Music over its Media3 MediaLibraryService (`com.miku.player/.PlaybackService`) with setMediaItems, and Miku Music resolves them in its own onSetMediaItems, so Miku Music stays the player. As on the Riot, a pick loads the queue and Now Playing waits for Select or Play. Genres come straight from MediaStore. Favorites, Top Tunes and Memory Lane use play counts that Riot mode keeps itself while it is open.

**FM.** Radio mode goes through the FM app's own media session (`com.caf.fmradio/.FmMediaBrowserService`). Play asks the FM app to power on, Stop to power off, and a frequency is tuned with `playFromMediaId("fm_freq:<kHz>")`. Riot mode never opens the tuner itself, so the FM app stays the only process that touches `/dev/radio0`. The station name and RadioText come from the session's metadata, and RDS, stereo, signal and song ID details from its PlaybackState extras when the FM app publishes them. Riot mode and MikuPod both playing FM through that session, with haptics, was confirmed on hardware on MikuOS 0.3.0, 2026-10-10.

**Deliberate differences from the original.**
- Organize > Delete... never deletes files. It walks the same screens, then says Miku Music owns the files. "Delete Everything!" clears only Riot mode's own playlists, settings and play counts.
- Equalizer > Bass/Treble saves the values but does not change the sound; Miku Music's EQ does that. The screen says so after Done.
- Time / Date shows the Android clock; the boxes are not editable.
- Preferences ends with an extra item, "Exit Riot Mode". It shows the tribute line. Holding the silver Menu button for 1.2 seconds also leaves Riot mode.
- The Information page scrolls, because it adds the tribute line under the original list.
- Japanese and other non-Latin titles draw through the system font with aliasing off at LCD size. The real player could not show them at all.
- Playback and Volume are the M500's own keys too: the volume ring is Volume, the side keys are Play/Pause, Forward and Backward.

**Unlock.** The app opens on `com.miku.riot.action.ENTER` (an exported activity alias) and as a HOME app. It runs if Settings.Global `miku_unlocks` has the key `secret.os.riot`, or if the intent carries the boolean extra `force=true`. Otherwise it shows the logo and "Not yet. Keep playing.", and any button goes back to the Miku launcher.
