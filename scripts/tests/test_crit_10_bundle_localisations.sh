#!/bin/bash
# CRIT-10 / WP-508: check-bundle.sh fails, naming `localisations`, when the Chinese Info.plist strings are missing.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# macOS's bash 3.2 doesn't stop for a failed [[ ]] under set -e, so every check calls fail itself.
fail() { echo "test_crit_10_bundle_localisations: $1" >&2; exit 1; }
APP=${1:-"$ROOT/build/DerivedData/Build/Products/Debug/Font Playground.app"}
[[ -d "$APP" ]] || { echo "test_crit_10_bundle_localisations: build the app first (make app)" >&2; exit 2; }
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
"$ROOT/scripts/check-bundle.sh" "$APP" | grep -q 'check-bundle: localisations OK'
ditto "$APP" "$scratch/Font Playground.app"
rm "$scratch/Font Playground.app/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"
status=0
output=$("$ROOT/scripts/check-bundle.sh" "$scratch/Font Playground.app" 2>&1) || status=$?
[[ $status -eq 1 && "$output" == *'check-bundle: localisations FAIL'*'zh-Hans.lproj/InfoPlist.strings'* ]] || fail "check-bundle did not fail localisations without zh-Hans InfoPlist.strings (exit $status): $output"
echo 'test_crit_10_bundle_localisations: OK'
