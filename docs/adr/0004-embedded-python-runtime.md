# ADR-0004: Embedded Python runtime: python-build-standalone 3.12

- **Status:** accepted (2026-09-29)
- **Evidence:** audit `TOOLING-1`, `TOOLING-M2`, `NATIVE-M4`

## Decision
- Embed a pinned **python-build-standalone** CPython 3.12 (aarch64-apple-darwin, `install_only_stripped`), verified by SHA-256. It is **physically at `Font Playground.app/Contents/Resources/fpengine/`**, with `Contents/Helpers/fpengine` as a relative symlink to it. codesign rejects the runtime's dotted directories (`lib/python3.12`, `*.dist-info`) under `Contents/Helpers` (verified during spec writing). About 80 MB on disk, about 30 MB compressed; the WP-203 budget is 85 MB.
- Install `fpengine` and its locked dependencies (`fonttools[unicode]`, `skia-pathops`) into that runtime from `engine/uv.lock` as **non-editable** wheels, and precompile them to `.pyc`.
- Invoke it with `Contents/Helpers/fpengine/bin/python3 -I -B -m fpengine`. `-B`, not `PYTHONDONTWRITEBYTECODE`, prevents bytecode writes under `-I`.
- No PyObjC in the helper. CoreText work happens in Swift.
- Don't use PyInstaller or py2app. There is no editable-install trap, and there is no GUI bootloader to worry about.
- Every Mach-O in the runtime is signed inside-out with Developer ID, the hardened runtime and a timestamp. No entitlements (ADR-0010). **Ad-hoc builds sign the helper's Mach-Os without `--options runtime`**: under library validation, ad-hoc code fails to import extensions with "different Team IDs" (verified).
- Notarization of Mach-O files under `Contents/Resources` is expected to work but has not been verified with a Developer ID. WP-601 must dry-run notarization early.

## Consequences
- `scripts/build-helper-runtime.sh` is part of the app build (WP-203), and CI caches its output.
- Updating Python means updating a pinned URL and checksum.
