#!/bin/bash
# Keep setup informative; app builds require the complete native toolchain.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/tool-versions.env"

warn=false
if [[ "${1:-}" == --warn ]]; then warn=true; shift; fi
if [[ $# != 0 ]]; then echo "usage: $0 [--warn]" >&2; exit 2; fi
problems=()
xcode_version=""
xcodegen_version=""
if xcode_output=$(xcodebuild -version 2>/dev/null); then
    xcode_version=$(awk '/^Xcode / {print $2; exit}' <<< "$xcode_output")
fi
if [[ -z "$xcode_version" ]]; then
    problems+=("Xcode not found. Install Xcode ${XCODE_MIN_MAJOR} or newer from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app")
elif [[ "${xcode_version%%.*}" -lt "$XCODE_MIN_MAJOR" ]]; then
    problems+=("Xcode $xcode_version is too old: Font Playground needs Xcode ${XCODE_MIN_MAJOR} or newer (docs/architecture.md §7).")
fi
if xcodegen_output=$(xcodegen --version 2>/dev/null); then
    xcodegen_version=$(awk '/Version: / {print $2; exit}' <<< "$xcodegen_output")
fi
if [[ -z "$xcodegen_version" ]]; then
    problems+=("xcodegen not found: brew install xcodegen")
elif [[ "$(printf '%s\n%s\n' "$XCODEGEN_MIN_VERSION" "$xcodegen_version" | sort -V | head -1)" != "$XCODEGEN_MIN_VERSION" ]]; then
    problems+=("xcodegen $xcodegen_version is older than ${XCODEGEN_MIN_VERSION}: brew upgrade xcodegen")
fi
if ! swift format --version >/dev/null 2>&1; then
    problems+=("swift-format not found: it ships with Xcode 16 and later; check xcode-select -p")
fi
if [[ ${#problems[@]} -gt 0 ]]; then
    prefix=error
    if $warn; then prefix=warning; fi
    for problem in "${problems[@]}"; do printf '%s: %s\n' "$prefix" "$problem" >&2; done
    if $warn; then exit 0; else exit 1; fi
fi
printf 'toolchain: Xcode %s, xcodegen %s\n' "$xcode_version" "$xcodegen_version"
