#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
printf 'int main(void){return 0;}\n' | xcrun clang -x c - -o "$scratch/ok"
"$ROOT/scripts/check-sdk.sh" "$scratch/ok"
xcrun vtool -set-build-version macos 14.0 15.0 -replace -output "$scratch/old" "$scratch/ok"
status=0
output=$("$ROOT/scripts/check-sdk.sh" "$scratch/old" 2>&1) || status=$?
[[ $status -eq 1 && "$output" == *'sdk 15.0 < 26'* ]]
echo "$output"
echo 'test_crit_1_check_sdk: OK'
