# ADR-0009: Install = copy into ~/Library/Fonts

- **Status:** accepted (2026-09-29)
- **Evidence:** audit `INSTALL-1`…`INSTALL-14`, `INSTALL-M1`…`INSTALL-M3`

## Decision
- **Install:**
  1. Validate the file with `CTFontManagerCreateFontDescriptorsFromURL`: it must return exactly the expected PostScript name.
  2. Stage it as a dot-file in `~/Library/Fonts` (the same volume).
  3. Rename it into place.
  4. Move a previous copy to the Trash, only if it is one of ours. Update writes the new copy under a new file name, and never renames over or overwrites in place.

  fontd activates the file and notifies other apps. No `CTFontManagerRegister…` call is made in production.
- **Ours** means the file carries the forged-font marker (see engine-metadata spec) **and** is listed in `~/Library/Application Support/<bundle-id>/installed.json` with a matching size and SHA-256. The app never deletes or overwrites any other file.
- **Uninstall** moves the file to the Trash.
- **Conflicts** are checked through CoreText against family names (including localised ones), full names and PostScript names across all registered fonts, including AssetsV2 and FontServices.
- There is no "All users" (`/Library/Fonts`) install.

## Consequences
- Works unsandboxed with no entitlements. Tests use a temporary folder and process scope.
