# ADR-0012: Licence handling of source fonts

- **Status:** accepted (2026-09-29); amended 2026-09-30 to keep the sources' notices in the forged font
- **Evidence:** audit `ENGINE-5`, `CRIT-3`

## Decision
- **Output fsType** is the most restrictive of the materials that contribute glyphs: restricted (0x2) > preview & print (0x4) > editable (0x8) > installable (0). The engine never raises permissions.
- **Licence class** is read from name IDs 13/14 plus copyright and vendor:
  - `open` (OFL or Apache)
  - `apple-sla`: an Apple copyright or vendor, or a file under `/System/Library` without an open licence
  - `microsoft-product`: the "Microsoft supplied font… Microsoft product" wording, or a path inside an Office app bundle
  - `unknown`
- The report and the Save/Install UI show one line for each non-open class, for example "Bundled with macOS: licensed for use on this Mac only; do not distribute the forged font."
- **Source notices stay in the font.** A forged font is a modified copy of its sources. Licences such as the SIL Open Font License and Apache-2.0 require a modified copy to keep the original copyright notice, and removing copyright management information can be unlawful in itself (for example US 17 U.S.C. §1202). So each contributing material's notices are carried into the output's name table, each once, in material order, one per line:
  - name ID 0 (copyright) keeps "Forged with Font Playground from: …" as its first line, so forged fonts are still recognised, and the sources' copyright notices follow;
  - name IDs 7 (trademark) and 14 (licence URL) hold the sources' values;
  - name ID 13 keeps the licence-class notes as its first line and adds the sources' licence descriptions.
  
  Re-forging a forged font carries the notices it holds, without repeating the marker. Copyright notices are kept first. A notice that doesn't fit in the name table (64 KB) is left out whole, never truncated, and the report says so.
- The app never refuses a build for licence reasons. It informs.

## Consequences
- The rules above are specified in `docs/specs/engine-metadata.md` (WP-110 Design §5 and §5a).
- The README and the About window carry a short licence note. They also say that Font Playground doesn't include or sell fonts, and the README, Help and Acknowledgements disclaim warranty, affiliation with font vendors, and legal advice.
