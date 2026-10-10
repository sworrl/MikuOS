#!/usr/bin/env bash
# Fetch the public-record broadcast databases the station catalogue is built from.
#
# All four FM/AM lists are the FCC's own query output in "list=4" pipe-delimited form, which is
# US federal public-domain record data. They include the Canadian and Mexican stations
# coordinated under the border agreements, which is why CA and MX appear without a separate
# source. facility.dat is the CDBS facility table and carries the date each call sign took
# effect, the closest thing in the public record to how long a station has been on the air.
#
# NOT fetched: station logos. Those are trademarks and this firmware is published, so they are
# pulled per-device at runtime and cached there instead of being redistributed in the image.
set -euo pipefail
cd "$(dirname "$0")"
OUT="${1:-.}"; mkdir -p "$OUT"; cd "$OUT"

fm_query() {   # $1 = service code
  curl -sS --max-time 300 -o "$1.txt" \
    "https://transition.fcc.gov/fcc-bin/fmq?state=&call=&city=&arn=&serv=$1&vac=&freq=0.0&fre2=108.0&facid=&class=&dkt=&list=4&dist=&dlat2=&mlat2=&slat2=&dlon2=&mlon2=&slon2=&NS=N&EW=W&size=9"
  echo "  $1: $(wc -l < "$1.txt") records"
}
echo "FCC FM services (FM full power, FX translators, FL low power)..."
fm_query FM; mv FM.txt fm.txt
fm_query FX
fm_query FL

echo "FCC AM..."
curl -sS --max-time 300 -o am.txt \
  "https://transition.fcc.gov/fcc-bin/amq?state=&call=&arn=&city=&freq=0&fre2=1700&type=0&facid=&class=&list=4&dist=&dlat2=&mlat2=&slat2=&dlon2=&mlon2=&slon2=&NS=N&EW=W&size=9"
echo "  am: $(wc -l < am.txt) records"

echo "CDBS facility table (call sign effective dates)..."
curl -sSL --max-time 300 -o facility.zip \
  "https://transition.fcc.gov/ftp/Bureaus/MB/Databases/cdbs/facility.zip"
unzip -oq facility.zip
echo "  facility.dat: $(wc -l < facility.dat) records"

echo
echo "Now run: python3 -I build_stations_db.py"
