#!/usr/bin/env python3
"""Make HiBy's Si4705 driver hand userspace a whole RDS group, and say whether it hears stereo.

usage: patch_si4705_rds.py <stock radio-si4705-common.ko> <output .ko>

si4705_fops_read() sends FM_RDS_STATUS (0x24), gets all four RDS blocks back from the chip,
packs them as  A(u16, host order)  B(u16, host order)  C D(4 bytes, chip order)  and then
copies only FOUR bytes to the reader. A and B arrive; C and D, which carry every character
of the station name (0A/0B, block D) and of RadioText (2A, blocks C and D), are dropped. So
no reader, ours or anyone's, can ever show PS or RT from this tuner on the stock driver.

The copy is a single static _copy_to_user() helper whose only caller is fops_read, with the
size baked in as an immediate twice: once in the access_ok() range check and once as the
length passed to __arch_copy_to_user. Both go from 4 to 8. Three bytes change; nothing
moves, so no relocation, symbol or section is touched.

Note what the driver does NOT do, which the reader has to cope with: read() returns 0 even
when it copied a group (it returns copy_to_user's "bytes not copied"), and RDS reception is
only switched on (FM_RDS_CONFIG 0x1502 = 0xFF01) from fops_poll() when a caller polls for
POLLIN while the chip is not in RDS sync. Stock FM2 never polls the node, which is the other
half of why stock never showed RDS.

STEREO. si4705_vidioc_g_tuner() reads FM_RSQ_STATUS (0x23) but never looks at RESP3, which is
where the chip reports PILOT (bit 7, a stereo pilot is present) and STBLEND (bits 6:0, how far
it has blended toward stereo, 0-100 %). rxsubchans is never filled in, so no V4L2 caller can
tell stereo from mono. The driver does pack RESP2's VALID bit into reserved[1] bit 8, and the
vendor JNI hands userspace (reserved[1] >> 8) & 0xF as element 6 of getV4L2RadioFmSignal().
Three instructions change what goes there:
    ldrb w11, [sp, #0xa]  ->  [sp, #0xb]        RESP3 instead of RESP2
    and  w11, w11, #1     ->  lsr w11, w11, #4  PILOT to bit 3, STBLEND's top three bits to 0-2
    bfi  w9, w11, #8, #1  ->  #8, #4            insert all four
so element 6 becomes  pilot << 3 | STBLEND / 16.  VALID is given up for it: nothing reads it
but our own app, and lock is the same test the driver itself uses for audmode (RSSI > 1 and
SNR != 0).

The input is checked against the stock module's hash, so this can only ever patch the exact
binary it was worked out from.
"""
import hashlib
import os
import struct
import sys

STOCK_MD5 = "e77cb0895d3c5bf8167d965bd66c368b"
PATCHED_MD5 = "aac849a29be71746a9e584b43b97fbcb"

# (.text offset, stock instruction, patched instruction)
PATCHES = [
    (0x0624, 0x39402BEB, 0x39402FEB),  # ldrb w11, [sp, #0xa] -> [sp, #0xb]  (RSQ RESP3)
    (0x0648, 0x1200016B, 0x53047D6B),  # and w11, w11, #1 -> lsr w11, w11, #4
    (0x0664, 0x33180169, 0x33180D69),  # bfi w9, w11, #8, #1 -> #8, #4
    (0x18E0, 0xB100116B, 0xB100216B),  # adds x11, x11, #4  ->  #8   (access_ok range)
    (0x195C, 0x52800082, 0x52800102),  # mov  w2, #4        ->  #8   (copy length)
]


# RANGE UNLOCK (opt-in, MIKU_FM_UNLOCK=1). si4705_vidioc_s_frequency() clamps every tune to the
# current entry of a four-band table in .rodata (v4l2_frequency_band: rangelow/rangehigh at
# +0x10/+0x14, 62.5 Hz units): below the band it tunes to rangelow, above it to rangehigh. Measured
# on 0.1.17: 110, 118, 136, 144 and 162.55 MHz all read back as 108.000, 50 and 63 as 87.000.
# Widening every entry to 50-250 MHz takes the driver out of the decision and lets the chip's own
# FM_TUNE_FREQ range check answer (its argument is f*625/100000 in 10 kHz units, which fits u16
# up to 655 MHz and the 32-bit multiply up to 429 MHz). Silicon Labs specifies 64-108 MHz; this
# is how to find out what this part really does.
BAND_TABLE = 0x39C                      # .rodata offset of band 0
BANDS_STOCK = [(1392000, 1728000), (1400000, 1728000), (1216000, 1728000), (1216000, 1440000)]
BAND_OPEN = (50 * 16000, 250 * 16000)
UNLOCKED_MD5 = "10da69ea347349be83828a2a7845a0fc"

# STEREO BLEND (opt-in, MIKU_FM_STEREO=1). The driver never sets the chip's blend thresholds, so
# the Si4705 defaults apply: full mono below RSSI 30 dBuV or SNR 14 dB. Indoors on a headphone
# cable every station measured RSSI 11-29 / SNR 8-10 (2026-10-10), so the radio was always mono.
# si4705_start() writes two properties that do nothing on this driver: FM_RSQ_SNR_LO_THRESHOLD
# (0x1202) and FM_RSQ_RSSI_LO_THRESHOLD (0x1204) only matter with RSQ interrupts, and the driver
# never enables those (FM_RSQ_INT_SOURCE stays 0). Those two writes are re-pointed at the blend
# mono thresholds, which widens the blend region downward: partial stereo at weak signal, with
# the extra hiss that costs. Older chip firmware without the 0x18xx blend properties rejects the
# write and nothing changes; the pilot/blend readout (signal[6]) shows which happened.
FULL_MD5 = "c1fdf0979d1061ef68a72d6858d4d021"   # RDS + range unlock + stereo blend
STEREO_PATCHES = [
    (0x1D74, 0x52824041, 0x52830021),  # mov w1, #0x1202 -> #0x1801  FM_BLEND_RSSI_MONO_THRESHOLD
    (0x1D78, 0x52800022, 0x52800242),  # mov w2, #1      -> #18 dBuV (default 30)
    (0x1DA8, 0x52824081, 0x528300A1),  # mov w1, #0x1204 -> #0x1805  FM_BLEND_SNR_MONO_THRESHOLD
    (0x1DAC, 0x52800042, 0x528000C2),  # mov w2, #2      -> #6 dB    (default 14)
]


def section_offset(d: bytes, want: bytes) -> int:
    shoff = struct.unpack_from("<Q", d, 0x28)[0]
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", d, 0x3A)
    strtab = struct.unpack_from("<IIQQQQIIQQ", d, shoff + shstrndx * shentsize)[4]
    for i in range(shnum):
        sh = struct.unpack_from("<IIQQQQIIQQ", d, shoff + i * shentsize)
        name = d[strtab + sh[0]:d.index(0, strtab + sh[0])]
        if name == want:
            return sh[4]
    raise SystemExit(f"no {want.decode()} section")


def unlock_range(d: bytearray) -> None:
    base = section_offset(d, b".rodata") + BAND_TABLE
    for i, (lo, hi) in enumerate(BANDS_STOCK):
        at = base + i * 64 + 0x10
        cur = struct.unpack_from("<II", d, at)
        if cur != (lo, hi):
            raise SystemExit(f"refusing: band {i} range is {cur}, expected {(lo, hi)}")
        struct.pack_into("<II", d, at, *BAND_OPEN)


def text_offset(d: bytes) -> int:
    shoff = struct.unpack_from("<Q", d, 0x28)[0]
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", d, 0x3A)
    strtab = struct.unpack_from("<IIQQQQIIQQ", d, shoff + shstrndx * shentsize)[4]
    for i in range(shnum):
        sh = struct.unpack_from("<IIQQQQIIQQ", d, shoff + i * shentsize)
        name = d[strtab + sh[0]:d.index(0, strtab + sh[0])]
        if name == b".text":
            return sh[4]
    raise SystemExit("no .text section")


def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    d = bytearray(open(src, "rb").read())
    md5 = hashlib.md5(d).hexdigest()
    if md5 == PATCHED_MD5 and os.environ.get("MIKU_FM_UNLOCK") != "1" and os.environ.get("MIKU_FM_STEREO") != "1":
        open(dst, "wb").write(d)
        print("already patched")
        return
    if md5 != STOCK_MD5:
        raise SystemExit(f"refusing: {src} md5 {md5} is not the stock module {STOCK_MD5}")
    off = text_offset(d)
    for at, old, new in PATCHES:
        cur = struct.unpack_from("<I", d, off + at)[0]
        if cur != old:
            raise SystemExit(f"refusing: .text+{at:#x} is {cur:#010x}, expected {old:#010x}")
        struct.pack_into("<I", d, off + at, new)
    if hashlib.md5(d).hexdigest() != PATCHED_MD5:
        raise SystemExit("patched module does not hash to the expected result")
    unlock = os.environ.get("MIKU_FM_UNLOCK") == "1"
    stereo = os.environ.get("MIKU_FM_STEREO") == "1"
    if unlock:
        unlock_range(d)
        if not stereo and hashlib.md5(d).hexdigest() != UNLOCKED_MD5:
            raise SystemExit("unlocked module does not hash to the expected result")
        print("range unlock: every band widened to 50-250 MHz; the chip decides what it accepts")
    if stereo:
        for at, old, new in STEREO_PATCHES:
            cur = struct.unpack_from("<I", d, off + at)[0]
            if cur != old:
                raise SystemExit(f"refusing: .text+{at:#x} is {cur:#010x}, expected {old:#010x}")
            struct.pack_into("<I", d, off + at, new)
        print("stereo blend: mono thresholds RSSI 18 dBuV, SNR 6 dB (chip defaults 30 / 14)")
    if unlock and stereo and hashlib.md5(d).hexdigest() != FULL_MD5:
        raise SystemExit("fully patched module does not hash to the expected result")
    open(dst, "wb").write(d)
    print("patched: RDS read copies 8 bytes (A B C D); signal[6] = pilot<<3 | blend/16")


if __name__ == "__main__":
    main()
