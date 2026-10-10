# Voice and sounds

Spoken announcements for MikuOS status events ("IEMs unplugged", "Battery low. Ten percent
left.") and voice lines and sound effects for the MikuOS apps (camera shutter, "Say
cheese!", alarm, game callouts), in three house voices. Everything is rendered offline on a
dev machine and shipped as small Ogg files. Nothing here runs on the device.

```
tools/voice/fetch_models.sh   set up the venv and download the model (once)
tools/voice/say.py            render one line: free text or an event id
tools/voice/sfx.py            synthesize one sound effect by recipe name
tools/voice/events.json       status event catalog: id -> phrases
tools/voice/app_sounds.json   app catalog: app -> voice lines and effects
tools/voice/build_all.py      render every status event in every voice
tools/voice/build_apps.py     render every app line and effect
mikuos/data/voice/            rendered voice clips
mikuos/data/sfx/              rendered effects
mikuos/data/sounds_index.json one flat index of all of it, for the apps
```

## Quick start

```
tools/voice/fetch_models.sh --with-verify
tools/voice/say.py "IEMs unplugged." --voice mirai --out /tmp/x.ogg --play
tools/voice/say.py --event battery_low_10 --voice cyber --out /tmp/x.wav
tools/voice/say.py --list
tools/voice/build_all.py --verify
tools/voice/sfx.py shutter_miku --play
tools/voice/build_apps.py --apps camera --verify
```

The scripts re-launch themselves inside the cache venv, so plain `python3`
or `./say.py` works. Set `MIKU_VOICE_CACHE=/some/dir` to keep the venv and model somewhere
other than `tools/voice/.cache/` (git-ignored, about 1 GB).

Needs `python3` 3.10 or newer, `curl`, and an `ffmpeg` built with libopus, libvorbis and
soxr (the stock Ubuntu/Debian one is fine). No GPU, no network after the fetch.

## The voices

| Voice | Character | Kokoro style blend | Shaping |
|---|---|---|---|
| `mirai` | bright, cheerful, quick | heart 45, bella 35, jf_alpha 20 | pitch median 285 Hz, wider range, formants +8%, presence and air EQ, light chorus |
| `hoshi` | soft, calm, unhurried | aoede 40, kore 30, nicole 15, jf_alpha 15 | pitch median 250 Hz, narrower range, formants +6%, warm EQ, small room echo |
| `cyber` | synthetic, tuned | bella 45, nova 25, jf_alpha 30 | pitch median 300 Hz, pitch snapped to an A major pentatonic scale, formants +10%, chorus, flanger, exciter |

None of them is a stock Kokoro voice. Each is a weighted mix of several Kokoro style
vectors, then reshaped with Praat (PSOLA pitch and formant shift) and ffmpeg. `jf_alpha` is
Kokoro's Japanese female voice; a minority share lifts the pitch and gives the anime color,
while more than about a third of it puts enough accent on the English that Whisper starts
mishearing words.

These are original voices. They are not Hatsune Miku and are not modeled on Saki Fujita or
any other real performer or commercial voicebank. Miku's voice is Crypton's commercial
product; there is no free or "standard" Miku voice, and this tool must not be pointed at one.

The voice settings live at the top of `say.py` (`VARIANTS`). Change a blend, a pitch target
or a filter chain, run `build_all.py`, listen.

## How a clip is made

1. **Kokoro-82M v1.0** (ONNX, CPU) speaks the text with the voice's blended style. Raw
   output is cached in `.cache/tts/` keyed on text, blend and speed.
2. **Praat "Change gender"** sets the pitch median, pitch range and formant shift.
3. **Cyber only:** the pitch contour is snapped to scale notes and resynthesized
   (overlap-add). That stepped, sung pitch is what makes it read as a synth voice.
4. **ffmpeg** at 48 kHz: high-pass, EQ, chorus or echo, de-esser, light compression, then
   leading and trailing silence trimmed.
5. **Loudness:** 15 ms fade in, 40 ms fade out, 30 ms lead-in and 80 ms tail of silence,
   gain to -16 LUFS integrated (BS.1770). If that puts the 4x oversampled true peak above
   -1.5 dBTP, a lookahead limiter catches the few plosive peaks.
6. **Encode:** Ogg Opus, mono, 48 kHz, 32 kb/s VBR. Android 10 and later play Opus in Ogg
   from MediaPlayer and SoundPool. `--codec vorbis` is there if something older needs it.

`build_all.py` decodes every file it writes and measures it again; the manifest records
those numbers. With `--verify` it also runs Whisper (base.en) over every clip and lists any
clip where the words it heard differ from the words intended.

### Pronunciation

`LEXICON` in `say.py` rewrites a few words before synthesis, because espeak-ng (Kokoro's
phonemizer) gets them wrong: "Miku" comes out as "MICK-oo", and "DAC" gets spelled out
letter by letter, which Whisper heard as "DSC". The written text in the catalog and manifest
stays as people read it. Add to the list when a new word comes out wrong.

A voice can also have its own `lexicon` and `takes` in `VARIANTS`. `cyber`'s scale snapping
smears some words the other two say fine, so only `cyber` respells "IEMs" as "eye ee emms",
"mode" as "mohd", and three single lines ("Say cheese!", "Two.", "Miss."). A respelling
written as `/.../` goes to Kokoro as IPA phonemes.

Praat's PSOLA step is random, so every render is a slightly different take. `say.py` seeds
it from the voice, the line and a take number, which makes builds repeatable. When one take
comes out muddy, set a different take number for that line in the voice's `takes` and
render it again. `cyber` uses take 1 for "USB DAC mode is on." and "FM radio on.".

### Known quirk

espeak-ng copies its data path into a 160 byte buffer. When the venv lives in a deep
directory it silently falls back to a path compiled into the wheel and then exits the whole
process. `say.py` copies the data to a short path under `/tmp` when that would happen.

## Event catalog

`events.json` maps an event id (which is also the file name) to a category, a priority
(`info`, `warn`, `critical`), a hint about which Android signal raises it, and a list of
phrases. The first phrase is the default; the rest are alternates a player can rotate
through so the same event does not sound identical every time.

Phrase style: plain US English, short, said the way a friendly person would say it.
"IEMs unplugged." "Bluetooth headphones connected." Numbers spelled out. No emojis. Keep the
cute to the voice, not the words.

To add an event, add an entry and run `build_all.py --events <id>`. A full build also
deletes clips that no event owns any more.

## Output

```
mikuos/data/voice/<voice>/<event_id>.ogg        phrases[0]
mikuos/data/voice/<voice>/<event_id>_alt1.ogg   phrases[1]
mikuos/data/voice/manifest.json
```

File names are lowercase with digits and underscores, so they are also valid Android
`res/raw` names. The manifest lists, per event and per phrase, the file for each voice with
its duration, measured loudness, true peak, size and (with `--verify`) Whisper word error
rate.

First build: 34 events, 2 phrases each, 3 voices = 204 clips, 0.9 to 2.7 s (1.5 s average),
1.3 MB of audio plus a 50 KB manifest. Every clip measures between -16.9 and -15.7 LUFS and
-1.0 dBTP or lower after decoding. In the first build Whisper misheard `cyber` "IEMs" ("IAMs",
"I am"), `cyber` "mode" ("mood") and `hoshi` "Wi-Fi connected" ("Wife I connected"). With
the `cyber` respellings and seeded takes above, Whisper hears all 324 rendered voice clips as
written. The check treats "Battery's" and "Batteries", and "MikuOS" and "Miku OS", as the
same words.

## App sounds

`app_sounds.json` lists, per app, `voice` lines (rendered in all three voices, same chain
and loudness as the status events) and `sfx` (rendered once, voice independent). A voice
entry can also be `compose`d from other lines on a fixed time grid; the camera's
`countdown_timed` is count_3, count_2 and count_1 one second apart, so the app can start it
with a 3 s self-timer and fire the shutter at 3.0 s.

```
mikuos/data/voice/<voice>/app/<app>/<id>.ogg
mikuos/data/sfx/<app>/<id>.ogg
mikuos/data/voice/manifest.json   "apps" section
mikuos/data/sfx/manifest.json
```

First app build: 41 lines in 3 voices (123 clips, plus the composed countdown in each voice)
and 30 effects across camera, recorder, clock, gallery, calculator, FM radio, the BPM game
and system. Together with the status events that is 357 files and 2.3 MB of audio. Single
past-tense words ("Paused.", "Deleted.") were misheard often enough that those lines say
two words instead ("Recording paused.", "File deleted."). `cyber` "Say cheese!", "Two." and
"Miss." were misheard too ("Cheezer", "To", "Mess up") until they got respellings.

### Effects

`sfx.py` makes every effect from scratch in numpy: FM bells, additive band-limited saws and
supersaw pads, filtered noise, pitch sweeps, and a reverb made by convolving with decaying
noise. No samples and no recordings, so there is nothing to license. The style is the
palette: glassy bells high up, A major pentatonic, bright saw pads, a small sparkle on top.
The melodies in `alarm_loop` and `ringtone_loop` were written for this file over a plain
I, vi, IV, V progression and do not quote anything. A fixed random seed makes every build
byte-for-byte repeatable.

Loudness: one-shots are set by their loudest 400 ms window (BS.1770 momentary), -20 LUFS by
default so they sit under the -16 LUFS voice on IEMs; key and tuning clicks are -28, focus
pips -24. Very short clicks hit the -1 dBTP ceiling first and land a little under target,
which is fine for a click. Loops are set by integrated loudness, -18 LUFS.

Format: one-shots are Ogg Opus at 64 kb/s in music mode, so the high sparkle survives.
Loops (`clock/alarm`, `system/ringtone`) are Ogg Vorbis tagged `ANDROID_LOOP=true`, which
makes MediaPlayer and the ringtone and alarm framework loop them in the decoder with no gap.
The reverb tail past the loop point is folded back onto the start, so the seam is clean.

### Index for apps

`mikuos/data/sounds_index.json` is rebuilt by both build scripts. It has two arrays so each
maps to one Kotlin data class; paths are relative to the index file and durations are
integer milliseconds.

```
{"version":1, "voices":["mirai","hoshi","cyber"], "default_voice":"mirai",
 "voice":[{"app":"camera","id":"say_cheese","alt":0,"text":"Say cheese!",
           "category":null,"priority":null,
           "files":{"mirai":"voice/mirai/app/camera/say_cheese.ogg", ...},
           "duration_ms":{"mirai":880, ...}}, ...],
 "sfx":[{"app":"camera","id":"shutter","file":"sfx/camera/shutter.ogg",
         "duration_ms":680,"loop":false}, ...]}
```

Status events appear in `voice` with `"app":"status"` and their category and priority.
Look a sound up by `(app, id)`, pick `files[userVoice] ?: files[default_voice]`, and for
lines with alternates choose among the rows with the same `(app, id)`.

## Licenses

This firmware is published, so everything that ends up in the image has to be
redistributable. Only the rendered `.ogg` files ship; the model and tools stay on the dev
machine.

| Component | License | Role |
|---|---|---|
| Kokoro-82M v1.0 weights and voice styles ([hexgrad/Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M)) | Apache-2.0 | the speech model. Trained only on permissive or non-copyrighted audio (public domain, Apache/MIT licensed, and synthetic audio). The CC BY 4.0 SIWIS and CC BY 3.0 Koniwa sets were part of training; credit given here. |
| kokoro-onnx ([thewh1teagle/kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx)) | MIT | ONNX runner and the ONNX export of the model |
| onnxruntime | MIT | inference |
| numpy, scipy | BSD-3-Clause | effect synthesis, build time only |
| espeak-ng (via espeakng-loader) and phonemizer | GPL-3.0 | text to phonemes, build time only |
| Praat (via praat-parselmouth) | GPL-3.0 | pitch and formant shaping, build time only |
| ffmpeg | LGPL/GPL | filters and encoding, build time only |
| faster-whisper and Whisper base.en | MIT | optional check, build time only |

The GPL tools are run as programs on the dev machine. Audio they produce is output, not a
derived work of the tool, and none of them is distributed in the image. Apache-2.0 on the
model puts no restriction on audio generated with it.

**Effects:** synthesized from code in this folder, no third-party audio in them.

**Generated clips:** made by this project from Apache-2.0 weights; ship them under the
repository's own license. A credit line such as "Voices made with Kokoro-82M (Apache-2.0)"
in the about screen is good manners, not a requirement.

### Evaluated and not used

- **Piper** (MIT engine). Each voice carries its own dataset license, and most English
  female voices are a problem for a published image: `amy`, `jenny_dioco` and `hfc_female`
  are fine-tuned from `lessac` (Blizzard 2013 data, research terms), and `hfc_female`'s own
  data is CC BY-NC-SA 4.0. `kristin` (LibriVox) and `ljspeech` (LJ Speech) are public domain
  and clean, and both were intelligible, but they are lower and plainer (pitch median about
  145 Hz and 185 to 225 Hz) and took more reshaping to sound young, which is where artifacts
  come from. Kokoro starts brighter.
- **Kasane Teto on OpenUtau.** Teto is the free one, but she is an UTAU singing voicebank:
  notes plus Japanese kana lyrics, not English speech. Her terms allow personal and doujin
  use and treat selling your own songs as non-commercial, but "other commercial use" needs
  permission through Piapro, redistributing the voicebank is forbidden, and nothing in them
  covers baking rendered audio into a published firmware. OpenUtau also has no headless
  render; export is from the GUI. Skipped. If a sung chime is wanted later, `cyber`'s scale
  snapping already gets most of the way there with no licensing question.
