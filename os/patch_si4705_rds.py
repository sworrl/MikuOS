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
    if md5 == PATCHED_MD5:
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
    open(dst, "wb").write(d)
    print("patched: RDS read copies 8 bytes (A B C D); signal[6] = pilot<<3 | blend/16")


if __name__ == "__main__":
    main()
