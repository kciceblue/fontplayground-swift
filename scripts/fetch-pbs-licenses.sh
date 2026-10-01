#!/bin/bash
# WP-602: maintainer-run only; never invoked by Make or CI.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/scripts/python-runtime.pin"
command -v zstd >/dev/null || { echo 'fetch-pbs-licenses: needs zstd (brew install zstd)' >&2; exit 2; }
CACHE="$ROOT/build/cache/pbs"
DEST="$ROOT/App/Licenses/python-build-standalone"
ASSET="cpython-${PBS_PYTHON}+${PBS_RELEASE}-${PBS_TRIPLE}-pgo+lto-full.tar.zst"
BASE="https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_RELEASE}"
mkdir -p "$CACHE" "$DEST"
STAGE=$(mktemp -d "$CACHE/.licenses.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
atomic_copy() {
  python3 - "$1" "$2" <<'PY'
import os, pathlib, sys, tempfile
source, target = map(pathlib.Path, sys.argv[1:])
fd, temporary = tempfile.mkstemp(prefix='.' + target.name + '.', dir=target.parent)
try:
    with os.fdopen(fd, 'wb') as stream:
        stream.write(source.read_bytes()); stream.flush(); os.fsync(stream.fileno())
    os.replace(temporary, target)
    directory = os.open(target.parent, os.O_RDONLY)
    try: os.fsync(directory)
    finally: os.close(directory)
finally:
    pathlib.Path(temporary).unlink(missing_ok=True)
PY
}
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
curl --fail --location --proto '=https' --silent --show-error "$BASE/SHA256SUMS" -o "$STAGE/SHA256SUMS"
EXPECTED=$(awk -v asset="$ASSET" '$2 == asset || $2 == "*" asset {print $1}' "$STAGE/SHA256SUMS")
[[ -n "$EXPECTED" ]] || { echo "fetch-pbs-licenses: $ASSET is not listed in SHA256SUMS" >&2; exit 1; }
# A cached archive that fails verification would make every later run fail against the same bad file.
if [[ -f "$CACHE/$ASSET" && $(sha256 "$CACHE/$ASSET") != "$EXPECTED" ]]; then
  echo "fetch-pbs-licenses: removing cached $ASSET: SHA-256 mismatch; downloading it again" >&2
  rm -f "$CACHE/$ASSET"
fi
if [[ ! -f "$CACHE/$ASSET" ]]; then
  curl --fail --location --proto '=https' --silent --show-error "$BASE/${ASSET//+/%2B}" -o "$STAGE/$ASSET"
  # Verify the staged download first, so a truncated or wrong archive never reaches the cache.
  if [[ $(sha256 "$STAGE/$ASSET") != "$EXPECTED" ]]; then
    echo "fetch-pbs-licenses: SHA-256 mismatch for $ASSET" >&2
    exit 1
  fi
  atomic_copy "$STAGE/$ASSET" "$CACHE/$ASSET"
fi
ACTUAL=$(sha256 "$CACHE/$ASSET")
zstd -dc "$CACHE/$ASSET" | tar -x -f - -C "$STAGE" python/licenses python/PYTHON.json
for name in openssl-3 sqlite mpdecimal expat liblzma bzip2 libffi libuuid; do
  FILE="LICENSE.$name.txt"
  [[ -s "$STAGE/python/licenses/$FILE" ]] || { echo "fetch-pbs-licenses: missing $FILE" >&2; exit 1; }
  atomic_copy "$STAGE/python/licenses/$FILE" "$DEST/$FILE"
  echo "fetch-pbs-licenses: copied $FILE"
done
echo "fetch-pbs-licenses: archive SHA-256 $ACTUAL"
