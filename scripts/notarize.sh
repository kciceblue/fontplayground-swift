#!/bin/bash
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: notarize.sh <app|dmg>' >&2; exit 2; }
target=$1
auth=()
if [[ -n ${NOTARY_KEYCHAIN_PROFILE:-} ]]; then
  auth=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
elif [[ -n ${NOTARY_KEY_PATH:-} && -n ${NOTARY_KEY_ID:-} && -n ${NOTARY_ISSUER_ID:-} ]]; then
  auth=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
  echo 'notarize: no credentials (set NOTARY_KEYCHAIN_PROFILE or NOTARY_KEY_PATH/NOTARY_KEY_ID/NOTARY_ISSUER_ID)' >&2
  exit 3
fi
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
submission=$target
if [[ "$target" == *.app ]]; then
  submission="$scratch/app.zip"
  ditto -c -k --keepParent "$target" "$submission"
fi
# Keep the service response even when notarytool returns a failing status.
status_code=0
xcrun notarytool submit "$submission" --wait --timeout 30m --output-format json "${auth[@]}" > "$scratch/result.json" || status_code=$?
cat "$scratch/result.json"
status=$(plutil -extract status raw -o - "$scratch/result.json" 2>/dev/null || true)
if [[ "$status" != Accepted || $status_code -ne 0 ]]; then
  identifier=$(plutil -extract id raw -o - "$scratch/result.json" 2>/dev/null || true)
  if [[ -n "$identifier" ]]; then
    xcrun notarytool log "$identifier" "${auth[@]}" "$scratch/notary-log.json"
    cat "$scratch/notary-log.json"
  fi
  exit 1
fi
xcrun stapler staple "$target"
xcrun stapler validate "$target"
