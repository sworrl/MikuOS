#!/usr/bin/env bash
# Fetch the offline voice engine for MikuOS status announcements.
#
#   tools/voice/fetch_models.sh                 venv + Kokoro model  (~1 GB on disk)
#   tools/voice/fetch_models.sh --with-verify   also faster-whisper for build_all.py --verify
#
# Everything lands in $MIKU_VOICE_CACHE (default tools/voice/.cache, which is git-ignored):
#   venv/                    Python env (kokoro-onnx, onnxruntime, praat-parselmouth, ...)
#   models/kokoro/           kokoro-v1.0.onnx (Apache-2.0) + voices-v1.0.bin
#   models/whisper/          only with --with-verify, downloaded on first use
#   tts/                     raw synthesis cache, safe to delete
#
# Needs: python3 >= 3.10, curl, ffmpeg with libopus/libvorbis and the soxr resampler.
# uv is used when present (fast), plain venv + pip otherwise.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CACHE="${MIKU_VOICE_CACHE:-$HERE/.cache}"
VERIFY=0
[[ "${1:-}" == "--with-verify" ]] && VERIFY=1

mkdir -p "$CACHE/models/kokoro"
for tool in curl ffmpeg python3; do
  command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 1; }
done
ffmpeg -hide_banner -encoders 2>/dev/null | grep -q libopus || echo "warning: ffmpeg has no libopus" >&2

echo "Python env in $CACHE/venv ..."
if command -v uv >/dev/null; then
  [[ -x "$CACHE/venv/bin/python" ]] || uv venv -q --python 3.12 "$CACHE/venv"
  VIRTUAL_ENV="$CACHE/venv" uv pip install -q -r "$HERE/requirements.txt"
  (( VERIFY )) && VIRTUAL_ENV="$CACHE/venv" uv pip install -q -r "$HERE/requirements-verify.txt"
else
  [[ -x "$CACHE/venv/bin/python" ]] || python3 -m venv "$CACHE/venv"
  "$CACHE/venv/bin/pip" install -q -r "$HERE/requirements.txt"
  (( VERIFY )) && "$CACHE/venv/bin/pip" install -q -r "$HERE/requirements-verify.txt"
fi

# Kokoro-82M v1.0, ONNX export by thewh1teagle/kokoro-onnx of hexgrad/Kokoro-82M (Apache-2.0).
BASE="https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"
fetch() {  # name sha256
  local f="$CACHE/models/kokoro/$1"
  if [[ -f "$f" ]] && echo "$2  $f" | sha256sum -c --status; then
    echo "  $1: present"; return
  fi
  echo "  $1: downloading"
  curl -fSL --retry 3 -o "$f.part" "$BASE/$1"
  echo "$2  $f.part" | sha256sum -c --status || { echo "checksum mismatch: $1" >&2; rm -f "$f.part"; exit 1; }
  mv "$f.part" "$f"
}
echo "Kokoro model ..."
fetch kokoro-v1.0.onnx 7d5df8ecf7d4b1878015a32686053fd0eebe2bc377234608764cc0ef3636a6c5
fetch voices-v1.0.bin  bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d

echo
echo "Ready. Try:"
echo "  $HERE/say.py --event iem_removed_35mm --voice mirai --out /tmp/x.ogg --play"
echo "  $HERE/build_all.py$( (( VERIFY )) && echo ' --verify')"
