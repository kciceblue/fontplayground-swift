# Audit prototypes (non-normative)

Throwaway code written during the 2026-09-29 macOS audit (`docs/research/macos-audit.md`) to prove that a fix works. **The specs in `docs/specs/` are normative. Where a prototype and a spec differ, the spec wins.** Several prototypes have known defects that the specs fix; they are listed below. Read them for technique, never copy them blindly.

| File | What it shows | Superseded by | Known problems |
|---|---|---|---|
| `engine-fixes.diff` | cmap normalisation after subsetting (ENGINE-1), `locl`/`aalt` lookup-sharing closure (ENGINE-3), per-glyph PathOps fallback (ENGINE-4), against the reference engine | engine-correctness.md WP-101, WP-104, WP-105 | No format 4 overflow handling (N-1); no `Issue` reporting |
| `macos-installer-prototype.patch` | A Python `MacInstaller` for the original Qt app: copy into a fonts folder, CoreText conflict lookups, Trash on uninstall, process-scope tests | mac-services.md WP-403 | **Deletes non-forged same-name files** (INSTALL-M1); removes the old copy before the new one is in place (INSTALL-M2); no pre-install validation (INSTALL-M3); misses conflicts between two of the app's own fonts (INSTALL-5 verifier) |
| `coretext-enumerator.py` | Listing font files through `CTFontManagerCopyAvailableFontURLs` and filtering hidden faces | mac-services.md WP-401, ADR-0007 | Linked against SDK ≥ 26, that API lists only menu-visible fonts (it misses Times, LastResort…); the spec adds a folder walk and priority-based dedupe |
| `forge-helper.py` | The minimal JSON Lines forge helper that the Swift prototype drove | helper.md WP-201, contracts §4–5 | Not the v1 protocol: no envelope, no `hello`, no cancel handling |
| `swift/shell.swift` | Swift `Process` + `Pipe` driving the helper, decoding progress, then CoreText drawing the forged font (process scope) | helper.md WP-204, mac-services.md WP-402 | Registers the font (the app uses URL descriptors); no cancel or timeouts |
| `swift/nofallback.swift` | The `[LastResort]` cascade list stopping CoreText font fallback (ADR-0011) | mac-services.md WP-402 | Needs the cascade on URL-created descriptors too |
| `swift/embolden.swift` | CGPath stroke + union as a possible Swift replacement for skia-pathops (NATIVE-4 option) | — (not planned in v1) | Evaluation only |
| `apple-font-inventory-macos27.jsonl` | One JSON record per face for 879 faces under `/System/Library/` on macOS 27.0 (26A428): tables, fsType, glyph and code-point counts, script-group counts, support status | Data for WP-106 (sanity thresholds), WP-107 (AAT counts), WP-111 (scenario expectations) | One Mac, one macOS version; downloaded AssetsV2 fonts vary per machine |
