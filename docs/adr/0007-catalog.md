# ADR-0007: Catalog = CoreText enumeration + helper scan, filtered and deduped

- **Status:** accepted (2026-09-29)
- **Evidence:** audit `CATALOG-1`, `CATALOG-2`, `CATALOG-M1`, `CATALOG-5`…`CATALOG-7`, `CRIT-5`, `CRIT-6`, `CRIT-9`, `NATIVE-M2`

## Decision
- **Files:** the union of three sources:
  - `CTFontManagerCopyAvailableFontURLs()` plus the `CTFontCollectionCreateFromAvailableFonts` descriptors (file URLs only).
  - A recursive walk of `/System/Library/Fonts`, `/Library/Fonts` and `~/Library/Fonts`. A binary linked against SDK ≥ 26 gets only menu-visible fonts from CoreText: 265 files instead of 430 on the audit Mac, missing Times, LastResort, Hiragino Kaku Gothic Pro, STIX and others (verified).
  - The user's extra folders. The folder walk skips AppleDouble `._*`, `__MACOSX`, `.Trashes`, and package directories (`.app`, `.bundle`, `.framework`), follows symlinked folders once, and has cycle protection.
- **Faces:** from `fpengine scan`, cached by `(path, size, mtime)` in `~/Library/Caches/<bundle-id>/`. The cache is pruned of vanished paths on every scan.
- **Filter:** hide faces whose family or PostScript name starts with `.`. Mark, but keep, faces CoreText hides from menus. Mark faces disabled in Font Book.
- **Dedupe:** by PostScript name. Prefer the descriptor with the highest `kCTFontPriorityAttribute`, read from the collection descriptors (AssetsV2 = 60000, PrivateFrameworks = 10000 for PingFang). Resolving the name through CoreText would be a name lookup, which is forbidden. Otherwise prefer files outside `/System/Library/PrivateFrameworks`.
- **Change observation:** `kCTFontManagerRegisteredFontsChangedNotification` on the distributed center, debounced. Plus an incremental update after the app's own install or uninstall.
- **Downloadable fonts:** v1 has "Get more fonts…", which opens Font Book. In-app download is an optional WP (WP-404).

## Consequences
- PingFang and the other AssetsV2 fonts appear (the Chinese list goes from 10 to 37 families on the audit Mac), and `.LastResort` never gets suggested.
