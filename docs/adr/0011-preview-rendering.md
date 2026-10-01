# ADR-0011: Preview rendering with CoreText, no fallback; planner parity via conformance fixtures

- **Status:** accepted (2026-09-29)
- **Evidence:** audit `NATIVE-3` (LastResort cascade verified), `NATIVE-M1`, `NATIVE-M3`, `CATALOG-4`, `ENGINE-6`

## Decision
- Material fonts are `CTFont`s created from URL descriptors, never registered and never looked up by name. The cascade list is `[LastResort]`, so a missing glyph shows as the LastResort box instead of borrowing from another font. That also applies to URL-created descriptors.
- Variations: the engine instances every non-`wght` axis at its fvar default (engine-correctness WP-104 notes). So the preview pins those axes, including `opsz`, to the same defaults. It applies `wght` as the engine does. Automatic optical sizing is backlog B-1.
- The preview text is an `NSAttributedString` with one run per `source_of` segment, drawn by an `NSTextView` (TextKit 2) wrapped for SwiftUI.
- `source_of` is ported to Swift (`FPCore.Planner`). Parity with `fpengine.planner.source_of` is enforced by conformance fixtures in `spec/fixtures/planner/*.json`.
- After a build, the preview draws the built file (a URL descriptor) and shows a small "Built font" badge.

## Consequences
- No Python is needed for keystroke-level preview updates.
- Any change to the engine planner must regenerate the fixtures (`make conformance`), and CI fails if they drift.
