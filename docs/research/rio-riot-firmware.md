# Rio Riot firmware (granite 1.25): format, encryption, what could be extracted

Input: `granite-1.25.fw`, 573,440 bytes, PE resource FIRMWARE/8269 (language 2057) of
`RioFW-granite-v1.25.exe`, which sits inside `RioRiot_125_firmware.exe` (a 7z SFX).
sha256 b0898372e8fbe55fe7a758fafdb281e5f5c7ebe0bc2b9d0dd51982702750fd56.

Short version: the image is encrypted with a keyed 32-bit block cipher used in ECB mode. The
key and the algorithm are on the player, not in the updater. Code, strings and fonts could not
be decrypted. Bitmaps can still be read, because the same 4-byte plaintext always turns into
the same 4-byte ciphertext. Solving those words from the shape of the pictures recovered the
boot logo and the USB icon pixel-exact, and the battery gauge set mostly. Everything else is
partial.

## 1. The updater does not transform the image

Static disassembly of the updater (radare2, nothing run):

- `fcn.00401aa0` calls FindResourceA(…, 8269, "FIRMWARE"), LoadResource, LockResource and
  SizeofResource. It wraps the pointer in a memory-stream object (vtable 0x43b798). The read
  method (0x4057c0) is a plain `rep movsd` memcpy and the seek methods only move a position.
- `RioChannelBase::SendFirmware` (0x40b530) reads the stream in 0x2000-byte blocks, zero-pads
  the last block, and passes each block unchanged to `RioProtocol::RioCommWriteFirmwareBlock`
  (0x40d330), which writes it to the USB bulk pipe (0x410950). There is no XOR, table lookup,
  CRC or decompression on the data path.
- The updater is the generic empeg/SONICblue "stingray" riocom stack
  (`S:\stingray_v1_60\empeg\lib\riocom\`). The protocol strings are CRIODATA, SRIODONE,
  "Got a FIRMWARE_START response" and "Next stage is %d". rioutil (hjelmn/rioutil) also sends
  firmware files unchanged.

So the player decrypts the image itself, and the key is in its boot code or flash.

## 2. File layout

| Offset | Content |
|---|---|
| 0x000 | "RIOROCK\0", u16 0x0096, u16 0x0028, u32 0x00000080 |
| 0x010-0x08f | 128 random-looking bytes (0x80; probably an RSA-1024 signature or a wrapped key) |
| 0x090 | second "RIOROCK\0", zero padding, u16 0x0022 at 0xbe |
| 0x0c0-0x0e7 | 40 random-looking bytes (0x28; the size of a DSA-1024/SHA-1 signature, r‖s) |
| 0x0e8 | plaintext "Created by Rioport GSF utility v2.07 on 12/20/02 at 14:45:06" |
| 0x128-0x3fff | about 16 KB in which every word is unique and the bytes are uniform (chi² ≈ 256). This is a different key or mode, or compressed data, perhaps a loader stage. |
| 0x4000-0x50fff | code-like ciphertext: frequent repeated words (see below) |
| 0x51000-0x5338f | tables: repeating 16-byte records with a zero field |
| 0x53394-0x58f7f | UI bitmaps (decoded in part, see section 4) |
| 0x58f80-0x5aa00 | 32-byte record tables |
| 0x5c000-0x75fff | data with a 64-byte period (codec tables or DSP code?) |
| 0x78000-0x84fff | almost uniform (compressed data?) |
| 0x86000-0x87fff | zero padding (word 8a979871 x1024 at 0x87000) |
| 0x88000-0x8afff | 12 KB of all-unique words, like the first 16 KB |

## 3. The cipher

- It works on 32-bit blocks in ECB mode and does not depend on position. The same aligned
  word repeats all over the file. 8a979871 occurs 4423 times between 0x400c and 0x8bc2c (it
  is almost certainly 0x00000000). Runs such as `ff50ed1f` x N and `080c1324` x N fill the
  bitmaps. The 64-bit block hypothesis fails because a repeated word sits next to different
  neighbours.
- It is not XOR, not a byte substitution, and not affine. A byte-wise XOR or substitution
  would turn zero into four equal bytes and keep the byte lanes independent. Instead, the
  bitmap area uses 19 distinct words, and each lane shows 17-19 different byte values. No
  quadruples of frequent words satisfy E(a)^E(b)^E(c) = E(a^b^c) or the additive version, so
  it is not GF(2)-affine or mod-2^32 affine.
- It diffuses well. Across 28,582 distinct code words, collisions on any 2 of the 4 bytes
  match a random permutation (6167-6414 against 6232 expected).
- The key and the round function are not in the files we have. No public decryption exists
  (searched empegbbs, rioutil, general web). On empegbbs in 2002, SONICblue's empeg team said
  the Riot firmware came from a different group. To decrypt code, strings or fonts we need
  plaintext from the device, such as a RAM or flash dump over JTAG, or the boot ROM.

`tools/analyze_cipher.py` reproduces all of these numbers.

## 4. Recovering bitmaps through the codebook (an "ECB penguin" attack)

Format, read from the boot logo:
- Bitmaps are stored column by column with one byte per pixel and no inline header. Each
  column is `h` bytes and images are packed back to back, so columns are often not
  word-aligned. (A table at 0x53000-0x53393 probably holds offsets and sizes, but it is
  encrypted.)
- Pixel levels (names only, the byte values are unknown):
  A = background, word ff50ed1f = AAAA.
  B = ink, word 080c1324 = BBBB.
  Z = word 8a979871 = ZZZZ, probably 0x00, used as the clear area of icons.
  A fourth level W shows up rarely.
- Codebook recovery. Each cipher word is a 4-pixel vertical run. Edge words were assigned by
  letting horizontally adjacent pixels vote, then confirmed by trying every assignment of the
  six transition patterns 0001, 0011, 0111, 1000, 1100, 1110 (720 cases). The vote result
  scored best. The rarer words came from an ICM solve with a Potts smoothness prior, under the
  rule that two cipher words cannot share a plaintext pattern. Because a column is 55 bytes and
  55 mod 4 = 3, every horizontal line shows up in all four word alignments, which pins the
  patterns down.
- `bitmaps/codebook_levels.json` maps cipher word to its 4 levels (0 = A, 1 = B, 2 = Z,
  3 = W). The 14 binary A/B patterns, A, B and Z are certain because they reproduce the logo
  exactly. The patterns that use Z or W are guesses.

Results (`art/rio-riot/extracted/bitmaps/`, metadata in `bitmaps.json`):

| File | Offset | Size | Confidence |
|---|---|---|---|
| boot_logo_rio_riot.png | 0x5499c | 240x55 | high. Pixel-exact "Rio riot™" boot logo: heavy "Rio" with a macron on the o, outlined italic "riot", ™. The first word (4 px, top-left) is an image-boundary word and is drawn as background. |
| usb_connected.png | 0x58c2a | 43x20 | high. USB trident icon; the vertical phase may be off by ±1 row. |
| battery_gauge_strip.png | 0x57d2c | 279x9 | medium. A run of 9 px battery gauge images: "E [cell] F", a "LOW" cell and fill levels, possibly with a "CHARGING" label first. Split points are not verified, and the later images have rows that do not line up. |
| preview_fm_tune_icon.png | 0x545cc | 44x21 | low. Reads as small "TUNE" over a large "FM"; geometry not verified. |
| preview_play_glyph.png | 0x534a8 | 28x23 | low. Right-pointing triangle on Z; the true height is probably 24-26, so it wraps. |
| ecb_overview_image_area.png | 0x53394-0x58f80 | sheet | Reference only. The whole bitmap area drawn at the column heights the segmenter chose (`segment.py`, a Viterbi fit over column height). Black, white and orange are solved levels; pink and purple mark unsolved words. More icons are visible at heights 8, 12, 16, 24 and 40, e.g. small 12 px transport glyphs and a 16 px dark square with a white symbol. |

In the PNGs, A is opaque white, B black, Z transparent and W gray. Magenta marks pixels whose
word is unsolved.

To reproduce (Python 3 + Pillow, run with -I):
1. `tools/colpen.py fw 0x54028 0x58c00 55 1 out.png` shows the logo as an ECB penguin.
2. `tools/vote.py` and `tools/perm6.py` recover the edge words. `tools/bij.py` adds the
   thin-stroke words.
3. `tools/gsolve.py fw codebook.json out.json 4 start:end:h ...` runs the global
   multi-segment solve.
4. `tools/export.py fw codebook.json specs.json outdir` writes the PNGs and the JSON
   (bitmaps.json lists each start, h and width).

## 5. What could not be extracted, and why

- Strings and menu text: these sit in the code region, encrypted word by word, and the
  codebook for arbitrary 4-character groups cannot be solved without known plaintext. Use the
  user guide wording (see `docs/rio-riot-research.md`); it matches the firmware closely.
- Fonts: no 1-byte-per-pixel glyph strips were found in the bitmap area. Text such as "LOW",
  "E", "F" and "TUNE FM" is pre-rendered into the icons. The runtime font is probably 1bpp
  packed (32 pixels per word), so it cannot be read from the codebook. Recreate the font from
  the manual drawings and video frames: a Helvetica/Arial-like proportional face with about
  9, 12 and 16 px sizes.
- Screen layouts are code-driven and encrypted. The manual drawings stay the reference.

## 6. Next steps if exact fonts or strings are wanted

- A dump from real hardware. The decrypted firmware is in the player's RAM or flash after it
  boots; JTAG on the SoC or reading the flash chip gives plaintext. Plaintext/ciphertext pairs
  for the whole image would then rebuild a full codebook, or reveal the cipher.
- Older Riot images (1.0-1.2), if one is found, encrypted with the same key would not help by
  themselves. A firmware build with the same key that is known to be plaintext somewhere
  would.

## Repository rules

The encrypted `.fw` image and the updater/SFX `.exe` files are SONICblue/Rioport binaries.
Keep them out of git; `art/rio-riot/extracted/.gitignore` ignores `*.fw *.exe *.bin *.img 8269`.
Only the derived UI assets (PNGs, JSON) and the analysis scripts live in the repo. The user
decided the Rio name and logo may be used in the homage.
