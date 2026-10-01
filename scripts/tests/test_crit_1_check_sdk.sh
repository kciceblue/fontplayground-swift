#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# macOS's bash 3.2 doesn't stop for a failed [[ ]] under set -e, so every check calls fail itself.
fail() { echo "test_crit_1_check_sdk: $1" >&2; exit 1; }
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
printf 'int main(void){return 0;}\n' | xcrun clang -x c - -o "$scratch/ok"
"$ROOT/scripts/check-sdk.sh" "$scratch/ok"
xcrun vtool -set-build-version macos 14.0 15.0 -replace -output "$scratch/old" "$scratch/ok"
status=0
output=$("$ROOT/scripts/check-sdk.sh" "$scratch/old" 2>&1) || status=$?
[[ $status -eq 1 && "$output" == *'sdk 15.0 < 26'* ]] || fail "check-sdk did not reject sdk 15.0 (exit $status): $output"
echo "$output"
echo 'test_crit_1_check_sdk: OK'
