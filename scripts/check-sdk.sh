#!/bin/bash
# CRIT-1: the deployment target does not prove which SDK linked the app.
set -euo pipefail
[[ $# -ge 1 && $# -le 2 ]] || { echo 'usage: check-sdk.sh <mach-o> [min_major=26]' >&2; exit 2; }
bin=$1
minimum=${2:-26}
sdk=$(otool -l "$bin" | awk '/cmd LC_BUILD_VERSION/{f=1} f&&$1=="sdk"{print $2; exit}')
if [[ -z "$sdk" ]]; then
  echo "check-sdk: no LC_BUILD_VERSION in $bin" >&2
  exit 1
fi
if [[ ${sdk%%.*} -lt $minimum ]]; then
  echo "check-sdk: FAIL $bin sdk $sdk < $minimum" >&2
  exit 1
fi
echo "check-sdk: OK $bin sdk $sdk"
