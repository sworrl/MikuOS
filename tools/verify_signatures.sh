#!/usr/bin/env bash
# ==============================================================================
# MikuOS Signing Verification & Diagnostic Engine
# ==============================================================================
# Performs end-to-end verification of all cryptographic keys, compiled APKs,
# partition images, and vbmeta Verified Boot containers.
#
# Usage:
#   tools/verify_signatures.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KEYS_DIR="$REPO_DIR/mikuos/signing"
OUT_DIR="$REPO_DIR/mikuos/out"
KOTLIN_DIR="$REPO_DIR/miku-player-kotlin"
AVBTOOL="$REPO_DIR/tools/avbtool.py"

# Auto-detect apksigner
find_apksigner() {
    if command -v apksigner >/dev/null 2>&1; then
        command -v apksigner
    elif [ -n "${ANDROID_HOME:-}" ] && ls "$ANDROID_HOME/build-tools"/*/apksigner 2>/dev/null | tail -1 >/dev/null; then
        ls -1 "$ANDROID_HOME/build-tools"/*/apksigner 2>/dev/null | tail -1
    elif ls "$HOME/Android/Sdk/build-tools"/*/apksigner 2>/dev/null | tail -1 >/dev/null; then
        ls -1 "$HOME/Android/Sdk/build-tools"/*/apksigner 2>/dev/null | tail -1
    fi
}
APKSIGNER="${APKSIGNER:-$(find_apksigner)}"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}====================================================================${NC}"
echo -e "${CYAN}${BOLD}              MikuOS Signing Verification Suite                     ${NC}"
echo -e "${CYAN}${BOLD}====================================================================${NC}"

# 1. Verify Canonical Keys
echo -e "\n${BOLD}[1/4] Checking Canonical MikuOS Key Set (mikuos/signing/)...${NC}"
declare -A EXPECTED_FINGERPRINTS=()
for role in platform releasekey media shared networkstack; do
    pem="$KEYS_DIR/$role.x509.pem"
    pk8="$KEYS_DIR/$role.pk8"
    jks="$KEYS_DIR/mikuos-$role.jks"
    if [ -f "$pem" ] && [ -f "$pk8" ]; then
        fp="$(openssl x509 -in "$pem" -noout -fingerprint -sha256 | sed 's/.*=//' | tr -d ':\r\n ' | tr 'A-F' 'a-f')"
        EXPECTED_FINGERPRINTS[$role]="$fp"
        echo -e "  [${GREEN}OK${NC}] $role:\t SHA-256: ${YELLOW}${fp:0:16}...${fp: -8}${NC} (JKS: $([ -f "$jks" ] && echo -e "${GREEN}present${NC}" || echo -e "${RED}missing${NC}"))"
    else
        echo -e "  [${RED}FAIL${NC}] $role key pair missing"
    fi
done

if [ -f "$KEYS_DIR/avb.pem" ] && [ -f "$KEYS_DIR/avb.key" ]; then
    avb_fp="$(openssl x509 -in "$KEYS_DIR/avb.pem" -noout -fingerprint -sha256 | sed 's/.*=//' | tr -d ':\r\n ' | tr 'A-F' 'a-f')"
    echo -e "  [${GREEN}OK${NC}] avb:\t\t SHA-256: ${YELLOW}${avb_fp:0:16}...${avb_fp: -8}${NC} (Public Key bin: $([ -f "$KEYS_DIR/avb_custom_key.bin" ] && echo -e "${GREEN}present${NC}" || echo -e "${RED}missing${NC}"))"
fi

# 2. Verify Compiled Gradle APKs
echo -e "\n${BOLD}[2/4] Checking Compiled MikuOS Core APKs...${NC}"
PLATFORM_FP="${EXPECTED_FINGERPRINTS[platform]:-}"
APK_COUNT=0
APK_PASS=0

if [ -n "$APKSIGNER" ] && [ -x "$APKSIGNER" ]; then
    while IFS= read -r apk; do
        APK_COUNT=$((APK_COUNT + 1))
        name="$(basename "$apk")"
        fp="$("$APKSIGNER" verify --print-certs "$apk" 2>/dev/null | grep -m1 "SHA-256 digest:" | sed 's/.*digest: //' | tr -d ':\r\n ' | tr 'A-F' 'a-f' || true)"
        
        if [ "$fp" = "$PLATFORM_FP" ]; then
            echo -e "  [${GREEN}MATCH${NC}] $name -> Platform Key"
            APK_PASS=$((APK_PASS + 1))
        elif [ -n "$fp" ]; then
            echo -e "  [${YELLOW}MISMATCH${NC}] $name -> Foreign SHA-256 (${fp:0:16}...)"
        else
            echo -e "  [${RED}UNSIGNED${NC}] $name"
        fi
    done < <(find "$KOTLIN_DIR" -path "*/build/outputs/apk/release/*.apk" 2>/dev/null)
    
    echo -e "  Summary: $APK_PASS / $APK_COUNT APKs matched canonical platform key."
else
    echo -e "  ${YELLOW}Skipping APK verification (apksigner not found)${NC}"
fi

# 3. Verify Custom System Overlays
echo -e "\n${BOLD}[3/4] Checking System Overlays...${NC}"
OVERLAY_APK="$REPO_DIR/tools/custom_overlays/MikuSystemUIOverlay/com.miku.systemui.overlay.apk"
if [ -f "$OVERLAY_APK" ] && [ -n "$APKSIGNER" ]; then
    ov_fp="$("$APKSIGNER" verify --print-certs "$OVERLAY_APK" 2>/dev/null | grep -m1 "SHA-256 digest:" | sed 's/.*digest: //' | tr -d ':\r\n ' | tr 'A-F' 'a-f' || true)"
    if [ "$ov_fp" = "$PLATFORM_FP" ]; then
        echo -e "  [${GREEN}MATCH${NC}] $(basename "$OVERLAY_APK") -> Platform Key"
    else
        echo -e "  [${YELLOW}MISMATCH${NC}] $(basename "$OVERLAY_APK") -> Foreign SHA-256 (${ov_fp:0:16}...)"
    fi
else
    echo -e "  [${YELLOW}SKIP${NC}] Overlay APK not found or apksigner missing"
fi

# 4. Verify Verified Boot & vbmeta
echo -e "\n${BOLD}[4/4] Checking AVB vbmeta Images (mikuos/out/)...${NC}"
for vb in vbmeta_disabled.img vbmeta_system_disabled.img vbmeta_signed.img vbmeta_system_signed.img; do
    vb_file="$OUT_DIR/$vb"
    if [ -f "$vb_file" ] && [ -f "$AVBTOOL" ]; then
        flags="$(python3 -c "with open('$vb_file', 'rb') as f: data=f.read(124); import struct; print(hex(struct.unpack('>I', data[120:124])[0]))" 2>/dev/null || echo "unknown")"
        algo="$(python3 "$AVBTOOL" info_image --image "$vb_file" 2>/dev/null | grep -m1 "Algorithm:" | sed 's/.*Algorithm:[[:space:]]*//' | tr -d '\r\n' || echo "N/A")"
        echo -e "  [${GREEN}OK${NC}] $vb: Flags=$flags, Algorithm=$algo"
    elif [ -f "$vb_file" ]; then
        echo -e "  [${GREEN}PRESENT${NC}] $vb ($(stat -c%s "$vb_file") bytes)"
    else
        echo -e "  [${YELLOW}NOT BUILT${NC}] $vb"
    fi
done

echo -e "\n${CYAN}${BOLD}====================================================================${NC}"
echo -e "${GREEN}${BOLD}             MikuOS Signing Verification Complete                   ${NC}"
echo -e "${CYAN}${BOLD}====================================================================${NC}"
