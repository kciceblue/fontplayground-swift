#!/bin/bash
# TOOLING-1: nested code must be signed inside-out, without entitlement inheritance.
set -euo pipefail
[[ $# -eq 2 ]] || { echo 'usage: sign-app.sh <app> <identity>' >&2; exit 2; }
APP=$1
IDENTITY=$2
[[ -d "$APP/Contents" ]] || { echo "sign-app: not an app: $APP" >&2; exit 1; }
SIGN="$(cd "$(dirname "$0")" && pwd)/codesign-retry.sh"
args=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" == 'Developer ID Application:'* ]]; then args+=(--timestamp); else args+=(--timestamp=none); fi
helper_args=("${args[@]}")
if [[ "$IDENTITY" != - ]]; then helper_args+=(--options runtime); fi
# Deliberately do not preserve entitlements: even get-task-allow is removed.
for kind in library executable; do
  location="$APP/Contents"
  [[ "$kind" != executable ]] || location="$APP/Contents/Resources"
  while IFS= read -r -d '' binary; do
    description=$(file -b "$binary")
    [[ "$description" == *Mach-O* ]] || continue
    if [[ "$kind" == executable ]]; then
      [[ "$description" == *executable* ]] || continue
    else
      [[ "$description" == *executable* ]] && continue
    fi
    "$SIGN" "${helper_args[@]}" "$binary"
  done < <(find "$location" -type f -print0)
done
"$SIGN" "${args[@]}" --options runtime "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
if [[ "$IDENTITY" != - ]]; then
  while IFS= read -r -d '' binary; do
    [[ $(file -b "$binary") == *Mach-O* ]] || continue
    metadata=$(codesign -dv "$binary" 2>&1)
    [[ "$metadata" == *'flags='*runtime* ]] || { echo "sign-app: hardened runtime missing: $binary" >&2; exit 1; }
  done < <(find "$APP" -type f -print0)
fi
echo 'sign-app: OK'
