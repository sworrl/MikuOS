#!/usr/bin/env python3
"""
Swap a file in the 1.20-based MikuOS image for HiBy's own 1.30 build of it, after checking both.

MikuOS is built on stock firmware 1.20. HiBy's 1.20 to 1.30 OTA fixed a few things in files that
can be dropped into the 1.20 image unchanged. This script takes the file as it is in the image,
HiBy's 1.30 file, and refuses unless both are exactly the expected builds. For kernel modules it
also re-checks that the 1.30 module will load on the 1.20 kernel. See
mikuos/docs/hiby-firmware-history.md and m500-nos-filter.md.

Parts:

  cs43198_dlkm.ko (vendor_dlkm /lib/modules)
      The CS43198 DAC driver. 1.30 widens the filter mask from 0xC0 to 0xE0 (NOS reaches the chip,
      the same fix as patch_cs43198_nos.py) and writes the second, balanced DAC (I2C 0x33) whatever
      the output is. 1.20 only wrote it while the output target was 3 (balanced), so a filter, DRE
      or sample-rate change made on 3.5 mm never reached the 4.4 mm DAC. The gate is gone in
      filter_set, init_reg_val (filter re-apply), dai_hw_params, dre_function_enable, write_reg
      and sys_set_reg_val. codec_set_mqa_source also changed, but nothing on the M500 calls it:
      the plat module's plat_set_mqa_source is an empty function, and no other module imports it.
      Accepts the stock 1.20 module or the MikuOS NOS-patched one as the file being replaced.

  cw2015_battery.ko (vendor_dlkm /lib/modules)
      The fuel gauge. In 1.20 the "charging" state is hard-wired to 0 and three FG_CW2015 log
      lines go to the kernel log every 2 seconds. 1.30 reads it from mp2731-charger (online, and
      status charging or full), smooths the percentage (at most 0.5% per 2 s step, and it only
      rises while charging) and drops the logging.

  android.hardware.health-service.qti (vendor /bin/hw)
      The health HAL. 1.20 checks for /sys/class/power_supply/mp2731-charger once at start. If the
      charger driver has not registered yet it falls back to sw7203-charger paths, which do not
      exist on the M500, and keeps them until the HAL restarts. 1.30 waits up to 2 s
      (10 x 200 ms) for mp2731-charger/type and /online. Same NEEDED libraries and the same
      undefined symbol set as 1.20; only that function changed.

Kernel module check (1.20 kernel 5.15.153-gca6de2449164-dirty, CONFIG_MODVERSIONS=y,
CONFIG_MODULE_SIG_FORCE not set): the kernel compares vermagic after the release string when the
module has CRCs, so only " SMP preempt mod_unload modversions aarch64" must match. Every imported
symbol's CRC must match what the 1.20 kernel exports. That was checked against all 365 modules of
the 1.20 image (vendor_dlkm, vendor_boot, system_dlkm); this script re-checks it against the 1.20
module it replaces, plus the pinned CRCs below for symbols the 1.20 module did not import. Vendor
modules are unsigned in both 1.20 and 1.30, so signature handling does not change.

Usage: adopt_hiby130.py <part> <file now in the image> <HiBy 1.30 file> <out>
"""
import hashlib
import struct
import sys

PARTS = {
    "cs43198_dlkm.ko": {
        "current": {
            "6ef92ff320d4b64f101eee7262260a2d": "stock 1.20",
            "d325d31d42768304fcf506afea2113e3": "1.20 with the MikuOS NOS patch",
        },
        "new": "12ded9dcbdf308f4d43ff56aaeca59e8",
        "extra_crcs": {},
    },
    "cw2015_battery.ko": {
        "current": {"0b235b979e5520586e84a78cc531551b": "stock 1.20"},
        "new": "330dce8812406814625dc918253f0c1d",
        # Imported by 1.30 only. 0x91406f94 is the CRC the 1.20 mp2731_charger, dwc3-msm,
        # qpnp-smb5-main and 10 other 1.20 modules import it with.
        "extra_crcs": {"power_supply_get_property": 0x91406F94},
    },
    "android.hardware.health-service.qti": {
        "current": {"4ab52b6c39d26b9350a80b1840f8265a": "stock 1.20"},
        "new": "437d92aa8c85157acd0bc69d6a977f83",
        "extra_crcs": None,
    },
}

SIG = b"~Module signature appended~\n"


def sections(d: bytes) -> dict:
    if d.endswith(SIG):
        siglen = struct.unpack(">I", d[-len(SIG) - 4:-len(SIG)])[0]
        d = d[:-(len(SIG) + 12 + siglen)]
    shoff = struct.unpack_from("<Q", d, 0x28)[0]
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", d, 0x3A)
    sh = [struct.unpack_from("<IIQQQQIIQQ", d, shoff + i * shentsize) for i in range(shnum)]
    stro = sh[shstrndx][4]
    out = {}
    for s in sh:
        name = d[stro + s[0]:d.index(0, stro + s[0])].decode()
        out[name] = (d, s)
    return out


def section_bytes(secs: dict, name: str) -> bytes:
    d, s = secs[name]
    return d[s[4]:s[4] + s[5]]


def imports(secs: dict) -> dict:
    v = section_bytes(secs, "__versions")
    return {v[i + 8:i + 64].split(b"\0")[0].decode(): struct.unpack_from("<Q", v, i)[0] & 0xFFFFFFFF
            for i in range(0, len(v), 64)}


def exports(secs: dict) -> dict:
    d, st = secs[".symtab"]
    # .symtab's sh_link is the index of its string table.
    shoff = struct.unpack_from("<Q", d, 0x28)[0]
    shentsize = struct.unpack_from("<H", d, 0x3A)[0]
    link = struct.unpack_from("<IIQQQQIIQQ", d, shoff + st[6] * shentsize)
    strtab = link[4]
    out = {}
    for i in range(0, st[5], 24):
        nm, _info, _other, _shndx, val, _size = struct.unpack_from("<IBBHQQ", d, st[4] + i)
        name = d[strtab + nm:d.index(0, strtab + nm)].decode()
        if name.startswith("__crc_"):
            out[name[6:]] = val & 0xFFFFFFFF
    return out


def vermagic_tail(secs: dict) -> str:
    for f in section_bytes(secs, ".modinfo").split(b"\0"):
        if f.startswith(b"vermagic="):
            v = f[len(b"vermagic="):].decode()
            return v[v.index(" "):]
    raise SystemExit("refusing: module has no vermagic")


def check_module(old: bytes, new: bytes, extra: dict) -> None:
    so, sn = sections(old), sections(new)
    if vermagic_tail(so) != vermagic_tail(sn):
        raise SystemExit(f"refusing: vermagic differs past the release: {vermagic_tail(so)!r} vs {vermagic_tail(sn)!r}")
    io, inew = imports(so), imports(sn)
    if "module_layout" not in inew or inew["module_layout"] != io.get("module_layout"):
        raise SystemExit("refusing: module_layout CRC differs (struct module layout changed)")
    for sym, crc in inew.items():
        want = io.get(sym, extra.get(sym))
        if want is None:
            raise SystemExit(f"refusing: 1.30 imports {sym}, which the 1.20 module does not and no CRC is pinned")
        if want != crc:
            raise SystemExit(f"refusing: {sym} CRC {crc:#010x}, 1.20 kernel has {want:#010x}")
    eo, en = exports(so), exports(sn)
    if eo != en:
        raise SystemExit(f"refusing: exported symbols or their CRCs differ: {sorted(set(eo.items()) ^ set(en.items()))}")


def main() -> None:
    if len(sys.argv) != 5 or sys.argv[1] not in PARTS:
        raise SystemExit(__doc__.split("Usage:")[1].strip() + "\nparts: " + ", ".join(PARTS))
    part, cur_path, new_path, dst = sys.argv[1:]
    p = PARTS[part]
    cur = open(cur_path, "rb").read()
    new = open(new_path, "rb").read()
    cur_md5, new_md5 = hashlib.md5(cur).hexdigest(), hashlib.md5(new).hexdigest()
    if cur_md5 == p["new"]:
        open(dst, "wb").write(cur)
        print(f"{part}: already the 1.30 build")
        return
    if cur_md5 not in p["current"]:
        raise SystemExit(f"refusing: {cur_path} md5 {cur_md5} is not a known 1.20 {part}")
    if new_md5 != p["new"]:
        raise SystemExit(f"refusing: {new_path} md5 {new_md5} is not HiBy's 1.30 {part} ({p['new']})")
    if p["extra_crcs"] is not None:
        check_module(cur, new, p["extra_crcs"])
    open(dst, "wb").write(new)
    print(f"{part}: {p['current'][cur_md5]} -> HiBy 1.30 ({new_md5})")


if __name__ == "__main__":
    main()
