#!/bin/bash
set -euo pipefail
ROOT=$(cd "$SRCROOT/.." && pwd)
APP="$TARGET_BUILD_DIR/$WRAPPER_NAME"
PYTHON="$APP/Contents/Resources/fpengine/bin/python3"
if [[ -x "$PYTHON" ]]; then
  "$PYTHON" -I -B "$ROOT/tools/release/collect_licenses.py" --app "$APP" --repo "$ROOT"
else
  mkdir -p "$APP/Contents/Resources/Licenses"
  ditto "$ROOT/LICENSE" "$APP/Contents/Resources/Licenses/LICENSE.txt"
  if [[ -d "$ROOT/App/Licenses" ]]; then ditto "$ROOT/App/Licenses" "$APP/Contents/Resources/Licenses"; fi
  rm -f "$APP/Contents/Resources/Licenses/index.json"
fi
