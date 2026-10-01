#!/bin/bash
# AGENTS.md rule 8: create and verify the image at a temporary path beside the destination, then fsync and rename it
# into place, so an interrupted or failed run never replaces the last good DMG with a partial one.
set -euo pipefail
[[ $# -eq 2 ]] || { echo 'usage: make-dmg.sh <app> <out.dmg>' >&2; exit 2; }
out=$2
mkdir -p "$(dirname "$out")"
scratch=$(mktemp -d)
partial="$(dirname "$out")/.$(basename "$out" .dmg).$$.partial.dmg"
trap 'rm -rf "$scratch"; rm -f "$partial"' EXIT
ditto "$1" "$scratch/Font Playground.app"
ln -s /Applications "$scratch/Applications"
rm -f "$partial"
if diskutil image create from --help >/dev/null 2>&1; then
  diskutil image create from --format ULFO --volumeName 'Font Playground' "$scratch" "$partial"
else
  hdiutil create -volname 'Font Playground' -srcfolder "$scratch" -format ULFO -fs APFS "$partial"
fi
hdiutil verify "$partial"
python3 - "$partial" "$out" <<'PY'
import os, sys
with open(sys.argv[1], 'rb') as stream:
    os.fsync(stream.fileno())
os.replace(sys.argv[1], sys.argv[2])
directory = os.open(os.path.dirname(os.path.abspath(sys.argv[2])), os.O_RDONLY)
try:
    os.fsync(directory)
finally:
    os.close(directory)
PY
