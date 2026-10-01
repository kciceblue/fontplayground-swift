#!/bin/bash
# WP-203: build in isolation; only publish a verified, relocatable runtime.
set -euo pipefail
if [[ $(uname -s) != Darwin || $(uname -m) != arm64 ]]; then
  echo 'build-helper-runtime: needs macOS on Apple silicon' >&2
  exit 2
fi
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/scripts/python-runtime.pin"
OUT="$ROOT/build/helper"
CACHE="$ROOT/build/cache"
ARCHIVE=''
KEEP_STAGING=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out|--cache|--python-archive)
      [[ $# -ge 2 && -n "$2" ]] || { echo "missing value for $1" >&2; exit 2; }
      case "$1" in --out) OUT="$2";; --cache) CACHE="$2";; --python-archive) ARCHIVE="$2";; esac
      shift 2;;
    --keep-staging) KEEP_STAGING=1; shift;;
    *) echo "unknown argument: $1" >&2; exit 2;;
  esac
done
echo '[1/12] Checking build tools'
for tool in uv curl shasum tar lipo codesign file; do
  command -v "$tool" >/dev/null || { echo "build-helper-runtime: missing tool: $tool" >&2; exit 2; }
done
mkdir -p "$OUT" "$CACHE/pbs"
OUT=$(cd "$OUT" && pwd)
CACHE=$(cd "$CACHE" && pwd)
# Roll back a publish that an earlier run left unfinished before anything else reads the output.
"$ROOT/scripts/publish-helper-runtime.sh" --recover "$OUT"
ASSET="cpython-${PBS_PYTHON}+${PBS_RELEASE}-${PBS_TRIPLE}-${PBS_FLAVOR}.tar.gz"
URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_RELEASE}/cpython-${PBS_PYTHON}%2B${PBS_RELEASE}-${PBS_TRIPLE}-${PBS_FLAVOR}.tar.gz"
STAGE=''
cleanup() {
  if [[ -n "$STAGE" && $KEEP_STAGING -eq 0 ]]; then rm -rf "$STAGE"; fi
}
trap cleanup EXIT
atomic_file() {
  uv run --project "$ROOT/engine" --frozen python - "$1" "$2" <<'PY'
import os, sys
with open(sys.argv[1], 'rb') as source:
    os.fsync(source.fileno())
os.replace(sys.argv[1], sys.argv[2])
directory = os.open(os.path.dirname(sys.argv[2]), os.O_RDONLY)
try:
    os.fsync(directory)
finally:
    os.close(directory)
PY
}
echo '[2/12] Verifying pinned Python archive'
EXPLICIT_ARCHIVE=0
if [[ -n "$ARCHIVE" ]]; then
  EXPLICIT_ARCHIVE=1
else
  ARCHIVE="$CACHE/pbs/$ASSET"
  if [[ -f "$ARCHIVE" ]]; then
    echo "using cached $ASSET"
  else
    curl --fail --location --proto '=https' --tlsv1.2 --retry 3 -o "$ARCHIVE.part" "$URL"
    atomic_file "$ARCHIVE.part" "$ARCHIVE"
  fi
fi
ACTUAL=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
if [[ "$ACTUAL" != "$PBS_SHA256" ]]; then
  echo "SHA-256 mismatch for $ARCHIVE: expected $PBS_SHA256, got $ACTUAL" >&2
  if [[ $EXPLICIT_ARCHIVE -eq 0 ]]; then rm -f "$ARCHIVE"; fi
  exit 1
fi
echo '[3/12] Extracting staging runtime'
STAGE=$(mktemp -d "$OUT/.staging.XXXXXX")
tar -xzf "$ARCHIVE" -C "$STAGE"
mv "$STAGE/python" "$STAGE/fpengine"
RT="$STAGE/fpengine"
SITE="$RT/lib/python3.12/site-packages"
echo '[4/12] Checking Python version'
"$RT/bin/python3" -I -B -c 'import sys; assert sys.version_info[:2] == (3, 12)'
echo '[5/12] Building non-editable engine wheel'
uv build --project "$ROOT/engine" --wheel --out-dir "$STAGE/wheels"
echo '[6/12] Installing locked wheels'
uv export --project "$ROOT/engine" --frozen --no-dev --no-editable --no-emit-project --format requirements-txt -o "$STAGE/requirements.txt" >/dev/null
uv pip install --python "$RT/bin/python3" --target "$SITE" --no-deps --require-hashes --only-binary :all: --link-mode copy -r "$STAGE/requirements.txt"
uv pip install --python "$RT/bin/python3" --target "$SITE" --no-deps --link-mode copy "$STAGE"/wheels/fpengine-*.whl
echo '[7/12] Removing builder-specific install metadata'
find "$SITE" -type f \( -name direct_url.json -o -name uv_cache.json \) -delete
echo '[8/12] Trimming development and unused libraries'
"$RT/bin/python3" -I -B - "$RT" <<'PY'
from pathlib import Path
import shutil, sys
root = Path(sys.argv[1])
patterns = [
    'include', 'share', 'lib/pkgconfig', 'lib/python3.12/config-3.12-darwin', 'BUILD',
    'lib/libtcl*', 'lib/tcl*', 'lib/tk*', 'lib/itcl*', 'lib/thread*',
    'lib/python3.12/lib-dynload/_tkinter*', 'lib/python3.12/lib-dynload/_dbm*',
    'lib/python3.12/lib-dynload/_crypt*', 'lib/python3.12/turtle.py',
    'lib/python3.12/site-packages/pip', 'lib/python3.12/site-packages/pip-*.dist-info',
    'lib/python3.12/site-packages/bin',
] + ['lib/python3.12/' + name for name in (
    'tkinter', 'idlelib', 'turtledemo', 'ensurepip', 'lib2to3', 'pydoc_data', 'venv', '__phello__', 'test'
)]
paths = [p for pattern in patterns for p in root.glob(pattern)]
paths += [p for p in (root / 'bin').iterdir() if p.name not in ('python3', 'python3.12')]
paths += list(root.rglob('__pycache__')) + list(root.rglob('*.pyc'))
for path in paths:
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink(missing_ok=True)
PY
echo '[9/12] Thinning every Mach-O to arm64'
while IFS= read -r -d '' binary; do
  if file -b "$binary" | grep -q 'Mach-O'; then
    if [[ $(lipo -archs "$binary") != arm64 ]]; then
      lipo -thin arm64 "$binary" -output "$binary.thin"
      atomic_file "$binary.thin" "$binary"
    fi
  fi
done < <(find "$RT" -type f -print0)
echo '[10/12] Compiling reproducible bytecode'
"$RT/bin/python3" -I -B -m compileall -q -j 0 --invalidation-mode unchecked-hash -s "$RT" -p /fpengine "$RT/lib/python3.12"
echo '[11/12] Checking complete runtime'
"$ROOT/scripts/check-helper-runtime.sh" "$RT"
echo '[12/12] Publishing verified runtime'
"$RT/bin/python3" -I -B - "$RT" "$STAGE/manifest.json" "$PBS_RELEASE" "$PBS_SHA256" <<'PY'
import importlib.metadata, json, os, subprocess, sys
from pathlib import Path
root, output = map(Path, sys.argv[1:3])
macho = sorted(str(p.relative_to(root)) for p in root.rglob('*') if p.is_file() and not p.is_symlink()
               and 'Mach-O' in subprocess.check_output(['file', '-b', str(p)], text=True))
manifest = dict(pbs_release=sys.argv[3], python='.'.join(map(str, sys.version_info[:3])), sha256=sys.argv[4],
                fpengine=importlib.metadata.version('fpengine'), fonttools=importlib.metadata.version('fonttools'),
                skia_pathops=importlib.metadata.version('skia-pathops'), unicodedata2=importlib.metadata.version('unicodedata2'),
                size_mb=int(subprocess.check_output(['du', '-sm', str(root)], text=True).split()[0]), macho=macho)
with output.open('w') as stream:
    json.dump(manifest, stream, indent=2); stream.write('\n'); stream.flush(); os.fsync(stream.fileno())
PY
# The runtime and its manifest switch together (WP-601 signs exactly the Mach-O files the manifest lists).
"$ROOT/scripts/publish-helper-runtime.sh" "$OUT" "$RT" "$STAGE/manifest.json"
"$OUT/fpengine/bin/python3" -I -B - "$OUT" "$ROOT" <<'PY'
import json, os, sys
from pathlib import Path
out, root = map(Path, sys.argv[1:])
data = json.loads((out / 'fpengine-runtime.json').read_text())
print(f"helper runtime OK: {os.path.relpath(out / 'fpengine', root)} ({data['size_mb']} MB, {len(data['macho'])} Mach-O files)")
PY
