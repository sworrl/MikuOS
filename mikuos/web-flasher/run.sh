#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f "./mikuos-flasher" ]; then
    echo "[*] Compiling MikuOS Web Flasher (Go)..."
    go build -o mikuos-flasher .
fi

echo "[*] Launching MikuOS Web Flasher on http://localhost:3939..."
exec ./mikuos-flasher "$@"
