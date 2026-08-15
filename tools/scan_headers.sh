# Runs ON the device. Reads /sdcard/MikuLibrary/paths.txt (one file path per line),
# emits "<path>\t<base64 of first 64 bytes>" to headers.txt for FLAC STREAMINFO parsing.
{ while IFS= read -r f; do
    printf '%s\t' "$f"
    head -c 64 "$f" 2>/dev/null | base64 | tr -d '\n'
    printf '\n'
  done < /sdcard/MikuLibrary/paths.txt
  echo "###DONE" ; } > /sdcard/MikuLibrary/headers.txt
