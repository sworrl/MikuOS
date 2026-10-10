# Click wheel era research (for MikuPod)

This is the research behind MikuPod (package `com.miku.wheel`, module `mikuos-wheel`), the fan tribute module that recreates four landmark iPod UI generations as skins on the HiBy M500. Each skin is a pixel-scaled panel at the top of the 720x1280 screen with an on-screen touch wheel below it.

Ground rules for this doc:

- Every claim group cites a source as [n]. The numbered list is at the bottom.
- Apple's own user guides and tech spec pages are the main sources. Where Apple says nothing, I used reviews, wikis, and photos on Wikimedia Commons.
- Pixel measurements (row height, title bar height, colors) are **estimates** from photos of real screens. Apple never published them. Treat them as starting points to tune by eye.
- Where sources disagree, or I could not confirm something, the doc says so.
- A few sites (theapplewiki.com, ipodwiki.com, O'Reilly, Macworld) were blocked from direct fetch. Facts from them come from search-result excerpts and are marked "(excerpt)".

## MikuPod skins mapped to the originals

| MikuPod skin | Based on | Native panel |
|---|---|---|
| MikuPod 2001 | iPod 1G (scroll wheel, 2001) and 2G (touch wheel, 2002) | 160x128, monochrome |
| MikuPod 2004 | iPod photo / iPod with color display (2004 to 2005), with a gray option for 4G click wheel and mini | 220x176 color (gray option: 160x128 look) |
| MikuPod 2005 | iPod 5G "with video" (2005 to 2006) | 320x240 color |
| MikuPod 2007 | iPod classic 6G (2007) | 320x240 color |

---

## 1. iPod 1G and 2G (2001 to 2002)

### Screen

- 2-inch monochrome LCD, 160x128 pixels, 0.24 mm dot pitch, white LED backlight [8][13].
- Low End Mac describes it as a "160 x 128 pixel LED-backlit LCD" [20].
- Later monochrome full-size iPods (4G click wheel) list a "blue-white LED backlight" and "grayscale LCD" on the same 160x128 grid [9]. Photos of lit 3G units show a pale blue-white cast [34c].

### Input

- 1G (Nov 2001): a mechanical scroll wheel that really rotated. 2G (July 2002): a touch-sensitive wheel that looks the same from outside [20][21].
- Four buttons sit around the wheel: **MENU at top, previous (|<<) at left, next (>>|) at right, play/pause at bottom**. The center button is Select [20]. On the 1G and 2G the labels are printed on the ring. "menu" is lowercase on the 1G ring (Commons photo [34a]).
- Controls from Apple's 2002 guide [1]:
  - Press any button to turn on.
  - Hold Play to turn off.
  - Hold MENU to toggle the backlight.
  - The Hold switch disables the buttons.
  - The wheel scrolls, Select chooses, and MENU goes back.
- In 2003 the 3G moved the four buttons into a row between the screen and wheel [21]. That is out of scope for MikuPod, but worth knowing when reading 3G guides.

### Menus

Firmware history matters here, because the menus changed in the first year:

- **1.0 (Nov 2001):** first release [19 excerpt].
- **1.1 (Mar 2002):** added Contacts (up to 1000 vCards), 20+ EQ presets, shuffle by album, and scrubbing from Now Playing [19 excerpt].
- **1.2 (Aug 2002, shipped with the 2G):** added Calendar and Clock [19 excerpt].

**Main menu, 1.2 and 1.3 (the settled 1G/2G layout).** Apple's 2002 guide says to "Select Playlists or Browse in iPod's main menu" and to use "Extras" for Contacts and Calendar [1]. The 2003 guide puts Backlight on the main menu and calls Settings "the fourth menu item" [2]. O'Reilly lists the same five items for software 1.3 (excerpt, [38]). The order is:

1. Playlists
2. Browse
3. Extras
4. Settings
5. Backlight

A "Now Playing" item also appears while music is playing [1].

**Main menu, 1.0 (unconfirmed).** Paul Thurrott's 2001 review lists the first screen as "Playlists, Artists, Songs, Settings, and About" (excerpt, [39]). That is consistent with About being reachable from the main menu, which is where the Brick easter egg lived (see below). I could not confirm whether 1.0 said "Browse" or showed Artists and Songs directly. **Recommendation:** use the 1.2/1.3 layout above, and put About inside Settings.

**Browse submenu.** You can browse "by artist, album, title, genre, or composer" [1]. The usual on-device order is:

1. Artists
2. Albums
3. Songs
4. Genres
5. Composers

That order is from screenshots and memory. The Apple guide gives the set of categories, not their order. One wiki excerpt credits 1.2 with adding album and genre browsing [19 excerpt], so the 1.0 Browse list may have been shorter.

**Extras (1.2 era).** The items are Contacts [1], Calendar [1], Clock [19], and Game. Brick was listed as "Game" once it left hiding [17][18]. I could not confirm the on-device order. Clock, Contacts, Calendar, Game is a reasonable guess.

**Brick easter egg.**

- On firmware 1.0, open the **About** screen and hold the center button for several seconds [17][18].
- In 1.1 it moved to the Legal screen under Settings [18].
- Later it became the Extras > Game item [17].
- Brick is a Breakout-style game. Wikipedia credits the design to Steve Wozniak [17].

**Settings.** Apple's spec page for the scroll wheel iPod lists these customizable settings [8]:

- Equalizer
- Shuffle songs or albums
- Repeat one or all
- Startup volume
- Sleep timer
- Backlight timer
- Display contrast
- Clicker
- Languages

Later guides add About, Legal, Reset All Settings, and Date & Time [2]. Known values:

| Setting | Values | Notes |
|---|---|---|
| Shuffle | Off / Songs / Albums | Albums arrived in 1.1 [19][2] |
| Repeat | Off / One / All | [2] |
| Backlight Timer | Off, 2 Seconds, 5 Seconds, 10 Seconds, 20 Seconds, Always On | Only the 2 to 20 second range plus Always On is confirmed [33]. The exact list is unconfirmed. The default is 10 seconds on the classic [6]. |
| Clicker | On / Off | The 1G spec lists "Clicker" with no options [8]. Speaker/Headphones/Both came with the click wheel (section 2). |
| EQ | Off plus about 20 presets (Acoustic, Bass Booster, Rock, and so on) | [19][9] |
| Contrast | Slider adjusted with the wheel | Hold MENU about 4 seconds to reset it [2] |
| Sleep Timer | Off plus minute steps | It sits under Settings on 1G/2G per the spec list [8]. It moved to Extras > Clock > Sleep Timer by 2003 [2]. |
| Language | List | [8] |
| Legal, Reset All Settings | Actions | Reset is a confirm screen whose second item is "Reset" [2] |

### Title bar and lists

- **Title bar:** play/pause state icon at left, centered title, and battery icon at right, with a 1 px rule under it. This is visible in Commons photos of Chicago-era screens [34b][34c].
  - The battery icon animates while charging and shows a lightning bolt when charging [2].
  - Apple only documents the classic's lock icon, which shows in the title bar when Hold is on [6]. An older-era lock glyph is likely but I could not confirm it.
- **Selection:** an inverted, full-width black bar with white text [34d][34e].
- **Submenu arrows:** rows that lead to another menu show ">" at the right edge [34d][34e]. The classic guide states the rule: "An arrow next to a menu item indicates that choosing it leads to another menu or screen" [6].
- **Rows (estimate):** 6 visible rows. The title bar is about 20 px including the rule, and rows are about 18 px each (20 + 6 x 18 = 128). This is measured from photos of the 3G and 4G mono menus, which share the 1G grid and font [34d][34e].

### Now Playing

The layout is visible in the Commons photos of Chicago-era screens [34b][34c]:

- Title bar as above. A play triangle sits at left. Apple's English firmware names this screen "Now Playing" [1], though the photographed unit shows the current list name instead.
- "11 of 17" in small bold, left-aligned under the title bar.
- Three centered lines: song title, artist, album.
- A rounded-outline progress bar that fills from the left.
- Elapsed time at bottom left ("0:13") and remaining time at bottom right ("-4:16").

Behavior:

- On this screen the wheel changes volume [1]. A volume bar shows in place of the progress bar while you turn. That detail is from memory: Apple documents the behavior, not the look.
- Pressing Select shows the scrubber, from 1.1 on [19][2].

### Font

Chicago, Apple's 1984 bitmap system font, in a slightly altered form [14][16].

### Boot

Reset and startup show the Apple logo [2][3]. On a monochrome LCD it is a dark logo on the light, backlit screen.

---

## 2. iPod mini and 4G click wheel (2004)

- **Screens:**
  - 4G: the same 160x128 grayscale grid with a blue-white LED backlight [9].
  - mini: a smaller screen. Photos show a strong blue backlight [34f].
- **Click Wheel:** introduced on the mini (Feb 2004) and adopted by the 4G (July 2004). The four buttons sit under a touch-sensitive ring, with MENU top, previous left, next right, play/pause bottom, and Select in the center [31][3].
- **Fonts:**
  - mini: Espy Sans, from the Newton [14][16].
  - 4G full size: still Chicago [14].
- **Main menu:**
  - The July 2004 4G added "Shuffle Songs, a new command in the main menu" [22].
  - A Commons photo of a 4G mono screen shows: **Music, Extras, Settings, Shuffle Songs, Backlight** [34e].
  - The 4G guide still says "Select the fourth menu item (Settings)" [3]. That line looks copied from the 3G guide [2], since the photo shows Settings third.
  - The first mini guide still says "Select Playlists or Browse from the main menu" [4], so the mini launched on the older layout.
  - A 3G running later firmware also shows Music, Extras, Settings, Shuffle Songs, Backlight, Now Playing [34d].
- **Music submenu (4G):** Playlists, Artists, Albums, Songs, Genres, Composers, Audiobooks.
  - The guides confirm Music > Playlists, the On-The-Go playlist, and audiobooks [3][5].
  - The full order is from memory, not an Apple document.
  - Podcasts joined this menu in mid-2005 firmware. Not confirmed here.
- **Extras (4G guide):** Clock (with Alarm Clock and Sleep Timer), Contacts, Calendar (with To Do), Notes, Games, plus Voice Memos and Photo Import when those accessories are attached [3]. Games: Brick, Music Quiz, Parachute, Solitaire [17].
- **Click sound:** "you can hear a clicking sound through the iPod internal speaker". The Clicker setting has four values [3]:
  - **Off**
  - **Speaker** (internal speaker)
  - **Headphones**
  - **Both**
- **Selection and title bar:** the same as 1G, with an inverted dark bar, white text, and ">" arrows [34e].
- **mini Now Playing (photo):** [34f]
  - Title bar: play icon left, clock time centered ("8:01 PM"), battery right.
  - "142 of 171" at left, shuffle icon at right.
  - Two centered lines: title and artist.
  - Progress bar, with elapsed time left and remaining time right.

---

## 3. iPod photo / iPod with color display (late 2004 to 2005)

- **Screen:** 2-inch color LCD, **220x176**, 0.18 mm dot pitch, 16-bit color (65,536 colors), blue-white LED backlight [10].
- **Font: not Chicago.** The color iPods introduced **Podium Sans**, an Apple bitmap humanist sans [15][16].
  - Apple's marketing at the time called it a "new Myriad typeface". The Wikipedia article points out it lacks Myriad's signature letterforms [15].
  - EveryMac simply says the color models use Myriad [14]. That is the marketing claim, not the actual face.
  - Practical upshot: a pixel sans is the right call for MikuPod 2004, because the original was a bitmap font too.
- **Main menu (Commons photo):** **Music, Photos, Extras, Settings, Shuffle Songs, Backlight** [34e].
- **Look (photo):** [34e]
  - Light gray title bar with a centered "iPod" and a green battery at right.
  - Blue gradient selection bar with white text.
  - ">" arrows on submenu rows.
  - About 7 rows of about 22 px each, under a title bar of about 20 px (estimate).
- **Album art:** from the Now Playing screen, pressing Select shows the album artwork [5]. Pressing it again gets to the scrubber [5].
  - A small art thumbnail on the main Now Playing view is common in photos of this era, but Apple's guide does not describe it.
  - Treat full-screen art on Select as the documented behavior.
- **Photos menu:** Photo Library and albums, plus Photo Import [5]. **Slideshow Settings** has [5]:
  - Time Per Slide
  - Music (a playlist, or From iPhoto)
  - Repeat (On/Off)
  - Shuffle Photos (On/Off)
  - Transitions
  - TV Out (Ask/On/Off)
  - TV Signal (NTSC/PAL)
- **Extras:** Clock, Contacts, Calendar, Notes, Games, plus Voice Memos with the accessory [5]. Games: Brick, Music Quiz, Parachute, Solitaire [17].
- **Clicker:** Off / Speaker / Headphones / Both [5].

---

## 4. iPod 5G "with video" (2005 to 2006)

- **Screen:** 2.5-inch QVGA transflective color LCD, **320x240**, 0.156 mm dot pitch, 65,000+ colors, white LED backlight [11].
- **Font:** Podium Sans, anti-aliased bitmap [15].
  - Popularly called Myriad [14], but the Wikipedia article on Podium Sans covers this exact mix-up [15].
  - The face is bold-looking and humanist, which is why PT Sans is a reasonable stand-in.
- **Main menu at launch (Commons photo, Nov 2005):** **Music, Photos, Videos, Extras, Settings, Shuffle Songs** [34g].
  - Backlight is no longer on the default menu. Users could add items through Settings > Main Menu [3][6].
- **List look (photos):** [34g][34h]
  - Light gray gradient title bar with a centered title ("iPod" on the main menu) and a green battery at right.
  - White to very light gray list background.
  - Blue gradient selection with white text.
  - ">" arrows on every row that has a submenu.
  - **9 visible rows** in the photographed album list (an "All" row plus 8 albums) [34h].
  - Estimate: title bar about 22 to 24 px, rows about 24 px.
- **Now Playing without art (photo):** [34i]
  - Title bar: "Now Playing" centered, a blue play triangle at left, battery at right.
  - "12 of 12" at top left.
  - Three centered lines: song, artist, album.
  - A glossy blue progress bar on a light track.
  - Elapsed time at bottom left, remaining time at bottom right.
- **Now Playing with art:** art at left, text to its right.
  - A 2007 review says the classic's art is "larger than on the older iPod video", which confirms the 5G showed art on this screen [24].
  - The exact geometry is not documented.
- **Extras:** Clock, Contacts, Calendar, Notes, Games, plus **Stopwatch** and **Screen Lock**. O'Reilly describes the color-screen models as having "four games, a stopwatch, a world clock, and a screen-locking feature" (excerpt, [38]).
  - Games: Brick, Music Quiz, Parachute, Solitaire [17].
  - I could not confirm which firmware added Stopwatch and Screen Lock. Search did not settle it.
- **Search:** arrived with the late-2006 revision (often called 5.5G), along with a brighter screen and gapless playback. Purchasable iPod Games came to all 5G units by firmware in September 2006 [21].
- **Clicker:** forum reports say 5G software offers only On/Off, while the nano and mini of the same period had Speaker/Headphones/Both [32]. Anecdotal.

---

## 5. iPod classic 6G (2007)

- **Screen:** 2.5-inch color LCD, **320x240** at 163 ppi [12].
- **Font:** the 2007 refresh switched the classic and nano UI to **Helvetica Bold**, to match the iPhone and iPod touch [15][14].
  - Not Myriad, and not Podium Sans.
  - The Register called it "smooth, bold lettering" [23].
- **Interface:** "completely overhauled", with more graphics and Cover Flow [21].
- **Split-screen main menu:**
  - The menu "fills just the left half the screen", and the right half is "devoted to graphics" [23].
  - The menu bar casts a drop shadow onto the image area [23].
  - The right side shows a random slideshow of album art, video art, and photos with a "Ken Burns style transition effect" [24].
  - The art changes with the highlighted item [23].
- **Main menu (Commons photo):** **Music, Videos, Photos, Podcasts, Extras, Settings, Shuffle Songs** [34j].
  - Podcasts moved out of Music into its own main menu item [24].
- **Title bar:** Apple's diagram labels the menu title, Lock icon, play status, and battery [6]. Photos show the title **left-aligned**, unlike earlier eras. A clock time shows at left in some states, and play/pause plus battery sit at right [34h][34j][34k].
- **Music submenu:** Apple documents **Cover Flow** and **Search** in the Music menu [6]. The full 2007 order from memory, unconfirmed by an Apple doc:
  1. Cover Flow
  2. Playlists
  3. Artists
  4. Albums
  5. Songs
  6. Genres
  7. Composers
  8. Audiobooks
  9. Search

  Later firmware added Genius Mixes [7].
- **List look (photos):** [34h][34k]
  - Bright cyan-to-blue gradient selection with white bold text and a white ">" at right.
  - Very light gray list background.
  - The album list uses two-line rows with a square thumbnail at left: bold title, plus a gray subtitle like "1 Song".
  - Plain lists show about 9 rows of about 24 px under a title bar of about 20 px (estimate from the matching nano 3G UI [34k]).
- **Cover Flow:**
  - "From the Music menu, choose Cover Flow". Scroll with the wheel or with next/previous. Select an album and press Center to get its track list [6].
  - Selecting a cover shows the track listing "just as it does on the iPhone" [23].
  - In 2007 firmware it sat on a **white background**, which The Register said exposed jagged edges [23].
  - A musical note placeholder shows until art loads [24].
  - Reflections under covers are described by ipodwiki (excerpt, [25]).
  - Firmware 1.0.2 (Oct 2007) improved Cover Flow performance [37].
- **Now Playing:** [6][24][25]
  - Album art at left shown in 3D perspective with a reflection beneath it, described as larger than the 5G's and with "a mirror effect".
  - Song title, artist, album, and rating to the right.
  - The song number ("x of y").
  - A song time progress bar with elapsed and remaining times.
  - Shuffle and repeat icons at top right.
  - Repeated Center presses cycle the scrubber (a diamond on the bar), rating, shuffle, and lyrics [6].
- **Extras (2008 guide):** Alarms, Calendars, Clocks (multiple time zones), Contacts, Games, Notes, Stopwatch, and Screen Lock [6].
  - Games: **iQuiz, Klondike, Vortex** [6][17].
  - The Gadgeteer notes Timer got its own menu and Stopwatch was "graphically updated" [24].
- **Settings:** Apple documents About (with pages cycled by Center), Shuffle, Repeat, Main Menu (checkmark list), Backlight Timer (default 10 seconds, plus "Always On"), Brightness (slider), EQ, Sound Check, Clicker, Language, and Reset Settings [6].
  - The Register says the right-hand art changes to reflect the current setting, for example the EQ sliders [23].
- **Clicker:** **On / Off** only [6]. The 2009 firmware moved it to Settings > General [7].

---

## Screen comparison

| Era | Resolution | Size | Colors | UI font (actual) | Visible rows (est.) |
|---|---|---|---|---|---|
| 1G/2G (2001 to 2002) | 160x128 | 2.0" | mono, white LED [8] | Chicago [14] | 6 |
| mini (2004) | 138x110 (not verified here) | 1.67" | gray, blue backlight | Espy Sans [14] | about 5 |
| 4G click wheel (2004) | 160x128 | 2.0" | grayscale, blue-white LED [9] | Chicago [14] | 6 |
| photo / color (2004 to 2005) | 220x176 | 2.0" | 65,536 [10] | Podium Sans [15] | about 7 |
| 5G video (2005 to 2006) | 320x240 | 2.5" | 65,000+ [11] | Podium Sans [15] | 9 [34h] |
| classic 6G (2007) | 320x240 | 2.5" | color, 163 ppi [12] | Helvetica Bold [15] | about 9 (half-width) |

The mini resolution is commonly given as 138x110, but I did not verify it against an Apple page in this pass.

## Click wheel and click sound

None of these players had a vibration motor. What you felt was the wheel itself and the switches under it. What you heard was the clicker.

### Wheel hardware

- **1G (2001):** a wheel that really turned, on a ball-bearing axle with a contactless optical "chopper" [47]. It had no detents. The four buttons were separate parts around it [20][34a].
- **2G (2002):** a Synaptics capacitive touch wheel in place of the turning one, same layout [47][20].
- **3G (2003):** touch wheel, with the four buttons moved to a row above it [21][47]. Out of scope here.
- **mini and 4G on (2004):** the Click Wheel. A capacitive ring with four mechanical switches under it (MENU, previous, next, play/pause) and a separate center switch [31][3]. Each switch gives a firm click you feel and hear.

### Steps per turn

Apple never published a step count. Rockbox's drivers are the best field-tested numbers:

- **1G to 3G:** 96 positions per turn (`WHEELCLICKS_PER_ROTATION 96`), one scroll step every 6 (`WHEEL_BASE_SENSITIVITY 6`). That is **16 steps per turn, 22.5 degrees each** [43]. On the 1G the wheel draws about 12 mA, so Rockbox powers it only while it moves [43].
- **Click wheel (4G, mini, photo, 5G, classic):** 96 positions per turn, one step every 4. That is **24 steps per turn, 15 degrees each**. The nano uses 6 because its wheel is smaller [30].
- **Acceleration:** the 1G "provides an accelerated scrolling capability" [47]. Rockbox smooths wheel velocity and speeds up past a threshold (1G to 3G: repeat above 45 degrees a second) [43][30]. The 2007 classic shows a big letter when you spin fast through a long list [6][7]. Apple's own curve is not documented.

### The clicker

- **What makes the sound:** a piezo element in the case. Apple calls it "the iPod internal speaker" [3]. A user who opened one describes "a piezoelectric speaker, which produces the click you hear", also used for the alarm beeps [49]. Apple's 3G and 4G guides say an alarm set to "Beep" plays "through the internal speaker" [2][3].
- **How Rockbox drives it:** a short square-wave burst from a timer:
  - PortalPlayer models (4G, mini, photo, 5G): period 91, where the pitch is about 91,225 / period Hz, so about **1.0 kHz for 4 ms**. Older Rockbox used about 1.85 kHz for 0.4 ms on the wheel and 3 ms on buttons [44].
  - 2007 classic (Samsung S5L8702): a 100 kHz timer with period 2 x 40 ticks, 4 periods, so **4 cycles at 1.25 kHz, 3.2 ms** [45].
  - Rockbox enables the hardware click on the 4G and 5G configs, not on 1G to 3G [46].
  - It ignores a new click while one is still playing [44][45].
  - A small piezo disc rings near its resonance, usually 2.5 to 4 kHz, so a 1 kHz drive comes out as a short high tick, not a tone. The resonance is typical for such parts, not measured on an iPod.
- **Buttons:** Rockbox plays the same click for button presses as for wheel steps [44]. Apple's guides only mention scrolling [3][5][6].
- **Level:** forum users say the click did not follow the music volume [32].

### Clicker setting by model

| Model | Clicker values | What Apple says | Source |
|---|---|---|---|
| 1G and 2G | On / Off | Tech specs list "Clicker", no options | [8] |
| 4G click wheel | Off / Speaker / Headphones / Both | "set Clicker to Headphones ... Off ... Speaker ... Both" | [3] |
| photo / color | Off / Speaker / Headphones / Both | same wording | [5] |
| 5G video | On / Off | forum reports only, no Apple guide found | [32] |
| classic 2007 (120 GB guide) | On / Off | "a clicking sound through the iPod classic internal speaker" | [6] |
| classic 2009 (160 GB guide) | On / Off, under Settings > General | "through the earphones or headphones and through the iPod classic internal speaker" | [7] |

MikuPod follows these guides.

### What MikuPod does

- **Steps:** 16 per turn (22.5 degrees) on 2001, 24 per turn (15 degrees) on 2004, 2005 and 2007. One tick per step that moves something. No tick at the end of a list.
- **Tap or drag:** a touch that starts on the center is only ever the center button. It never scrolls, like the real switch. A touch on the ring scrolls once it has turned more than half a step, otherwise it is a button on release. On 2001 the outer band is four buttons that never scroll and the inner wheel scrolls but cannot be pressed, as on the 1G and 2G.
- **Click timing:** the center clicks (sound and pulse) as the finger goes down, like a dome switch. A ring button clicks when the tap is recognized, at release or when a hold starts.
- **Sound:** synthesized per era at runtime, no samples. A square burst at the Rockbox drive (2001: 3 cycles at 1 kHz, inferred. 2004 and 2005: 4 cycles at 1 kHz. 2007: 4 cycles at 1.25 kHz) through a band-pass at 3.0 to 3.75 kHz standing in for the piezo, plus a little of the raw edge. It peaks near 3 kHz and drops 20 dB within 4 to 5 ms.
- **Clicker setting:** 2004 has Off / Speaker / Headphones / Both. The others have On / Off. "On" is Speaker on 2001 and Both on 2005 and 2007. Speaker plays on the sonification stream, which keeps its own volume like the piezo did. Headphones mixes into the music stream at the music volume. The M500 has no speaker, so both reach the active output. Saved per era.
- **Haptics:** a MikuPod addition, since the originals had no motor. Wheel step 22 ms, ring switches and 2001 buttons 32 ms, center 36 ms. Step pulses are skipped while the motor is still running or coasting, and never closer than 45 ms. The sound still plays for every step. Pulses use the touch usage and also check `haptic_feedback_enabled` and `miku_haptics`. Pulse lengths come from mikuos/docs/m500-haptics.md.

## Radio

### What existed

- **iPod Radio Remote (2006):** an FM tuner in the headphone remote for the 5G video iPod and the nanos. With it plugged in, "Radio" shows up in the main menu, and tuning happens "in the color display with your Click Wheel" [52]. One reviewer saw Radio under Music too, and a radio region setting in Settings [51].
- **Remote screen:** Center switches the lower half between the radio dial and the station text. With the dial up, the wheel tunes. Holding next or previous scans [50]. Holding Center marks a favorite, and favorites show as small triangles under the dial [50]. One classic user saw a small blue dot instead [53]. Next and previous jump between favorites [51].
- **Steps:** 0.2 MHz in the US, 0.1 MHz in Europe, set by region [51]. 87.5 to 107.9 MHz in the US and Europe, 76 to 90 MHz in Japan [52].
- **RDS:** station and song text where stations send it [52]. On a classic it showed after a few seconds, along the bottom or in the title bar [53].
- **2009 nano (5th gen):** built-in tuner, documented in detail [48]:
  - The headphone cord is the antenna, and the radio does not play without headphones.
  - The radio screen shows RDS data, the radio dial, favorite markers, a signal icon "when the radio is on and receiving a signal", and the frequency.
  - Next or previous seeks, or steps through favorites when there are any. Holding them scans with a five-second preview of each station.
  - Hold Center, then "Add to Favorites".
  - Menu from the radio screen opens the Radio menu: Play Radio, Stop Radio, Favorites, Tagged Songs, Recent Songs, Radio Regions, Live Pause.
  - Radio Regions: Americas 87.5 to 107.9 / 200 kHz, Asia 87.5 to 108.0 / 100 kHz, Australia 87.5 to 107.9 / 200 kHz, Europe 87.5 to 108.0 / 100 kHz, Japan 76.0 to 90.0 / 100 kHz.
- **Nothing for 2001 to 2004.** No tuner or radio accessory from Apple worked with the 1G to 4G or the photo.

### What MikuPod does

- **2005 and 2007:** modeled on the Radio Remote screen, with the menu and region list from the 2009 nano guide because the Remote's own guide could not be fetched. The menu has Play or Stop Radio, Favorites and Radio Regions. Tagging, Recent Songs and Live Pause are left out.
- **2001 and 2004: invented.** No radio existed for these. The screen is the same layout drawn in the era's own font, title bar, bars and colors.
- **Screen:** title "Radio", the frequency large with "FM", a signal icon while the tuner is up, the station name, then the dial or the RDS text (Center switches). The dial has ticks every 0.2 MHz, labels every 2 MHz, a needle, and favorites as triangles.
- **Controls:** wheel tunes one region step per click with the clicker. Center switches dial and text. Hold Center adds or removes a favorite. Next and previous go to the next favorite, or seek when there are none. Holding them seeks every 5 seconds. Play/pause turns the radio on or off.
- **Region:** Americas by default (0.2 MHz). Europe and Asia give 0.1 MHz.
- **Antenna:** without wired headphones the screen says to connect them, since the cord is the antenna [48].
- **Tuner:** driven only through the FM app's media session (`com.caf.fmradio`). MikuPod never opens the radio device.

## Trademark and legal

- **Trademarks:** **iPod**, **Cover Flow**, and the **Apple logo** are registered Apple trademarks [29].
  - "Click Wheel" is not on Apple's current list, but it was Apple's product name for the control [22][29]. Treat it as Apple's.
  - Chicago, Espy Sans, Podium Sans, and Helvetica are owned by Apple or its licensors.
- **Name:** the product is **MikuPod**. "MikuPod" replaces "iPod" everywhere the originals showed it, such as the main menu title and About screens.
  - The app name, launcher label, and package (`com.miku.wheel`) do not use "iPod" or "Apple".
- **Logo (user decision):** a 1-bit Apple logo may appear on in-skin boot and About screens where the original showed it.
  - It must be **redrawn by us as pixel art**, not a copied image file.
  - Store it as **one replaceable drawable per skin** so it can be swapped out quickly.
  - Keep it out of launcher icons and any store or marketing art. The logo is a registered mark [29], so being able to remove it fast is the right hedge.
- **Disclaimer:** every skin's About screen carries this line: "A fan tribute. Not affiliated with or endorsed by Apple Inc."
- **No Apple fonts or images ship:**
  - No Chicago, Myriad, Podium Sans, Espy Sans, or Helvetica.
  - No Apple screenshots, icons, or sounds.
  - Click sounds are synthesized or recorded by us.
- **Cover Flow history:**
  - Artist Andrew Coulter Enright conceived the interaction (he called it "fliptych"), and Jonathan del Strother first built it. It shipped as "CoverFlow" from Steel Skies [26].
  - Apple bought it in 2006 and put it in iTunes 7 (Sept 12, 2006) [26].
  - It came to the iPod classic, nano 3G, and iPod touch in Sept 2007 [26].
  - Apple holds design patent **D613,300** (April 2010) on the interface [26] and utility patent **8,230,360** (July 2012) on Cover Flow style media browsing [27].
  - Mirror Worlds won a $625.5M verdict over related patents in 2010, which was reversed in April 2011 [28][26].
- **In-app label for the Cover Flow screen:** "Cover Flow" is a registered mark [29]. The research recommendation was a neutral label such as **"Covers"**. The build keeps the era's own wording, "Cover Flow", on the 2007 Music menu, because the user allowed in-skin screens to show the original wording where it appeared. It is one constant (`Skin.COVER_FLOW` in mikuos-wheel), so switching to "Covers" is a one-line change if that is ever wanted. It is never used in the app name, launcher label, or package.

## Fonts and licenses (shipped choices)

- **Pixel Operator** by Jayvee Enaguas (HarvettFox96).
  - License: **Creative Commons Zero (CC0) 1.0**, public domain. The license changed to CC0 in release 2018.10.04-1 [35].
  - DaFont's sidebar also tags it "Public domain / GPL / OFL", but the author note says CC0 [35].
  - Pages: https://www.dafont.com/pixel-operator.font, source at https://notabug.org/HarvettFox96/ttf-pixeloperator [35][36].
  - Use: the Chicago-style pixel face for **MikuPod 2001** and **MikuPod 2004**. For 2004 this stands in for Chicago (gray option) and Podium Sans (color). Both originals were bitmap faces, so a pixel font is faithful in spirit.
- **PT Sans** by ParaType.
  - License: **SIL Open Font License 1.1**, "Copyright (c) 2010, ParaType Ltd." [37].
  - The license reserves the font names "PT Sans" and "ParaType". We ship the files unmodified (no subsetting), so no renaming is needed.
  - Source: https://github.com/google/fonts/tree/main/ofl/ptsans [37].
  - Use: the stand-in for Podium Sans on **MikuPod 2005**. The original was a humanist bitmap sans often mistaken for Myriad [15], so PT Sans Bold is a close match.
- **Liberation Sans** by Red Hat (digitized data by Google, reserved names Liberation, Arimo).
  - License: **SIL Open Font License 1.1** (version 2.1.5) [42].
  - Shipped unmodified, so the reserved names are untouched.
  - Use: **MikuPod 2007**. The original was **Helvetica Bold** [15][14], a grotesque. Liberation Sans shares Arial's metrics and is much closer to Helvetica than PT Sans, so 2007 uses it instead.
- All three license texts ship inside the APK under `assets/licenses/`, and the in-skin Settings > Legal screen credits each font.
- **ChiKareGo2** was considered for the Chicago look and **rejected**, because its license could not be confirmed. Search turned up no license page for it [41].

---

## Sources

1. Apple, iPod (Original) User's Guide, 2002. https://cdsassets.apple.com/live/6GJYWVAV/user/ma518_ipod_originaluserguide.pdf
2. Apple, iPod (with Dock Connector) User's Guide, 3G, 2004. https://cdsassets.apple.com/live/6GJYWVAV/user/ma517_ipoddockconnectoruserguide.pdf
3. Apple, iPod (Click Wheel) User's Guide, 4G, 2004. https://cdsassets.apple.com/live/6GJYWVAV/user/ma520_ipod_click_wheel_userguide.pdf
4. Apple, iPod mini User's Guide, 2004. https://cdsassets.apple.com/live/6GJYWVAV/user/ma734_0190191_ipodmini_ug.pdf
5. Apple, iPod with color display User's Guide, 2005. https://cdsassets.apple.com/live/6GJYWVAV/user/ma92_ipod_user_guide_color_display.pdf
6. Apple, iPod classic (120GB) User Guide, 2008. https://cdsassets.apple.com/live/6GJYWVAV/user/ma630_ipod_classic_120gb_en.pdf
7. Apple, iPod classic 160GB User Guide, 2009. https://cdsassets.apple.com/live/6GJYWVAV/user/ma1195_ipod_classic_160gb_user_guide.pdf
8. Apple Tech Specs, iPod with scroll wheel (5 and 10 GB). https://support.apple.com/en-ae/112530
9. Apple Tech Specs, iPod click wheel (20/40 GB). https://support.apple.com/en-ae/112541
10. Apple Tech Specs, iPod photo. https://support.apple.com/en-ae/112449
11. Apple Tech Specs, iPod (5th generation). https://support.apple.com/en-ae/111923
12. Apple Tech Specs, iPod classic (2007). https://support.apple.com/en-ae/112478
13. EveryMac, iPod (Original/Scroll Wheel) specs. https://everymac.com/systems/apple/ipod/specs/ipod.html
14. EveryMac, iPod font FAQ. https://everymac.com/systems/apple/ipod/ipod-faq/ipod-inventor-designer-font-used-where-to-buy.html
15. Wikipedia, Podium Sans. https://en.wikipedia.org/wiki/Podium_Sans
16. Wikipedia, Chicago (typeface). https://en.wikipedia.org/wiki/Chicago_(typeface)
17. Wikipedia, iPod game. https://en.wikipedia.org/wiki/IPod_game
18. Apple Wiki (Fandom), Breakout. https://apple.fandom.com/wiki/Breakout
19. The Apple Wiki, Firmware/iPod (excerpt). https://theapplewiki.com/wiki/Firmware/iPod
20. Low End Mac, Original iPod. https://lowendmac.com/2001/original-ipod/
21. Wikipedia, iPod Classic. https://en.wikipedia.org/wiki/IPod_Classic
22. Apple Newsroom, "Apple Introduces the New iPod", July 19, 2004. https://www.apple.com/newsroom/2004/07/19Apple-Introduces-the-New-iPod/
23. The Register, iPod classic review, Sept 2007, pages 2 and 3. https://www.theregister.com/2007/09/13/review_apple_ipod_classic/?page=2 and https://www.theregister.com/2007/09/13/review_apple_ipod_classic/?page=3
24. The Gadgeteer, Apple iPod classic review, Sept 2007. https://the-gadgeteer.com/2007/09/19/apple_ipod_classic/
25. ipodwiki, iPod classic (6th Generation) (excerpt); Digital Trends iPod classic 80GB review (excerpt). https://ipodwiki.com/wiki/IPod_classic_(6th_Generation) and https://www.digitaltrends.com/mp3-player-reviews/apple-ipod-classic-80gb-review/
26. Wikipedia, Cover Flow. https://en.wikipedia.org/wiki/Cover_Flow
27. AppleInsider, "Apple wins patent for Cover Flow-like user interface", July 2012. https://appleinsider.com/articles/12/07/25/apple_wins_patent_for_cover_flow_like_user_interface
28. AppleInsider, "Apple wins appeal reversing $625.5 million Cover Flow patent dispute", April 2011. https://appleinsider.com/articles/11/04/05/apple_wins_appeal_reversing_625_5_million_cover_flow_patent_dispute
29. Apple, Trademark List. https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html
30. Rockbox, iPod click wheel driver (button-clickwheel.c). https://github.com/Rockbox/rockbox/blob/master/firmware/target/arm/ipod/button-clickwheel.c
31. Wikipedia, iPod click wheel. https://en.wikipedia.org/wiki/IPod_click_wheel
32. Forum reports on Clicker options and the 3G click: Apple Community https://discussions.apple.com/thread/168990 and https://discussions.apple.com/thread/861602 ; MacRumors https://forums.macrumors.com/threads/ipod-clicker.99149
33. Chron, "How to Troubleshoot the iPod Backlight". https://smallbusiness.chron.com/troubleshoot-ipod-backlight-47484.html
34. Wikimedia Commons photos (used for layout, rows, and colors):
    - a. https://commons.wikimedia.org/wiki/File:IPod_first_generation_click-wheel-2004-11-30.jpg (1G wheel and buttons)
    - b. https://commons.wikimedia.org/wiki/File:Early_iPod_interface.png (Chicago Now Playing)
    - c. https://commons.wikimedia.org/wiki/File:Ipod_backlight.jpg (lit 3G Now Playing)
    - d. https://commons.wikimedia.org/wiki/File:IPod_3G.jpg (3G main menu, later firmware)
    - e. https://commons.wikimedia.org/wiki/File:IPod_4G_and_iPod_photo-2005-03-02.jpg (4G mono and photo main menus)
    - f. https://commons.wikimedia.org/wiki/File:Ipod_mini_1G.jpg (mini Now Playing)
    - g. https://commons.wikimedia.org/wiki/File:IPod_5G_menu-2005-11-03.jpg (5G main menu)
    - h. https://commons.wikimedia.org/wiki/File:IPod_5-6_Gen_side-by-side_crop.jpg (5G vs 6G lists)
    - i. https://commons.wikimedia.org/wiki/File:IPod_5G_black_now_playing-2005-11-14.jpg (5G Now Playing)
    - j. https://commons.wikimedia.org/wiki/File:IPod_classic_6G_black_new_interface-2007-09-15.jpg (6G split main menu)
    - k. https://commons.wikimedia.org/wiki/File:3G_iPod_nano_UI.jpg (2007 UI on nano 3G, same toolkit as classic)
35. DaFont, Pixel Operator. https://www.dafont.com/pixel-operator.font
36. NotABug, HarvettFox96/ttf-pixeloperator. https://notabug.org/HarvettFox96/ttf-pixeloperator
37. Google Fonts, PT Sans (OFL.txt, METADATA.pb), https://github.com/google/fonts/tree/main/ofl/ptsans ; iPod classic 1.0.2 update coverage, Macwelt https://www.macwelt.de/article/935952/software-update-1-0-2-fuer-ipod-nano-und-classic-verbessert-cover-flow.html
38. O'Reilly, iPod & iTunes: The Missing Manual, ch. 1 and ch. 8 (excerpts). https://oreilly.com/library/view/ipod-itunes/059652675X/ch08.html
39. Thurrott, "20 Years Later: My Original Apple iPod Review" (excerpt). https://www.thurrott.com/music-videos/258569/20-years-later-my-original-apple-ipod-review
40. Hackaday, "Obsession: the search for the perfect click". https://hackaday.io/project/13124-box-of-clicky-light-awesomeness/log/46182-obsession-the-search-for-the-perfect-click
41. ChiKareGo2 license search: no license page found (searched Oct 2026). Related Chicago-style fonts with clear terms are listed at https://www.fontspace.com/chicagogo-font-f6680 for comparison.
42. Liberation Fonts 2.1.5 release and LICENSE (SIL OFL 1.1), https://github.com/liberationfonts/liberation-fonts/releases
43. Rockbox, iPod 1G to 3G button driver (button-1g-3g.c). https://github.com/Rockbox/rockbox/blob/master/firmware/target/arm/ipod/button-1g-3g.c
44. Rockbox, PortalPlayer iPod piezo driver (piezo.c). https://github.com/Rockbox/rockbox/blob/master/firmware/target/arm/ipod/piezo.c
45. Rockbox, iPod classic piezo driver (piezo-6g.c). https://github.com/Rockbox/rockbox/blob/master/firmware/target/arm/s5l8702/ipod6g/piezo-6g.c
46. Rockbox target configs with HAVE_HARDWARE_CLICK: ipod4g.h and ipodvideo.h (not ipod1g2g.h or ipod3g.h). https://github.com/Rockbox/rockbox/tree/master/firmware/export/config
47. Electronic Design, "Inside iPod". https://www.electronicdesign.com/technologies/industrial/displays/article/21760166/inside-ipod
48. Apple, iPod nano (5th generation) User Guide, 2009, chapter 6 "Listening to FM Radio". https://cdsassets.apple.com/live/6GJYWVAV/user/ma1194_ipod_nano_5th_gen_userguide.pdf
49. Apple Community, "What makes that Clicking sound from the Clicker?". https://discussions.apple.com/thread/704092
50. Macworld, review of the Apple iPod Radio Remote, 2006 (excerpt; page blocked from direct fetch). https://www.macworld.com/article/178604/ipodfrmremote.html
51. James Cridland, "A review of the Apple iPod Radio Remote", 2006. https://james.cridland.net/blog/2006/review-of-apple-ipod-radio-remote/
52. EveryMac, "Can you get radio on the iPod?" (quotes Apple's Radio Remote product copy). https://everymac.com/systems/apple/ipod/ipod-faq/how-to-listen-to-radio-on-ipod-radio-remote.html
53. Apple Community, "Ipod classic + Radio remote - no RDS?". https://discussions.apple.com/thread/1210261
