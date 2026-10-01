#!/bin/bash
# codesign-retry.sh retries timestamp refusals only, and gives up after five attempts.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/codesign" <<'FAKE'
#!/bin/bash
echo "$*" > "$FAKE_COUNT.args"
count=$(($(cat "$FAKE_COUNT" 2>/dev/null || echo 0) + 1))
echo "$count" > "$FAKE_COUNT"
if ((count <= FAKE_FAILURES)); then echo "$FAKE_MESSAGE" >&2; exit 1; fi
FAKE
chmod +x "$scratch/codesign"
refused='x: The timestamp service is not available.'
# macOS's bash 3.2 doesn't stop for a failed [[ ]] under set -e, so every check exits by itself.
expect() { [[ "$1" == "$2" ]] || { echo "test_release_codesign_retry: expected '$2', got '$1'" >&2; exit 1; }; }
run() {
  rm -f "$scratch/count"
  PATH="$scratch:$PATH" FAKE_COUNT="$scratch/count" FAKE_FAILURES=$1 FAKE_MESSAGE=$2 CODESIGN_RETRY_DELAY=0 \
    "$ROOT/scripts/codesign-retry.sh" --force --timestamp --sign - x 2>/dev/null
}
run 2 "$refused"
expect "$(cat "$scratch/count")" 3
if run 1 'x: errSecInternalComponent'; then exit 1; fi
expect "$(cat "$scratch/count")" 1
if run 9 "$refused"; then exit 1; fi
expect "$(cat "$scratch/count")" 5
# The v1.0.0 tag run: a fleet job's fresh HOME has no keychain search list, so CI names its keychain.
run 0 ''
expect "$(cat "$scratch/count.args")" '--force --timestamp --sign - x'
CODESIGN_KEYCHAIN="$scratch/release.keychain-db" run 0 ''
expect "$(cat "$scratch/count.args")" "--keychain $scratch/release.keychain-db --force --timestamp --sign - x"
echo 'test_release_codesign_retry: OK'
