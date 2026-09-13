#!/usr/bin/env python3
import sys

def patch_vbmeta(src_path, dst_path):
    with open(src_path, "rb") as f:
        data = bytearray(f.read())
    
    assert data[:4] == b"AVB0", "Not a valid AVB0 image"
    
    # AVB Header flags field is at offset 120 (4 bytes, big-endian uint32)
    # Bit 0: AVB_VBMETA_IMAGE_FLAGS_HASHTREE_DISABLED (1)
    # Bit 1: AVB_VBMETA_IMAGE_FLAGS_VERIFICATION_DISABLED (2)
    # Value 3 disables both dm-verity hashtrees and signature checks
    data[120:124] = b"\x00\x00\x00\x03"
    
    with open(dst_path, "wb") as f:
        f.write(data)
    print(f"Generated {dst_path} with verification & verity disabled (flags=3).")

if __name__ == "__main__":
    patch_vbmeta(
        "/home/reaver/Documents/GitHub/m500/m500-system-archive/firmware/extracted_1.00/vbmeta.img",
        "/home/reaver/Documents/GitHub/m500/mikuos/out/vbmeta_disabled.img"
    )
    patch_vbmeta(
        "/home/reaver/Documents/GitHub/m500/m500-system-archive/firmware/extracted_1.00/vbmeta_system.img",
        "/home/reaver/Documents/GitHub/m500/mikuos/out/vbmeta_system_disabled.img"
    )
