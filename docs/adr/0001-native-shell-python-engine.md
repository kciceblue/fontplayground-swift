# ADR-0001: Native Swift shell with the Python fontTools engine as a helper

- **Status:** accepted (2026-09-29)
- **Evidence:** audit `NATIVE-1`…`NATIVE-11`, `NATIVE-M1`, `CRIT-1`

## Context
The original app is PySide6 + fontTools. The audit compared four routes on this Mac:
1. Qt with a macOS layer: 3.5–5 person-weeks, reuses about 95% of the code.
2. A SwiftUI/AppKit + CoreText shell with the Python engine as a helper: 10–14 weeks after a 1–2 week seam.
3. A full Swift rewrite: 22–33 weeks.
4. A Rust core: 17–25 weeks.

No Swift, C or Rust library replaces `fontTools.merge`. HarfBuzz `hb-subset` matches the subset closure, but nothing does merging. Qt draws with its bundled HarfBuzz, not CoreText. So a Qt preview can show correct Arabic joining that the forged font will not have in any Mac app (`NATIVE-M1`), which breaks the app's core promise. Qt/PyInstaller executables are also linked against the macOS 15 SDK, which gives the app the pre-26 look (`CRIT-1`).

## Decision
Build a native SwiftUI/AppKit app that renders with CoreText. Keep the fontTools engine in Python, run as a bundled out-of-process helper (`fpengine`). Do not ship Qt.

## Consequences
- The preview is honest by construction (CoreText, no fallback).
- The model logic (`ui/model.py`, `smart.py`, `languages.py`, `mix.py`) is ported to Swift, using the original tests and generated conformance fixtures as the spec.
- The app embeds a Python runtime (about 80 MB on disk, about 30 MB compressed, measured in the WP-203 spec work). We accept this.
- An engine rewrite is deferred. It becomes worth considering only if App Store, iPad or a no-Python binary becomes a goal. Note that iPadOS cannot install fonts generated at runtime anyway (`NATIVE-M6`).
