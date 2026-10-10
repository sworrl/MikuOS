#!/usr/bin/env python3
"""
Give MikuOS notification sounds back.

HiBy's 1.20 services.jar has NotificationManagerService.playSound(NotificationRecord, Uri) cut
down to: read the flags, return false if audio focus is exclusive, read the stream volume, return
false. Nothing ever reaches SystemUI's RingtonePlayer, so no notification makes a sound. HiBy's
1.30 services.jar puts the AOSP body back: if focus is not exclusive and the stream volume is not
0, clear the calling identity and call IRingtonePlayer.playAsync(uri, sbn.getUser(), looping,
attributes). That is the only change on the notification path between 1.20 and 1.30 (SystemUI's
RingtonePlayer is identical in both).

We can't take the 1.30 services.jar itself: it needs the 1.30 framework.jar and it adds the
unprotected IAudioService.setProperties()/getProperties() pair. So this script takes the 1.20
jar, disassembles the one dex that holds NotificationManagerService (classes2.dex), swaps in the
1.30 playSound method (the same smali HiBy 1.30 ships, same .line numbers), reassembles that dex
and repacks the jar. Every other jar entry is copied byte for byte. Stored entries stay stored
and 4-byte aligned, like the original.

The rest of the dex round-trips unchanged except that smali drops explicit default values on
two classes' static fields (DexOptHelper, ShutdownThread: "= false" / "= null"), which is what
they hold anyway.

Needs baksmali and smali 2.5.2 on PATH (Debian/Ubuntu "smali" package) and java. smali runs
with -j 1: with more threads its output changes from run to run, and then the hash check below
would fail.

Usage: patch_services_notif_sound.py <stock services.jar> <out services.jar>
"""
import hashlib
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

STOCK_MD5 = "e85a833ace82d47d1afa7f55458df72a"        # 1.20 /system/framework/services.jar
STOCK_DEX_MD5 = "6e0b408046ebe2fba3eebddd1ae5c6a3"    # its classes2.dex
PATCHED_DEX_MD5 = "c713938d8cc71dfb7c4bc5250a4268a5"
PATCHED_MD5 = "4e600da27bf860d42a272201b4d373a4"
DEX = "classes2.dex"
SMALI = "com/android/server/notification/NotificationManagerService.smali"
API = "34"
TOOL_VERSION = "2.5.2"

STOCK_METHOD = """\
.method public final playSound(Lcom/android/server/notification/NotificationRecord;Landroid/net/Uri;)Z
    .registers 3

    .line 8590
    invoke-virtual {p1}, Lcom/android/server/notification/NotificationRecord;->getNotification()Landroid/app/Notification;

    move-result-object p2

    iget p2, p2, Landroid/app/Notification;->flags:I

    .line 8594
    iget-object p2, p0, Lcom/android/server/notification/NotificationManagerService;->mAudioManager:Landroid/media/AudioManager;

    invoke-virtual {p2}, Landroid/media/AudioManager;->isAudioFocusExclusive()Z

    move-result p2

    if-nez p2, :cond_1b

    iget-object p0, p0, Lcom/android/server/notification/NotificationManagerService;->mAudioManager:Landroid/media/AudioManager;

    .line 8596
    invoke-virtual {p1}, Lcom/android/server/notification/NotificationRecord;->getAudioAttributes()Landroid/media/AudioAttributes;

    move-result-object p1

    invoke-static {p1}, Landroid/media/AudioAttributes;->toLegacyStreamType(Landroid/media/AudioAttributes;)I

    move-result p1

    .line 8595
    invoke-virtual {p0, p1}, Landroid/media/AudioManager;->getStreamVolume(I)I

    :cond_1b
    const/4 p0, 0x0

    return p0
.end method
"""

AOSP_METHOD = """\
.method public final playSound(Lcom/android/server/notification/NotificationRecord;Landroid/net/Uri;)Z
    .registers 11

    .line 8590
    invoke-virtual {p1}, Lcom/android/server/notification/NotificationRecord;->getNotification()Landroid/app/Notification;

    move-result-object v0

    iget v0, v0, Landroid/app/Notification;->flags:I

    and-int/lit8 v0, v0, 0x4

    const/4 v1, 0x1

    const/4 v2, 0x0

    if-eqz v0, :cond_e

    move v0, v1

    goto :goto_f

    :cond_e
    move v0, v2

    .line 8594
    :goto_f
    iget-object v3, p0, Lcom/android/server/notification/NotificationManagerService;->mAudioManager:Landroid/media/AudioManager;

    invoke-virtual {v3}, Landroid/media/AudioManager;->isAudioFocusExclusive()Z

    move-result v3

    if-nez v3, :cond_70

    iget-object v3, p0, Lcom/android/server/notification/NotificationManagerService;->mAudioManager:Landroid/media/AudioManager;

    .line 8596
    invoke-virtual {p1}, Lcom/android/server/notification/NotificationRecord;->getAudioAttributes()Landroid/media/AudioAttributes;

    move-result-object v4

    invoke-static {v4}, Landroid/media/AudioAttributes;->toLegacyStreamType(Landroid/media/AudioAttributes;)I

    move-result v4

    .line 8595
    invoke-virtual {v3, v4}, Landroid/media/AudioManager;->getStreamVolume(I)I

    move-result v3

    if-eqz v3, :cond_70

    .line 8598
    invoke-static {}, Landroid/os/Binder;->clearCallingIdentity()J

    move-result-wide v3

    .line 8600
    :try_start_2b
    iget-object p0, p0, Lcom/android/server/notification/NotificationManagerService;->mAudioManager:Landroid/media/AudioManager;

    invoke-virtual {p0}, Landroid/media/AudioManager;->getRingtonePlayer()Landroid/media/IRingtonePlayer;

    move-result-object p0

    if-eqz p0, :cond_6d

    const-string v5, "NotificationService"

    .line 8602
    new-instance v6, Ljava/lang/StringBuilder;

    invoke-direct {v6}, Ljava/lang/StringBuilder;-><init>()V

    const-string v7, "Playing sound "

    invoke-virtual {v6, v7}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v6, p2}, Ljava/lang/StringBuilder;->append(Ljava/lang/Object;)Ljava/lang/StringBuilder;

    const-string v7, " with attributes "

    invoke-virtual {v6, v7}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    .line 8603
    invoke-virtual {p1}, Lcom/android/server/notification/NotificationRecord;->getAudioAttributes()Landroid/media/AudioAttributes;

    move-result-object v7

    invoke-virtual {v6, v7}, Ljava/lang/StringBuilder;->append(Ljava/lang/Object;)Ljava/lang/StringBuilder;

    invoke-virtual {v6}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v6

    .line 8602
    invoke-static {v5, v6}, Landroid/util/Slog;->v(Ljava/lang/String;Ljava/lang/String;)I

    .line 8604
    invoke-virtual {p1}, Lcom/android/server/notification/NotificationRecord;->getSbn()Landroid/service/notification/StatusBarNotification;

    move-result-object v5

    invoke-virtual {v5}, Landroid/service/notification/StatusBarNotification;->getUser()Landroid/os/UserHandle;

    move-result-object v5

    .line 8605
    invoke-virtual {p1}, Lcom/android/server/notification/NotificationRecord;->getAudioAttributes()Landroid/media/AudioAttributes;

    move-result-object p1

    .line 8604
    invoke-interface {p0, p2, v5, v0, p1}, Landroid/media/IRingtonePlayer;->playAsync(Landroid/net/Uri;Landroid/os/UserHandle;ZLandroid/media/AudioAttributes;)V
    :try_end_64
    .catch Landroid/os/RemoteException; {:try_start_2b .. :try_end_64} :catch_6d
    .catchall {:try_start_2b .. :try_end_64} :catchall_68

    .line 8610
    invoke-static {v3, v4}, Landroid/os/Binder;->restoreCallingIdentity(J)V

    return v1

    :catchall_68
    move-exception p0

    invoke-static {v3, v4}, Landroid/os/Binder;->restoreCallingIdentity(J)V

    .line 8611
    throw p0

    .line 8610
    :catch_6d
    :cond_6d
    invoke-static {v3, v4}, Landroid/os/Binder;->restoreCallingIdentity(J)V

    :cond_70
    return v2
.end method
"""


def md5(b: bytes) -> str:
    return hashlib.md5(b).hexdigest()


def run(*cmd: str) -> str:
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout


def zip_entries(d: bytes):
    """Central directory records of a zip with no zip64 and no comment tricks."""
    eocd = d.rindex(b"PK\x05\x06")
    n, cd_size, cd_off = struct.unpack_from("<HII", d, eocd + 10)
    out, p = [], cd_off
    for _ in range(n):
        if d[p:p + 4] != b"PK\x01\x02":
            raise SystemExit("refusing: bad central directory")
        nl, el, cl = struct.unpack_from("<HHH", d, p + 28)
        lho = struct.unpack_from("<I", d, p + 42)[0]
        out.append((d[p:p + 46 + nl + el + cl], d[p + 46:p + 46 + nl].decode(), lho))
        p += 46 + nl + el + cl
    return out, cd_off, d[eocd:]


def repack(stock: bytes, name: str, new_data: bytes) -> bytes:
    entries, cd_off, eocd = zip_entries(stock)
    starts = sorted([lho for _, _, lho in entries] + [cd_off])
    body, central = bytearray(), bytearray()
    for cd, fname, lho in entries:
        end = starts[starts.index(lho) + 1]
        rec = stock[lho:end]
        method = struct.unpack_from("<H", rec, 8)[0]
        nl, el = struct.unpack_from("<HH", rec, 26)
        cd = bytearray(cd)
        if method == 0:
            # Stored: rebuild the local header so the data starts 4-byte aligned (zero padding
            # in the extra field, as soong_zip does). Stored entries here carry no other extra.
            data = new_data if fname == name else rec[30 + nl + el:]
            if fname != name and len(data) != struct.unpack_from("<I", rec, 22)[0]:
                raise SystemExit(f"refusing: unexpected trailer on stored entry {fname}")
            hdr = bytearray(rec[:30 + nl])
            pad = (-(len(body) + 30 + nl)) % 4
            if fname == name:
                crc = zlib.crc32(data) & 0xFFFFFFFF
                struct.pack_into("<III", hdr, 14, crc, len(data), len(data))
                struct.pack_into("<III", cd, 16, crc, len(data), len(data))
            struct.pack_into("<H", hdr, 28, pad)
            rec = bytes(hdr) + b"\0" * pad + data
        elif fname == name:
            raise SystemExit(f"refusing: {name} is not stored")
        struct.pack_into("<I", cd, 42, len(body))
        body += rec
        central += cd
    tail = bytearray(eocd)
    struct.pack_into("<II", tail, 12, len(central), len(body))
    return bytes(body + central + tail)


def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    stock = open(src, "rb").read()
    if md5(stock) == PATCHED_MD5:
        open(dst, "wb").write(stock)
        print("already patched")
        return
    if md5(stock) != STOCK_MD5:
        raise SystemExit(f"refusing: {src} md5 {md5(stock)} is not the stock 1.20 services.jar {STOCK_MD5}")
    for tool in ("baksmali", "smali"):
        if TOOL_VERSION not in run(tool, "--version"):
            raise SystemExit(f"refusing: {tool} is not {TOOL_VERSION}; the result hash depends on it")
    entries, _, _ = zip_entries(stock)
    lho = next(l for _, f, l in entries if f == DEX)
    nl, el = struct.unpack_from("<HH", stock, lho + 26)
    size = struct.unpack_from("<I", stock, lho + 22)[0]
    dex = stock[lho + 30 + nl + el:lho + 30 + nl + el + size]
    if md5(dex) != STOCK_DEX_MD5:
        raise SystemExit(f"refusing: {DEX} md5 {md5(dex)} is not {STOCK_DEX_MD5}")

    work = tempfile.mkdtemp(prefix="notif_sound_")
    try:
        open(os.path.join(work, DEX), "wb").write(dex)
        smali_dir = os.path.join(work, "smali")
        run("baksmali", "d", "-a", API, "-o", smali_dir, os.path.join(work, DEX))
        path = os.path.join(smali_dir, SMALI)
        text = open(path).read()
        if text.count(STOCK_METHOD) != 1:
            raise SystemExit("refusing: playSound is not the stock 1.20 body")
        open(path, "w").write(text.replace(STOCK_METHOD, AOSP_METHOD))
        out_dex = os.path.join(work, "out.dex")
        run("smali", "a", "-a", API, "-j", "1", "-o", out_dex, smali_dir)
        new_dex = open(out_dex, "rb").read()
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if PATCHED_DEX_MD5 and md5(new_dex) != PATCHED_DEX_MD5:
        raise SystemExit(f"patched {DEX} md5 {md5(new_dex)} is not the expected {PATCHED_DEX_MD5}")
    out = repack(stock, DEX, new_dex)
    if PATCHED_MD5 and md5(out) != PATCHED_MD5:
        raise SystemExit(f"patched jar md5 {md5(out)} is not the expected {PATCHED_MD5}")
    open(dst, "wb").write(out)
    print("patched: NotificationManagerService.playSound plays notification sounds again (AOSP body from HiBy 1.30)")


if __name__ == "__main__":
    main()
