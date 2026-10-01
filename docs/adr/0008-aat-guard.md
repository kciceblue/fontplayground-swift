# ADR-0008: Apple AAT shaping is detected and guarded, not carried over

- **Status:** accepted (2026-09-29)
- **Evidence:** audit `ENGINE-2`, `NATIVE-6`, `NATIVE-M1`, `UI-M2`, `ENGINE-7`

## Context
189 faces (84 families) on a stock Mac have `morx` but no `GSUB`. They include Geeza Pro, Devanagari MT and Thonburi. Merging them keeps no shaping, so Arabic comes out unjoined and Indic without reordering. No engine option can merge `morx`.

## Decision
- `fpengine scan` reports each face's OpenType script tags (GSUB and GPOS `ScriptList`) and AAT flags (`morx`, `kerx`, `kern` v1, `trak`).
- **Per script, not per group.** A face can shape a Unicode script if the script needs no complex shaping, or if the face's OpenType tables carry a script tag that serves it. The table of tags is in `docs/specs/engine-metadata.md`.
  - GSUB is required for Arabic, Indic, Khmer, Myanmar and similar.
  - GPOS alone suffices for the marks-only scripts (Hebrew, Thai, Lao, Thaana).
- Characters a face maps but cannot shape are its **`unshaped`** set. They are left out of planning (warning `unshaped_left_out`), so a font with incidental complex coverage stays usable for its other scripts. Examples: Lucida Grande for Hebrew points, Arial Unicode MS for Thai.
- The picker hides fonts that don't shape a complex group (Arabic, Indic, Southeast Asian, Hebrew with marks). A toggle shows them greyed out, with the reason.
- `forge` returns the **error** `aat_unsupported_script` only when an explicit rule assigns a complex group to a face that shapes none of that group. It returns **warnings** for lost AAT ligatures, kerning or tracking on simple scripts.
- **CoreText nuance** (verified during spec writing): CoreText joins Arabic from presentation forms when a font has *no GSUB at all*. It draws unjoined letters when a GSUB exists without an `arab` script, which is the shape of a merged result. The guard is therefore always needed.
- Suggestions offer OpenType alternatives that ship with macOS.

## Consequences
- Some beloved Apple fonts can't be used for Arabic or Indic. The UI says why.
