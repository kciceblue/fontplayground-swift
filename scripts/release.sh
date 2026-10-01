#!/bin/bash
# TOOLING-1: one ordered path exercises the actual signed and mounted products.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
# macOS's bash 3.2 doesn't stop for a failed [[ ]] under set -e, so every check calls fail itself.
fail() { echo "release: $1" >&2; exit 1; }
adhoc=0
identity=${MACOS_DEVELOPER_ID_IDENTITY:-}
version=''
build_number=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --adhoc) adhoc=1; shift;;
    --identity|--version|--build-number)
      [[ $# -ge 2 && -n "$2" ]] || { echo "release: missing value for $1" >&2; exit 2; }
      case "$1" in --identity) identity=$2;; --version) version=$2;; --build-number) build_number=$2;; esac
      shift 2;;
    *) echo "release: unknown argument: $1" >&2; exit 2;;
  esac
done
marketing=$(awk '/^MARKETING_VERSION[[:space:]]*=/{print $3}' App/Version.xcconfig)
engine_version=$(python3 -c 'import pathlib,re; print(re.search(r"(?m)^version\s*=\s*\"([^\"]+)\"", pathlib.Path("engine/pyproject.toml").read_text())[1])')
version=${version:-$marketing}
if [[ "$version" != "$marketing" || "$version" != "$engine_version" ]]; then
  echo "release: version $version does not match App/Version.xcconfig ($marketing) / engine ($engine_version)" >&2
  exit 2
fi
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || { echo 'release: build number must be a positive integer' >&2; exit 2; }
if [[ $adhoc -eq 1 ]]; then identity=-; fi
[[ -n "$identity" ]] || { echo 'release: supply --identity or --adhoc' >&2; exit 2; }
rm -rf build/release dist
make setup
make helper-runtime
xcodegen generate --spec App/project.yml --quiet
xcodebuild -project App/FontPlayground.xcodeproj -scheme FontPlayground -configuration Release \
  -derivedDataPath build/release/DerivedData ARCHS=arm64 CODE_SIGN_IDENTITY=- CURRENT_PROJECT_VERSION="$build_number" build
APP="$ROOT/build/release/Font Playground.app"
ditto 'build/release/DerivedData/Build/Products/Release/Font Playground.app' "$APP"
scripts/check-sdk.sh "$APP/Contents/MacOS/Font Playground"
scripts/check-bundle.sh "$APP" --release
"$APP/Contents/MacOS/Font Playground" --self-test --require-embedded-engine
scripts/sign-app.sh "$APP" "$identity"
"$APP/Contents/MacOS/Font Playground" --self-test --require-embedded-engine
codesign --verify --deep --strict "$APP"
if [[ $adhoc -eq 0 ]]; then
  scripts/check-bundle.sh "$APP" --release --distribution
  scripts/notarize.sh "$APP"
  assessment=$(spctl --assess --type execute --verbose=4 "$APP" 2>&1)
  echo "$assessment"
  [[ "$assessment" == *accepted* && "$assessment" == *'source=Notarized Developer ID'* ]] || fail 'Gatekeeper did not accept the notarized app'
fi
DMG="dist/FontPlayground-$version-arm64.dmg"
scripts/make-dmg.sh "$APP" "$DMG"
if [[ $adhoc -eq 0 ]]; then
  scripts/codesign-retry.sh --force --timestamp --sign "$identity" "$DMG"
  scripts/notarize.sh "$DMG"
  assessment=$(spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG" 2>&1)
  echo "$assessment"
  [[ "$assessment" == *accepted* && "$assessment" == *'source=Notarized Developer ID'* ]] || fail 'Gatekeeper did not accept the notarized DMG'
fi
scratch=$(mktemp -d)
mounted=0
cleanup() {
  if [[ $mounted -eq 1 ]]; then diskutil eject "$scratch/mnt" || hdiutil detach "$scratch/mnt"; fi
  rm -rf "$scratch"
}
trap cleanup EXIT
mkdir "$scratch/mnt"
if diskutil image attach --help >/dev/null 2>&1; then
  diskutil image attach --readOnly --nobrowse --mountPoint "$scratch/mnt" "$DMG"
else
  hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$scratch/mnt" "$DMG"
fi
mounted=1
[[ -d "$scratch/mnt/Font Playground.app" && -L "$scratch/mnt/Applications" ]] || fail 'the DMG lacks Font Playground.app or the Applications link'
[[ $(readlink "$scratch/mnt/Applications") == /Applications ]] || fail 'the DMG Applications link does not point to /Applications'
# Filesystem metadata is not a user-visible payload item.
count=$(find "$scratch/mnt" -mindepth 1 -maxdepth 1 ! -name '.*' | wc -l | tr -d ' ')
[[ "$count" -eq 2 ]] || fail "the DMG holds $count items instead of 2"
"$scratch/mnt/Font Playground.app/Contents/MacOS/Font Playground" --self-test --require-embedded-engine
diskutil eject "$scratch/mnt" || hdiutil detach "$scratch/mnt"
mounted=0
# Name the DMG without its folder so `shasum -c` works next to a downloaded copy.
(cd "$(dirname "$DMG")" && shasum -a 256 "$(basename "$DMG")") > "$DMG.sha256.tmp"
python3 - "$DMG.sha256.tmp" "$DMG.sha256" <<'PY'
import os, sys
with open(sys.argv[1], 'rb') as stream:
    os.fsync(stream.fileno())
os.replace(sys.argv[1], sys.argv[2])
PY
kind=notarized
[[ $adhoc -eq 0 ]] || kind=adhoc
size=$(du -m "$DMG" | awk '{print $1}')
echo "release: $DMG ($size MB, $kind)"
