#!/usr/bin/env bash
# Rewrite mac_permissions.xml cert pins for the MikuOS platform re-key.
#
# mac_permissions.xml maps a signer's X.509 cert (DER hex) to an SELinux
# `seinfo` tag; seapp_contexts then keys the app's SELinux domain off that tag.
# After re-signing framework-res + platform apps with our own key, these files
# still pin the OLD (AOSP test) cert, so our apps stop getting seinfo=platform
# → wrong domain → system_server denied → BOOT HANG. This swaps the pinned cert
# for ours, per signer. (Same job AOSP's sign_target_files_apks ReplaceCerts does.)
#
# Matching is by CERT FINGERPRINT, not XML structure: we pull every unique
# signature="HEX" (any case), SHA-256 its DER, and if that fingerprint is one of
# the AOSP test keys we re-key, swap the whole hex for our new cert's DER hex.
# This can't silently miss an entry due to seinfo ordering, indentation, or hex
# case — the old positional regex could (and left media/network_stack pins stale).
#
# Editing rewrites the file (sed -i = temp+rename), which DROPS its
# security.selinux xattr + mode — so capture the label as HEX (-e hex keeps the
# trailing NUL byte that bash command-substitution would otherwise strip, which
# left the file with a truncated 28-byte label instead of 29) and restore both.
#
# Usage: patch_mac_permissions.sh <rootfs_dir>   (run as root for setfattr)
set -uo pipefail

ROOT="${1:?usage: patch_mac_permissions.sh <rootfs_dir>}"
DIR="$(cd "$(dirname "$0")" && pwd)"
KEYS="$(cd "$DIR/../signing" && pwd)"

# AOSP public test-key SHA-256 fingerprint (colonless lowercase) -> our key role.
declare -A MAP=(
  [c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8]=platform
  [a40da80a59d170caa950cf15c18c454d47a39b26989d8b640ecd745ba71bf5dc]=releasekey
  [465983f7791f2abeb43ea2cbdc7f21a8260b72bc08a55c839fc1a43bc741a81e]=media
  [28bbfe4a7b97e74681dc55c2fbb6ccb8d6c74963733f6af6ae74d8c3a6e879fd]=shared
  [e1dbadce60dc080d15b58a014b0dcf9400e24de23fa00b287a5a982bfebda2ee]=networkstack
  # Legacy custom keys
  [467aa492c2993fefd4ea09ef3e0487e6f309143fc10c7637f2600f1fdfb02066]=platform
  [417bcef029a64f0f8ea80b8564822a5efe295222429f83f46e52ab49d51903d8]=releasekey
  [20ac32d0ab9a281c75bb485818972a72ae499c39323566e51acef42f095e5cd5]=media
  [a246defa3446d2938cc250460d77816f247d96ea00b5528633cc7b6d3b661894]=shared
  [73bbe2e3ac6585831acb4e297ab4f060116851fc93d9e5dc8a6ab3ea65230497]=networkstack
  [dfe220d2c2e64f8f50d1d4ba1eb5d6b699750eaa20b0d14adce24660cbff7c61]=platform
)

# Only repoint pins for roles that resign_system.sh actually re-keys. Must match its
# REKEY_ROLES default: networkstack stays on the AOSP cert because APEX-embedded
# members of android.uid.networkstack (TetheringNext, CellBroadcastServiceModule)
# cannot be re-signed, and a split shared-UID cert is fatal to system_server on A14.
REKEY_ROLES="${REKEY_ROLES:-platform releasekey shared}"
role_enabled() { case " $REKEY_ROLES " in *" $1 "*) return 0;; *) return 1;; esac; }

# Precompute our new cert DER hex (lowercase) per role.
declare -A NEWHEX=()
for role in platform releasekey media shared networkstack; do
  NEWHEX[$role]="$(openssl x509 -in "$KEYS/$role.x509.pem" -outform DER 2>/dev/null | xxd -p -c0)"
done

# Process substitution (not a pipe) so the loop runs in this shell; a file with
# no matching certs is not an error.
while IFS= read -r f; do
    ctx="$(getfattr -n security.selinux -e hex --only-values "$f" 2>/dev/null | tr -cd '0-9a-fA-Fx' || true)"
    mode="$(stat -c%a "$f" 2>/dev/null || echo 644)"
    changed=0
    # Every unique signature hex in the file, normalized to lowercase.
    while IFS= read -r old; do
        [ -z "$old" ] && continue
        fp="$(printf '%s' "$old" | xxd -r -p 2>/dev/null | openssl dgst -sha256 2>/dev/null | sed 's/.* //')"
        role="${MAP[$fp]:-}"; [ -z "$role" ] && continue
        role_enabled "$role" || { echo "  keep [$role pin, role disabled] in: $f"; continue; }
        new="${NEWHEX[$role]}"; [ -z "$new" ] || [ "$old" = "$new" ] && continue
        # Case-insensitive global swap (file may store the old hex upper- or lower-case).
        sed -i "s/$old/$new/gI" "$f" && { changed=1; echo "  patched [$role] in: $f"; }
    done < <(grep -oiE 'signature="[0-9a-fA-F]+"' "$f" 2>/dev/null \
                 | sed -E 's/.*"([0-9a-fA-F]+)".*/\1/' | tr 'A-F' 'a-f' | sort -u)
    if [ -n "$ctx" ]; then setfattr -n security.selinux -v "$ctx" "$f" 2>/dev/null || true; fi
    chmod "$mode" "$f" 2>/dev/null || true
done < <(find "$ROOT" -name "*mac_permissions*.xml" 2>/dev/null)
exit 0
