#!/usr/bin/env python3
"""
Give the M500 the CS43198's real NOS (non-oversampling) filter.

HiBy's cs43198_dlkm.ko, cs43198_codec_digital_filter_set(): the filter name is compared with
the four roll-off filters (fast/slow x low-latency/phase-compensated -> 0x00/0x40/0x80/0xC0);
any other name, which is what "nos" is, gets 0x20. That is the right value: in the CS43198's
PCM Filter Option register (0x090000) bit 7 is FILTER_SLOW_FASTB, bit 6 PHCOMP_LOWLATB and
bit 5 NOS (Cirrus DS1156, PCM Filter Option register; with NOS set the other two are ignored).
But every write of that register passes mask 0xC0, so bit 5 never reaches the chip and "NOS" plays
as fast roll-off, low latency. There are four writes: two in filter_set (the main DAC, and the
second DAC in 4.4 mm balanced mode) and the same two in cs43198_init_reg_val, which re-applies the
saved filter whenever the DAC powers up.

Widening the mask to 0xE0 at all four sites lets the NOS bit through. The roll-off filters still
work: their values have bit 5 clear, so choosing one also turns NOS back off. Bits 4..0 (high
pass, de-emphasis, wideband flatness) stay outside the mask, as before.

Usage: patch_cs43198_nos.py <stock cs43198_dlkm.ko> <out>
"""
import hashlib
import struct
import sys

STOCK_MD5 = "6ef92ff320d4b64f101eee7262260a2d"
PATCHED_MD5 = "d325d31d42768304fcf506afea2113e3"

# (.text offset, stock instruction, patched instruction)
PATCHES = [
    # cs43198_codec_digital_filter_set: the user picks a filter.
    (0x1118, 0x52801804, 0x52801C04),  # mov w4, #0xc0 -> #0xe0  (mask, main DAC)
    (0x1144, 0x52801804, 0x52801C04),  # mov w4, #0xc0 -> #0xe0  (mask, second DAC, balanced)
    # cs43198_init_reg_val: the saved filter is re-applied every time the DAC powers up. Without
    # these two, NOS would hold only until the next DAC power cycle (idle, track start).
    (0x0B6C, 0x52801804, 0x52801C04),  # mov w4, #0xc0 -> #0xe0  (mask, main DAC)
    (0x0B9C, 0x52801804, 0x52801C04),  # mov w4, #0xc0 -> #0xe0  (mask, second DAC, balanced)
]


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
    if PATCHED_MD5 and md5 == PATCHED_MD5:
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
    if PATCHED_MD5 and hashlib.md5(d).hexdigest() != PATCHED_MD5:
        raise SystemExit("patched module does not hash to the expected result")
    open(dst, "wb").write(d)
    print("patched: CS43198 filter mask 0xC0 -> 0xE0 (NOS bit reaches the DAC)")


if __name__ == "__main__":
    main()
