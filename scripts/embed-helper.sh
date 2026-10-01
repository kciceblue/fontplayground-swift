#!/bin/bash
set -euo pipefail
src=${FP_HELPER_RUNTIME_DIR:-$SRCROOT/../build/helper/fpengine}
res="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/fpengine"
contents="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
link="$contents/Helpers/fpengine"
if [[ ! -x "$src/bin/python3" ]]; then
  if [[ "$CONFIGURATION" == Release ]]; then
    echo "error: helper runtime missing at $src; run 'make helper-runtime' (WP-203)" >&2
    exit 1
  fi
  echo "warning: helper runtime not found at $src; the app will use FP_ENGINE_PYTHON" >&2
  rm -rf "$res" "$link"
  exit 0
fi
mkdir -p "$res" "$(dirname "$link")"
rsync -a --delete "$src/" "$res/"
identity=${EXPANDED_CODE_SIGN_IDENTITY:--}
[[ -n "$identity" ]] || identity=-
args=(--force --sign "$identity")
# Xcode can supply a certificate hash; its display name identifies Developer ID.
if [[ ${EXPANDED_CODE_SIGN_IDENTITY_NAME:-$identity} == 'Developer ID Application:'* ]]; then
  args+=(--timestamp)
else
  args+=(--timestamp=none)
fi
[[ "$identity" == - ]] || args+=(--options runtime)
for kind in library executable; do
  while IFS= read -r -d '' binary; do
    description=$(file -b "$binary")
    [[ "$description" == *Mach-O* ]] || continue
    if [[ "$kind" == executable ]]; then
      [[ "$description" == *executable* ]] || continue
    else
      [[ "$description" == *executable* ]] && continue
    fi
    if [[ $(lipo -archs "$binary") != arm64 ]]; then
      lipo -thin arm64 -output "$binary.thin" "$binary"
      mv "$binary.thin" "$binary"
    fi
    # Ad-hoc helper code must not use runtime: pathops otherwise fails library validation.
    codesign "${args[@]}" "$binary"
  done < <(find "$res" -type f -print0)
done
ln -sfn ../Resources/fpengine "$link"
for location in "$contents/MacOS" "$contents/Frameworks"; do
  [[ -d "$location" ]] || continue
  invalid=$(find "$location" -type d -name '*.*' -print)
  [[ -z "$invalid" ]] || { echo "error: dotted directories in code location: $invalid" >&2; exit 1; }
done
