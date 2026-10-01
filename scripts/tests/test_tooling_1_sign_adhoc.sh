#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# macOS's bash 3.2 doesn't stop for a failed [[ ]] under set -e, so every check calls fail itself.
fail() { echo "test_tooling_1_sign_adhoc: $1" >&2; exit 1; }
cd "$ROOT"
[[ -x build/helper/fpengine/bin/python3 ]] || { echo "run 'make helper-runtime' first" >&2; exit 2; }
make app
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
APP="$scratch/Font Playground.app"
ditto 'build/DerivedData/Build/Products/Debug/Font Playground.app' "$APP"
scripts/sign-app.sh "$APP" -
output=$(codesign --verify --deep --strict --verbose=2 "$APP" 2>&1)
echo "$output"
[[ "$output" == *'valid on disk'* && "$output" == *'satisfies its Designated Requirement'* ]] || fail 'codesign --verify did not accept the signed app'
"$APP/Contents/Helpers/fpengine/bin/python3" -I -B -c 'import pathops'
[[ -z $(codesign -d --entitlements - --xml "$APP" 2>/dev/null) ]] || fail 'the signed app has entitlements'
scripts/check-bundle.sh "$APP"
"$APP/Contents/MacOS/Font Playground" --self-test --require-embedded-engine
codesign --verify --deep --strict "$APP"
echo 'test_tooling_1_sign_adhoc: OK'
