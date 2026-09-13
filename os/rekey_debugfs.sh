#!/usr/bin/env bash
# Platform re-key of ONE partition image WITHOUT mounting it.
#
# Why: the previous re-key path (`e2fsck -E unshare_blocks` → `mount -o loop,rw` →
# apksigner in place → `umount`) corrupts the image intermittently — proven by the
# REKEY_NOOP bisection build (mount+umount only, re-signs nothing) hanging on the boot
# splash exactly like the real re-key. The debugfs injection path the rest of the
# builder uses has never produced a bad image, so the re-key now goes through it too:
#
#   1. `debugfs rdump /` the whole tree to a host scratch dir (no mount)
#   2. run the unchanged resign_system.sh + patch_mac_permissions.sh on that tree
#   3. write ONLY the files those scripts changed back with dfput semantics
#      (rm + write — debugfs `write` silently no-ops on an existing path), then
#      restore the original mode and security.selinux label (debugfs writes create
#      UNLABELED files; an unlabeled /system APK can't be read by its own process)
#   4. verify every written inode owns data blocks and matches the host size
#      (debugfs also silently no-ops on a full fs → zero-block inodes)
#
# Prereq: the image must already be unshare_blocks'd (builder step [2]) and have free
# space for the v2/v3 signing-block growth (~a few KB per APK; the builder's resize2fs
# slack covers it). Usage: rekey_debugfs.sh <partition.img>   (env: APKSIGNER, WORK_DIR)
set -uo pipefail
IMG="${1:?usage: rekey_debugfs.sh <partition.img>}"
[ -f "$IMG" ] || { echo "!! no such image: $IMG"; exit 1; }
NAME="$(basename "$IMG" .img)"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESIGN="$DIR/resign_system.sh"
MACP="$DIR/patch_mac_permissions.sh"
export APKSIGNER="${APKSIGNER:-$(ls ~/Android/Sdk/build-tools/*/apksigner 2>/dev/null | tail -1)}"
[ -n "$APKSIGNER" ] || { echo "!! apksigner not found (set APKSIGNER)"; exit 1; }

WORK="$(mktemp -d "${WORK_DIR:-${TMPDIR:-/tmp}}/rekey_${NAME}.XXXXXX")"
TREE="$WORK/tree"; mkdir -p "$TREE"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

echo "[rekey:$NAME] dumping tree (debugfs rdump) → $TREE"
# rdump warns "Operation not permitted while changing ownership" when not root — harmless,
# ownership/xattrs are restored from the IMAGE on write-back, never from the host copy.
debugfs -R "rdump / $TREE" "$IMG" 2>&1 | grep -v 'changing ownership\|^debugfs 1\.' || true
n_apk="$(find "$TREE" -name '*.apk' | wc -l)"
[ "$n_apk" -gt 0 ] || { echo "!! [$NAME] rdump produced no APKs — aborting"; exit 1; }
echo "[rekey:$NAME] $n_apk APKs in tree"

MARK="$WORK/.marker"; touch "$MARK"; sleep 1.1   # mtime granularity guard for -newer

echo "[rekey:$NAME] re-signing (resign_system.sh APPLY=1)"
APPLY=1 "$RESIGN" "$TREE" || { echo "!! [$NAME] resign_system.sh failed"; exit 1; }
echo "[rekey:$NAME] patching mac_permissions cert pins"
"$MACP" "$TREE" || { echo "!! [$NAME] patch_mac_permissions.sh failed"; exit 1; }

# --- write-back -----------------------------------------------------------------
get_ctx()  { debugfs -R "ea_get $1 security.selinux" "$IMG" 2>/dev/null | sed -n 's/.*= "\(.*\)\\000"[[:space:]]*$/\1/p' | head -1; }
get_mode() { debugfs -R "stat $1" "$IMG" 2>/dev/null | sed -n 's/.*Mode:[[:space:]]*0\{0,1\}\([0-7]\{3\}\).*/\1/p' | head -1; }
get_size() { debugfs -R "stat $1" "$IMG" 2>/dev/null | sed -n 's/^Size:[[:space:]]*\([0-9]*\).*/\1/p; s/.*[[:space:]]Size:[[:space:]]*\([0-9]*\).*/\1/p' | head -1; }
get_blocks() { debugfs -R "stat $1" "$IMG" 2>/dev/null | sed -n 's/.*Blockcount:[[:space:]]*\([0-9]*\).*/\1/p' | head -1; }

changed=0; failed=0
while IFS= read -r f; do
    rel="/${f#"$TREE"/}"
    ctx="$(get_ctx "$rel")"; mode="$(get_mode "$rel")"
    [ -n "$ctx" ]  || { echo "  !! [$NAME] no security.selinux on $rel in image — refusing to write unlabeled"; failed=$((failed+1)); continue; }
    [ -n "$mode" ] || mode=644
    debugfs -w -R "rm $rel" "$IMG" >/dev/null 2>&1
    if debugfs -w -R "write $f $rel" "$IMG" 2>&1 | grep -qi 'already exists\|No space\|not found'; then
        echo "  !! [$NAME] write failed: $rel"; failed=$((failed+1)); continue
    fi
    debugfs -w -R "set_inode_field $rel mode 0100$mode" "$IMG" >/dev/null 2>&1
    debugfs -w -R "ea_set $rel security.selinux ${ctx}\\000" "$IMG" >/dev/null 2>&1
    # verify: size matches host copy, inode owns blocks, label round-trips
    hsz="$(stat -c%s "$f")"; isz="$(get_size "$rel")"; blk="$(get_blocks "$rel")"; rctx="$(get_ctx "$rel")"
    if [ "$hsz" != "$isz" ] || [ -z "$blk" ] || [ "$blk" = "0" ] || [ "$rctx" != "$ctx" ]; then
        echo "  !! [$NAME] verify failed: $rel host=$hsz img=$isz blocks=$blk ctx='$rctx' (want '$ctx')"; failed=$((failed+1)); continue
    fi
    changed=$((changed+1))
done < <(find "$TREE" -type f -newer "$MARK" | sort)

echo "[rekey:$NAME] wrote back $changed file(s), $failed failure(s)"
[ "$failed" -eq 0 ] || exit 1
[ "$changed" -gt 0 ] || { echo "!! [$NAME] nothing changed — expected re-signed APKs"; exit 1; }
e2fsck -fn "$IMG" >/dev/null 2>&1 || { echo "!! [$NAME] e2fsck reports errors after write-back"; e2fsck -fn "$IMG" 2>&1 | tail -5; exit 1; }
echo "[rekey:$NAME] OK — filesystem clean"
