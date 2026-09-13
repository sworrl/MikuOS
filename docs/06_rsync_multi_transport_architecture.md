# M500 Native Rsync Architecture

## Control and Topology

The M500 runs an `rsyncd` daemon directly on the device as root (`uid=0`, `gid=0`), listening on TCP port 8730.

The host computer acts as the client and pushes files to the M500:

```
[Host Computer: rsync client] ---> TCP 8730 ---> [M500: rsyncd root daemon] ---> /storage/<SD_UUID>/
```

### Why M500 Runs the Server (Host Pushes to M500)

1. **Zero Host Setup**: The host requires only a standard `rsync` client. No SSH keys, daemon services, or network open ports are needed on the PC.
2. **Root File Permissions**: Running `rsyncd` on the M500 under Magisk root gives the daemon direct write access to the raw exFAT SD card, bypassing Android scoped storage restrictions and FUSE overhead.
3. **Transport Routing**: The host script `tools/rsync/m500-sync.sh` probes whether a USB connection exists. If present, it creates an ADB port forward (`adb forward tcp:8730 tcp:8730`) and pushes over `127.0.0.1:8730`. If absent, it routes over Wi-Fi to `<SYNC_HOST>:<SYNC_PORT>`, where the host/port come from the gitignored `tools/m500-sync.env` (copy `tools/m500-sync.env.example`) — no address is hardcoded.

### Speed Comparison

| Transport | Route | Sustained Throughput | Notes |
| :--- | :--- | :--- | :--- |
| **USB High-Speed** | `127.0.0.1:8730` via ADB tunnel | **35 to 82 MB/s** | USB 2.0 High-Speed physical layer |
| **5GHz Wi-Fi** | `<SYNC_HOST>:8730` via direct TCP | **15.0 to 18.5 MB/s** | 802.11ac wireless raw socket |
| **Legacy ADB Push** | `adb push` over Wi-Fi | **3.5 MB/s** | Bottlenecked by ADB sync packet framing |

Pushing to the M500 is faster than having the M500 pull from the host because the host CPU can read and stream disk blocks faster, while the M500 only has to accept raw TCP buffers and write them to flash.

## Files

- `rsyncd.conf`: Module targets (`music`, `movies`, `staging`) and subnet access control (defaults to the RFC1918 private ranges plus loopback; no personal subnet is baked in).
- `m500_rsyncd.sh`: Magisk startup service deployed to `/data/adb/service.d/`.
- `m500-sync.sh`: Host sync script that auto-detects USB vs Wi-Fi and routes traffic to port 8730. Reads the sync host/port from the gitignored `tools/m500-sync.env`.
