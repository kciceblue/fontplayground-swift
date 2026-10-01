# Engine correctness on Apple fonts

> Scope: WP-101, WP-102, WP-103, WP-104, WP-105, WP-111 · Env: linux (WP-101 to WP-105), macos (WP-111) · Architecture refs: docs/architecture.md §1 (goal 3), §2 (`fpengine`), §3, §8 · ADRs: 0001, 0002, 0003, 0008, 0011, 0012

## Context

The engine turns a `ForgeSpec` into one TrueType font in six stages: validate, plan, prepare, merge, finish and verify (`reference/fontplayground-py/fontplayground/engine/forge.py:32`). `prepare()` makes one merge-ready part per material (`reference/fontplayground-py/fontplayground/engine/prepare.py:137`). It loads the face (`prepare.py:30`), instances a variable font (`prepare.py:35`) and subsets to the planned code points with every feature except `locl` (`prepare.py:58-75`). It then converts legacy `kern` to GPOS (`kern.py:66`), converts CFF to `glyf` (`prepare.py:78`), applies synthetic bold (`synth_bold.py:16`), scales (`prepare.py:123`), strips the tables outside `KEEP_TABLES` (`prepare.py:19`, `:131`) and saves. `merge_fonts()` runs `fontTools.merge.Merger` (`merge.py:21`). `finish()` subsets again and rewrites names, OS/2 and metrics (`merge.py:112`). `verify()` reloads the file and compares the code points (`merge.py:129`).

On Windows fonts this works. On the Mac's own fonts it fails in the ways below. The audit (`docs/research/macos-audit.md`, section `ENGINE-*`) found them. This spec fixes them, then locks them with a real-font suite.

| Finding | Severity | What the reference does on macOS | Root cause | WP |
|---|---|---|---|---|
| ENGINE-1 | blocker | Helvetica Neue + PingFang SC fails at verify after about 22 s with "coverage mismatch: 2083 missing". 21 faces in 9 families are affected. | `fontTools.merge` reads only format 4 `(3,1) (0,3) (0,4) (0,6)` and format 12 `(3,10) (0,4) (0,6)` subtables (`fontTools/merge/cmap.py`, `_CmapUnicodePlatEncodings`). Helvetica Neue, Cochin and Didot have only `(0,1)` format 4, and Geneva has only `(0,3)` format 12. | 101 |
| **N-1** (new, see below) | major | Avenir Next + Hiragino Sans W3 (Han, Kana) + Apple SD Gothic Neo (Hangul) fails at finish with `struct.error: 'H' format requires 0 <= number <= 65535`. | The merged `(3,1)` format 4 subtable is larger than 65,535 bytes, the limit of its `uint16` length field. | 101 |
| ENGINE-M2 | minor | Geneva, Cochin (all 4 faces) and AppleMyungjo fail in prepare with "unpack requires a buffer of 2 bytes". | The subsetter decompiles Apple's `bloc` table through the EBLC reader and crashes. `drop_tables` lists EBDT/EBLC but not `bdat`/`bloc`/`bhed`. | 102 |
| ENGINE-12 | minor | Bitmap strikes (`bdat`, `EBDT`) are dropped without a word. | No report line. | 102 |
| ENGINE-M1 | major | Courier ×4, AppleGothic, AppleMyungjo, and the downloadable Hei, Kai and GungSeo fail. As main font: `[finish] KeyError: "'OS/2' table not found"`. As secondary: `[merge] TypeError: '>' not supported between instances of 'NotImplementedType' and 'int'`. | No OS/2 table. | 103 |
| ENGINE-3 | major | PingFang SC keeps 48,124 glyphs instead of 38,054. A 4-script pan-CJK mix reaches 64,363 glyphs, 1,172 below the limit. With `uharfbuzz` installed, the forge never finishes. | `cv08`/`cv09` reuse PingFang's `locl` lookups, and `aalt` (27,112 alternates) pulls in the rest. `hb.repack` fails and loops on each overflow. | 104 |
| ENGINE-4 | major | Helvetica Neue Bold + PingFang SC Regular at weight 700 fails with "PathOpsError: operation did not succeed". | `pathops.op` fails on 2 of 36,717 glyphs, and one bad glyph aborts the whole forge. | 105 |
| all `ENGINE-*` | — | Nothing tests real Mac fonts (CRIT-7). | Only synthetic fixtures. | 111 |

**N-1** was found while measuring the WP-111 matrix for this spec. It is not in the audit digest. It reproduces on the unmodified reference engine with the fonts above, and on Linux with the synthetic fixture in AC-101-4. It is in scope for WP-101 because the fix lives in the same cmap builder.

**Evidence base.** Every glyph count, timing, size and closure figure in this spec's tables was re-measured on the reference machine (§Shared definitions 6). Quotes attributed to the audit are cited by finding ID. The measurements used a scratch prototype that applies all five fixes exactly as designed here. The 66 ported reference engine tests (`test_forge`, `test_prepare`, `test_synth_bold`, `test_spec`, `test_planner`, `test_scripts`, `test_fixtures`, `test_face`) pass on that prototype unchanged. Every new synthetic fixture fails on the reference and passes on the prototype, and the WP-111 matrix numbers come from it.

## Shared definitions

### 1. Module layout (assumption about WP-002)

WP-002 copies `reference/fontplayground-py/fontplayground/engine/*.py` to `engine/src/fpengine/*.py`, flat, as ADR-0011's `fpengine.planner` implies. It ports `catalog/face.py` to `engine/src/fpengine/face.py`, the fixtures to `engine/tests/fixtures.py` (`build_font`, `cps`, `glyph_name`, `fake_face`) and the `font_dir` fixture to `engine/tests/conftest.py`. The test examples below import them the way the reference does (`from tests.fixtures import build_font, cps`). If WP-002 chose other module names, apply each change to the equivalent module and note it under "Spec deviations".

| Reference | `fpengine` module | Edited by |
|---|---|---|
| `engine/prepare.py` | `engine/src/fpengine/prepare.py` | 101, 102, 103, 104, 105 |
| `engine/merge.py` | `engine/src/fpengine/merge.py` | 101 (`finalize_cmap`), 104 (`merge_fonts`) |
| `engine/forge.py` | `engine/src/fpengine/forge.py` | 101 (issues plumbing, `finalize_cmap` call), 105 (bold size check) |
| `engine/spec.py` | `engine/src/fpengine/spec.py` | 101 (`Issue`, `ForgeReport.issues`) |
| `engine/synth_bold.py` | `engine/src/fpengine/synth_bold.py` | 105 |
| `catalog/face.py` | `engine/src/fpengine/face.py` | 103 (one-line weight fallback) |

### 2. The prepare and forge pipeline after this spec (normative order)

`prepare(material, codepoints, target_upem, weight, scale, workdir, index) -> PreparedFont`:

1. `font = load_face(material)`: unchanged. Right after it, engine-metadata.md WP-107 §6 records the AAT losses from the source font, before any table is added or removed.
2. `synthesized = ensure_os2(font)`: **WP-103**.
3. If the face is variable: `instance_variable(font, weight)`. On the existing GPOS-retry path (`prepare.py:143-158`) the font is reloaded, so call `ensure_os2(font)` again after the reload.
4. `dropped = drop_unused_tables(font)`: **WP-102**. Then record the issues in this order: `os2_synthesized` (WP-103, if step 2 or the call after the reload in step 3 added a table), then `bitmaps_dropped` (WP-102).
5. `subset_font(font, codepoints)` with the new `kept_features()`: **WP-104**.
6. `normalize_cmap(font)`: **WP-101**.
7. `kern_to_gpos(font)`: unchanged.
8. `cff_to_glyf(font)` for CFF outlines: unchanged.
9. Synthetic bold: `embolden()` returns a `BoldResult`, and its issues are recorded: **WP-105**.
10. `scale_font(...)`, then `strip_tables(font)`: unchanged. `strip_tables` stays as a guard.
11. `disable_hb_repacker(font)`: **WP-104**. Then `font.save(...)`.

`forge()`: validate, plan, prepare (as above), then `merge_fonts()`, which disables the repacker on the merged font (**WP-104**). Then the glyph-limit check, then `finish()` (unchanged by this spec), then `finalize_cmap(font)` (**WP-101**), both inside the existing `try` that maps failures to stage `finish` (`forge.py:65-76`). Then save, then `verify()`. Then the forge-level issues are collected into `forge_issues`: `cmap_format4_partial` (**WP-101**), then the synthetic-bold size check (**WP-105**). The last step is `_report(..., forge_issues)` (**WP-101** plumbing, §3).

### 3. `Issue` and the report plumbing (normative)

`contracts.md` §4 fixes the JSON shape of `ForgeReport.issues`, and `spec/protocol/forge-report.schema.json` requires all five keys. The engine type below produces it. It is **the same type** as engine-metadata.md §S5 `Issue`: same name, same fields in the same order, same message convention. **WP-101 lands it** (WP-101 is the first to merge in wave 3, and it emits `cmap_format4_partial`). WP-102, WP-103 and WP-105 also emit issues. If WP-101 is not yet on `main` when they are implemented, they add this block **verbatim**, and on rebase they keep `main`'s copy. The helper (WP-201, which serialises it with `dataclasses.asdict`) and engine-metadata (WP-107, WP-110, which reuse it per their §S5 "reuse it and don't duplicate it") do not define another.

```python
# engine/src/fpengine/spec.py
from typing import Literal

IssueSeverity = Literal["warning", "error"]


@dataclass(frozen=True)
class Issue:
    """One machine-readable report item (contracts.md §4 `issues`, engine-metadata.md §S5).

    `message` is the full sentence. For a per-material issue it is f"{display_name}: {note}", exactly the line
    that also appears in ForgeReport.warnings; for a report-level issue (material_index None) it is the note itself."""
    code: str
    severity: IssueSeverity
    material_index: int | None
    group: str | None
    message: str

    def to_dict(self) -> dict[str, object]:
        """Keys in schema order; equal to dataclasses.asdict(self)."""
        return {"code": self.code, "severity": self.severity, "material_index": self.material_index,
                "group": self.group, "message": self.message}


@dataclass
class ForgeReport:                      # existing fields unchanged, in the same order
    materials: list[MaterialReport]
    total_codepoints: int
    total_glyphs: int
    warnings: list[str]
    output_path: str
    issues: list[Issue] = field(default_factory=list)   # new, defaulted (engine-metadata §S5 adds more fields after it)
```

```python
# engine/src/fpengine/prepare.py
@dataclass
class PreparedFont:                     # existing fields unchanged
    path: str
    upem: int
    warnings: list[str] = field(default_factory=list)            # notes, as in the reference (no name prefix)
    issues: list[Issue] = field(default_factory=list)            # WP-101 (plumbing)
    dropped_tables: list[str] = field(default_factory=list)      # WP-102
    bold_added_bytes: int = 0                                    # WP-105


def _note(warnings: list[str], issues: list[Issue], code: str, note: str, index: int, display_name: str) -> None:
    """Every per-material issue is also a human-readable note (the text report stays complete)."""
    warnings.append(note)
    issues.append(Issue(code, "warning", index, None, f"{display_name}: {note}"))
```

`prepare()` calls `_note(warnings, issues, code, note, index, face.display_name)`, where `warnings`/`issues` are the lists it later puts into `PreparedFont`.

Rules for `forge._report()` (reference `forge.py:19-29`). Its signature becomes `_report(spec, p, prepared, n_cps, n_glyphs, out, forge_issues: Sequence[Issue] = ()) -> ForgeReport`:

- **Notes.** For material `i`, `notes = pf.warnings`, then the reference's restricted and "contributes no characters" notes (`forge.py:23-26`), then the note of every issue in `forge_issues` whose `material_index == i` (only `bold_size_doubled` in this spec). The note of a per-material issue is its `message` with the `f"{display_name}: "` prefix removed. `MaterialReport.warnings = notes`.
- **Warnings.** `ForgeReport.warnings` is, in material order, `f"{display_name}: {note}"` for every note (as the reference), followed by the `message` of every report-level issue (`material_index is None`) in `forge_issues`.
- **Issues.** `all = [*pf.issues for each pf in material order, *forge_issues]`, then `ForgeReport.issues = sorted(all, key=lambda x: (x.material_index is None, x.material_index or 0))`. The sort is stable, so within one material the order is the order of raising: `os2_synthesized`, `bitmaps_dropped`, `synthetic_bold`, `bold_glyphs_skipped`, then `bold_size_doubled`. Report-level issues come last. This matches engine-metadata.md §S5 "Issue order" (sorted by `material_index`, report-level last). Its §S6 codes, once WP-107/WP-110 add them, come after this spec's codes within a material.
- `ForgeReport.as_text()` is unchanged. Issues reach the text through `warnings`.

### 4. Issue codes introduced by this spec

All have severity `"warning"` and `group = None`. The table gives the **note**. A per-material issue's `message` is `f"{display_name}: {note}"`, where `display_name` is the material's `face.display_name` (the same name as `MaterialReport.name`). A report-level issue's `message` is the note.

| Code | WP | `material_index` | Exact note (Python f-string) |
|---|---|---|---|
| `cmap_format4_partial` | 101 | `None` | `f"{n:,} characters from U+{first:04X} up are only in the font's full Unicode character map; current apps read it, but very old apps that read only the basic map will not show them"` |
| `bitmaps_dropped` | 102 | material | `f"embedded bitmaps ({', '.join(tags)}) are not kept; the forged font draws outlines at every size"` (`tags` sorted) |
| `os2_synthesized` | 103 | material | `"has no OS/2 table; one was made from its other tables, so its embedding permissions are unknown"` |
| `synthetic_bold` | 105 | material | `f"synthetic bold (+{delta})"`: the reference string, byte for byte |
| `bold_glyphs_skipped` | 105 | material | `f"{n:,} of {total:,} glyphs could not be made bolder and keep their regular outline ({shown})"`, where `shown` is the first 5 names joined by `", "`, followed by `", …"` (U+2026) when `n > 5` |
| `bold_size_doubled` | 105 | the material that added the most bytes (the lowest index on a tie) | `f"synthetic bold more than doubled the file size ({size(without)} without it, {size(final)} with it); a heavier weight of this font, if you have one, gives a smaller, better-looking result"` |

`size(n)` means `f"{n / 1_000_000:.1f} MB"` when `n >= 1_000_000`, else `f"{max(1, round(n / 1000))} KB"` (decimal units, as Finder shows them).

### 5. Test conventions for WP-101 to WP-105

- Each WP adds **its own test module**, and keeps its fixture builders inside that module or a module-local helper. Do not add them to the shared `engine/tests/fixtures.py`. Five wave-3 PRs editing one file would conflict.
- Every finding has a regression test named after it (AGENTS.md): `test_engine_1_…`, `test_engine_m2_…`, and so on. The docstring states what the reference did on that input (for example `reference: [finish] KeyError 'OS/2'`), so a reviewer can check that the fixture really reproduces the bug.
- **"Issue X@i with note N"** in an AC means all of: `report.issues` has an `Issue` with `code == X`, `severity == "warning"`, `material_index == i`, `group is None` and `message == f"{report.materials[i].name}: {N}"`; `N` is in `report.materials[i].warnings`; and `f"{report.materials[i].name}: {N}"` is in `report.warnings`. At `prepare()` level (no report yet) it means `N in pf.warnings` and `pf.issues` has that code with `material_index == i` and `message == f"{face.display_name}: {N}"`.
- Unless an AC says otherwise, "fixture A" is `font_dir / "A.ttf"` (`Fixture A Regular`, `cps("abc1,")`), faces are read with `fpengine.face.read_faces`, and a forge is `forge(ForgeSpec([MaterialSpec(face), …], …), tmp_path / "out.ttf")`.
- Fixtures are synthetic (`fontTools.fontBuilder`, `feaLib`, raw `DefaultTable` bytes). No font file is committed.
- Every test runs on Linux under `make engine-test`.

### 6. Reference machine for all numbers

Apple M5 Pro (15 CPU cores), 24 GB RAM, macOS 27.0, Python 3.12, fontTools 4.66.0, skia-pathops 0.9.2. One forge at a time, each in a fresh process. The timing is the `forge()` wall time and does not include interpreter start, which the helper adds (about 0.3 s). Peak RSS is `ru_maxrss` of that process. Glyph and character counts depend on the macOS font versions, and the counts below are for macOS 27.0.

---

## WP-101: Normalise cmap after subsetting

**Goal:** Every prepared part and the finished font carry Windows-Unicode cmap subtables that `fontTools.merge` reads and that always compile. Apple fonts whose only cmap is on the Unicode platform then keep every character.
**Depends on:** WP-002 · **Env:** linux · **Size:** S · **Closes findings:** ENGINE-1, N-1

### Scope
- In:
  - `build_unicode_cmap()`, `normalize_cmap()` (in prepare, right after subsetting) and `finalize_cmap()` (on the merged font after `finish()`).
  - A guard against format 4 overflow, with the `cmap_format4_partial` issue.
  - The `Issue` plumbing in §Shared definitions 3 (types, `_note`, `_report()` notes, warnings and issue order), with its tests.
- Out:
  - Symbol `(3,0)` cmaps (Webdings, Wingdings). `getBestCmap()` returns nothing for them, so their FaceRecord coverage is empty. WP-106 marks these faces unsupported and forge validation rejects them with an explicit reason (AC-101-6). Supporting symbol cmaps remains a separate cross-platform task (see backbone note: propose a backlog item).
  - Mac-platform `(1,x)` subtables. `getBestCmap()` never reads them, and they are dropped as before.
  - Scan-side coverage (`FaceRecord.coverage` is `getBestCmap()` of the source, owned by WP-106), which is unchanged.

### Touched paths
- `engine/src/fpengine/prepare.py` (edit)
- `engine/src/fpengine/merge.py` (edit: `finalize_cmap`)
- `engine/src/fpengine/forge.py` (edit: plumbing, `finalize_cmap` call)
- `engine/src/fpengine/spec.py` (edit: `Issue`, `ForgeReport.issues`)
- `engine/tests/test_cmap.py` (new)
- `engine/tests/test_issues.py` (new)

### Design

**Facts this design relies on** (fontTools 4.66, checked):
- `TTFont.getBestCmap()` prefers `(3,10) (0,6) (0,4) (3,1) (0,3) (0,2) (0,1) (0,0)`. It returns the Unicode mapping of Apple's `(0,1)`/`(0,0)` format 4 and `(0,3)` format 12 subtables.
- The subsetter keeps, in each Unicode subtable, only the requested code points (`fontTools/subset/__init__.py`, `cmap.subset_glyphs`, where `u in s.unicodes_requested`). It also drops empty subtables. A part's `getBestCmap()` after subsetting is therefore a subset of its assigned code points.
- `fontTools.merge` takes a font's format 12 over its format 4 when both are readable, and reads format 14 only as `(0,5)`.
- `CmapSubtable` format 4 `compile()` raises `struct.error` when the subtable would exceed 65,535 bytes (`_c_m_a_p.py`, `cmap_format_4.compile`). `FontBuilder.setupCharacterMap()` raises `ValueError("cmap format 4 subtable overflowed…")` in the same case.

**Interfaces** (`prepare.py` unless noted):

```python
FORMAT4_MAX_BYTES = 65535

def build_unicode_cmap(font: TTFont, best: Mapping[int, str],
                       uvs: Sequence[CmapSubtable]) -> tuple[list[CmapSubtable], int]:
    """Subtables for `best`: (3,1) fmt 4 [+ (3,10) fmt 12] [+ each fmt 14 as (0,5)].
    Returns (subtables, number of BMP code points left out of the fmt 4 subtable)."""

def normalize_cmap(font: TTFont) -> int:
    """Replace font['cmap'] subtables with build_unicode_cmap(font, font.getBestCmap() or {}, <its fmt 14 subtables>).
    Sets cmap.tableVersion = 0. Returns the omitted count."""

# merge.py
def finalize_cmap(font: TTFont) -> tuple[int, int | None]:
    """normalize_cmap() on the finished font. Returns (omitted count, first omitted code point or None)."""
```

**Algorithm (`build_unicode_cmap`):**
1. `bmp = sorted(cp for cp in best if cp <= 0xFFFF)`.
2. Build a format 4 subtable: `CmapSubtable.newSubtable(4)`, `platformID=3`, `platEncID=1`, `language=0`, `cmap={cp: best[cp] for cp in bmp}`.
3. If it does not fit, meaning `compile(font)` raises `struct.error` or returns more than `FORMAT4_MAX_BYTES` bytes, binary-search the **largest prefix** `bmp[:k]` whose format 4 subtable fits. Use that subtable, and set `omitted = len(bmp) - k`. This is deterministic. The prefix keeps the lowest code points: Latin, symbols, Kana and CJK Unified Ideographs before Hangul syllables and half/full-width forms.
4. Add a `(3,10)` format 12 subtable (`language=0`) holding **all** of `best` when any code point is above U+FFFF **or** `omitted > 0`.
5. Append each surviving format 14 subtable after setting `platformID, platEncID = 0, 5`. `language` is already 0.
6. If `best` is empty, the result is one empty `(3,1)` format 4 subtable. That compiles, and the merger accepts it.

**Where it runs:**
- In `prepare()`, immediately after `subset_font()` and before `kern_to_gpos()` (pipeline step 6). Omissions at part level are not reported. The merger reads the part's format 12, so nothing is lost.
- In `forge()`, after `M.finish(...)` and before `font.save(...)` (inside the same `try`), call `omitted, first = M.finalize_cmap(font)`. After `verify()`, if `omitted > 0`, add `Issue("cmap_format4_partial", "warning", None, None, note)` to `forge_issues` (§Shared definitions 2 and 4), with `n = omitted` and `first` the lowest code point left out of format 4. `finish()` itself is **not** edited, because WP-109 and WP-110 edit it in parallel.
- `finalize_cmap` reads the merged font's format 14 subtables (the merger writes them as `(0,5)`), so variation sequences survive the rebuild.

**Why not reorder glyphs by code point** (`fontTools.ttLib.reorderGlyphs`, which would make format 4 compact)? It rewrites every glyph ID in GSUB/GPOS/GDEF, which is a larger and riskier change. Truncating format 4 loses nothing for CoreText, DirectWrite or HarfBuzz, which all read format 12. CoreText was checked on the N-1 output: U+D55C and U+D7A3, which are only in format 12, map to glyphs through a URL descriptor.

**Performance:** without overflow, one format 4 compile per part and one for the final font, a few milliseconds. With overflow, the binary search takes about 16 compiles, under 1 s for 40,000 code points on the reference machine. The N-1 mix goes from failing to OK in 16.0 s in total.

**Non-normative reference** (the prototype that was measured):

```python
def _fits(font, mapping) -> bool:
    t = CmapSubtable.newSubtable(4); t.platformID, t.platEncID, t.language, t.cmap = 3, 1, 0, mapping
    try:
        return len(t.compile(font)) <= FORMAT4_MAX_BYTES
    except struct.error:            # fontTools packs the uint16 length before we can measure it
        return False
```

### Acceptance criteria
- **AC-101-1** `test_engine_1_mac_unicode_cmap` in `engine/tests/test_cmap.py`, parametrized over the source cmap layout `(0,1,4)`, `(0,0,4)`, `(0,3,12)` and `(0,4,12)`. The fixture is `build_font(…, cps("xyz"))` with its cmap replaced by that single subtable. The format 12 cases also map U+1F600. The test forges the fixture alone, and again as material 1 under fixture A (`cps("abc1,")`, no rules). Both forges succeed, and the output's `getBestCmap()` keys equal the union of the materials' code points. (Reference: the `(0,1,4)`, `(0,0,4)` and `(0,3,12)` cases fail at stage `verify` with "coverage mismatch".)
- **AC-101-2** `test_prepared_part_cmap_is_windows_unicode`: after `prepare()`, the saved part (`TTFont(pf.path)`) has cmap subtables whose `(platformID, platEncID, format)`, in file order (fontTools sorts them on save), are exactly `[(3,1,4)]` for a BMP-only assignment. They are `[(3,1,4), (3,10,12)]` when a non-BMP code point is assigned; the format 12 subtable then holds every mapping and the format 4 subtable only the BMP ones. An empty assignment gives `[(3,1,4)]` with 0 entries. Every subtable has `language == 0`.
- **AC-101-3** `test_uvs_subtable_kept_as_0_5`: a FontBuilder fixture maps U+0061 to `uni0061` and U+FE00 to `uniFE00`, and has `uvs=[(0x61, 0xFE00, "uni0061.alt"), (0x61, 0xFE01, None)]` (glyphs `.notdef uni0061 uni0061.alt uniFE00`). Forged alone, the output cmap has a `(0,5,14)` subtable whose `uvsDict[0xFE00] == [(0x61, "uni0061.alt")]`.
- **AC-101-4** `test_cmap_format4_overflow_keeps_every_character` (N-1). The fixture is built with FontBuilder, **without** `setupCharacterMap`. It has 8,500 code points `0x4E00 + 2*k` (`k < 8500`), each with its own rectangle glyph, and `font["cmap"]` has one `(3,10)` format 12 subtable. Each code point needs its own 8-byte format 4 segment, so a full format 4 subtable would need 8 × 8,501 + 16 = 68,024 bytes, and at most 8,188 code points fit. The forge alone succeeds. The output has a `(3,1,4)` subtable whose keys are exactly the smallest `m` code points (`0 < m < 8500`; 8,188 with fontTools 4.66) and a `(3,10,12)` subtable with all 8,500. `getBestCmap()` has all 8,500. `report.issues` contains exactly one `cmap_format4_partial`, with `material_index is None` and `group is None`, and its message equals the §Shared definitions 4 note with `n = 8500 - m` and `first = 0x4E00 + 2*m`. The same message is the last entry of `report.warnings`. (Reference: `[finish] error: 'H' format requires 0 <= number <= 65535`.)
- **AC-101-5** `test_build_unicode_cmap_prefix_is_maximal`. For the mapping of AC-101-4, the returned format 4 subtable compiles to at most 65,535 bytes, and the prefix one code point longer does not fit.
- **AC-101-6** After WP-106, `test_symbol_cmap_font_is_rejected_with_explicit_reason`: a fixture whose only cmap subtable is `(3,0)` format 4 has empty coverage and, when forged as material 1 under fixture A, raises `ForgeError(stage="validate")` with the material name and `"no Unicode characters (symbol or empty character map)"`; no output file is created. This supersedes WP-101's interim zero-contribution result because WP-106 makes empty-Unicode faces unsupported (architecture §8: no silent drops).
- **AC-101-7** In `engine/tests/test_issues.py`:
  - `test_issue_to_dict`: `list(Issue("x", "warning", 1, None, "m").to_dict())` is exactly `["code", "severity", "material_index", "group", "message"]`, and `to_dict() == dataclasses.asdict(issue)`.
  - `test_report_issues_default_empty`: a forge of fixture A alone has `report.issues == []`, and `ForgeReport([], 0, 0, [], "x").issues == []`.
  - `test_report_issue_plumbing`: `monkeypatch` wraps `fpengine.forge.prepare` so that, for material 1 of `[A, B.otf]`, it calls the real `prepare` and then `_note(pf.warnings, pf.issues, "test_code", "a note", 1, name)`. Then "issue `test_code`@1 with note `"a note"`" holds (§Shared definitions 5).
  - `test_report_issue_order`: `_report()` called directly (spec of two `fake_face` materials, `Plan({0: {0x61}, 1: {0x62}}, {0x61: 0, 0x62: 1})`, two hand-made `PreparedFont`s) with prepared issues at indexes 1 and 0 and `forge_issues = [Issue("r", "warning", None, None, "report level"), Issue("s", "warning", 0, None, f"{name0}: late")]` returns issues ordered `[index 0 (prepared), "s", index 1, "r"]`; `"late"` is the last entry of `materials[0].warnings`; and `"report level"` is the last entry of `report.warnings`.
- **AC-101-8** `make engine-test` passes, including the ported reference tests, unchanged.

### Verification
```bash
make engine-test
make lint
```

### Notes for the implementer
- Normalise **after** subsetting, not before. The subsetter handles platform-0 subtables correctly, and only the merger does not.
- The UVS test must forge U alone, or pin its Latin group to U. When fixture A draws `a`, the planner assigns U+0061 to A, and the subsetter rightly drops U's variation sequence.
- Do not build the AC-101-4 fixture with `build_font()`/`setupCharacterMap()`. They raise on the oversized format 4 subtable, which is exactly the bug. Assign `font["cmap"]` by hand before `setupOS2()`, which needs a cmap for its Unicode ranges.
- `verify()` (`merge.py:129`) uses `getBestCmap()`, which prefers `(3,10)`. It keeps passing with a partial format 4 subtable, and it must not be changed.
- Audit evidence to reread: ENGINE-1 (the verifier's count of 21 faces in 9 families, and the `(3,0)` note).

---

## WP-102: Drop non-kept and Apple bitmap tables before subsetting

**Goal:** Tables the output never keeps are removed before the subsetter sees them. Apple's `bloc`/`bdat`/`bhed` then cannot crash a forge, and dropped bitmap strikes are reported.
**Depends on:** WP-002, WP-101 · **Env:** linux · **Size:** S · **Closes findings:** ENGINE-M2, ENGINE-12

### Scope
- In:
  - `drop_unused_tables()`, called in `prepare()` after instancing and before subsetting.
  - `bdat`, `bloc` and `bhed` added to `subset_options().drop_tables` as a second line of defence, since `final_subset()` reuses the options.
  - The `bitmaps_dropped` issue and `PreparedFont.dropped_tables`.
- Out:
  - Warnings for lost AAT shaping (`morx`, `kerx`, `kern` v1, `trak`). That is WP-107 (engine-metadata.md), which may read `PreparedFont.dropped_tables`.
  - Keeping vertical metrics or `BASE`/`meta` (backlog B-2, ENGINE-11).
  - Colour (`sbix`, `CBDT`) and CFF2 faces. They are rejected at validate as before (`unsupported_font`).

### Touched paths
- `engine/src/fpengine/prepare.py` (edit)
- `engine/tests/test_tables.py` (new)

### Design

```python
KEEP_TABLES = {...}                                   # unchanged (prepare.py:19)
PREPARE_TABLES = frozenset(KEEP_TABLES | {"CFF "})    # what prepare() still needs after instancing
BITMAP_TABLES = frozenset({"EBDT", "EBLC", "EBSC", "bdat", "bloc", "bhed"})

def drop_unused_tables(font: TTFont) -> list[str]:
    """Delete every table outside PREPARE_TABLES; return the deleted tags, sorted. Never decompiles a table."""
    dropped = sorted(tag for tag in font.keys() if tag != "GlyphOrder" and tag not in PREPARE_TABLES)
    for tag in dropped:
        del font[tag]
    return dropped
```

- **Why this works.** `Subsetter.subset()` walks every table and decompiles any tag that has a `prune_pre_subset`/`subset_glyphs` method. fontTools maps `bloc` to the EBLC reader, which raises `struct.error` on Apple's data (`E_B_L_C_.py`). `TTFont.__delitem__` removes a table from the reader without decompiling it.
- **Order.** Call it after `instance_variable()`, which still needs `fvar`/`gvar`/`avar`/`HVAR`/`MVAR`/`STAT`, and before `subset_font()`. `cff_to_glyf()` deletes `VORG` only if it is present, so dropping it earlier is safe.
- **Defence in depth.** `subset_options()` also gets `o.drop_tables = list(o.drop_tables) + ["DSIG", "bdat", "bloc", "bhed"]`. The reference already adds `DSIG`, and the result must contain each tag once.
- **Issue.** `bitmaps = sorted(set(dropped) & BITMAP_TABLES)`. If it is non-empty, call `_note(..., "bitmaps_dropped", note, index, face.display_name)` with the note from §Shared definitions 4.
- **Report data.** `PreparedFont.dropped_tables = dropped` (sorted tags) for later consumers (WP-107).
- **Tables this removes early on the audit Mac** (911 faces scanned): `meta` 734, `prep` 358, `cvt ` 337, `fpgm` 336, `feat` 283, `hdmx` 279, `morx` 274, `vhea`/`vmtx` 198, `gasp` 132, `VORG` 121, `BASE` 116, `Zapf` 98, `prop` 85, `just` 83, `trak` 75, `fond` 72, `DSIG` 61, `STAT` 57, `kerx` 51, `bsln` 49, `VDMX` 46, `LTSH` 45, `fdsc` 37, `ankr` 33, `FFTM` 29, `PCLT` 28, `ltag` 27, `cidg` 24, `bdat`/`bloc` 18, `xref` 17, `EBDT`/`EBLC` 10, `fmtx` 7, `MERG` 6, `TSIV` 6, `lcar` 5, `opbd` 5, `CVTM` 4, `JSTF` 4, `MTfn` 3, `bhed` 1, `MATH` 1, and a few singletons. `strip_tables()` removed all of them after subsetting anyway. The output is unchanged apart from fonts that used to crash.

### Acceptance criteria
- **AC-102-1** `test_engine_m2_malformed_apple_bitmap_tables` in `engine/tests/test_tables.py`. The fixture is `build_font(…, cps("gh"))` plus raw `DefaultTable` tables: `bloc = struct.pack(">LL", 0x00020000, 1) + b"\0\0"` (claims one strike, then truncated), `bdat = struct.pack(">L", 0x00020000)` and `bhed = b"\0\1"`. Forging it alone, and as material 1 under fixture A, both succeed. The output tables, apart from `GlyphOrder`, are a subset of `KEEP_TABLES`. Issue `bitmaps_dropped`@0 (alone) and @1 (under A) with note `"embedded bitmaps (bdat, bhed, bloc) are not kept; the forged font draws outlines at every size"` (§Shared definitions 5). (Reference: `[prepare (…)] error: unpack requires a buffer of 16 bytes`.)
- **AC-102-2** `test_engine_12_bitmap_strikes_reported`, parametrized. `prepare()` of `build_font(…, cps("gh"))` plus raw `DefaultTable`s `{EBDT, EBLC}` gives issue `bitmaps_dropped`@0 with the note with `(EBDT, EBLC)`, and `{bdat, bloc}` gives `(bdat, bloc)`. Raw bytes (for example `b"\0\2\0\0junk"`) are enough because neither table is decompiled.
- **AC-102-3** `test_unused_tables_dropped_before_subsetting`. The fixture carries raw junk tables `morx, mort, feat, trak, kerx, ankr, just, prop, lcar, opbd, bsln, fond, Zapf, meta` (for example `b"\0\1junk"`, which `trak` and `meta` could not decompile). A spy on `fontTools.subset.Subsetter.subset` records `set(font.keys()) - {"GlyphOrder"}` at call time, and that set is a subset of `PREPARE_TABLES`. `prepare()` succeeds, `PreparedFont.dropped_tables` equals the sorted list of those 14 tags, and there is no `bitmaps_dropped` issue.
- **AC-102-4** `test_subset_options_drop_apple_bitmaps`: `{"DSIG", "bdat", "bloc", "bhed"}` is a subset of `set(subset_options().drop_tables)`, and `DSIG` appears exactly once.
- **AC-102-5** `test_plain_fonts_drop_nothing`: `A.ttf` and the CFF `B.otf` from `font_dir` give `dropped_tables == []` and `issues == []`.
- **AC-102-6** `make engine-test` passes.

### Verification
```bash
make engine-test
make lint
```

### Notes for the implementer
- Never iterate `font.tables` to find tags. Use `font.keys()`, which includes tables still in the reader. Never touch `font[tag]` for a tag you are about to drop, because that decompiles it.
- Keep `strip_tables()`. It also removes anything a later step adds by mistake.
- Audit evidence: ENGINE-M2 (Geneva traceback, the six faces that forge after the fix), ENGINE-12 (the verifier's correction).

---

## WP-103: Synthesize a missing OS/2 table

**Goal:** A face without an OS/2 table forges as main font or as a secondary material, with a report note, instead of crashing.
**Depends on:** WP-002, WP-101 · **Env:** linux · **Size:** S · **Closes findings:** ENGINE-M1

### Scope
- In:
  - `ensure_os2()` in prepare, with the field derivation below and the `os2_synthesized` issue.
  - The face reader's weight fallback for faces without OS/2 (`face.py`, reference `catalog/face.py:190`). It becomes `700 if head.macStyle & 1 else 400`, so Courier Bold is not synthetically emboldened a second time.
- Out:
  - `FaceRecord.has_os2` and `fs_type: null` in the scan output (WP-106, engine-metadata.md).
  - How an unknown embedding permission affects the output fsType and licence notes (WP-110, ADR-0012). The synthesized table carries `fsType = 0`, and WP-110 decides what that means.

### Touched paths
- `engine/src/fpengine/prepare.py` (edit)
- `engine/src/fpengine/face.py` (edit: one line, the weight fallback; plus `READER_VERSION` per engine-metadata.md §S3, because `read_faces` now returns a different `weight_class` for the same bytes: raise it by 1, or create it as `READER_VERSION = 4` if WP-106 has not landed yet)
- `engine/tests/test_os2.py` (new)

### Design

```python
def ensure_os2(font: TTFont) -> bool:
    """Add an OS/2 v4 table derived from head/hhea/post/cmap when the face has none. True when one was added."""
```

It uses `fontTools.fontBuilder.FontBuilder(font=font).setupOS2(**values)`, which creates the table from fontTools' defaults plus `values`, recalculates `xAvgCharWidth` from `hmtx` and the Unicode ranges from the cmap. Values, with `head`, `hhea` and `upem = head.unitsPerEm` from the face:

| Field | Value |
|---|---|
| `version` | 4 |
| `usWeightClass` | `700 if head.macStyle & 1 else 400` |
| `usWidthClass` | 5 |
| `fsType` | 0 (embedding unknown; flagged by the issue) |
| `fsSelection` | bit 0 = `macStyle & 2` (italic), bit 5 = `macStyle & 1` (bold), bit 6 when neither. Other bits 0 |
| `achVendID` | `"NONE"` |
| `sTypoAscender`, `sTypoDescender`, `sTypoLineGap` | `hhea.ascent`, `hhea.descent`, `hhea.lineGap` |
| `usWinAscent` | `max(hhea.ascent, head.yMax, 0)` |
| `usWinDescent` | `max(-hhea.descent, -head.yMin, 0)` |
| `sxHeight` | `round(yMax)` of the glyph the cmap maps U+0078 to, measured with `fontTools.pens.boundsPen.BoundsPen(font.getGlyphSet())`. 0 if unmapped or empty. Works for `glyf` and CFF |
| `sCapHeight` | the same for U+0048 |
| `ySubscriptXSize`, `ySuperscriptXSize` | `round(upem * 0.65)` |
| `ySubscriptYSize`, `ySuperscriptYSize` | `round(upem * 0.6)` |
| `ySubscriptXOffset`, `ySuperscriptXOffset` | 0 |
| `ySubscriptYOffset` | `round(upem * 0.075)` |
| `ySuperscriptYOffset` | `round(upem * 0.35)` |
| `yStrikeoutSize` | `post.underlineThickness` if it is above 0, else `round(upem * 0.05)` |
| `yStrikeoutPosition` | `round(sxHeight * 0.6)` if `sxHeight`, else `round(upem * 0.22)` |
| `ulCodePageRange1/2` | 0 (`finish()` recalculates them for the output, `merge.py:122`) |
| `usDefaultChar`, `usBreakChar`, `usMaxContext` | 0, 32, 0 (`finish()` recalculates `usMaxContext`) |
| `sFamilyClass`, `panose` | fontTools defaults (0, all zero) |
| `usFirstCharIndex`, `usLastCharIndex` | computed by fontTools when the table compiles |

- **Where.** In `prepare()` right after `load_face()` (pipeline step 2), and again after the reload on the variable-font GPOS-retry path. If either call returns True, call `_note(..., "os2_synthesized", note, index, face.display_name)` (§Shared definitions 4) exactly once per prepare, just before the `bitmaps_dropped` check (pipeline step 4).
- **Why this fixes both crashes.** The synthesized table is in `KEEP_TABLES`, so the saved part has one. `finish()`'s `upgrade_os2`/`copy_vertical_metrics` (`merge.py:78`, `:102`) then find `base["OS/2"]`, and the merger no longer sees `NotImplemented` for the missing table.
- **Face reader.** In the port of `catalog/face.py:190`, change `weight_class=int(os2.usWeightClass) if os2 else 400` to `… if os2 else (700 if font["head"].macStyle & 1 else 400)`. The italic fallback on line 191 already uses `macStyle`. `prepare()` decides synthetic bold from `face.weight_class` (`prepare.py:165-166`). Without this change, Courier Bold (macStyle 1) at weight 700 would get +300 synthetic bold.

**Non-normative reference:** the verifier's `ensure_os2` in the audit covered the weights, typo and win metrics and `fsType`. This design adds x-height, cap height, sub/superscript and strikeout values so CoreText's `CTFontGetXHeight` and strikethrough are sensible for a Courier-based result.

### Acceptance criteria
- **AC-103-1** `test_engine_m1_missing_os2_as_main` in `engine/tests/test_os2.py`. The fixture is `build_font(…, "Fixture N", "Bold Italic", cps("xyzH"))` with `del font["OS/2"]` and `head.macStyle = 3`. Forged alone, it succeeds. The output `OS/2.version >= 4`, and `report.issues == [Issue("os2_synthesized", "warning", 0, None, "Fixture N Bold Italic: " + note)]` with the §Shared definitions 4 note; the note is in `materials[0].warnings`. (Reference: `[finish] KeyError: "'OS/2' table not found"`.)
- **AC-103-2** `test_engine_m1_missing_os2_as_secondary`: the same fixture as material 1 under fixture A succeeds, with issue `os2_synthesized`@1 and the §Shared definitions 4 note. (Reference: `[merge] TypeError` about `NotImplementedType`; the operator in the text varies between runs, `'>' not supported…` or `unsupported operand type(s) for |…`.)
- **AC-103-3** `test_ensure_os2_field_derivation`. On the AC-103-1 fixture loaded with `TTFont` (upem 1000, hhea 800/−200/0, rectangles 0..700 high so `head.yMin` 0 and `yMax` 700, `post.underlineThickness` 0 from `setupPost()`, so the strikeout size falls back to `round(1000 × 0.05)`), `ensure_os2()` returns True and sets: `usWeightClass` 700, `fsSelection` `0x21`, `sTypoAscender` 800, `sTypoDescender` −200, `sTypoLineGap` 0, `usWinAscent` 800, `usWinDescent` 200, `sxHeight` 700, `sCapHeight` 700, `achVendID` `"NONE"`, `fsType` 0, `yStrikeoutSize` 50, `yStrikeoutPosition` 420, `ySuperscriptYOffset` 350. With `macStyle = 0` it gives `usWeightClass` 400 and `fsSelection` `0x40`.
- **AC-103-4** `test_ensure_os2_keeps_existing_table`: on `A.ttf`, `ensure_os2()` returns False and `font["OS/2"]` is the same object with unchanged fields.
- **AC-103-5** `test_missing_os2_cff_face`: the CFF fixture (`build_font(…, cps("xyzH"), cff=True)`) without OS/2 forges alone, with issue `os2_synthesized`@0, and its `ensure_os2()` gives `sxHeight == 700`. This proves `BoundsPen` works on CFF. (Reference: `[finish] KeyError: "'OS/2' table not found"`.)
- **AC-103-6** `test_no_os2_bold_face_reads_as_bold`: `read_faces()` gives `weight_class == 700` for the AC-103-1 fixture (macStyle bit 0), and `400` for the same fixture with `macStyle = 0`. Forging the AC-103-1 fixture with `default_weight=700` produces no `synthetic_bold` issue and no `"synthetic bold"` warning. (Reference: `weight_class == 400`, so +300 synthetic bold.)
- **AC-103-7** `make engine-test` passes. `fpengine.face.READER_VERSION` is raised by exactly 1 against `main`, or created as 4 (reviewer check with `git diff main -- engine/src/fpengine/face.py`, as engine-metadata.md AC-106-13).

### Verification
```bash
make engine-test
make lint
```

### Notes for the implementer
- `setupOS2()` asserts that `hmtx` and `cmap` exist, which they do on every loaded face. Call it before any table is dropped.
- Do not recompute `fsType` from anything. Licence handling is WP-110's.
- The one-line change in `face.py` touches a function WP-106 and WP-108 also edit in wave 3, so rebase in merge order.

---

## WP-104: Feature closure: drop `aalt` and lookup-sharing features; disable the HarfBuzz repacker

**Goal:** Dropping `locl` actually removes the per-language variant glyphs, `aalt` no longer pulls in every alternate, and a forge can never enter HarfBuzz's repack loop.
**Depends on:** WP-002 · **Env:** linux · **Size:** S · **Closes findings:** ENGINE-3

### Scope
- In:
  - `kept_features()` with the alias rule below, and `is_discretionary()`.
  - `disable_hb_repacker()` on every prepared part and on the merged font.
  - The recalibrated glyph-estimate constants: numbers and procedure in this section, consumed by core.md.
- Out:
  - Porting the estimate itself (WP-303/WP-304, core.md: `face_glyph_share`, `estimate_glyphs`, `exceeds_glyph_budget`, `reference/.../ui/smart.py:129-153`).
  - Adding or pinning `uharfbuzz`. It is not a dependency, and the cfg switch makes the engine safe either way.
  - Optical-size pinning (B-1, ENGINE-6); see Notes.

### Touched paths
- `engine/src/fpengine/prepare.py` (edit)
- `engine/src/fpengine/merge.py` (edit: `merge_fonts`)
- `engine/tests/test_features.py` (new)

### Design

**Feature rule:**

```python
DROPPED_FEATURES = frozenset({"locl"})     # unchanged meaning (prepare.py:58)
ALWAYS_DROPPED = frozenset({"aalt"})       # a glyph-palette feature; never applied to text
DISCRETIONARY_FEATURES = frozenset({"salt", "swsh", "cswh", "titl", "ornm", "nalt", "hist", "smpl", "trad", "tnam",
                                    "jp78", "jp83", "jp90", "jp04", "hojo", "nlck", "expt", "dlig", "hlig"})
_SS_CV = re.compile(r"ss(0[1-9]|1[0-9]|20)|cv(0[1-9]|[1-9][0-9])")

def is_discretionary(tag: str) -> bool:
    """Off by default and chosen by the user: alternates, stylistic sets, character variants, JIS/regional forms."""
    return tag in DISCRETIONARY_FEATURES or _SS_CV.fullmatch(tag) is not None

def kept_features(font: TTFont) -> list[str]:
    """Every GSUB/GPOS feature tag, minus DROPPED_FEATURES, minus 'aalt', minus every *discretionary* feature that
    shares a LookupListIndex with a DROPPED_FEATURES feature of the same table."""
```

Algorithm, per table (`GSUB`, then `GPOS`). The two tables have separate lookup index spaces.
1. Skip the table if it is absent or has no `FeatureList`.
2. `records = table.FeatureList.FeatureRecord`. Add every `r.FeatureTag` to `tags`.
3. `dropped_lookups = {i for r in records if r.FeatureTag in DROPPED_FEATURES for i in r.Feature.LookupListIndex}`
4. `drop |= {r.FeatureTag for r in records if is_discretionary(r.FeatureTag) and dropped_lookups & set(r.Feature.LookupListIndex)}`

Return `sorted(tags - DROPPED_FEATURES - ALWAYS_DROPPED - drop)`. The decision is per tag: if any record of a tag aliases, the whole tag is dropped, because the subsetter's `layout_features` option works by tag.

**Deviation from the verifier's recommendation, deliberately.** The verifier said to drop *every* feature sharing a lookup with `locl`. A scan of all 185 `locl`-bearing GSUB/GPOS tables on the audit Mac found these sharers: PingFang SC `cv08/cv09`, TC `cv04/cv05`, HK/MO `cv06/cv07`, Arial Unicode MS `salt/smpl/trad`, Euphemia UCAS `ss19/ss20` (+`aalt`), and **Noto Sans Cham `clig`**. `clig` is applied by default when shaping. Dropping it removes 3 of Noto Sans Cham's 132 glyphs and breaks its required ligatures, so only discretionary sharers are dropped. On PingFang and Arial Unicode MS the result is identical to the verifier's measurements.

| Face (full cmap, alone) | Reference closure | This rule | Ratio glyphs/characters (reference → fixed) |
|---|---|---|---|
| PingFang SC Regular | 48,124 | 38,054 | 1.342 → 1.061 |
| PingFang HK Regular | 45,509 | 34,301 | 1.368 → 1.031 |
| PingFang TC Regular | 44,527 | 33,338 | 1.380 → 1.033 |
| Arial Unicode MS | 50,367 | 41,280 | 1.294 → 1.061 |
| Noto Sans Cham | 132 | 132 (the verifier's rule: 129) | — |
| Pan-CJK: Avenir Next + PingFang SC (Han) + Hiragino Sans W3 (Kana) + Apple SD Gothic Neo (Hangul), forged | 64,363 | 53,217 | 1.324 → 1.095 |

**HarfBuzz repacker:**

```python
from fontTools.ttLib.tables.otBase import USE_HARFBUZZ_REPACKER

def disable_hb_repacker(font: TTFont) -> None:
    """ENGINE-3: with uharfbuzz importable, hb.repack fails on PingFang's GSUB and fontTools loops for 20+ minutes."""
    font.cfg[USE_HARFBUZZ_REPACKER] = False
```

- Call it in `prepare()` right before `font.save()` (pipeline step 11). Instancing may return a new `TTFont`, so an earlier call could be lost.
- Call it in `merge_fonts()` on the object `Merger().merge(paths)` returns. That is a **new** `TTFont` with default cfg. Then return that object.
- `Subsetter.subset()` does not touch `cfg`. Only the `pyftsubset` CLI's `save_font()` does (`fontTools/subset/__init__.py`, `save_font`). `final_subset()` in `finish()` therefore keeps the setting.
- With `False`, `BaseTTXConverter.compile` uses the pure-Python serializer (`otBase.py`, `use_hb_repack is False`). The verifier measured PingFang's fixed GSUB compiling in 0.1 s with 0 overflow resolutions.

**Glyph-estimate recalibration** (numbers for core.md: WP-303 ports `estimate_glyphs`, WP-304 ports `exceeds_glyph_budget`):

The estimate is `1 + Σ round(glyph_count × assigned / |cmap| × VARIANT_FACTOR)` (`reference/.../ui/smart.py:129-148`). The UI warns above `GLYPH_WARN` and blocks the build above `MAX_GLYPHS` = 65,535 (`reference/.../ui/model.py:598-604`). Measured with the fixed closure on the reference machine:

| Mix (rules) | Actual glyphs | Estimate at F = 0.8 | Error |
|---|---|---|---|
| Helvetica Neue + PingFang SC (Kana, Han, CJK symbols, Emoji) | 39,252 | 40,835 | +4.0 % |
| PingFang SC alone | 38,054 | 39,627 | +4.1 % |
| PingFang TC alone | 33,338 | 39,627 | +18.9 % |
| Georgia + PingFang HK (Kana, Han, CJK symbols, Emoji) | 34,504 | 39,852 | +15.5 % |
| Helvetica Neue + Songti SC (Kana, Han, CJK symbols, Emoji) | 34,135 | 35,558 | +4.2 % |
| Avenir Next + PingFang SC (Han, Kana, CJK symbols, Emoji) + Apple SD Gothic Neo (Hangul) | 50,276 | 49,747 | −1.1 % |
| Pan-CJK (4 fonts, as in the table above) | 53,217 | 50,406 | −5.3 % |
| Avenir Next + Hiragino Sans W3 (Han, Kana, CJK symbols) + Apple SD Gothic Neo (Hangul) | 30,915 | 26,559 | −14.1 % |
| SF + Hiragino Sans W3 (Kana, Han, CJK symbols) | 19,973 | 17,672 | −11.5 % |
| Hiragino Sans W3 alone | 18,781 | 16,272 | −13.4 % |
| Avenir Next + Apple SD Gothic Neo (Hangul, Kana, Han, CJK symbols) | 18,746 | 15,405 | −17.8 % |
| Apple SD Gothic Neo alone | 18,084 | 14,931 | −17.4 % |

The per-material factor `(part glyphs − 1) / (glyph_count × assigned / |cmap|)` is 0.67–0.77 for the PingFang faces and Songti SC, whose glyph counts include other regions' glyphs. It is 0.90–0.92 for Hiragino with Han, 0.95–0.98 for Avenir Next and Apple SD Gothic Neo, and 2.69 for Hiragino with Kana only (829 characters give 3,268 glyphs through `nalt`, `ruby`, `hkna`, `vrt2` and `dlig`). Before the fix, the pan-CJK mix was estimated at −21.7 % (64,363 actual against 50,406) and got no warning at 58,000.

**Decision (normative for core.md):**
- `VARIANT_FACTOR = 0.8`: **unchanged**. It sits in the middle of the post-fix error band (−18 % to +19 %).
- `GLYPH_WARN = 55_000`: **was 58,000**. Among mixes of 30,000 glyphs or more, the most negative measured error is −14.1 %, and 65,535 × (1 − 0.141) = 56,294. At 58,000, a mix of that kind that truly exceeds the limit would get no warning. 55,000 covers it with about 2 % margin.
- `MAX_GLYPHS = 65_535` stays the blocking threshold. Consequence, accepted: PingFang TC/HK-heavy mixes overestimate by up to +19 %, so such a mix is blocked from about 55,100 real glyphs.

**Procedure:** WP-111's `test_glyph_estimate_calibration` recomputes this table on the running Mac and fails if the band or the warning coverage breaks. To recalibrate, choose `VARIANT_FACTOR` so the median error over the calibration mixes is closest to 0, rounded to 0.05. Then set `GLYPH_WARN = round(65,535 × (1 + e_min − 0.02) / 500) × 500`, where `e_min` is the most negative error among calibration mixes of at least 30,000 glyphs. With `e_min = −0.141` this gives `round(54,983.9 / 500) × 500 = 55,000`. Check that the result still satisfies `GLYPH_WARN ≤ 65,535 × (1 + e_min)` (the WP-111 bound). Change the constants in core.md and in `engine/tests/apple_fonts/calibration.py` in the same PR.

### Acceptance criteria
- **AC-104-1** `test_kept_features_drops_aalt_and_discretionary_aliases` in `engine/tests/test_features.py`. The fixture "F" is built with FontBuilder: family `Fixture F`, style `Regular`, upem 1000, glyph order `.notdef uni0061 uni0062 uni0063 a.locl b.locl b.salt c.alt`, cmap U+0061/62/63 → `uni0061/62/63`, every glyph the `build_font` rectangle (x 50..150, y 0..700, advance 200, lsb 50), `setupOS2()`/`setupPost()` defaults. Features are added with `fontTools.feaLib.builder.addOpenTypeFeaturesFromString` before saving:
  ```
  languagesystem DFLT dflt; languagesystem latn dflt; languagesystem latn TRK;
  lookup LOCL_A { sub uni0061 by a.locl; } LOCL_A;
  lookup LOCL_B { sub uni0062 by b.locl; } LOCL_B;
  feature locl { script latn; language TRK; lookup LOCL_A; lookup LOCL_B; } locl;
  feature cv01 { lookup LOCL_A; } cv01;
  feature clig { lookup LOCL_B; } clig;
  feature salt { sub uni0062 by b.salt; } salt;
  feature aalt { feature salt; sub uni0063 from [c.alt]; } aalt;
  feature liga { sub uni0061 uni0062 by uni0063; } liga;
  feature kern { pos uni0061 uni0062 -50; } kern;
  ```
  `kept_features(font) == ["clig", "kern", "liga", "salt"]`. (Reference: `["aalt", "clig", "cv01", "kern", "liga", "salt"]`.)
- **AC-104-2** `test_engine_3_locl_alias_and_aalt_dropped`: `prepare()` of that fixture for `cps("abc")` gives the glyph order `[".notdef", "uni0061", "uni0062", "uni0063", "b.locl", "b.salt"]`. `a.locl` (only via `cv01`) and `c.alt` (only via `aalt`) are gone, and `b.locl` stays because the default-on `clig` uses it. (Reference: `a.locl` and `c.alt` kept.)
- **AC-104-3** `test_alias_rule_is_per_table`. The fixture has GSUB lookups `SUB0` (a→a.ss01) and `SUB1` (b→b.locl), and GPOS lookups `POS0` and `POS1`. The features are `locl{SUB1}`, `ss01{SUB0}`, `ss03{SUB1}`, `kern{POS0}` and `ss02{POS1}`, so GPOS `ss02` has the same index (1) as GSUB `locl`. `kept_features == ["kern", "ss01", "ss02"]`: `ss03` is dropped, and `ss02` is kept.
- **AC-104-4** `test_is_discretionary`: True for `salt, smpl, trad, nalt, swsh, jp78, ss01, ss20, cv01, cv99`. False for `ccmp, locl, rlig, liga, clig, calt, kern, mark, mkmk, init, medi, fina, isol, vert, vrt2, ss00, ss21, cv00, aalt`. (`aalt` is handled by `ALWAYS_DROPPED`, not by this predicate.)
- **AC-104-5** `test_engine_3_hb_repacker_disabled`. The test first builds the AC-104-1 fixture and fixture A, **then** monkeypatches `fontTools.ttLib.tables.otBase.have_uharfbuzz = True` and `otBase.hb` (`raising=False`) to a fake module. The fake's `serialize_with_tag`, `repack` and `repack_with_tag` raise a sentinel exception, and it has a `RepackerError` class. *Control:* compiling the fixture's GSUB on a freshly loaded `TTFont` with default cfg raises the sentinel. This proves the probe is live. *Test:* forging `[A, F]` with `script_rules={"latin": 1}` succeeds. (Reference: `[prepare (Fixture F Regular)] Sentinel`.)
- **AC-104-6** `test_repacker_cfg_false_on_every_saved_font`: after the fixtures are built, a spy (`monkeypatch.setattr(TTFont, "save", …)` wrapping the original) records `self.cfg[USE_HARFBUZZ_REPACKER]` for every save during the forge of `[A, F]` with `script_rules={"latin": 1}` (no fake `hb`). Exactly 3 saves are recorded (both parts and the final font), and every recorded value is `False`. (Reference: all three are `None`.)
- **AC-104-7** `make engine-test` passes.

### Verification
```bash
make engine-test
make lint
```

### Notes for the implementer
- Build fixtures **before** installing the fake `hb`. Saving a fixture compiles its GSUB.
- `feaLib` gives named lookups indices in definition order within each table, and a named lookup referenced by several features is shared. Both facts were checked.
- **Optical size (ADR-0011).** `instance_variable()` (`prepare.py:35-41`) pins every axis except `wght` to its `fvar` default, and this WP does not change that. The preview (WP-402) must therefore pin `opsz` to the `fvar` default, which is the value the engine instantiates. Changing it to a text size is backlog B-1 (ENGINE-6).
- Audit evidence: ENGINE-3 (the verifier's closure table; both parts of the fix are needed, since dropping `cv08/cv09` alone gives 48,124 glyphs and dropping `aalt` alone gives 48,113).

---

## WP-105: Robust synthetic bold (per-glyph fallback, report)

**Goal:** One glyph that `skia-pathops` cannot union never fails a forge. Such glyphs are counted and reported, and a synthetic bold that more than doubles the file size is flagged.
**Depends on:** WP-002, WP-101 · **Env:** linux · **Size:** S · **Closes findings:** ENGINE-4

### Scope
- In:
  - `union_with_stroke()` with a retry on simplified paths.
  - A per-glyph fallback that keeps the regular outline with the bold metrics.
  - `BoldResult`, and the issues `synthetic_bold`, `bold_glyphs_skipped` and `bold_size_doubled`.
- Out:
  - Preferring the nearest real weight of the same family (PingFang Medium/Semibold, Hiragino W0–W9) over synthetic bold. That belongs to WP-304 (core.md, "nearest real weight"). The engine only reports.
  - Cancelling inside the bold loop. The helper's SIGTERM handling (WP-201) covers that.

### Touched paths
- `engine/src/fpengine/synth_bold.py` (edit)
- `engine/src/fpengine/prepare.py` (edit: bold call site, issues)
- `engine/src/fpengine/forge.py` (edit: size check)
- `engine/tests/test_bold_fallback.py` (new)

### Design

```python
@dataclass
class BoldResult:
    delta: int                                        # applied delta, min(requested, MAX_DELTA)
    emboldened: int = 0                               # glyphs whose outline got thicker
    skipped: list[str] = field(default_factory=list)  # glyph names kept at the regular outline, in glyph order
    added_bytes: int = 0                              # Σ compiled glyf bytes after − before, over all written glyphs

def union_with_stroke(path: pathops.Path, width: float) -> pathops.Path:
    """Fill ∪ round-joined stroke. On PathOpsError, retry once on simplified operands; re-raise if that fails too."""
    stroked = pathops.Path(path)
    stroked.stroke(width, pathops.LineCap.ROUND_CAP, pathops.LineJoin.ROUND_JOIN, 4.0)
    stroked.convertConicsToQuads()
    try:
        return pathops.op(path, stroked, pathops.PathOp.UNION)
    except pathops.PathOpsError:
        return pathops.op(pathops.simplify(path), pathops.simplify(stroked), pathops.PathOp.UNION)

def embolden(font: TTFont, delta_weight: int) -> BoldResult: ...
```

`embolden` keeps the reference's structure (`synth_bold.py:16-46`): take a snapshot of every outline first, then write back. For each snapshotted glyph:
1. `before = len(glyf[name].compile(glyf, recalcBBoxes=False))`, taken during the snapshot pass.
2. `result = union_with_stroke(path, w)`. On `pathops.PathOpsError`, append `name` to `skipped` and set `result = pathops.Path(path)`. This keeps the regular outline.
3. As in the reference: `convertConicsToQuads()`, translate by `w / 2`, draw into `TTGlyphPen(None)`, `recalcBounds`, store the glyph, and set `hmtx[name] = (advance + round(w), glyph.xMin)`. **Skipped glyphs get the same shift and advance**, so spacing and CJK full-width grids stay uniform.
4. `added_bytes += len(glyph.compile(glyf, recalcBBoxes=False)) - before`, and `emboldened += 1` unless the glyph was skipped.

`hhea.advanceWidthMax` is recomputed as before. The byte accounting costs about 1.4 s per pass over 38,000 glyphs on the reference machine, against 25–32 s of union work.

**Call site** (`prepare.py:165-171`), when `delta >= 50`:
- `res = embolden(font, delta)`.
- `_note(…, "synthetic_bold", f"synthetic bold (+{res.delta})", index, face.display_name)`. The note is the reference's warning text, unchanged.
- If `res.skipped`: `_note(…, "bold_glyphs_skipped", note, index, face.display_name)` with the §Shared definitions 4 note, `n = len(res.skipped)`. `total` is the number of glyphs with contours, which is `res.emboldened + len(res.skipped)`.
- `bold_added_bytes = res.added_bytes` goes into `PreparedFont.bold_added_bytes`.

The `delta <= -50` warning is unchanged.

**Forge-level size check** (`forge()`, after `verify()` and before `_report()`, §Shared definitions 2): let `added = Σ pf.bold_added_bytes` and `final = out.stat().st_size`. If `added > 0 and added > final − added`, the result is more than twice the size it would have without synthetic bold. Then add `Issue("bold_size_doubled", "warning", i, None, f"{display_name_i}: {note}")` to `forge_issues`, where `i` is the index with the largest `bold_added_bytes` (the lowest index on a tie), `without = final − added`, and the note is §Shared definitions 4's. `_report()` puts the note into material `i`'s `warnings` and the prefixed line into `report.warnings` (§Shared definitions 3). A round-joined stroke roughly doubles a glyph's data (measured ×1.9–×2.5 for +100 to +300). The check therefore uses the whole file. It fires when bold glyphs dominate the output, as PingFang at +300 does (11.1 → 25.0 MB), and not for SF + Hiragino W6 at +100 (8.5 → 14.6 MB).

### Acceptance criteria
- **AC-105-1** `test_engine_4_pathops_failure_keeps_glyph` in `engine/tests/test_bold_fallback.py`. `monkeypatch` wraps `pathops.op` so that its first two calls raise `pathops.PathOpsError` (both attempts for the first glyph, `.notdef`) and later calls go to the real `op`. `prepare()` of `build_font(…, cps("ab"))` at weight 700 succeeds. `.notdef` keeps its 4-point outline with bounds `xMin, xMax == 80, 180` and `hmtx == (260, 80)`. `uni0061` has `xMin == 50`, `xMax` within 1 of 210, and `hmtx == (260, 50)`. `pf.warnings == ["synthetic bold (+300)", "1 of 3 glyphs could not be made bolder and keep their regular outline (.notdef)"]`, and the codes of `pf.issues` are `["synthetic_bold", "bold_glyphs_skipped"]`, both with `material_index` equal to the `index` argument. (Reference: `PathOpsError` propagates, and the forge fails at `[prepare (…)]`.)
- **AC-105-2** `test_engine_4_pathops_retry_on_simplified_paths`: `pathops.op` raises on every odd-numbered call (1st, 3rd, …) and calls the real `op` otherwise. `prepare()` of the AC-105-1 fixture at weight 700 emboldens every glyph (`uni0061` bounds as in AC-105-1, `.notdef` now also 50..210), `op` is called exactly 6 times (twice per glyph), and there is no `bold_glyphs_skipped` issue.
- **AC-105-3** `test_engine_4_all_glyphs_fail`: `pathops.op` always raises. A forge of `build_font(…, cps("abcdefg"))` alone with `default_weight=700` succeeds. It has issue `bold_glyphs_skipped`@0 with note `"8 of 8 glyphs could not be made bolder and keep their regular outline (.notdef, uni0061, uni0062, uni0063, uni0064, …)"` (the ellipsis is U+2026), and every advance in the output `hmtx` is 260. (Reference: the forge fails at `[prepare (…)] PathOpsError`.)
- **AC-105-4** `test_synthetic_bold_issue_and_legacy_warning`: `A.ttf` at weight 700 gives `pf.warnings == ["synthetic bold (+300)"]` and exactly one issue, `synthetic_bold`. The ported reference tests `test_prepare_applies_synthetic_bold_only_when_needed` and `test_forge_single_material_with_bold_and_scale` pass unchanged.
- **AC-105-5** `test_engine_4_bold_size_doubled_warning`. `build_font(…, set(range(0x4E00, 0x4E00 + 300)))` forged alone with `default_weight=700` has exactly one `bold_size_doubled` issue, `material_index == 0`, whose note matches `r"^synthetic bold more than doubled the file size \(\d+ KB without it, \d+ KB with it\); a heavier weight of this font"` and appears last in `materials[0].warnings`. (Measured: the output is about 27.6 KB, against 12.5 KB when forged without bold.) Fixture A with `default_weight=700` has no `bold_size_doubled` issue.
- **AC-105-6** `test_bold_result`: `embolden(A, 300)` returns `delta == 300`, `emboldened == 6` (`.notdef` plus 5 glyphs), `skipped == []` and `added_bytes > 0`. `embolden(A, 900)` returns `delta == 500` (`MAX_DELTA`).
- **AC-105-7** `make engine-test` passes.

### Verification
```bash
make engine-test
make lint
```

### Notes for the implementer
- Monkeypatch `pathops.op`, the attribute on the `pathops` module. `synth_bold` calls it through the module, so the patch reaches it, and pytest restores it.
- The real-font proof is WP-111 scenario AF-12. On the reference machine, PingFang SC's `cid13022` and `cid43492` fail at +300 without the retry and succeed with it. The forge then completes with **no** skipped glyph in 65 s, with a 25.0 MB output.
- Audit evidence: ENGINE-4 (the verifier's probe: +100/+200 fine, +300 fails, and Semibold at +100 has 0 failures).

---

## WP-111: Real-Apple-font regression suite (scenario matrix)

**Goal:** A macOS-only pytest suite forges the Mac's own fonts through the real helper and proves every `ENGINE-*` fix on real data. It covers outcomes, report issues, glyph budgets, time and memory, and CoreText shaping of the results.
**Depends on:** WP-101, WP-102, WP-103, WP-104, WP-105, WP-106, WP-107, WP-108, WP-109, WP-110, WP-201 · **Env:** macos · **Size:** M · **Closes findings:** all ENGINE-* except ENGINE-6, ENGINE-11 (backlog B-1, B-2); CRIT-7

### Scope
- In:
  - The scenario matrix below, run by `make engine-apple-fonts`.
  - A file-based font locator (no CoreText name lookups).
  - A helper runner with per-process time and RSS measurement.
  - CoreText shaping checks through URL descriptors (pyobjc, test-only).
  - Scan-metadata checks on real files, a cancel check, the glyph-estimate calibration test, and a Linux-safe source check that forbids name-based CoreText APIs.
  - A Linux-safe synthetic test for the parity item "Result" of docs/plan.md §6 (AC-111-12), so WP-701 has one named test for every property that item lists.
- Out:
  - ENGINE-6 (optical size, `trak`) and ENGINE-11 (vertical metrics) are backlog B-1 and B-2. The suite does not assert them.
  - UI or CoreText rendering services (WP-402).

### Touched paths
- `engine/tests/apple_fonts/__init__.py` (exists since WP-001, with the placeholder `test_wiring.py`; delete `test_wiring.py` now that real tests exist)
- `engine/tests/apple_fonts/conftest.py` (new)
- `engine/tests/apple_fonts/locate.py` (new)
- `engine/tests/apple_fonts/runner.py` (new)
- `engine/tests/apple_fonts/scenarios.py` (new)
- `engine/tests/apple_fonts/calibration.py` (new)
- `engine/tests/apple_fonts/coretext.py` (new)
- `engine/tests/apple_fonts/test_scenarios.py` (new)
- `engine/tests/apple_fonts/test_calibration.py` (new)
- `engine/tests/apple_fonts/test_shaping.py` (new)
- `engine/tests/apple_fonts/test_scan.py` (new)
- `engine/tests/apple_fonts/test_cancel.py` (new)
- `engine/tests/test_apple_fonts_locate.py` (new, runs on Linux)
- `engine/tests/test_result_parity.py` (new, runs on Linux; AC-111-12)
- `engine/tests/test_apple_fonts_safety.py` (new, runs on Linux; also holds `test_interim_report_fields_are_gone`: `fpengine.protocol.report.INTERIM_REPORT_FIELDS == {}` once WP-101 and WP-110 have landed, helper.md H9)
- `engine/pyproject.toml`, `engine/uv.lock` (no edit expected: WP-001 already declares the dev dependency `pyobjc-framework-CoreText>=11; sys_platform == 'darwin'`, foundation-release.md WP-001; edit only if it is missing)

### Design

**1. Gating.** Every `engine/tests/apple_fonts/test_*.py` module starts with `pytestmark = [pytest.mark.apple_fonts, pytest.mark.macos, pytest.mark.slow]`, so `make engine-apple-fonts` (`-m apple_fonts`) selects them however hooks are ordered. `engine/tests/apple_fonts/conftest.py` also adds the three markers to every item under its folder (`pytest_collection_modifyitems`). It skips them all with the reason `"needs macOS and FP_APPLE_FONTS=1"` unless `sys.platform == "darwin"` and `os.environ.get("FP_APPLE_FONTS") == "1"`. This holds even if the root conftest (WP-001/002) already does the same. No module in `apple_fonts/` imports `CoreText`/`Foundation` at module level: `coretext.py` imports them inside its functions. Collection on Linux therefore never fails.

**2. Locating fonts (file search only).** `locate.py`:

```python
SEARCH_ROOTS = (Path("/System/Library/Fonts"), Path("/System/Library/Fonts/Supplemental"))
ASSET_GLOB = "/System/Library/AssetsV2/com_apple_MobileAsset_Font*/*/AssetData"
FONT_SUFFIXES = (".ttf", ".otf", ".ttc", ".otc")

@dataclass(frozen=True)
class FaceLocation:
    postscript_name: str
    path: str        # absolute, as listed (not resolved)
    index: int       # face index in a collection, else 0
    size: int
    mtime: float

@dataclass
class FontIndex:
    faces: dict[str, FaceLocation]   # PostScript name -> first location found
    unreadable: list[str]

def search_dirs(roots: Sequence[Path] = SEARCH_ROOTS, asset_glob: str = ASSET_GLOB) -> list[Path]: ...
def build_index(dirs: Sequence[Path]) -> FontIndex: ...
```

- **Order.** `search_dirs()` returns the roots in order, then `sorted(glob.glob(asset_glob))`. The directories are not recursive. `build_index()` lists each directory's files sorted by `unicodedata.normalize("NFC", name)`; Hiragino's names are stored in NFD on disk. It keeps regular files whose suffix, compared case-insensitively, is in `FONT_SUFFIXES`, and reads **only the `name` table**: `TTCollection(path, lazy=True)` for collections, `TTFont(path, lazy=True)` otherwise, and `getDebugName(6)`. The first occurrence of a PostScript name wins. Unreadable files are listed, not raised.
- **Excluded on purpose:** `~/Library/Fonts` and `/Library/Fonts`. They hold user-installed fonts that can shadow system names.
- **Speed.** It takes about 0.2 s for 418 files on the reference machine. It is a session fixture.
- **Never** use `CTFontCreateWithName`, `CTFontDescriptorCreateWithNameAndSize`, `CTFontDescriptorCreateMatchingFontDescriptors`, `NSFont(name:)` or any other name lookup to find a font. A name that is not installed can start a system download (CATALOG-5; AGENTS.md rule 4).

**3. Running the helper.** `runner.py`:

```python
@dataclass
class HelperRun:
    returncode: int
    events: list[dict]          # parsed stdout JSON lines
    wall_s: float
    peak_rss_mb: float          # the child's ru_maxrss (bytes on macOS) / 2**20
    timed_out: bool
    stderr_tail: str            # last 4 KB, for failure messages
    @property
    def result(self) -> dict | None: ...   # payload of the single `result` event, if any
    @property
    def error(self) -> dict | None: ...    # payload of the single `error` event, if any

def run_helper(command: Literal["forge", "scan"], request: dict, *, tmpdir: Path, timeout_s: float,
               cancel_after_s: float | None = None) -> HelperRun: ...
```

- **Process.** `argv = [python, "-I", "-B", "-m", "fpengine", command]`, where `python = os.environ.get("FP_ENGINE_PYTHON") or sys.executable`. This mirrors architecture §3. stdin, stdout and stderr are files in `tmpdir`, which avoids pipe deadlocks.
- **Environment.** `env = {**os.environ, "TMPDIR": str(tmpdir / "helper-tmp"), "PYTHONDONTWRITEBYTECODE": "1"}`, and that directory is created first.
- **Waiting.** Start with `subprocess.Popen`, then poll `os.wait4(pid, os.WNOHANG)` every 50 ms (it returns `(0, 0, …)` while the child runs). This yields the **child's own** `rusage`. `RUSAGE_CHILDREN` would mix children. After reaping with `wait4`, set `returncode = os.waitstatus_to_exitcode(status)`, store it in `popen.returncode` yourself, and never call `popen.wait()`. A helper that exits 143 by itself (its SIGTERM handler, helper.md H6) gives `143`; one killed by an unhandled signal gives a negative number (`-15`, `-9`), which the cancel test treats as a failure.
- **Signals.** When `cancel_after_s` elapses, send SIGTERM once. When `timeout_s` elapses, send SIGTERM, then SIGKILL after 2 s (ADR-0003), and set `timed_out`.
- **Requests.** Forge requests follow contracts.md §4 and `spec/protocol/forge-request.schema.json`: `{"spec": {materials, base_index: 0, script_rules: dict(rules), default_weight, default_scale: 1.0, family_name, style_name}, "output_path": str(tmpdir / "out.ttf")}`, with `default_weight`, `family_name` (`family` or `f"FP Test {id}"`) and `style_name` (`style`) from the `Scenario`. Every material is `{path, index, weight: null, scale: null, expect: {postscript_name, size, mtime}}` from its `FaceLocation`. Scan requests are `{"files": [path, …]}` (`spec/protocol/scan-request.schema.json`, helper.md).

**4. Scenarios as data.** `scenarios.py` defines the frozen dataclass `Scenario` and the tuple `SCENARIOS`, which is the single source of the matrix in §5 (keep them in sync):

```python
@dataclass(frozen=True)
class Scenario:
    id: str                                    # "AF-01"
    materials: tuple[str, ...]                 # PostScript names, main font first
    rules: tuple[tuple[str, int], ...]         # (script group, material index) pairs; other groups null. A tuple keeps
                                               # the frozen dataclass hashable
    default_weight: int | None = None
    style: str = "Regular"
    family: str | None = None                  # None -> f"FP Test {id}"
    expect: str = "ok"                         # "ok" or an error code from contracts.md §5
    error_material: int | None = None
    must_issues: frozenset[tuple[str, int | None]] = frozenset()   # (code, material_index)
    max_glyph_ratio: float | None = None       # total_glyphs <= ratio * total_codepoints
    max_glyphs: int | None = None
    fs_type: int | None = None                 # expected ForgeReport.fs_type (WP-110 rule)
    budget_s: float = 15.0                     # × FP_APPLE_FONTS_TIME_FACTOR
    budget_rss_mb: int = 512
    optional: bool = False                     # font is a Font Book download, absent on a stock Mac
    stale_expect: bool = False                 # AF-29: send a wrong expect.postscript_name for the last material
    findings: tuple[str, ...] = ()
    reference: tuple[int, int, float, int] | None = None   # glyphs, characters, s, MB on the reference machine
```

**Checks for every scenario** (`test_scenarios.py::test_scenario[AF-nn]`, through a session-scoped memoising runner so other tests reuse the run):
- **Skip.** If any material's PostScript name is missing from the index: `pytest.skip(f"not installed: {name}")`.
- **Time and memory.** `wall_s <= budget_s × factor`, where `factor = float(os.environ.get("FP_APPLE_FONTS_TIME_FACTOR", "1"))`. `timeout_s = budget_s × factor`. `peak_rss_mb <= budget_rss_mb`.
- **When `expect == "ok"`:**
  - `returncode == 0`, and there is exactly one terminal event, of type `result`.
  - For every `(code, idx)` in `must_issues`, a matching issue exists. No other code from §Shared definitions 4 appears, and no issue has `severity == "error"`.
  - `total_glyphs <= max_glyph_ratio × total_codepoints` and `total_glyphs <= max_glyphs` when set, and `fs_type` matches when set.
  - The output file reloads with fontTools, `len(getBestCmap()) == total_codepoints`, `maxp.numGlyphs == total_glyphs`, and every table except `GlyphOrder` is in `KEEP_TABLES`.
- **Otherwise:** `returncode == 3`, `error.code == expect` and `error.material_index == error_material`.

**Finding tests.** `scenarios.py` also defines `FINDING_PROOFS: dict[str, tuple[str, ...]]`, the AF scenario ids of each row of the "Finding → proof" table below. Rows with no AF scenario are left out: ENGINE-6 and ENGINE-11 (backlog), ENGINE-9 (`test_cancel`), ENGINE-10 and ENGINE-M4 (`test_scan`). `test_scenarios.py::test_engine_finding[<finding id>]` (for example `test_engine_finding[ENGINE-1]`) reuses the memoised runs and passes when every listed scenario passed its checks, allowing only `optional` scenarios to be skipped. These are the per-finding regression tests AGENTS.md asks for.

The **reference** values are documentation. A `pytest_terminal_summary` hook in the local conftest prints one line per scenario with id, outcome, glyphs, characters, seconds, MB and budget. That table is what goes into the PR.

**5. The matrix.** The reference numbers are from the reference machine (§Shared definitions 6). Budgets are about 3× the reference time (at least 15 s) and 1.5× its RSS, rounded to a tier. "Chars" means code points. Rule groups not listed are `null`. PS means PostScript name. File hints are for humans: the locator finds fonts by PostScript name.

| ID | Fonts (PS name → file hint) | Rules → material | Weight / style | Expected | Must-have issues | Extra checks | Reference: glyphs / chars / s / MB | Budget s / MB | Findings |
|---|---|---|---|---|---|---|---|---|---|
| AF-01 | `HelveticaNeue` (HelveticaNeue.ttc) + `PingFangSC-Regular` (AssetsV2 …/PingFang.ttc) | kana, han, cjk_symbols, emoji → 1 | — | ok | — | ratio ≤ 1.10; `fs_type` 4; licence_notes has an `apple-sla` note including index 1 | 39,252 / 37,350 / 17.3 / 786 | 60 / 1,536 | ENGINE-1, -3, -5 |
| AF-02 | `PingFangSC-Regular` | — | — | ok | — | ratio ≤ 1.10 (reference 1.342) | 38,054 / 35,854 / 16.6 / 794 | 60 / 1,536 | ENGINE-3 |
| AF-03 | `.SFNS-Regular` (SFNS.ttf, variable) + `HiraginoSans-W3` (ヒラギノ角ゴシック W3.ttc) | kana, han, cjk_symbols → 1 | — | ok | — | ratio ≤ 1.50; output has no `fvar`; `fs_type` 8 | 19,973 / 14,726 / 17.2 / 412 | 60 / 1,024 | ENGINE-3, -6 (instancing only) |
| AF-04 | `AvenirNext-Regular` (Avenir Next.ttc) + `AppleSDGothicNeo-Regular` | hangul, kana, han, cjk_symbols → 1 | — | ok | — | ratio ≤ 1.10; `fs_type` 4 | 18,746 / 18,468 / 6.0 / 273 | 30 / 512 | ENGINE-3 |
| AF-05 | `Georgia` (Supplemental) + `PingFangHK-Regular` | kana, han, cjk_symbols, emoji → 1 | — | ok | — | ratio ≤ 1.10 (reference closure 1.368); `fs_type` 4 | 34,504 / 33,793 / 16.4 / 763 | 60 / 1,536 | ENGINE-3, -5 |
| AF-06 | `Courier` (Courier.ttc #0; no OS/2) | — | — | ok | `os2_synthesized`@0 | — | 1,237 / 1,230 / 0.1 / 40 | 15 / 512 | ENGINE-M1 |
| AF-07 | `Courier-Bold` (Courier.ttc #1; no OS/2, macStyle bold) | — | 700 / Bold | ok | `os2_synthesized`@0 | `synthetic_bold` absent | — | 15 / 512 | ENGINE-M1 |
| AF-08 | `AvenirNext-Regular` + `AppleGothic` (Supplemental; no OS/2) | hangul → 1 | — | ok | `os2_synthesized`@1 | — | 18,417 / 18,267 / 5.0 / 204 | 30 / 512 | ENGINE-M1 |
| AF-09 | `Cochin` (Cochin.ttc #0; `(0,1)` cmap, `bdat/bloc`) | — | — | ok | `bitmaps_dropped`@0 | — | 1,079 / 1,084 / 0.1 / 40 | 15 / 512 | ENGINE-M2, -1, -12 |
| AF-10 | `Geneva` (Geneva.ttf; `(0,3)` format 12, `bdat/bloc`) | — | — | ok | `bitmaps_dropped`@0 | — | 3,254 / 3,249 / 0.2 / 46 | 15 / 512 | ENGINE-M2, -1, -12 |
| AF-11 | `AvenirNext-Regular` + `AppleMyungjo` (no OS/2, `bdat/bloc`) | hangul → 1 | — | ok | `os2_synthesized`@1, `bitmaps_dropped`@1 | — | 18,373 / 18,216 / 8.1 / 247 | 30 / 512 | ENGINE-M1, -M2 |
| AF-12 | `HelveticaNeue-Bold` (HelveticaNeue.ttc #1) + `PingFangSC-Regular` | kana, han, cjk_symbols, emoji → 1 | 700 / Bold | ok | `synthetic_bold`@1, `bold_size_doubled`@1 | `bold_glyphs_skipped` absent | 39,246 / 37,345 / 65.2 / 1,063 (25.0 MB file) | 200 / 1,792 | ENGINE-4 |
| AF-13 | `.SFNS-Regular` + `HiraginoSans-W6` | kana, han, cjk_symbols → 1 | 700 / Bold | ok | `synthetic_bold`@1 | `bold_size_doubled` and `bold_glyphs_skipped` absent | 19,973 / 14,726 / 41.1 / 556 | 150 / 1,024 | ENGINE-4 |
| AF-14 | `AvenirNext-Regular` + `GeezaPro` (AAT only) | arabic → 1 | — | `aat_unsupported_script` | — | `error_material` 1 | — | 15 / 512 | ENGINE-2 |
| AF-15 | `AvenirNext-Regular` + `Damascus` (GSUB `arab` + morx) | arabic → 1 | — | ok | — | shaping identical (§6); `materials[1].name` starts with `Damascus` | 2,646 / 2,009 / 0.5 / 56 | 15 / 512 | ENGINE-2, -M4 |
| AF-16 | `AvenirNext-Regular` + `KohinoorDevanagari-Regular` | indic → 1 | — | ok | — | shaping identical (§6) | 2,153 / 1,112 / 0.6 / 63 | 15 / 512 | ENGINE-2 |
| AF-17 | `AvenirNext-Regular` + `DevanagariMT` (AAT only) | indic → 1 | — | `aat_unsupported_script` | — | `error_material` 1 | — | 15 / 512 | ENGINE-2 |
| AF-18 | `AvenirNext-Regular` + `Thonburi` (AAT only) | southeast_asian → 1 | — | `aat_unsupported_script` | — | `error_material` 1 | — | 15 / 512 | ENGINE-2 |
| AF-19 | `AvenirNext-Regular` + `PingFangSC-Regular` + `HiraginoSans-W3` + `AppleSDGothicNeo-Regular` | han, cjk_symbols, emoji → 1; kana → 2; hangul → 3 | — | ok | — | glyphs ≤ 58,000 and ratio ≤ 1.15 (reference 64,363 / 1.324); `fs_type` 4 | 53,217 / 48,610 / 22.9 / 865 | 75 / 1,536 | ENGINE-3 |
| AF-20 | `AvenirNext-Regular` + `HiraginoSans-W3` + `AppleSDGothicNeo-Regular` | han, kana, cjk_symbols → 1; hangul → 2 | — | ok | `cmap_format4_partial`@null | output cmap has `(3,1,4)` and `(3,10,12)`; CoreText maps U+D55C (§6) | 30,915 / 26,348 / 16.0 / 482 | 60 / 1,024 | N-1 |
| AF-21 | `HelveticaNeue` + `AppleSymbols` | symbols, emoji, other → 1 | — | ok | — | — | 5,215 / 5,196 / 0.7 / 62 | 15 / 512 | ENGINE-1 |
| AF-22 | `HelveticaNeue` | — | — | ok | — | `total_codepoints` == `len(getBestCmap())` of the source face; CoreText width check (§6) | 2,088 / 2,085 / 0.2 / 50 | 15 / 512 | ENGINE-1, -7 |
| AF-23 | `HelveticaNeue` + `STSongti-SC-Regular` (Songti.ttc) | kana, han, cjk_symbols, emoji → 1 | — | ok | — | ratio ≤ 1.10; `fs_type` 8 | 34,135 / 34,353 / 9.7 / 358 | 45 / 768 | ENGINE-3 |
| AF-24 | `NotoSansCham-Regular` (Supplemental) | — | — | ok | — | `total_glyphs` == source `maxp.numGlyphs` (132; the verifier's rule gives 129); licence_notes has no `apple-sla` note | 132 / 104 / 0.0 / 37 | 15 / 512 | ENGINE-3 (alias rule), -5 |
| AF-25 | `ArialUnicodeMS` (Supplemental/Arial Unicode.ttf) | — | — | ok | — | ratio ≤ 1.10 (reference 1.294) | 41,280 / 38,917 / 5.8 / 381 | 30 / 768 | ENGINE-3 |
| AF-26 | `HelveticaNeue` + `AppleColorEmoji` | emoji → 1 | — | `unsupported_font` | — | `error_material` 1 | — | 15 / 512 | ENGINE-12 |
| AF-27 | `.SFDevanagari-Regular` (SFIndia.ttc; CFF2) | — | — | `unsupported_font` | — | `error_material` 0 | — | 15 / 512 | ENGINE-12 |
| AF-28 (optional) | `AvenirNext-Regular` + `SIL-Hei-Med-Jian` (AssetsV2 …/Hei.ttf; Font Book download) | han, cjk_symbols → 1 | — | ok | `os2_synthesized`@1, `bitmaps_dropped`@1 | — | 8,421 / 8,266 / 2.7 / 121 | 15 / 512 | ENGINE-M1, -M2 |
| AF-29 | AF-04 with `expect.postscript_name = "NotAppleSDGothicNeo"` for material 1 | as AF-04 | — | `stale_material` | — | `error_material` 1 | — | 15 / 512 | ENGINE-8 |
| AF-30 | `AvenirNext-Regular` + `Damascus`, family `"Avenir Next دمشق"` | arabic → 1 | — | ok | — | `postscript_name` matches `^[A-Za-z0-9-]{1,63}$`, is not `AvenirNext-Regular`, and is not in the index | — | 15 / 512 | ENGINE-M3 |
| AF-31 | `AvenirNext-Regular`, family `"我的字体"`, two forges: style Regular and style Bold | — | — / Regular, Bold | ok | — | both PostScript names ASCII, different, and not in the index | — | 15 / 512 each | ENGINE-M3 |

`HiraginoSans-W6` has `weight_class` 600, so AF-13 applies +100 of synthetic bold. SF has a `wght` axis and is instanced at 700. AF-12 is the audit's failing case: the retry rescues both of PingFang's failing glyphs at +300.

**Finding → proof** (what "closes all ENGINE-*" means here):

| Finding | Proved by |
|---|---|
| ENGINE-1 | AF-01, AF-09, AF-10, AF-21, AF-22 |
| ENGINE-2 | AF-14, AF-17, AF-18 (errors); AF-15, AF-16 (OpenType controls, shaping identical); `test_scan` shapes_groups |
| ENGINE-3 | AF-02, AF-05, AF-19, AF-24, AF-25; calibration test |
| ENGINE-4 | AF-12, AF-13 |
| ENGINE-5 | `fs_type` and licence checks on AF-01, AF-03, AF-04, AF-05, AF-19, AF-23, AF-24 (WP-110 rules, engine-metadata.md) |
| ENGINE-6 | Not closed (B-1). AF-03 and AF-13 only prove that the variable SF instances |
| ENGINE-7 | AF-22 (Helvetica Neue kern v0 survives: width check). AF-12 also has `kerx`, but Helvetica Neue Bold carries legacy `kern` pairs: when those convert to a GPOS `kern` feature, WP-107 preserves kerning and correctly emits no `aat_kerning_dropped` warning |
| ENGINE-8 | AF-29 |
| ENGINE-9 | `test_cancel`; the RSS budgets |
| ENGINE-10, ENGINE-M4 | `test_scan` |
| ENGINE-11 | Not closed (B-2) |
| ENGINE-12 | AF-09, AF-10, AF-26, AF-27 |
| ENGINE-M1 | AF-06, AF-07, AF-08, AF-11, AF-28 |
| ENGINE-M2 | AF-09, AF-10, AF-11, AF-28 |
| ENGINE-M3 | AF-30, AF-31 |
| N-1 | AF-20 |

**6. CoreText checks** (`coretext.py`, `test_shaping.py`). They use pyobjc `CoreText` and `Foundation` only, with URL descriptors only:

```python
@dataclass
class Shaped:
    glyph_names: list[str]      # names from the font's own glyph order, '#<n>' merge suffixes stripped
    foreign_glyphs: int         # glyphs CoreText took from another font (cascade)
    width: float                # CTLineGetTypographicBounds width, points

def shape(path: str, postscript_name: str | None, text: str, face_index: int = -1, size: float = 24.0) -> Shaped
def glyph_for(path: str, postscript_name: str | None, char: str) -> int     # 0 when unmapped
# glyph_for uses CTFontGetGlyphsForCharacters on the UTF-16 code units of `char` (one unit for BMP characters)
```

- **Fonts.** `CTFontManagerCreateFontDescriptorsFromURL(NSURL.fileURLWithPath_(path))`. Pick the descriptor whose `CTFontDescriptorCopyAttribute(desc, kCTFontNameAttribute)` equals `postscript_name`, or the first one when the name is `None`, which is the case for forged files. Then `CTFontCreateWithFontDescriptor(desc, size, None)`. There is no registration and no lookup by name.
- **Shaping.** `CTLineCreateWithAttributedString` → `CTLineGetGlyphRuns` → `CTRunGetGlyphs`. Map glyph IDs to names through `TTFont(path, fontNumber=face_index, lazy=True).getGlyphOrder()`. A run whose `CTFontCopyPostScriptName` differs from the chosen font counts as foreign.
- **AF-15.** `"مرحبا بالعالم"` shaped with the source `Damascus` and with the forged file gives equal `glyph_names` (13 glyphs, joined forms such as `u0645.final.meem`) and `foreign_glyphs == 0` for both.
- **AF-16.** `"नमस्ते क्षत्रिय"` shaped with the source `KohinoorDevanagari-Regular` and with the forged file gives equal `glyph_names` (9 glyphs).
- **AF-22.** `"office fifty flow AVAWAY"`: `abs(width_source − width_forged) <= 0.5` at 24 pt (reference 256.2 against 256.1), and `foreign_glyphs == 0` for the forged file.
- **AF-20.** `glyph_for(forged, None, "한") != 0` and `glyph_for(forged, None, "힣") != 0`. Both lie above the partial format 4 subtable's range.

Reference evidence: with the pre-WP-107 engine, Geeza Pro, Devanagari MT and Thonburi shape differently after forging (unjoined, 9 → 15 glyphs, 10 → 22 glyphs). This is why AF-14, AF-17 and AF-18 must be errors.

**7. Scan metadata on real files** (`test_scan.py`). One `scan` run over `GeezaPro.ttc`, `SFNS.ttf`, `LastResort.otf`, `Courier.ttc` (all in `/System/Library/Fonts`) and `Damascus.ttc` (in `Supplemental`), each located by file name under `SEARCH_ROOTS` (skip with the reason when a file is missing). The test reads the `face` events and the terminal `result`. FaceRecord fields are per contracts.md §3 and the WP-106/107/108 rules in engine-metadata.md:
- Geeza Pro: `family == "Geeza Pro"` (ENGINE-M4), `aat.morx` is true, and `"arabic"` is not in `shapes_groups`.
- Damascus: `family == "Damascus"`, and `"arabic"` is in `shapes_groups`.
- SFNS: `hidden` is true (ENGINE-10).
- LastResort: `suspicious_coverage` is true.
- Courier: `has_os2` is false for all 4 faces, and `Courier-Bold` has `weight_class == 700` (WP-103).

**8. Cancel** (`test_cancel.py`, ENGINE-9). Start AF-02's request with `cancel_after_s=5.0`, so SIGTERM arrives during prepare. Then `returncode == 143`, the process has exited within 2.5 s after SIGTERM, no `result` or `error` event was written, and `TMPDIR` (`tmpdir/helper-tmp`) is empty afterwards (ADR-0003).

**9. Glyph-estimate calibration** (`calibration.py`, `test_calibration.py`, WP-104):

```python
VARIANT_FACTOR = 0.8     # must equal FPCore's constant (core.md, WP-303); change both together
GLYPH_WARN = 55_000      # must equal FPCore's constant (core.md, WP-303)
MAX_GLYPHS = 65_535
CALIBRATION = ("AF-01", "AF-02", "AF-03", "AF-04", "AF-05", "AF-19", "AF-20", "AF-23")

def estimate(glyph_counts: Sequence[int], cmap_sizes: Sequence[int], assigned: Sequence[int]) -> int:
    return 1 + sum(round(g * a / max(c, 1) * VARIANT_FACTOR) for g, c, a in zip(glyph_counts, cmap_sizes, assigned))
```

`glyph_counts` and `cmap_sizes` come from the source faces (`maxp.numGlyphs`, `len(getBestCmap())`, read with fontTools). `assigned` is the report's `materials[i].codepoints`. With `err = (estimate − total_glyphs) / total_glyphs` for each calibration scenario that ran:
- every run with `total_glyphs >= 30_000` has `−0.18 <= err <= +0.22`;
- AF-19 has `abs(err) <= 0.10`;
- `GLYPH_WARN <= 65_535 × (1 + min(err over runs with total_glyphs >= 30_000))`. The reference minimum is −14.1 % (AF-20), so the bound is 56,294.

**10. Linux-safe checks.**
- `engine/tests/test_apple_fonts_locate.py` builds a fake tree in `tmp_path`. It has `Fonts/`, `Fonts/Supplemental/` and `AssetsV2/com_apple_MobileAsset_Font9/abc.asset/AssetData/`, holding `build_font` fonts, one `.ttc` from `build_collection`, one file with an NFD name (`"ヒラギノ W3.ttf"` NFD-normalised) and one garbage file. It checks the resolution order, TTC indexes, NFD handling, `unreadable`, and that a missing name is absent.
- `engine/tests/test_apple_fonts_safety.py` has two tests.
  - `test_no_name_lookups_or_installs` reads every `.py` under `engine/tests/apple_fonts/`. It fails if any contains one of the substrings `CTFontCreateWithName`, `CTFontDescriptorCreateWithNameAndSize`, `CTFontDescriptorCreateMatchingFontDescriptor`, `CTFontDescriptorCreateWithAttributes`, `CTFontManagerRegister`, `CTFontManagerActivate`, `NSFont`, `AppKit`, `shutil.copy`, `shutil.move` or `copyfile`. The substrings `Path.home` and `expanduser` may appear only in `conftest.py` (the read-only `_font_folders_untouched` fixture below needs the home folder); any other file containing them fails. It also checks that every entry of `locate.SEARCH_ROOTS` and `locate.ASSET_GLOB` starts with `/System/Library/`. Because the check is textual, do not write these API names in comments or docstrings under `apple_fonts/` either (say "name-based CoreText lookups" instead).
  - `test_apple_fonts_gated_without_env` runs `[sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", "<engine>/tests/apple_fonts"]` in a subprocess, with `FP_APPLE_FONTS` removed from the environment. The exit code is 0, the summary line reports skipped items and no `passed`/`failed`/`error`, and the run takes under 30 s. That proves no helper was started.
- The local conftest has an autouse, session-scoped fixture `_font_folders_untouched`. At session start it snapshots `sorted((name, st_size, st_mtime))` of `~/Library/Fonts` and `/Library/Fonts` (read-only listing; a missing folder counts as empty). At teardown it asserts both snapshots are unchanged. The fixture only lists these folders and never writes to them.

**11. Dependency.** `pyobjc-framework-CoreText` is in the engine's `dev` dependency group with the marker `sys_platform == 'darwin'` since WP-001 (foundation-release.md), because linux WPs cannot re-lock offline. Check that it is there; add it and re-lock (this WP runs on the Mac, with network) only if it is missing. It pulls in `pyobjc-framework-Cocoa`, which provides `Foundation`. It is never part of the helper runtime, which WP-203 installs from the non-dev lock (ADR-0004: no PyObjC in the helper). On Linux the marker excludes it.

### Acceptance criteria
- **AC-111-1** On an Apple silicon Mac with the stock fonts of the reference macOS version (§Shared definitions 6), `make engine-apple-fonts` passes (with `FP_APPLE_FONTS_TIME_FACTOR` unset on a machine at least as fast as the reference, or set as in Verification on a slower one). It reports 0 failures and 0 errors, and at most AF-28 is skipped (Font Book download). The PR pastes the terminal summary table.
- **AC-111-2** `test_scenarios.py::test_scenario[AF-01]` … `[AF-31]` pass. Each asserts its row of the matrix in §5 as specified in "Checks for every scenario": expected outcome, must-have and forbidden issue codes, glyph bounds, `fs_type`, time and RSS budgets, and output-file consistency.
- **AC-111-3** `test_calibration.py::test_glyph_estimate_calibration` passes with the §9 bounds, and prints each calibration run's `err`.
- **AC-111-4** `test_shaping.py`: `test_damascus_shapes_like_source` (AF-15), `test_kohinoor_shapes_like_source` (AF-16), `test_helvetica_neue_kerning_width` (AF-22) and `test_hangul_beyond_format4_maps` (AF-20) pass.
- **AC-111-5** `test_scan.py::test_real_face_metadata` passes with the §7 assertions.
- **AC-111-6** `test_cancel.py::test_sigterm_during_prepare` passes: exit 143 within 2.5 s of SIGTERM, no terminal event, `TMPDIR` empty.
- **AC-111-7** On Linux, `make engine-test` passes, the `apple_fonts` items are skipped with the reason `"needs macOS and FP_APPLE_FONTS=1"`, and `test_apple_fonts_locate.py` and `test_apple_fonts_safety.py` run and pass.
- **AC-111-8** `test_apple_fonts_safety.py::test_apple_fonts_gated_without_env` passes on macOS under `make engine-test`: with `FP_APPLE_FONTS` unset, every `apple_fonts` item is skipped and no helper process starts.
- **AC-111-9** `make engine-apple-fonts` finishes without a teardown error from `_font_folders_untouched`, so `~/Library/Fonts` and `/Library/Fonts` are unchanged by the run. `test_apple_fonts_safety.py::test_no_name_lookups_or_installs` passes (on Linux and macOS), so the suite contains no name-based CoreText lookup, registration or copying API, and only `conftest.py` refers to the home folder.
- **AC-111-10** `test_scenarios.py::test_engine_finding[…]` passes for every key of `FINDING_PROOFS` (ENGINE-1, -2, -3, -4, -5, -7, -8, -12, -M1, -M2, -M3 and N-1; ENGINE-9, -10 and -M4 are proved by AC-111-5 and AC-111-6), and `FINDING_PROOFS` has exactly the AF ids of those rows of the "Finding → proof" table.
- **AC-111-11** `test_apple_fonts_safety.py::test_interim_report_fields_are_gone` passes on Linux: `fpengine.protocol.report.INTERIM_REPORT_FIELDS == {}` (helper.md H9), so every protocol `ForgeReport` field comes from the engine at the M1 exit.
- **AC-111-12** (parity §6 "Result"; runs on Linux under `make engine-test`) `test_parity_result_properties` in `engine/tests/test_result_parity.py`. Two fixtures are built in `tmp_path` with the ported `build_font`:
  - **P** = `build_font(tmp/"P.ttf", "Fixture P", "Regular", cps("ab"), kern={(ord("a"), ord("b")): -50})`, then given TrueType hinting and saved: `fpgm` and `prep` tables whose `program` is a `fontTools.ttLib.tables.ttProgram.Program` from `fromBytecode(b"\xb0\x00")`, a `cvt ` table with `values = array.array("h", [16])`, and glyph `uni0061` with the program `fromBytecode(b"\xb0\x00\x21")`;
  - **Q** = `build_font(tmp/"Q.ttf", "Fixture Q", "Regular", cps("漢字"))`, then `fontTools.feaLib.builder.addOpenTypeFeaturesFromString(font, "languagesystem DFLT dflt; languagesystem hani dflt;\nfeature liga { sub uni6F22 uni5B57 by uni5B57; } liga;\n")`, `hhea` (ascent, descent, lineGap) = (950, −250, 30) and `OS/2` (`sTypoAscender`, `sTypoDescender`, `sTypoLineGap`, `usWinAscent`, `usWinDescent`) = (950, −250, 30, 960, 260), then saved.

  Forging `ForgeSpec([MaterialSpec(P), MaterialSpec(Q)], base_index=1, script_rules={"han": 1}, family_name="Parity Mix", style_name="Regular")` succeeds, and the output has all of these:
  1. *One glyph per character, no unused glyphs:* `set(getBestCmap()) == cps("ab漢字")` and `maxp.numGlyphs == report.total_glyphs == 5` (4 characters + `.notdef`).
  2. *Hinting removed:* no `fpgm`, `prep` or `cvt ` table, every table except `GlyphOrder` is in `KEEP_TABLES`, and no `glyf` glyph has non-empty instructions (`getattr(g, "program", None)` is `None` or `g.program.getBytecode() == b""`).
  3. *OpenType features kept per font:* the GSUB FeatureList has `liga`, and the GPOS FeatureList has `kern`.
  4. *Legacy `kern` converted to GPOS:* `"kern" not in font`, and the PairPos format 1 `XAdvance` for (`uni0061`, `uni0062`) is −50 (copy `_pairpos_values` from the ported `test_forge.py`; don't import across test modules).
  5. *Fresh name table:* name ID 0 starts with `"Forged with Font Playground"`, name ID 1 is `"Parity Mix"`, and no record other than name ID 0 contains `"Fixture P"` or `"Fixture Q"`.
  6. *Vertical metrics from the main (line-spacing) font:* `hhea` (ascent, descent, lineGap) == (950, −250, 30), and the five `OS/2` values == (950, −250, 30, 960, 260). Control: the same forge with `base_index=0` gives `hhea` (800, −200, 0).

  All six held for the reference engine (fontTools 4.66) when this AC was written. WP-701 cites this test as the evidence for the parity item "Result", together with AC-111-2 and AC-111-4 on real fonts.

### Verification
```bash
make engine-test                                       # Linux and macOS: locate + safety tests; apple_fonts skipped
make engine-apple-fonts                                # macOS: the matrix (about 6 minutes on the reference machine)
FP_APPLE_FONTS_TIME_FACTOR=2 make engine-apple-fonts   # slower Macs / CI runners
make lint
```

### Notes for the implementer
- Never run the suite in parallel (no `-n`). Budgets assume one forge at a time.
- **Dependency on WP-201** (see backbone note). The suite drives `python -m fpengine forge|scan`, reads contract error codes and relies on SIGTERM → exit 143. It also uses WP-107 (`aat_unsupported_script`, AAT warnings), WP-109 (PostScript names) and WP-110 (`fs_type`, `licence_notes`) as specified in engine-metadata.md. When a check fails because one of those behaves differently from its spec, fix that WP rather than loosening the check.
- **Which fonts are required.** PingFang is an AssetsV2 font preinstalled on current macOS, at a path containing a content hash that changes with updates (ENGINE-8). Always find it through `ASSET_GLOB`. Hei, Kai and GungSeo are Font Book downloads. AF-28 is `optional`, and a missing optional font is not a failure.
- **Reference numbers.** They are for macOS 27.0. The checks use ratios and structural bounds so that font updates do not break them. If a macOS update changes a count enough to break a bound, re-measure, confirm the engine is not at fault (compare with the reference closure numbers in WP-104), and update `scenarios.py` and this table in one PR.
- `AF-24` asserts `total_glyphs == maxp.numGlyphs` of Noto Sans Cham 2.x, which has no unreachable glyphs. If a future version adds some, replace the check with "equal to the glyph set reachable with `clig` kept" and say so in the PR.
- The audit's `forge_one.py`/`vforge.py` harnesses pinned groups through `smart.resolve_rules`. This suite states explicit `rules` instead, because there is no Python `smart` any more. The rules above reproduce the audit's plans (identical glyph and character counts).
