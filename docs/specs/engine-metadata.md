# Engine metadata, AAT guard, names and licences

> Scope: WP-106, WP-107, WP-108, WP-109, WP-110 · Env: linux · Architecture refs: docs/architecture.md §2 (`fpengine`), §4 (steps 2 Scan, 3 Catalog, 6 Forge), §5 (identity of a face), §8 (no silent drops) · ADRs: 0002, 0003, 0007, 0008, 0009, 0011, 0012

## Context

Everything in this spec is Python in `engine/` and runs on Linux with synthetic fonts. No WP here needs macOS. Real Apple fonts are exercised later by WP-111 (see [Hand-off to WP-111](#hand-off-to-wp-111-real-font-checks)).

**What the original app does** (`reference/fontplayground-py/`, read-only):

- **Reading faces.** `fontplayground/catalog/face.py:170-197` (`_face`) builds one frozen `FontFace` per face. It reads family and style with `_best_name` (`:109-128`), which uses `_name_rank` (`:100-106`). That ranking puts **any** Windows record ahead of a Mac Roman English record (1,0,0). `_local_names` (`:131-160`) falls back only to Mac Japanese (1,1) records. `_face` indexes `font["head"]` unconditionally (`:191-192`), and embedding comes from fsType (`:90-97`). No OpenType script tags, AAT flags, PostScript name, licence data or sanity flags are read. `read_faces` (`:200-214`) opens `.ttc/.otc` through `TTCollection(lazy=True)`.
- **Naming the result.** `fontplayground/engine/merge.py:50-71` (`set_names`) writes a fresh name table. Name ID 0 is `f"{FORGED_NOTICE} from: …"` (`FORGED_NOTICE`, `:47`). Name ID 3 is `"{full}; FontPlayground {date}"`, name ID 5 is always `"Version 1.000"`, and name ID 6 comes from `postscript_name` (`:32-36`), which deletes every non-ASCII character and falls back to `Forged`/`Regular`.
- **Licence.** `merge.py:120` sets the output `OS/2.fsType = 0` unconditionally. `fontplayground/engine/forge.py:23-24` warns only for `restricted` sources.
- **Forged marker.** `fontplayground/ui/install.py:63-75` (`is_forged`) is true when name ID 0 (`getDebugName(0)`) starts with `FORGED_NOTICE`.
- **Planning.** `fontplayground/engine/planner.py:10-27`: `source_of` gives each code point to the ruled material if it has the character, otherwise to the first material that has it. `plan()` feeds it each face's full `codepoints`.
- **AAT.** Nothing. `prepare.py:19` (`KEEP_TABLES`) and `strip_tables` (`:131-134`) drop `morx`/`kerx`/`trak` silently. `kern.py:20-31` converts only format-0 `kern` subtables.

**What the audit found** (`docs/research/macos-audit.md`; the verifier's recommendation wins where it differs):

| Finding | Verified severity | What goes wrong on macOS | WP |
|---|---|---|---|
| ENGINE-2 | blocker | 189 faces (84 families) have `morx` and no `GSUB`. They forge without an error, but the result is broken: Arabic comes out unjoined, and Indic and Thai lose their shaping. The check must be **per script tag**, not "has GSUB" (verifier) | 106 (scan data), 107 (guard) |
| NATIVE-6 | major | The same issue from the architecture view: the preview shapes with `morx`, and the result cannot | 106 |
| NATIVE-M1 | major | The result must never depend on shaper fallbacks, such as presentation forms still in `cmap` | 107 |
| UI-M2 | major | The preview is not honest for AAT fonts. Ligatures (Helvetica Neue fi/fl) and Indic shaping are lost silently | 107 |
| ENGINE-7 | minor | AAT kerning is dropped silently: `kern` v1 subtables of format 1, 2 or 3, and `kerx` (Geeza Pro: twelve format-1 subtables) | 107 |
| CATALOG-2 | blocker | 112 hidden `.`-faces reach the catalog. `.LastResort` (7 glyphs, 1,114,112 code points) becomes the top suggestion | 106 |
| ENGINE-10 | polish | Hidden `.`-families (.SF Arabic, .New York…) are listed and forged | 106 |
| CATALOG-8 | polish | NISC18030.ttf has `bhed` instead of `head`, which gives a permanent "1 file couldn't be read" | 106 |
| CATALOG-3 | major | Arabic and Indic Apple fonts get native family and style names (Al Bayan → 'البيان'). 33 faces disagree with CoreText | 108 |
| UI-M1 | major | The same fonts can't be found by their English name | 108 |
| ENGINE-M4 | minor | Those native names reach the report, name ID 0 and the default family names | 108 |
| CATALOG-M2 | minor | Native names stored only in Mac Chinese and Korean records are ignored (STSong 华文宋体, LiSong Pro 儷宋 Pro) | 108 |
| ENGINE-M3 | major | The forged PostScript name can equal a system font's name (`AvenirNext-Regular`), or collapse to `Forged-Regular` | 109 |
| INSTALL-5 | major | Every CJK-named forged font gets `Forged-Regular`. The style fallback also collides (粗体 and 细体 both become `Regular`) | 109 |
| ENGINE-5 | major | fsType is always 0, and there is a warning only for "restricted". The verifier's correction: 140 of 398 `/System/Library` files are OFL or Apache, so "bundled with macOS" does not mean "licensed for this Mac only" | 110 |
| CRIT-3 | minor | The Microsoft Office `DFonts` are licensed for use with the Microsoft product only | 110 |

## Shared definitions

These are normative for all five WPs.

### S1. Where things live

Paths are WP-002's layout (foundation-release.md WP-002 §1): the reference `fontplayground/engine/*.py` lives at `engine/src/fpengine/*.py`, `fontplayground/catalog/face.py` lives at `engine/src/fpengine/face.py`, and the reference cache's dict helpers (`_ranges`, `_expand`, `face_to_dict`, `face_from_dict`, `catalog/cache.py:13-40`) live in `engine/src/fpengine/records.py` as `ranges`, `expand`, `face_to_dict` and `face_from_dict`. There is **no** `fpengine/catalog/` package and no ported `CatalogCache`/`SCHEMA` (WP-002's `test_tooling_18_engine_has_no_discovery_or_cache_io` asserts that `fpengine.catalog` does not exist; Swift owns the cache, WP-401). Tests are in `engine/tests/`, with the ported `fixtures.py` (`build_font`, `build_collection`, `fake_face`, `cps`), the ported `test_records.py`, and the `font_dir` session fixture. If a module is somewhere else on `main`, edit it where it actually is and note that under "Spec deviations"; do not add alias modules.

| Module | Owner in this spec | Content |
|---|---|---|
| `fpengine/face.py` | 106, 107, 108, 110 edit (103 changes one line, engine-correctness.md) | `FontFace` v2, `read_faces`, name ranking, `source_notices`, `READER_VERSION` |
| `fpengine/records.py` (created by WP-002 with `ranges`, `expand`, `face_to_dict`, `face_from_dict`) | 106 edits | adds `FACE_RECORD_KEYS`, `face_record`, `face_from_record`: `FaceRecord` JSON serialisation (contracts §3) |
| `fpengine/licence.py` (new) | 106 creates, 110 completes | `vendor_id_of` and `normalise_notice` (106); classification, fsType propagation, note texts (110). A leaf module: it never imports `face.py` |
| `fpengine/shaping.py` (new) | 107 | Script shaping table, `unshaped`/`shapes_groups`, rule check, OpenType alternatives |
| `fpengine/naming.py` (new) | 109 | `FORGED_NOTICE`, `clean_name`, `postscript_name`, version and unique ID, `is_forged` |
| `fpengine/spec.py` | 107, 109, 110 edit | `ForgeError` fields, `Issue`, `LicenceNote`, `ForgeReport` fields, `validate` rules |
| `fpengine/merge.py`, `forge.py`, `planner.py`, `prepare.py` | 107, 109, 110 edit | See each WP |

`fpengine` keeps using only fontTools (with `unicodedata2` through `fonttools[unicode]`) and the standard library. No new runtime dependency is added (AGENTS rule 11).

### S2. `FontFace` v2 and its `FaceRecord`

`FontFace` stays a `@dataclass(frozen=True)`: hashable, and comparable with `==`. The reference fields stay as they are (`face.py:18-38`). All new fields have defaults, so `fake_face()` and existing tests keep working. Fields are flat (no nested dataclasses), so any `dataclasses.asdict` user keeps working.

| `FontFace` field | Type | Default | `FaceRecord` key (contracts §3) | Filled in by |
|---|---|---|---|---|
| `full_name` | `str` | `""` | `full_name` (the record uses `display_name` when empty) | 106 (ranking from 108) |
| `postscript_name` | `str \| None` | `None` | `postscript_name` | 106 |
| `fs_type` | `int \| None` | `None` | `fs_type` | 106 |
| `has_os2` | `bool` | `True` | `has_os2` | 106 |
| `hidden` | `bool` | `False` | `hidden` | 106 |
| `suspicious_coverage` | `bool` | `False` | `suspicious_coverage` | 106 |
| `ot_gsub` | `tuple[str, ...]` | `()` | `ot_scripts.gsub` | 106 |
| `ot_gpos` | `tuple[str, ...]` | `()` | `ot_scripts.gpos` | 106 |
| `aat_morx` / `aat_kerx` / `aat_kern_v1` / `aat_trak` | `bool` | `False` | `aat.morx` / `.kerx` / `.kern_v1` / `.trak` | 106 |
| `font_revision` | `str` | `"1.000"` | `font_revision` | 106 |
| `is_forged` | `bool` | `False` | `is_forged` | 106 (the marker itself is defined by 109) |
| `vendor_id` | `str \| None` | `None` | `licence.vendor_id` | 106 |
| `licence_notice` | `str \| None` | `None` | `licence.notice` | 106 |
| `licence_class` | `str` | `"unknown"` | `licence.class` | 110 (106 always leaves `"unknown"`) |
| `unshaped` | `frozenset[int]` | `frozenset()` | `unshaped` (ranges; **proposed contract addition**) | 107 (106 leaves it empty) |
| `shapes_groups` | `tuple[str, ...]` | `()` | `shapes_groups` | 107 (106 leaves it empty) |

The existing `unsupported_reason`/`supported` properties feed `unsupported_reason`/`supported` in the record. `group_counts` keeps its reference meaning until WP-107, which switches it to plannable coverage (S4).

Why placeholders: WP-201 writes the JSON Schema in wave 4, in parallel with WP-107 and WP-110. The record shape must therefore be complete when WP-106 lands. The placeholder values have the final types.

### S3. `READER_VERSION`

`fpengine/face.py` defines `READER_VERSION: int`. It changes whenever `read_faces()` can return a different `FontFace` for the same file bytes. It carries on from the reference cache schema (`reference/…/catalog/cache.py:10`, `SCHEMA = 3`).

- A WP that changes what `read_faces` returns increases it by exactly 1: WP-103 (engine-correctness.md: the `weight_class` fallback), WP-106, WP-107, WP-108 and WP-110 each do. If the constant does not exist yet, create it with value 4. Two parallel PRs both raising it produce a merge conflict on that line; the second one rebases and increments again.
- The Swift catalog cache (WP-401) needs this number to invalidate its cache entries. The helper exposes it as `hello.face_reader_version` (helper.md WP-201, `spec/protocol/hello.schema.json`), and `FPEngineClient.EngineHello.faceReaderVersion` carries it to Swift (WP-204).

### S4. Complex groups and plannable coverage

- `COMPLEX_GROUPS = ("hebrew", "arabic", "indic", "southeast_asian")`, in `GROUPS` order (`reference/…/engine/scripts.py:16-32`). These are the groups ADR-0008 guards with an **error**.
- **Plannable coverage** of a face = `codepoints − unshaped`. It is the set of characters the face can contribute to a forged font **with the shaping the text needs**. `unshaped` is defined in WP-107 (rules U1/U2).
- The engine planner, `group_counts`, and every consumer that decides "which font draws this character" use plannable coverage: the Swift `source_of` callers, the suggestions, "draws it well" and the missing-character list. `coverage` (the raw best cmap) stays in the record for rendering and diagnostics.

### S5. Report and error types (in `fpengine/spec.py`)

`Issue` and `ForgeReport.issues` are **landed by WP-101** (engine-correctness.md Shared definitions 3: the same class, with `severity: Literal["warning", "error"]` and a `to_dict()` method, plus `PreparedFont.issues` and the `forge._report(..., forge_issues)` plumbing). WP-107 and WP-110 reuse that type and plumbing and never define a second one; the `Issue` block below only restates its fields. `ForgeError`'s keyword fields are added by the first of WP-107/WP-201 to land; the other reuses them. `LicenceNote` is WP-110's.

```python
class ForgeError(Exception):
    def __init__(self, stage: str, material: str | None, message: str, *,
                 code: str | None = None, material_index: int | None = None):
        # code: a contracts §5 error code; None lets the helper derive it from `stage`.
        # Sets self.stage, self.material, self.message (as the reference, spec.py:9-13), plus
        # self.code and self.material_index. str(e) keeps the reference format "[stage (material)] message".
        ...

@dataclass(frozen=True)
class Issue:                   # defined by WP-101 (engine-correctness.md Shared definitions 3); restated here
    code: str                  # see S6 and engine-correctness.md Shared definitions 4
    severity: IssueSeverity    # Literal["warning", "error"]
    material_index: int | None
    group: str | None          # script group id, or None
    message: str               # full sentence including the material's display name

@dataclass(frozen=True)
class LicenceNote:
    licence_class: str         # JSON key "class": "apple-sla" | "microsoft-product" | "unknown"
    material_indexes: tuple[int, ...]
    text: str
```

`ForgeReport` (reference `spec.py:112-129`) gains fields with defaults, so existing constructors still work:

| Field | Type | Added by |
|---|---|---|
| `family_name`, `style_name`, `postscript_name`, `full_name` | `str` (default `""`) | 109 |
| `issues` | `list[Issue]` (default empty) | 101 (engine-correctness.md) |
| `fs_type` | `int` (default `0`) | 110 |
| `licence_notes` | `list[LicenceNote]` (default empty) | 110 |

JSON serialisation of these (snake_case, with `LicenceNote.licence_class` written as `"class"`) belongs to WP-201 (contracts §4).

**Material notes.** Each material issue is built from a **note** (the exact texts given in WP-107 §7 and WP-110 §4), and its `message` is always `f"{face.display_name}: {note}"`. Every issue that has a `material_index` also appends its note to that material's `MaterialReport.warnings`. That keeps `ForgeReport.warnings` and `as_text()` in the reference format `f"{name}: {note}"` (`forge.py:28`). Report-level issues (`material_index` is `None`) are appended to `ForgeReport.warnings` as their `message`, after all material lines.

**Order of `MaterialReport.warnings`** (deterministic): the prepare warnings (`PreparedFont.warnings`, as in the reference), then the notes of that material's issues in issue order (below; `licence_*` issues excluded, see the next paragraph), then `"contributes no characters"` when the material's assignment is empty (reference `forge.py:25-26`). `ForgeReport.warnings` lists `f"{name}: {note}"` for every material note in material order, then the report-level messages.

The one exception is the `licence_*` issues. They are summarised once per class in `licence_notes` (WP-110), and are not repeated in the warnings. Otherwise every forge of an ordinary user font would carry a "Licence unknown" line per material.

**Issue order** is deterministic. Issues are sorted by `material_index` (stable sort, engine-correctness.md Shared definitions 3). Within one material, the engine-correctness codes come first in their raise order (`os2_synthesized`, `bitmaps_dropped`, `synthetic_bold`, `bold_glyphs_skipped`, `bold_size_doubled`), then the S6 codes in S6 row order (with `unshaped_left_out` by group, in `GROUP_IDS` order). Report-level issues come last (`cmap_format4_partial`, then `output_fs_type`).

### S6. Issue codes

| Code | Severity | `material_index` | `group` | Raised when | WP |
|---|---|---|---|---|---|
| `aat_morx_dropped` | warning | i | null | Material i contributes characters, has `morx` or `mort`, and has no `GSUB` script record | 107 |
| `aat_kerning_dropped` | warning | i | null | Material i contributes characters, has `kerx` or a `kern` subtable of format ≠ 0, and its prepared part has no GPOS `kern` feature | 107 |
| `aat_tracking_dropped` | warning | i | null | Material i contributes characters and has `trak` | 107 |
| `unshaped_left_out` | warning | i | group id | Characters material i covers but can't shape, which it would have drawn by priority or by rule, went to other fonts or were left out | 107 |
| `embedding_restricted` / `embedding_preview_print` / `embedding_editable` | warning | i | null | A contributing material's fsType class is not installable | 110 |
| `licence_apple_sla` / `licence_microsoft_product` / `licence_unknown` | warning | i | null | A contributing material's licence class is not `open` | 110 |
| `notices_left_out` | warning | i | null | Some of a contributing material's copyright or licence notices don't fit in the output's name table (WP-110 Design §5a) | 110 |
| `output_fs_type` | warning | null | null | The output fsType is not 0 | 110 |

The error code `aat_unsupported_script` is raised as a `ForgeError` with `stage="validate"` (WP-107). It is not an `Issue`.

The complete v1 set of issue codes is this table plus engine-correctness.md Shared definitions 4 (`cmap_format4_partial`, `bitmaps_dropped`, `os2_synthesized`, `synthetic_bold`, `bold_glyphs_skipped`, `bold_size_doubled`). Swift consumers (ui-shell.md WP-505/506) treat unknown codes as plain warnings.

### S7. Test fixture helpers (`engine/tests/meta_fixtures.py`, new in WP-106)

All helpers use fontTools only, so they work on Linux. WP-106 creates the complete API below. Later WPs use it and do not change its signature.

```python
def decorate(path: Path, *, out: Path | None = None,
             tables: Mapping[str, bytes] | None = None,   # opaque tables, e.g. {"morx": b"\0\2\0\0\0\0\0\0"}
             fea: str | None = None,                      # feaLib source, added with addOpenTypeFeaturesFromString
             drop: Iterable[str] = (),                    # table tags to delete, e.g. ("OS/2",)
             vendor: str | None = None,                   # OS/2.achVendID (padded to 4 with spaces)
             fs_type: int | None = None,                  # OS/2.fsType
             font_revision: float | None = None,          # head.fontRevision
             kern_v1_format: int | None = None,           # Apple kern v1 with one subtable of this format
             name_records: Mapping[int, list[tuple]] | None = None,  # same shape as build_font(name_records=…)
             ) -> Path:
    """Open a font made by fixtures.build_font, apply the changes, and save to `out` (default: in place)."""

def build_bitmap_only_font(path: Path, family: str, codepoints: Iterable[int], *, fs_type: int = 2) -> Path:
    """Like NISC18030.ttf: 'bhed' instead of 'head', and no glyf, loca, CFF, hmtx or hhea (CATALOG-8)."""

def build_many_to_one_font(path: Path, n_codepoints: int, *, glyphs: int = 3, start: int = 0x4E00) -> Path:
    """`glyphs` glyphs and a cmap that maps n_codepoints consecutive code points to one of them (.LastResort-like)."""
```

Implementation notes, checked with fontTools 4.66:

- **Opaque tables.** `fontTools.ttLib.tables.DefaultTable.DefaultTable(tag)` with `.data = bytes` survives save and load. The subsetter drops unknown AAT tables ("morx NOT subset… dropped"), so forging such fixtures works.
- **`kern_v1_format=0`.** `newTable("kern")` with `version = 1.0`, holding one `KernTable_format_0(apple=True)` with `coverage = 0`, `format = 0`, `tupleIndex = 0` and one pair (the first two non-`.notdef` glyphs, value −40).
- **`kern_v1_format` in 1…3.** `KernTable_format_unkown(fmt)` (the fontTools spelling) with `.data = struct.pack(">LBBH", 14, 0, fmt, 0) + b"\0" * 6`. Reading it back gives `kern.version == 1.0`, a subtable `.format == fmt`, and raw table bytes that start with `00 01 00 00`.
- **`build_bitmap_only_font`.** Build with `FontBuilder`. Copy the `head` table's attributes into `newTable("bhed")`, then delete `glyf`, `loca`, `head`, `hmtx` and `hhea`, and set `maxp.tableVersion = 0x00005000`. `TTFont(path)["head"]` then raises `KeyError`, which is exactly the reference failure.

### S8. Landing order and overlaps

- **Wave 3** (106 ∥ 108 ∥ 109) and **wave 4** (107 ∥ 110). Several of these WPs edit the same files: `face.py` (106/107/108/110), `forge.py` and `spec.py` (107/109/110), `merge.py` (109/110), and `prepare.py` (107, after 101–105).
- Merge in numeric order within a wave, and rebase.
- WP-110 builds on WP-109's `set_names`/`finish` and report names. WP-109 lands in wave 3, before WP-110 starts.
- WP-107 and WP-110 reuse `Issue`, `ForgeReport.issues` and the `forge._report(..., forge_issues)` plumbing that WP-101 lands in wave 3 (engine-correctness.md Shared definitions 3). Dispatch them only after WP-101 is on `main` (it is not in the plan's "Depends on" column; backbone note). WP-107 merges after WP-101–105; in the code, its AAT-loss capture sits right after `load_face` (step 1 of engine-correctness.md Shared definitions 2), before `ensure_os2` and `drop_unused_tables`.

---

## WP-106: Face metadata v2 (script tags, AAT flags, hidden, PS name, licence fields, sanity)

**Goal:** `read_faces` returns every contracts §3 field, and `fpengine.records` serialises a face as a `FaceRecord`, so the catalog can hide private and bogus faces, and later WPs can guard AAT shaping and licences.
**Depends on:** WP-002 · **Env:** linux · **Size:** M · **Closes findings:** ENGINE-2, CATALOG-2, ENGINE-10, NATIVE-6, CATALOG-8

### Scope
- **In:**
  - New `FontFace` fields (S2), computed in `_face`.
  - `bhed` handling.
  - The "no Unicode characters" unsupported reason.
  - `fpengine/records.py`.
  - The reading helpers in `fpengine/licence.py`.
  - `READER_VERSION` (S3).
  - Test helpers (S7).
- **Out:**
  - Filtering hidden faces and deduping by PostScript name (catalog, WP-401).
  - The shaping rule, `unshaped` and `shapes_groups` (WP-107).
  - Name ranking (WP-108).
  - Licence classes (WP-110).
  - The JSON Schema and the `face` event (WP-201).
  - Using `suspicious_coverage` in suggestions (core, WP-304).

### Touched paths
- `engine/src/fpengine/face.py` (edit)
- `engine/src/fpengine/records.py` (edit: add `FACE_RECORD_KEYS`, `face_record`, `face_from_record`; make `face_to_dict`/`face_from_dict` round-trip every S2 field, see Design §4)
- `engine/src/fpengine/licence.py` (new)
- `engine/tests/meta_fixtures.py` (new)
- `engine/tests/test_face_metadata.py` (new)
- `engine/tests/test_records.py` (edit: WP-002 ported it; add the record tests)
- `engine/tests/test_cmap.py`, `docs/specs/engine-correctness.md` (edit: align AC-101-6 with the unsupported empty-Unicode reason; see Design §3)

### Design

**1. Header table.** `_head(font)` returns `font["head"]` if present, else `font["bhed"]` (fontTools parses it as `table__b_h_e_d`, which subclasses `head`). If both are missing, it raises `KeyError` and the file is reported as unreadable, as before. Every use of `font["head"]` in `_face` (`upem`, the italic fallback, `font_revision`) goes through `_head`.

**2. Field rules** (in `_face`; `name = font["name"]`, `os2 = font["OS/2"] if "OS/2" in font else None`):

| Field | Rule |
|---|---|
| `postscript_name` | `(name.getDebugName(6) or "").strip() or None` |
| `full_name` | `_best_name(name, (4,)) or f"{family} {style}"`, using the same ranking as family and style (WP-108 changes the ranking, not this rule) |
| `fs_type` | `int(os2.fsType)` if `os2` else `None`. `embedding` stays `_embedding(fs_type)` (`face.py:90-97`), and `"installable"` when there is no OS/2 |
| `has_os2` | `os2 is not None` |
| `hidden` | `is_hidden(family, postscript_name)` = `family.startswith(".") or (postscript_name or "").startswith(".")`. This catches `.LastResort` (family `.LastResort`, PS `LastResort`) and SFNS (family `System Font`, PS `.SFNS-Regular`) |
| `suspicious_coverage` | `is_suspicious_coverage(len(codepoints), glyph_count)` = `n >= SUSPICIOUS_MIN_CODEPOINTS and n > SUSPICIOUS_RATIO * glyph_count`, with `SUSPICIOUS_MIN_CODEPOINTS = 256` and `SUSPICIOUS_RATIO = 4`. `glyph_count` is `maxp.numGlyphs` |
| `ot_gsub`, `ot_gpos` | `script_tags(font, "GSUB")` / `script_tags(font, "GPOS")`: sorted, de-duplicated 4-character `ScriptTag`s from `table.ScriptList.ScriptRecord`, trailing spaces kept (`"lao "`, `"nko "`). `()` when the table is missing, its `ScriptList` is `None`, or reading raises **any** exception (a malformed table must not fail the face) |
| `aat_morx` | `"morx" in font or "mort" in font` |
| `aat_kerx` | `"kerx" in font` |
| `aat_trak` | `"trak" in font` |
| `aat_kern_v1` | `is_apple_kern(font)`: if `"kern"` is missing, `False`. Otherwise, if `font.reader` is not `None` and `"kern" in font.reader`, the result is `bytes(font.reader["kern"][:4]) == b"\x00\x01\x00\x00"` (the raw check avoids decompiling large tables). Otherwise it is `float(getattr(font["kern"], "version", 0)) == 1.0`. Exceptions give `False` |
| `font_revision` | `f"{float(_head(font).fontRevision):.3f}"` |
| `is_forged` | `(name.getDebugName(0) or "").startswith(FORGED_NOTICE)`, the same test as the reference `install.is_forged` (`install.py:70-75`). Where `FORGED_NOTICE` comes from: if `fpengine/naming.py` (WP-109, a leaf module) exists, import it from there at module level. Otherwise import it from `fpengine.merge` **inside** the helper function: `face.py → merge.py → prepare.py → spec.py → face.py` is an import cycle at module level. Whichever of WP-106/WP-109 lands second switches `face.py` to the module-level `from fpengine.naming import FORGED_NOTICE`, so a `scan` does not import the merge stack |
| `vendor_id` | `licence.vendor_id_of(os2)`: `None` if no OS/2. Otherwise `str(os2.achVendID).rstrip(" \x00")`, or `None` if that is empty. `"????"` stays `"????"` |
| `licence_notice` | `licence.normalise_notice(_best_name(name, (13,)) or _best_name(name, (0,)))`. `normalise_notice(text: str \| None) -> str \| None` collapses runs of whitespace (including `\r\n`) to one space and strips. Longer than 300 characters → the first 299 characters + `"…"` (300 in total). Empty or `None` → `None`. `licence.py` must not import `face.py` (`face.py` imports it), so the name lookup stays in `face.py` |
| `licence_class` | `"unknown"` (placeholder for WP-110) |

**Why these thresholds.** In the audit inventory of 889 faces on the audit Mac (Apple silicon, macOS 27), `.LastResort` maps 1,114,112 code points to 7 glyphs, a ratio of 159,159. The next highest ratio is 1.13 (Symbol: 226 code points, 200 glyphs). CJK fonts sit between 0.71 and 1.00 (PingFang SC 35,854/49,533; Hiragino Sans GB 29,318/29,352), and the verifier found no other face above 2 (CATALOG-2). A ratio of 4 leaves 3.5× margin over the highest real font. The 256-code-point floor keeps tiny fonts that map several space or dash code points to one glyph from being flagged.

**3. `unsupported_reason`** (property, reference `face.py:61-68`). Checks run in this order, and the first match wins:
1. `outline == "none"` → `"bitmap-only font (no outlines)"` (a `bhed` font lands here)
2. `outline == "CFF2"` → `"CFF2 outlines are not supported"`
3. `has_color` → `"colour fonts are not supported"`
4. `not codepoints` → **new**: `"no Unicode characters (symbol or empty character map)"`. `getBestCmap()` ignores (3,0) symbol subtables (Webdings, Wingdings: ENGINE-1 verifier), so such a face could never contribute anything.

`hidden` and `suspicious_coverage` faces stay **supported**. They are flags for the catalog and for suggestions, not reasons to refuse a face.

**Spec deviation resolved at integration (WP-101/WP-106).** The existing `ForgeSpec.validate()` rejects unsupported faces, so a symbol-only face must now fail validation with its explicit empty-Unicode reason. AC-101-6's earlier successful forge with zero contribution is superseded. The regression checks the material name, reason and absence of an output file, consistent with architecture §8's requirement to surface unusable inputs.

**4. `fpengine/records.py`** (edit; WP-002 created it):

```python
FACE_RECORD_KEYS: tuple[str, ...]  # the 33 contracts §3 keys + "unshaped", in contracts order
# existing since WP-002 (do not rename): ranges(codepoints) -> list[list[int]]  (sorted, merged, inclusive; cache.py:13-20)
#                                         expand(rs) -> frozenset[int]
def face_record(face: FontFace) -> dict[str, Any]
def face_from_record(record: Mapping[str, Any]) -> FontFace        # ignores unknown keys; missing optional keys take S2 defaults
```

`face_record` output. It must be JSON-serialisable with `json.dumps(record, ensure_ascii=False, allow_nan=False)`.

```json
{"path": "/fonts/A.ttf", "index": 0, "size": 1234, "mtime": 1727600000.0,
 "family": "Fixture A", "style": "Regular", "full_name": "Fixture A Regular", "postscript_name": null,
 "local_names": [], "outline": "glyf", "is_collection": false, "is_variable": false, "axes": [],
 "weight_class": 400, "italic": false, "upem": 1000, "glyph_count": 6,
 "coverage": [[44, 44], [49, 49], [97, 99]], "group_counts": {"latin": 5},
 "embedding": "installable", "fs_type": 0, "has_color": false, "supported": true, "unsupported_reason": null,
 "hidden": false, "suspicious_coverage": false, "ot_scripts": {"gsub": [], "gpos": []},
 "aat": {"morx": false, "kerx": false, "kern_v1": false, "trak": false}, "shapes_groups": [],
 "licence": {"class": "unknown", "vendor_id": "????", "notice": null},
 "has_os2": true, "is_forged": false, "font_revision": "1.000", "unshaped": []}
```

Field rules for the record:

- `axes` → `[{"tag", "min", "default", "max"}]`, with floats.
- `group_counts` → `{g: n}` for the non-empty groups, in `GROUPS` order, taken from `face.counts`. For a hand-built face with no `group_counts`, `counts` derives it from the code points (`face.py:74-83`; from `codepoints - unshaped` after WP-107). `face_from_record` reads it back as `tuple((g, gc[g]) for g in GROUP_IDS if gc.get(g))` with `gc = record.get("group_counts") or {}`, ignoring unknown group ids.
- `supported` and `unsupported_reason` come from the properties.
- `shapes_groups` → a list; `unshaped` → ranges.
- `face_from_record(face_record(f)) == f` for every face `read_faces` returns.

**The reference dict helpers.** `records.face_to_dict`/`face_from_dict` (WP-002, the reference cache layout of `catalog/cache.py:27-40`) keep their own dict layout, and ported tests assert it (`codepoints` as ranges, `axes` as lists). Don't replace them with `face_record`. Extend them instead: `unshaped` is stored as ranges, the tuple fields (`ot_gsub`, `ot_gpos`, `shapes_groups`) are rebuilt as tuples, and `face_from_dict(json.loads(json.dumps(face_to_dict(f)))) == f` still holds.

**5. Error containment.** A file that can't be opened, or a face with neither `head` nor `bhed`, still raises (a file error, as before). Everything else in the table above is contained per field: a malformed `GSUB`, `GPOS` or `kern` gives the empty or false value instead of failing the face.

**6. Reference → destination**

| Reference | Destination | Change |
|---|---|---|
| `catalog/face.py:18-38` `FontFace` | `fpengine/face.py` | + S2 fields |
| `catalog/face.py:61-68` `unsupported_reason` | same | + reason 4 |
| `catalog/face.py:170-197` `_face` | same | `_head`, the new fields |
| `catalog/cache.py:13-40` `_ranges`, `face_to_dict` | `fpengine/records.py` (already `ranges`, `face_to_dict` since WP-002) | + `face_record`/`face_from_record`: record shape per contracts §3 |
| `ui/install.py:63-75` `is_forged` | `face.py` helper (the field) | Same test, done at read time |

### Acceptance criteria
Tests are in `engine/tests/test_face_metadata.py` unless another file is named. "Fixture A/B/C/K/V/T" are the ported `font_dir` fonts (`reference/fontplayground-py/tests/conftest.py:34-45`); "decorated" means built with S7 `decorate`.
- **AC-106-1** Given every face in `font_dir` (A, B, C, K, V, T[0], T[1]), `set(face_record(f)) == set(FACE_RECORD_KEYS)`, and `FACE_RECORD_KEYS` equals the contracts §3 list plus `"unshaped"`. The record survives `json.dumps(..., allow_nan=False)`, and each value has the type in contracts §3. (`test_face_record_has_exactly_the_contract_fields`, `engine/tests/test_records.py`)
- **AC-106-2** `face_from_record(json.loads(json.dumps(face_record(f)))) == f` and the hashes are equal, for every `font_dir` face and for a face read from the S7 bitmap-only fixture. (`test_face_record_round_trip`)
- **AC-106-3** `ranges({1, 2, 3, 7, 9, 10}) == [[1, 3], [7, 7], [9, 10]]`, `ranges([]) == []`, `expand(ranges(s)) == frozenset(s)`, and unknown keys in a record are ignored by `face_from_record`. (`test_ranges_and_forward_compatibility`)
- **AC-106-4 (CATALOG-8)** Given `build_bitmap_only_font(tmp/"bitmap.ttf", "Fixture Bitmap", cps("a一"))`, `read_faces` returns exactly one face and does not raise. The face has `outline == "none"`, `supported is False`, `unsupported_reason == "bitmap-only font (no outlines)"`, `upem == 1000`, `font_revision == "1.000"` and `fs_type == 2`. (`test_catalog_8_bhed_bitmap_font_is_unsupported_not_unreadable`)
- **AC-106-5 (CATALOG-2, ENGINE-10)** `is_hidden(".LastResort", "LastResort")`, `is_hidden("System Font", ".SFNS-Regular")` and `is_hidden(".SF Arabic", None)` are true, and `is_hidden("Helvetica", "Helvetica")` is false. A font built with family `.Fixture Hidden` reads with `hidden is True`. So does a font with family `Fixture S` and name ID 6 `.FixtureS-Regular` (set via `name_records`). (`test_catalog_2_dot_faces_are_hidden`, `test_engine_10_dot_families_are_hidden`)
- **AC-106-6 (CATALOG-2)**
  - Boundary cases: `is_suspicious_coverage(256, 63)` is true; `(256, 64)`, `(255, 1)`, `(35854, 49533)` (PingFang SC) and `(226, 200)` (Symbol) are false; `(1114112, 7)` (.LastResort) is true.
  - `build_many_to_one_font(tmp/"lr.ttf", 2000)` reads with `suspicious_coverage is True` and `supported is True`.
  - Fixture A reads with `suspicious_coverage is False`.
  
  (`test_catalog_2_suspicious_coverage_rule`)
- **AC-106-7 (ENGINE-2, NATIVE-6)** Given fixture A decorated with:
  - `fea="languagesystem arab dflt; feature init { sub uni0061 by uni0062; } init;"`,
  - `tables={"morx": b"\0\2\0\0\0\0\0\0", "kerx": b"\0\2\0\0\0\0\0\0", "trak": b"\0\1\0\0\0\0\0\0\0\0\0\0"}` (opaque bytes; the reader only tests presence) and `kern_v1_format=1`,
  
  `read_faces` gives `ot_gsub == ("arab",)`, `ot_gpos == ()`, and all four `aat_*` flags true. Fixture K (a version-0 `kern` with a format-0 subtable) gives `aat_kern_v1 is False`, and fixture A decorated with `kern_v1_format=0` gives `aat_kern_v1 is True`. A GPOS-only fixture (`fea="languagesystem lao dflt; feature kern { pos uni0061 uni0062 -10; } kern;"`) gives `ot_gpos == ("lao ",)`, with the trailing space kept. (`test_engine_2_script_tags_and_aat_flags`, `test_native_6_aat_only_face_flags`)
- **AC-106-8** A fixture decorated with an opaque, malformed `GSUB` (`tables={"GSUB": b"\x00\x01\x00\x00\xff\xff\x00\x00\x00\x00"}`) reads without raising, and has `ot_gsub == ()`. (`test_malformed_layout_table_does_not_fail_the_face`)
- **AC-106-9** Given fixture A with name ID 6 records `[(3, 1, 0x409, "FixtureA-Regular"), (1, 0, 0, "FixtureA-Regular")]` and name ID 4 `[(3, 1, 0x409, "Fixture A Regular")]`:
  - it reads with `postscript_name == "FixtureA-Regular"` and `full_name == "Fixture A Regular"`;
  - the unmodified fixture A reads with `postscript_name is None` and `face_record(...)["full_name"] == "Fixture A Regular"`;
  - fixture A decorated with `drop=("OS/2",)` reads with `has_os2 is False`, `fs_type is None` and `embedding == "installable"`;
  - fixture C reads with `fs_type == 2` and `embedding == "restricted"`.
  
  (`test_postscript_full_name_and_os2_fields`)
- **AC-106-10** Given fixture A decorated with `vendor="APPL"` and name ID 13 set to a 400-character string containing `\r\n`:
  - `vendor_id == "APPL"`;
  - `licence_notice` has 300 characters, ends with `"…"` and contains no `\r` or `\n`.
  
  With no name ID 13, the notice falls back to name ID 0: fixture A with `name_records={0: [(3, 1, 0x409, "Copyright 2024 Example Foundry")]}` reads with `licence_notice == "Copyright 2024 Example Foundry"`. With neither, it is `None`: the unmodified fixture A (which has only name IDs 1 and 2) reads with `licence_notice is None` and `vendor_id == "????"`. Vendor `"MS  "` becomes `"MS"`. (`test_vendor_id_and_licence_notice`)
- **AC-106-11** Given fixture A with name ID 0 `[(3, 1, 0x409, "Forged with Font Playground from: Fixture A Regular")]`, the face has `is_forged is True`, and the unmodified fixture A has `is_forged is False`. (`test_is_forged_field_reads_the_notice`)
- **AC-106-12** A font whose cmap has only a (3,0) symbol subtable reads with `codepoints == frozenset()`, `supported is False` and `unsupported_reason == "no Unicode characters (symbol or empty character map)"`. Build it in the test from fixture A: replace `font["cmap"].tables` with one subtable `st = CmapSubtable.newSubtable(4)` with `st.platformID, st.platEncID, st.language = 3, 0, 0` and `st.cmap = {0xF061: "uni0061", 0xF062: "uni0062", 0xF063: "uni0063"}` (`fontTools.ttLib.tables._c_m_a_p`), then save. (`test_symbol_only_cmap_is_unsupported`)
- **AC-106-13** `READER_VERSION` is increased by exactly 1 against `main` (reviewer check: `git diff main -- engine/src/fpengine/face.py` shows exactly one changed `READER_VERSION = N` line, or the new constant `READER_VERSION = 4`). `fpengine.face.READER_VERSION` is an `int >= 4` (`test_reader_version_is_an_int`).
- **AC-106-14** All ported reference tests from `test_face.py` and `test_records.py` (the two `test_catalog.py` round-trip tests WP-002 ported) pass unchanged, and `make lint` and `make engine-test` pass.

### Verification
```bash
make lint
make engine-test
```

### Notes for the implementer
- Keep `read_faces` lazy (`TTFont(..., lazy=True)`, `TTCollection(..., lazy=True)`). Reading `ScriptList` from a lazily loaded GSUB costs less than 10 ms on PingFang (measured on the audit Mac), and the raw `kern` check avoids decompiling large kern tables.
- Don't resolve symlinks or rewrite `path` (contracts §2).
- Don't filter hidden or suspicious faces here. The helper emits every face, and the Swift catalog decides (ADR-0007, CATALOG-2: "keep dropped faces in the cache so the file isn't re-read").
- `is_forged` is filled here and not by WP-109, because 106 and 109 run in parallel (wave 3). WP-109 owns the marker constant, and must keep `fpengine.merge.FORGED_NOTICE` importable.
- `READER_VERSION` conflicts with WP-108 are expected: rebase and bump again (S3).

---

## WP-107: AAT guard in forge (per-script shaping check, errors and warnings)

**Goal:** a face never supplies characters whose shaping would be lost in the forged font. The engine computes `unshaped` and `shapes_groups` per face, plans with plannable coverage, refuses a rule that assigns a complex group to a font that can't shape it, and reports every AAT feature that is dropped.
**Depends on:** WP-101, WP-102, WP-106 · **Env:** linux · **Size:** M · **Closes findings:** ENGINE-2, ENGINE-7, UI-M2, NATIVE-M1

### Scope
- **In:**
  - `fpengine/shaping.py`.
  - Filling in `unshaped`, `shapes_groups` and plannable `group_counts` at read time.
  - `plan()` using plannable coverage.
  - The forge-time rule check (`aat_unsupported_script`).
  - AAT-loss and `unshaped_left_out` issues.
  - The OpenType alternatives data and its fixture file.
- **Out:**
  - Picker filtering and greying (WP-503).
  - Suggestions using the alternatives (WP-304).
  - The Swift planner using plannable coverage (core, WP-302/303; see backbone issues).
  - Converting `kerx` or `morx` (not feasible, ADR-0008).
  - Baking `trak` (backlog B-1).

### Touched paths
- `engine/src/fpengine/shaping.py` (new)
- `engine/src/fpengine/face.py` (edit: `unshaped`, `shapes_groups`, `group_counts`, `READER_VERSION`)
- `engine/src/fpengine/planner.py` (edit: `plan`)
- `engine/src/fpengine/prepare.py` (edit: record AAT losses)
- `engine/src/fpengine/forge.py` (edit: rule check, issues)
- `engine/src/fpengine/spec.py` (edit: S5 types, if they are missing)
- `spec/fixtures/shaping/ot_alternatives.json` (new, generated)
- `engine/tests/test_shaping.py` (new)
- `engine/tests/test_aat_guard.py` (new)

### Design

**1. Script shaping table** (`shaping.SCRIPT_SHAPING: dict[str, ScriptShaping]`). The keys are ISO 15924 codes as returned by `fontTools.unicodedata.script`. `ot_tags` must equal `tuple(fontTools.unicodedata.ot_tags_from_script(code))`, with the new ("v2") Indic tag first. "Marks only" means only `Mn`/`Mc`/`Me` characters need shaping. "GPOS ok" means a GPOS ScriptList entry alone is enough.

```python
@dataclass(frozen=True)
class ScriptShaping:
    script: str               # ISO 15924 code, e.g. "Arab"
    name: str                 # English name used in messages, e.g. "Arabic"
    group: str                # script group id (scripts.py GROUP_IDS)
    ot_tags: tuple[str, ...]  # OpenType script tags; any one satisfies
    marks_only: bool
    gpos_ok: bool

SCRIPT_SHAPING: dict[str, ScriptShaping]   # the table below, in table order (dicts keep insertion order)
```

| Script | Name | Group | OpenType tags (any one satisfies) | Marks only | GPOS ok | Why |
|---|---|---|---|---|---|---|
| Arab | Arabic | arabic | arab | no | no | Joining needs GSUB `init/medi/fina` |
| Hebr | Hebrew | hebrew | hebr | yes | yes | Letters need nothing; points and cantillation need mark positioning |
| Deva | Devanagari | indic | dev2, deva | no | no | Reordering and conjuncts are GSUB |
| Beng | Bengali | indic | bng2, beng | no | no | " |
| Guru | Gurmukhi | indic | gur2, guru | no | no | " |
| Gujr | Gujarati | indic | gjr2, gujr | no | no | " |
| Orya | Odia | indic | ory2, orya | no | no | " |
| Taml | Tamil | indic | tml2, taml | no | no | " |
| Telu | Telugu | indic | tel2, telu | no | no | " |
| Knda | Kannada | indic | knd2, knda | no | no | " |
| Mlym | Malayalam | indic | mlm2, mlym | no | no | " |
| Sinh | Sinhala | indic | sinh | no | no | " |
| Thai | Thai | southeast_asian | thai | yes | yes | Base letters need nothing; vowel and tone marks need positioning |
| Laoo | Lao | southeast_asian | `lao ` | yes | yes | " |
| Khmr | Khmer | southeast_asian | khmr | no | no | Reordering and coeng subscripts |
| Mymr | Myanmar | southeast_asian | mym2, mymr | no | no | Reordering and medials |
| Syrc | Syriac | other | syrc | no | no | Joining |
| Thaa | Thaana | other | thaa | yes | yes | Vowel marks |
| Nkoo | N'Ko | other | `nko ` | no | no | Joining |
| Mong | Mongolian | other | mong | no | no | Joining |
| Tibt | Tibetan | other | tibt | no | no | Stacking |
| Adlm | Adlam | other | adlm | no | no | Joining |
| Rohg | Hanifi Rohingya | other | rohg | no | no | Joining |

`PRESENTATION_FORMS = ((0xFB1D, 0xFB4F), (0xFB50, 0xFDFF), (0xFE70, 0xFEFF))`: precomposed forms need no shaping.

**2. Rules** (pure functions; `category` = `fontTools.unicodedata.category`):

- `needs_shaping(cp, s)`: true when `cp` is not in `PRESENTATION_FORMS`, its category is not `Nd`, and either `not s.marks_only` or its category is in `{"Mn", "Mc", "Me"}`.
- `satisfied(s, gsub, gpos)`: true when `set(s.ot_tags) & set(gsub)`, or when `s.gpos_ok and set(s.ot_tags) & set(gpos)`. A face that has both GSUB `arab` and `morx` (Damascus) is satisfied, because `morx` plays no part.
- **`script_members(codepoints) -> dict[str, list[int]]`**: the code points of each table script present in the face. Find them by bisecting the sorted code points against ranges built once, at import, from `fontTools.unicodedata.Scripts.RANGES`/`VALUES` (the entries whose value is a table key). Don't call `script()` per code point for this. It takes 0.004 s for `.LastResort`'s 1.1 M code points on the audit Mac.
- **U1 (script rule).** Script `s` is **unshaped by the face** when some member needs shaping and `not satisfied(...)`. All of that script's members are then unshaped: letters, digits and presentation forms alike, so one script is never split between two fonts.
- **U2 (inherited and common characters).** This rule only runs when U1 found at least one unshaped script. Let `covered` be the set of **all** script codes (not only table scripts) that have at least one code point in the face, found with the same `RANGES` bisection, minus `Zyyy`, `Zinh` and `Zzzz`. So a face with `a` and Arabic letters has `covered == {"Latn", "Arab"}`. A code point whose script is `Zinh` or `Zyyy` (again found by range bisection, not by calling `script()` on every code point: `.LastResort` has 1.1 M code points) is also unshaped when `rel = set(script_extension(chr(cp))) & covered` is non-empty and `rel ⊆ unshaped scripts`.
  - Example: Geeza Pro's harakat U+064B–U+0655, U+0670, and its comma, semicolon, question mark and tatweel. Their script extensions are only scripts the face can't shape.
  - Lucida Grande's U+0307 stays plannable, because Latin is in its `rel`.
- `unshaped_codepoints(codepoints, gsub, gpos) -> frozenset[int]` = U1 ∪ U2.
- `shapes_groups(codepoints, unshaped) -> tuple[str, ...]`: the groups `g` in `COMPLEX_GROUPS` (in that order) for which some code point in `codepoints − unshaped` has `group_of(cp) == g`. In words: the face can contribute at least one correctly shaped character of `g`.
- `plannable(face) -> frozenset[int]` = `face.codepoints - face.unshaped`.

Imports: `shaping.py` imports only the standard library, `fontTools.unicodedata` and `fpengine.scripts` at module level, because `face.py` imports it. `rule_errors` and `plannable` take duck-typed `spec`/`face` arguments; any `fpengine.spec` import goes under `typing.TYPE_CHECKING`.

**3. Read time** (`face.py`). `_face` sets:
- `unshaped = unshaped_codepoints(codepoints, ot_gsub, ot_gpos)`
- `shapes_groups = shapes_groups(codepoints, unshaped)`
- `group_counts = _group_counts(codepoints - unshaped)`

It then increments `READER_VERSION`. `records.face_record` already emits these fields (WP-106).

`FontFace.counts` (reference `face.py:74-83`) keeps using `group_counts` when it is non-empty. Its fallback changes from `codepoints` to `codepoints - unshaped`. Otherwise a face whose every character is unshaped (a pure Arabic AAT font: `group_counts == ()`) would fall back to counting its raw Arabic coverage. For hand-built faces `unshaped` is empty, so nothing changes for them.

**4. Planner** (`planner.py`, reference `:19-27`). `plan(spec)` uses `sets = [plannable(m.face) for m in spec.materials]`. `source_of` is unchanged, so its conformance fixtures still hold. The Swift callers must pass plannable sets (S4).

**5. Forge-time rule check.** `shaping.rule_errors(spec) -> list[tuple[int, str, str]]` returns `(material_index, group, message)` in `COMPLEX_GROUPS` order. It reports each group `g` in `COMPLEX_GROUPS` whose rule points to a valid material `r` whose face covers some character of `g` (`any(group_of(cp) == g for cp in face.codepoints)`), when `g not in shapes_groups(face.codepoints, face.unshaped)`. It recomputes that from `unshaped` rather than reading the `shapes_groups` field, so a hand-built face (`fake_face`, `unshaped` empty) never fails the check. For faces read by `read_faces` the two are equal. Call it in `forge()` right after `spec.validate()` passes. If the list is non-empty, raise:

```python
ForgeError("validate", materials[i].face.display_name, " ".join(m for _, _, m in errs),
           code="aat_unsupported_script", material_index=i)   # i = the first error's material index
```

A rule to a face that shapes **part** of the group (for example Devanagari shaped, one Gurmukhi character not) is **not** an error. The unshaped characters simply move on (§7).

**Message** (exact):
- `{name}` is the display name, and `{label}` is `LABELS[g]` from `scripts.py:34`.
- `{scripts}` lists the English names of the face's unshaped table scripts whose group is `g`. They are ordered by unshaped code-point count (each unshaped code point counted once, under its responsible script from `explain_unshaped`, §7), largest first, with ties in table order, and joined as "A", "A and B", or "A, B and C".
- If the face has `aat_morx`: `"{name} can't draw {label} in the forged font: it shapes {scripts} with Apple-only rules (AAT) that can't be carried over."`
- Otherwise: `"{name} can't draw {label} in the forged font: it has no OpenType shaping rules for {scripts}."`
- Then, if `OT_ALTERNATIVES[first script]` is non-empty, append `" Choose an OpenType font instead, for example {alts}."`. `{alts}` is the first three families of that list, joined as "A", "A or B", or "A, B or C".

**5a. GPOS retry.** A variable face can be plannable for a "GPOS ok" script only because of its GPOS. When `instance_variable` fails and `prepare()` retries without GPOS, it first calls `refuse_lost_mark_positioning(face, codepoints)`. That recomputes `explain_unshaped(face.codepoints, face.ot_gsub, ())`. If any **assigned** code point is unshaped without GPOS but was plannable at scan time, it raises `ForgeError("prepare", display_name, f"{names} marks need this font's positioning rules, but its variable positioning data (GPOS) is broken and has to be dropped. Let another font draw {names}.")`. `names` is `join_names` over `responsible_scripts` (the helper maps it to `prepare_failed`). A retry that loses no assigned marks keeps the existing `GPOS dropped:` warning. (`test_gpos_retry_refuses_marks_that_needed_gpos`, `test_gpos_retry_keeps_the_face_when_another_font_draws_the_marks`)

**6. AAT losses** (`prepare.py`). Right after `load_face`, before **any** table is removed (including WP-102's pre-subset drop), compute from the source `TTFont`:
- `morx`: `"morx"` or `"mort"` is present, and there is no GSUB script record (use WP-106's `script_tags(font, "GSUB") == ()`).
- `kerning_source`: `"kerx"` is present, or `"kern"` has a subtable whose `getattr(st, "format", 0) != 0`.
- `tracking`: `"trak"` is present.

After `kern_to_gpos(font)`, `kerning = kerning_source and not has_kern_feature(font)` (`kern.py:13-17`). `PreparedFont` gains `aat_losses: frozenset[str] = frozenset()`, a subset of `{"morx", "kerning", "tracking"}`.

**7. Issues** (`forge.py` `_report`, reference `:19-29`). The three AAT-loss issues come from `prepared[i].aat_losses` (`"morx"` → `aat_morx_dropped`, `"kerning"` → `aat_kerning_dropped`, `"tracking"` → `aat_tracking_dropped`) and only apply to contributing materials (`p.assignments[i]` non-empty). Note texts are exact:
- `aat_morx_dropped`: `"Apple-only (AAT) ligatures and alternates are not carried over; the forged font uses plain letter forms"`
- `aat_kerning_dropped`: `"Apple-only (AAT) kerning is not carried over"`
- `aat_tracking_dropped`: `"Apple tracking (trak) is not carried over; spacing can differ from the original at some sizes"`

**`unshaped_left_out`** applies to every material, contributing or not: a font whose only characters were unshaped contributes nothing, and this issue says why. Let `raw_sets = [m.face.codepoints for m in spec.materials]`. For each material `i`, take `would = {cp in face.unshaped : source_of(cp, raw_sets, spec.script_rules) == i}`: the characters it would have drawn without the guard.
- Give each code point in `would` a **responsible script**: for U1, its own script; for U2, the first unshaped script in its `rel`, in table order. `shaping.py` exposes this as `explain_unshaped(codepoints, gsub, gpos) -> dict[int, str]` (unshaped code point → responsible script code); `unshaped_codepoints(...)` is `frozenset(explain_unshaped(...))`. `_report` calls it with the face's `codepoints`, `ot_gsub` and `ot_gpos`.
- Group `would` by the responsible script's `group`, and add one issue per group, with group ids in `GROUP_IDS` order. The issue's `group` is that group id. Geeza Pro's harakat and tatweel therefore count under `arabic`, not `symbols`.
- `drawn = |would ∩ p.source.keys()|`, `left = |would| − drawn`.
- Note: `"{scripts} characters are drawn by other fonts or left out ({drawn} drawn by other fonts, {left} left out): this font {reason}"`.
- `{scripts}` lists the English names of the responsible scripts of that group, ordered and joined as in §5 (most code points first).
- `{reason}` is `"shapes them with Apple-only rules (AAT) that can't be carried over"` if `aat_morx`, otherwise `"has no OpenType shaping rules for them"`.

**8. OpenType alternatives** (`shaping.OT_ALTERNATIVES: dict[str, tuple[Alternative, ...]]`). Each `Alternative(family: str, postscript_name: str, where: str)` (a frozen dataclass) is a font that ships with macOS and satisfies the script's rule. `where` is `"system"` (under `/System/Library/Fonts`, including `Supplemental`) or `"asset"` (an AssetsV2 system font that Font Book may need to download). The list is ordered best first, and was checked on the audit Mac (Apple silicon, macOS 27) by reading each file's GSUB ScriptList with fontTools:

| Script | Alternatives (family / PostScript name / where) |
|---|---|
| Arab | Damascus / Damascus / system; Noto Nastaliq Urdu / NotoNastaliqUrdu / system; Arial / ArialMT / system; Times New Roman / TimesNewRomanPSMT / system; Tahoma / Tahoma / system; Courier New / CourierNewPSMT / system; Microsoft Sans Serif / MicrosoftSansSerif / system |
| Hebr | Arial Hebrew / ArialHebrew / system; Arial Hebrew Scholar / ArialHebrewScholar / system; Arial / ArialMT / system; Times New Roman / TimesNewRomanPSMT / system; Tahoma / Tahoma / system |
| Deva | Kohinoor Devanagari / KohinoorDevanagari-Regular / system; ITF Devanagari / ITFDevanagari-Book / system; Devanagari Sangam MN / DevanagariSangamMN / system; Shree Devanagari 714 / ShreeDev0714 / system |
| Beng | Kohinoor Bangla / KohinoorBangla-Regular / system; Bangla Sangam MN / BanglaSangamMN / system; Bangla MN / BanglaMN / system; Tiro Bangla / TiroBangla / asset |
| Guru | Gurmukhi Sangam MN / GurmukhiSangamMN / system; Gurmukhi MN / GurmukhiMN / system |
| Gujr | Kohinoor Gujarati / KohinoorGujarati-Regular / system; Gujarati Sangam MN / GujaratiSangamMN / system |
| Orya | Oriya Sangam MN / OriyaSangamMN / system; Oriya MN / OriyaMN / system; Noto Sans Oriya / NotoSansOriya / system |
| Taml | Tamil MN / TamilMN / system; InaiMathi / InaiMathi / system; Tamil Sangam MN / TamilSangamMN-Medium / asset |
| Telu | Kohinoor Telugu / KohinoorTelugu-Regular / system; Telugu Sangam MN / TeluguSangamMN / system; Telugu MN / TeluguMN / system |
| Knda | Kannada Sangam MN / KannadaSangamMN / system; Kannada MN / KannadaMN / system; Noto Sans Kannada / NotoSansKannada-Regular / system |
| Mlym | Sama Malayalam / SamaMalayalam-Regular / asset; Baloo Chettan 2 / BalooChettan2-Regular / asset |
| Sinh | Sinhala Sangam MN / SinhalaSangamMN / system; Sinhala MN / SinhalaMN / system |
| Thai | Sukhumvit Set / SukhumvitSet-Text / system; Tahoma / Tahoma / system; Microsoft Sans Serif / MicrosoftSansSerif / system |
| Laoo | Lao Sangam MN / LaoSangamMN / system; Lao MN / LaoMN / system |
| Khmr | Khmer Sangam MN / KhmerSangamMN / system; Khmer MN / KhmerMN / system |
| Mymr | Myanmar Sangam MN / MyanmarSangamMN / system; Myanmar MN / MyanmarMN / system; Noto Sans Myanmar / NotoSansMyanmar-Regular / system |
| Syrc | Noto Sans Syriac / NotoSansSyriac-Regular / system |
| Thaa | Noto Sans Thaana / NotoSansThaana-Regular / system |
| Nkoo | Noto Sans NKo / NotoSansNKo-Regular / system |
| Mong | Noto Sans Mongolian / NotoSansMongolian-Regular / system |
| Adlm | Noto Sans Adlam / NotoSansAdlam-Regular / system |
| Rohg | Noto Sans Hanifi Rohingya / NotoSansHanifiRohingya-Regular / system |
| Tibt | (none: Kailasa and Kokonor, the Tibetan fonts on the audit Mac, are AAT-only) |

Malayalam has no OpenType font under `/System/Library/Fonts` on the audit Mac: Malayalam MN and Malayalam Sangam MN are AAT-only.

**Consumers must match these entries against catalog faces by PostScript name, then by family. They must never look them up by name in CoreText** (architecture §8: name lookups can start downloads).

**Fixture export.** `shaping.fixture_payload() -> dict` returns:

```json
{"header": {"generator": "python -m fpengine.shaping write-fixture", "fpengine_version": "<fpengine.__version__>",
            "inputs": ["engine/src/fpengine/shaping.py"]},
 "complex_groups": ["hebrew", "arabic", "indic", "southeast_asian"],
 "scripts": [{"script": "Arab", "name": "Arabic", "group": "arabic", "ot_tags": ["arab"],
              "marks_only": false, "gpos_ok": false}],
 "alternatives": {"Arab": [{"family": "Damascus", "postscript_name": "Damascus", "where": "system"}], "Tibt": []}}
```

The example shows only the first entries. The real payload has every script, in table order, in both `scripts` and `alternatives`.

`python -m fpengine.shaping write-fixture <path>` writes it atomically as UTF-8, `ensure_ascii=False`, `indent=2`, `sort_keys=False`, with a trailing newline. It is committed at `spec/fixtures/shaping/ot_alternatives.json`, and consumed by core WP-304.

**9. Reference → destination**

| Reference | Destination | Change |
|---|---|---|
| `engine/planner.py:19-27` `plan` | `fpengine/planner.py` | Plannable sets |
| `engine/prepare.py:137-183` `prepare` | `fpengine/prepare.py` | Record AAT losses before tables are dropped |
| `engine/forge.py:19-29,32-81` | `fpengine/forge.py` | Rule check after validate; issues |
| `engine/kern.py:13-31` | unchanged | Used for the "kerning survived" test |
| (none) | `fpengine/shaping.py` | New |

### Acceptance criteria
AC-107-1, -2 and -10 are in `engine/tests/test_shaping.py`, the others in `engine/tests/test_aat_guard.py`. Fixtures are built with the ported `build_font` (glyph names `uniXXXX`) and S7 `decorate`. Opaque AAT tables use the bytes `b"\0\2\0\0\0\0\0\0"`.
- **AC-107-1** For every `SCRIPT_SHAPING` entry:
  - `ot_tags == tuple(ot_tags_from_script(code))`;
  - `group == group_of(<first code point of the script's first range>)`;
  - `name` is non-empty ASCII.
  
  `COMPLEX_GROUPS` equals S4. (`test_shaping_table_matches_fonttools`, `engine/tests/test_shaping.py`)
- **AC-107-2** Unit cases for `unshaped_codepoints` and `shapes_groups`, with no font files involved:

  | Case | Code points | GSUB | GPOS | Expected `unshaped` | Expected `shapes_groups` |
  |---|---|---|---|---|---|
  | a | Arabic letters U+0627–U+064A, U+0660–U+0669, U+FE8D, U+064E, `a` | () | () | every code point except `a` (the Zyyy U+0640 tatweel and the Zinh U+064E come in through U2) | () |
  | b | same as (a) | ("arab",) | () | ∅ | ("arabic",) |
  | c | Hebrew U+05D0–U+05EA + U+05B8 | () | ("hebr",) | ∅ | ("hebrew",) |
  | d | same as (c) | () | () | all of U+05D0–U+05EA and U+05B8 | () |
  | e | Hebrew letters only U+05D0–U+05EA | () | () | ∅ | ("hebrew",) |
  | f | Devanagari U+0915–U+0939 + U+094D | ("deva",) | () | ∅ | ("indic",) |
  | f | same | ("dev2",) | () | ∅ | ("indic",) |
  | f | same | () | ("dev2",) | the Devanagari set | () |
  | g | (f) + U+0A15 | ("dev2",) | () | {0x0A15} | ("indic",) |
  | h | Thai U+0E01–U+0E2E + U+0E31 | () | ("thai",) | ∅ | ("southeast_asian",) |
  | i | U+0660–U+0669 only | () | () | ∅ | ("arabic",) |
  | j | Tibetan U+0F40–U+0F47, U+0F49–U+0F6C (U+0F48 is unassigned) + `a` | () | () | the Tibetan code points | () |
  | k | Lao U+0E81 + U+0EB1 | () | ("lao ",) | ∅ | ("southeast_asian",) |
  | l | Latin `a`, U+0307 + Hebrew (d) | () | () | Hebrew only (U+0307 stays) | () |

  (`test_unshaped_and_shapes_groups_cases`)
- **AC-107-3 (ENGINE-2)** The fixtures, built with `build_font` + `decorate`:
  - **geeza**: family `Fixture Geeza`, style `Regular`, the case (a) code points, `tables={"morx": b"\0\2\0\0\0\0\0\0"}`, no GSUB;
  - **arabic_ot**: family `Fixture Arabic OT`, the case (a) code points minus `a`, `fea="languagesystem arab dflt; feature init { sub uni0628 by uni0627; } init;"`;
  - **latin_ot**: family `Fixture Latin`, `cps("ab")`.
  
  Then:
  - `read_faces` gives geeza `unshaped` = every code point except `a`, `shapes_groups == ()`, and `group_counts == (("latin", 1),)`;
  - `plan(ForgeSpec([geeza, arabic_ot]))` assigns every code point except `a` to material 1, and `a` to material 0;
  - **geeza_only**: the geeza fixture without `a` (family `Fixture Geeza Only`) reads with `group_counts == ()` and `counts["arabic"] == 0` (the `counts` fallback uses plannable coverage).
  
  (`test_engine_2_planner_leaves_unshaped_arabic_to_an_opentype_font`, `engine/tests/test_aat_guard.py`)
- **AC-107-4 (ENGINE-2)** Forging `[latin_ot, geeza]` with `script_rules={"arabic": 1}` raises `ForgeError` with:
  - `stage == "validate"`, `code == "aat_unsupported_script"`, `material_index == 1`;
  - message: `"Fixture Geeza Regular can't draw Arabic in the forged font: it shapes Arabic with Apple-only rules (AAT) that can't be carried over. Choose an OpenType font instead, for example Damascus, Noto Nastaliq Urdu or Arial."`
  
  The same fixture without `morx` (family `Fixture Geeza`, built without `tables`) gives exactly `"Fixture Geeza Regular can't draw Arabic in the forged font: it has no OpenType shaping rules for Arabic. Choose an OpenType font instead, for example Damascus, Noto Nastaliq Urdu or Arial."`. A rule `{"arabic": 1}` to `arabic_ot` does not raise. `rule_errors` for a `ForgeSpec` of two `fake_face`s (the second covering U+0627–U+064A) with `{"arabic": 1}` is `[]`. (`test_engine_2_rule_to_aat_arabic_is_refused`)
- **AC-107-5** Fixture **indic_g**: family `Fixture Indic`, the case (g) code points, `fea="languagesystem dev2 dflt; feature akhn { sub uni0915 uni094D by uni0916; } akhn;"` (GSUB script `dev2`; Devanagari shaped, U+0A15 unshaped). Forging `[indic_g]` alone with the rule `{"indic": 0}` does **not** raise. The report has one `unshaped_left_out` issue with `material_index == 0` and `group == "indic"`, whose message contains `"Gurmukhi"` and `"(0 drawn by other fonts, 1 left out)"`. (`test_partial_shaping_is_a_warning_not_an_error`)
- **AC-107-6 (NATIVE-M1)** Forging `[latin_ot, geeza]` with no rules succeeds, and the output `getBestCmap()` keys are exactly `{a, b}`. The report has exactly one `unshaped_left_out` issue: `material_index == 1`, `group == "arabic"`, with a message that contains `"(0 drawn by other fonts, 48 left out)"`. Material 1's warnings also contain `"contributes no characters"`. (`test_native_m1_unshaped_arabic_never_reaches_the_output`)
- **AC-107-7 (ENGINE-7)** Forging each fixture alone (so it contributes every character), the report's `aat_kerning_dropped` issues are:
  - fixture A decorated with `kern_v1_format=1` → exactly one, `material_index == 0`, note `"Apple-only (AAT) kerning is not carried over"`;
  - fixture A decorated with `tables={"kerx": …}` → exactly one;
  - fixture A decorated with `kern_v1_format=0` (converted to a GPOS `kern` feature by `kern_to_gpos`) → none;
  - fixture K (kern v0) → none.
  
  (`test_engine_7_aat_kerning_loss_is_reported`)
- **AC-107-8 (UI-M2)** Forging alone: fixture A decorated with `tables={"morx": …}` (no GSUB) → one `aat_morx_dropped`. Fixture A decorated with `morx` plus `fea="languagesystem arab dflt; feature init { sub uni0061 by uni0062; } init;"` (a GSUB script record) → none. Fixture A decorated with `tables={"trak": …}` → one `aat_tracking_dropped`. Forging `[fixture A, fixture A decorated with morx]` → material 1 contributes no characters and has no `aat_*` issue. Each issue's note also appears in that material's `MaterialReport.warnings`, and `f"{name}: {note}"` appears in `ForgeReport.warnings`. (`test_ui_m2_morx_loss_is_reported`, `test_aat_issues_only_for_contributing_materials`)
- **AC-107-9** The case (a) font read from disk has `face_record(f)["unshaped"] == ranges(unshaped)` and `face_record(f)["shapes_groups"] == []`. `READER_VERSION` is incremented by 1 (reviewer check with `git diff main`, as AC-106-13). (`test_records_carry_unshaped_and_shapes_groups`)
- **AC-107-10** `spec/fixtures/shaping/ot_alternatives.json` exists and equals `fixture_payload()`, ignoring `header.fpengine_version`. Every script in `SCRIPT_SHAPING` has a key in `alternatives`, and every `postscript_name` matches `^[A-Za-z0-9-]{1,63}$`. (`test_shaping_fixture_is_current`)
- **AC-107-11** All ported engine tests, including `test_planner.py` and `test_forge.py`, pass unchanged. Their fixtures have no unshaped code points, so plans are identical. `make lint` and `make engine-test` pass.

### Verification
```bash
make lint
make engine-test
```

### Notes for the implementer
- **Evidence the rule is right.** A re-run on the audit Mac's system fonts gave these failures, which match ENGINE-2 and its verifier:
  - **Arabic:** Al Bayan, Al Nile, Al Tarikh, Baghdad, Beirut, DecoType Naskh, Diwan Kufi, Diwan Thuluth, Farah, Farisi, Geeza Pro, KufiStandardGK, Mishafi, Mishafi Gold, Muna, Nadeem, Sana, Waseem.
  - **Hebrew:** Raanana, New Peninim MT, Corsiva Hebrew, Lucida Grande, and Arial Unicode MS (which has no `hebr`).
  - **Indic:** Devanagari MT, Gujarati MT, Gurmukhi MT, Malayalam MN, Malayalam Sangam MN, and Arial Unicode MS for Bengali, Odia, Telugu and Malayalam.
  - **Southeast Asian:** Thonburi, Sathu, Ayuthaya, Krungthep, Silom.
  
  Damascus, Kohinoor Devanagari and Arial Hebrew pass. Fonts with a handful of stray characters (Rockwell: 1 Arabic character; Maku: 1 Gurmukhi character) lose only those characters, which is why U1 is per script and the error is per group.
- The error is for explicit rules only. With automatic rules, core's `smart_supplier` must count plannable characters (`group_counts` already does after this WP), so it never picks such a face.
- Don't add any CoreText or name lookup. Don't decompile `morx`.
- If WP-202's generator (`tools/conformance/generate.py`) exists when you start, also have it call `fixture_payload()`. Otherwise leave that to the backbone follow-up.
- `script_extension` and `category` come from `fontTools.unicodedata` (unicodedata2 18.0.0 in the audit venv). Pin nothing new.

---

## WP-108: Name reading: Mac Roman English, Mac CJK encodings

**Goal:** family, style and full names are English where the font has English (including Mac Roman-only English), and native names from Mac Chinese, Korean and Japanese records show up in `local_names`, so Apple fonts are named and searchable the way macOS names them.
**Depends on:** WP-002 · **Env:** linux · **Size:** S · **Closes findings:** CATALOG-3, CATALOG-M2, ENGINE-M4, UI-M1

### Scope
- **In:** `_name_rank`, a two-pass `_best_name`, the `_local_names` Mac CJK fallback, and the `READER_VERSION` bump.
- **Out:**
  - Search UI (WP-503).
  - Smart default names (core, WP-304). They improve automatically, because they read `family`.

### Touched paths
- `engine/src/fpengine/face.py` (edit)
- `engine/tests/test_face.py` (edit: add cases to the ported parametrised tests)
- `engine/tests/test_names.py` (new)

### Design

**1. Ranking** (replaces `face.py:100-106`; lower ranks first; `None` means the record is left to `getDebugName`):

| Rank | Records | Why |
|---|---|---|
| 0 | platform 3, encoding 0, 1 or 10, language 0x409 | What Windows shows in English |
| 1 | platform 1, encoding 0, language 0, and `record.toBytes()` is printable ASCII (every byte in 0x20–0x7E) | Apple's English names (Al Bayan, Geeza Pro). Shift-JIS mojibake (EPSON) is never plain ASCII, so the reference protection stays |
| 2 | platform 3, encoding 0, 1 or 10, any other language | Localised Windows names |
| 3 | platform 1, encoding 1, 2, 3 or 25 (Mac Japanese, Traditional Chinese, Korean, Simplified Chinese) | fontTools decodes these reliably (`x_mac_japanese_ttx`, `x_mac_trad_chinese_ttx`, `x_mac_korean_ttx`, `x_mac_simp_chinese_ttx`, checked with fontTools 4.66) |
| None | everything else | |

**2. `_best_name(name, name_ids)`** (replaces `face.py:109-128`):

```python
def _best_name(name, name_ids) -> str | None:
    # Pass 1: English only (rank 0 or 1), in name_ids order, so an English ID 1 beats a native-only ID 16.
    for nid in name_ids:
        for rec in sorted((r for r in name.names if r.nameID == nid and _name_rank(r) in (0, 1)), key=_name_rank):
            text = _decode(rec)            # rec.toUnicode(); None on UnicodeDecodeError
            if text:
                return text
    # Pass 2: the reference algorithm with the new ranks, then fontTools' getDebugName.
    for nid in name_ids:
        for rec in sorted((r for r in name.names if r.nameID == nid and _name_rank(r) is not None), key=_name_rank):
            text = _decode(rec)
            if text:
                return text
        text = name.getDebugName(nid)
        if text:
            return text
    return None
```

`sorted` is stable, so records of equal rank keep name-table order. This applies to family `(21, 16, 1)`, style `(22, 17, 2)` and `full_name` `(4,)`, and to the licence notice's `(13,)`/`(0,)` lookups if WP-106 has landed.

**3. `_local_names(name, family)`** (replaces `face.py:131-160`):
- Collect Windows non-English records first, exactly as the reference does.
- **Only when there are none**, collect records with platform 1 and encoding in `{1, 2, 3, 25}` (the reference collects only `(1, 1)`). Key them by `MAC_LANG_TO_LCID.get(r.langID, 0x10000 + r.langID)`, with `MAC_LANG_TO_LCID = {33: 0x804, 19: 0x404, 11: 0x411, 23: 0x412}`, so they sort with `LOCAL_LANGS` (`face.py:15`).
- Mac Roman `(1, 0)` and other Mac encodings are never collected. `(1, 5)` Hebrew records can raise `UnicodeDecodeError` (Raanana, CATALOG-M2); the existing `try/except` skips them.
- Dropping names equal to `family` (casefold) and removing duplicates stay as they are.

**4.** Increase `READER_VERSION` by 1 (S3).

**Evidence.**
- **CoreText comparison.** On the audit Mac, both this ranking and the one-pass variant give **0** family and **0** style mismatches against CoreText (`CTFontManagerCreateFontDescriptorsFromURL` over 1,296 visible faces, matched by PostScript name). The reference ranking gives 33 family and 31 style mismatches.
- **Mac CJK local names.** The widened fallback yields STSong → `('华文宋体',)`, STHeiti → `('华文黑体',)`, STKaiti → `('华文楷体',)`, STFangsong → `('华文仿宋',)` and LiSong Pro → `('儷宋 Pro',)`.
- **Unchanged cases.** PingFang, Songti and Hiragino keep their Windows-derived local names, and Raanana and AppleGothic stay `()`.

**5. Reference → destination:** `catalog/face.py:100-160` → `fpengine/face.py`, same function names.

### Acceptance criteria
Tests are in `engine/tests/test_names.py` unless another file is named. Fonts are built with the ported `build_font(..., name_records={name_id: [(platform, encoding, language, text)]})`. "Family records" are name ID 1 records and "style records" are name ID 2 records, unless an ID is given.
- **AC-108-1 (CATALOG-3, UI-M1)**
  - Family records `[(1, 0, 0, "Al Bayan"), (3, 1, 0x0C01, "البيان")]` read as `family == "Al Bayan"` and `local_names == ("البيان",)`.
  - Style records `[(1, 0, 0, "Bold"), (3, 1, 0x0C01, "عريض")]` read as `style == "Bold"`.
  - The Al Bayan font's `face_record` has `family == "Al Bayan"` and `"البيان" in local_names`, so both the English and the native name are searchable (UI-M1).
  
  (`test_catalog_3_mac_roman_english_beats_other_windows_languages`, `test_ui_m1_english_and_native_names_are_both_in_the_record`)
- **AC-108-2 (ENGINE-M4)** The Geeza-like records:
  - family `[(1, 0, 0, "Geeza Pro"), (3, 1, 0x420, "گیزا پرو"), (3, 1, 0x439, "गीज़ा प्रो"), (3, 1, 0xC01, "جيزة")]`,
  - style `[(1, 0, 0, "Regular"), (3, 1, 0x420, "عادي")]`,
  - code points `cps("ab")`,
  
  read as `display_name == "Geeza Pro Regular"` and `local_names == ("گیزا پرو", "गीज़ा प्रो", "جيزة")` (sorted by language ID). Forging it alone gives `report.materials[0].name == "Geeza Pro Regular"`, and output name ID 0 == `"Forged with Font Playground from: Geeza Pro Regular"`. (`test_engine_m4_default_names_are_english`)
- **AC-108-3** English beats a native-only typographic family: ID 16 `[(3, 1, 0xC01, "جيزة")]` with ID 1 `[(1, 0, 0, "Geeza Pro")]` reads as `family == "Geeza Pro"`. ID 16 `[(3, 1, 0x409, "Fixture T")]` with ID 1 `[(3, 1, 0x409, "Fixture T Light")]` reads as `"Fixture T"`. (`test_english_typographic_and_legacy_families`)
- **AC-108-4** The ported EPSON cases (`reference/…/tests/test_face.py:46-62`) all still pass. New parametrised rows:
  - `[(1, 0, 0, "Old Mac"), (3, 1, 0x411, JA)]` → `"Old Mac"`;
  - `[SJIS_AS_MAC_ROMAN, (1, 25, 33, "华文宋体")]` → `"华文宋体"`;
  - `[(1, 0, 0, "Café".encode("mac_roman"))]` → `"Café"` (non-ASCII Mac Roman falls through to `getDebugName`).
  
  (`test_family_comes_from_a_correctly_decoded_record` in `engine/tests/test_face.py`)
- **AC-108-5 (CATALOG-M2)** Family `(3, 1, 0x409, "Fixture ST")` plus:
  - `(1, 25, 33, "华文宋体".encode("gb2312"))` → `local_names == ("华文宋体",)`;
  - `(1, 2, 19, "儷宋 Pro".encode("big5"))` → `("儷宋 Pro",)`;
  - `(1, 3, 23, "애플고딕".encode("euc_kr"))` → `("애플고딕",)`;
  - all four Mac CJK records (33, 19, 11, 23) → local names ordered zh-Hans, zh-Hant, ja, ko.
  
  (`test_catalog_m2_mac_chinese_korean_local_names`)
- **AC-108-6** Mac CJK records are ignored when a Windows non-English record exists: `(3, 1, 0x411, "テスト")` + `(1, 25, 33, …)` → `("テスト",)`. A `(1, 0, 0, …)` record is never a local name. A `(1, 25, 33, b"\xa4")` record whose bytes don't decode (fontTools raises `UnicodeDecodeError`) is skipped without an error, and a valid `(1, 3, 23, …)` record next to it is still returned. (`test_local_names_fallback_rules`)
- **AC-108-7** `READER_VERSION` is increased by exactly 1 (reviewer check with `git diff main`, as AC-106-13), and `make lint` and `make engine-test` pass.

### Verification
```bash
make lint
make engine-test
```

### Notes for the implementer
- `NameRecord.toBytes()` returns the stored bytes, and `makeName(bytes, …)` stores bytes as they are. That is how the EPSON fixture keeps Shift-JIS inside a Mac Roman record.
- Don't normalise Unicode (NFC/NFD) in names. CoreText returns them as the font stores them.
- WP-106 may land first and add `full_name`, which uses `_best_name(name, (4,))`. Keep that call.

---

## WP-109: Unique, stable PostScript names; version and unique-ID fields; forged-font marker

**Goal:** every forged font gets a deterministic, collision-resistant PostScript name that can't match a real font; name ID 3, name ID 5 and `head.fontRevision` change on every forge; and the forged-font marker is defined once, unchanged from the Windows app.
**Depends on:** WP-002 · **Env:** linux · **Size:** S · **Closes findings:** ENGINE-M3, INSTALL-5

### Scope
- **In:** `fpengine/naming.py`, the `set_names` changes, the forge stamp, the name-validation rules, the report names, the file-level `is_forged`, and updating the ported forge tests.
- **Out:**
  - The catalog and CoreText PostScript-name conflict check before install (WP-403/WP-505).
  - The Swift port of `postscript_name` (core) and its conformance fixtures (WP-202; the cases are listed below).
  - The `is_forged` field in the `FaceRecord` (WP-106).

### Touched paths
- `engine/src/fpengine/naming.py` (new)
- `engine/src/fpengine/merge.py` (edit)
- `engine/src/fpengine/forge.py` (edit)
- `engine/src/fpengine/spec.py` (edit)
- `engine/src/fpengine/face.py` (edit, only if WP-106 has landed: import `FORGED_NOTICE` from `fpengine.naming` at module level; see WP-106 Design §2, `is_forged` row)
- `engine/tests/test_naming.py` (new)
- `engine/tests/test_forge.py` (edit: the two PostScript-name asserts)

### Design

**1. `fpengine/naming.py`.** It is a leaf module: it imports nothing from `fpengine`, so anything can import it.

```python
FORGED_NOTICE = "Forged with Font Playground"          # exact; starts name ID 0 of every forged font
MAX_POSTSCRIPT = 63
MAX_STYLE_PART = 20
TAG_PREFIX = "FP"
VERSION_EPOCH = datetime(2000, 1, 1, tzinfo=timezone.utc)

def clean_name(s: str) -> str: ...                      # s.strip()  (Python str.isspace set, see below)
def ascii_alnum(s: str) -> str: ...                     # re.sub(r"[^A-Za-z0-9]", "", s)
def fnv1a64(data: bytes) -> int: ...
def name_tag(family: str, style: str) -> str: ...        # 8 lowercase hex digits
def postscript_name(family: str, style: str) -> str: ...

@dataclass(frozen=True)
class ForgeStamp:
    when: datetime          # timezone-aware, UTC, microsecond == 0
    nonce: str              # 8 lowercase hex digits
def new_stamp() -> ForgeStamp: ...                      # now (UTC, seconds) + secrets.token_hex(4)
def version_parts(stamp: ForgeStamp) -> tuple[int, int]: ...   # (days, fraction5)
def version_string(stamp: ForgeStamp) -> str: ...       # "Version {days}.{fraction5:05d}"
def font_revision(stamp: ForgeStamp) -> float: ...      # days + fraction5 / 100000
def unique_id(full_name: str, stamp: ForgeStamp) -> str: ...

def is_forged_name_table(name_table) -> bool: ...        # (name.getDebugName(0) or "").startswith(FORGED_NOTICE)
def is_forged(path: str | Path, index: int = 0) -> bool: ...  # port of reference ui/install.py:63-75
```

`merge.py` keeps `FORGED_NOTICE` importable with `from fpengine.naming import FORGED_NOTICE`, and `merge.postscript_name` becomes a re-export of `naming.postscript_name`.

**2. PostScript name algorithm** (normative; the Swift port must match byte for byte):

```
family, style := clean_name(family), clean_name(style)
h64  := FNV-1a 64 over UTF-8(family) ‖ 0x00 ‖ UTF-8(style)      offset 0xcbf29ce484222325, prime 0x100000001b3, mod 2^64
tag  := "FP" + lowercase hex, 8 digits, of ((h64 >> 32) XOR (h64 AND 0xFFFFFFFF))
sty  := (ascii_alnum(style) or "Regular")[:20]
fam  := (ascii_alnum(family) or "Forged")[: 63 - 1 - len(sty) - len(tag)]
PS   := fam + tag + "-" + sty
```

Properties:
- It matches `^[A-Za-z0-9]+-[A-Za-z0-9]+$` and is at most 63 characters, with exactly one hyphen (Adobe TN 5088 family-style convention).
- It is deterministic for the same cleaned `(family, style)`, so "Update installed font" keeps it.
- It differs whenever the cleaned pairs differ, up to a 32-bit hash collision. That includes all-CJK names and names that differ only in spaces.
- It can't equal a non-forged font's name unless that font happens to end its family part in exactly this `FP` + 8-hex token. The strict check against installed fonts stays with the installer and UI (WP-403/WP-505, CoreText), which keeps the algorithm free of catalog state and portable to Swift.

`clean_name` strips exactly the characters for which Python's `str.isspace()` is true: U+0009–U+000D, U+001C–U+001F, U+0020, U+0085, U+00A0, U+1680, U+2000–U+200A, U+2028, U+2029, U+202F, U+205F, U+3000. There is no Unicode normalisation, so NFC and NFD spellings give different names, and callers must pass the same string each time.

Worked examples (normative; computed with the reference implementation, audit venv, Python 3.12):

| family | style | PostScript name |
|---|---|---|
| `Avenir Next PingFang` | `Regular` | `AvenirNextPingFangFP61d27706-Regular` |
| `Avenir Next` | `Regular` | `AvenirNextFP76fdbbf4-Regular` (never `AvenirNext-Regular`) |
| `我的字体` | `Regular` | `ForgedFP5ef09893-Regular` |
| `你的字体` | `Regular` | `ForgedFP4f4f31c7-Regular` |
| `Noto 我的` | `Regular` | `NotoFP193bc651-Regular` |
| `Noto 你的` | `Regular` | `NotoFP39174c89-Regular` |
| `甲字体` | `粗体` | `ForgedFP4baff28f-Regular` |
| `甲字体` | `细体` | `ForgedFP865d96ec-Regular` |
| `My Font` | `Bold Italic` | `MyFontFP072c765b-BoldItalic` |
| `MyFont` | `Bold Italic` | `MyFontFP3601e1d1-BoldItalic` |
| `␠␠Forged Test␠` (␠ = U+0020) | `␠Regular␠` | `ForgedTestFP373d14cc-Regular` (the same as unpadded) |
| `A Very Long Family Name That Keeps Going And Going Forever` | `Extra Condensed Semibold Italic` | `AVeryLongFamilyNameThatKeepsGoinFP4bedb3c1-ExtraCondensedSemibo` (63) |

`fnv1a64(b"") == 0xcbf29ce484222325` and `fnv1a64(b"a") == 0xaf63dc4c8601ec8c`.

Non-normative Swift sketch for the core port (Foundation only, Linux-safe):

```swift
func fnv1a64(_ bytes: [UInt8]) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in bytes { h ^= UInt64(b); h = h &* 0x0000_0100_0000_01b3 }
    return h
}
let h = fnv1a64(Array(family.utf8) + [0] + Array(style.utf8))
let tag = "FP" + String(format: "%08x", UInt32(truncatingIfNeeded: (h >> 32) ^ (h & 0xffff_ffff)))
```

**3. Version and unique ID**
- `version_parts`: `d = stamp.when - VERSION_EPOCH`, `days = d.days`, `fraction5 = d.seconds * 100000 // 86400`. `ValueError` if `when` is before the epoch or `days > 32767`, since `head.fontRevision` is a signed 16.16 Fixed; that limit falls in 2089.
- `version_string` gives `"Version 9768.61258"` for 2026-09-29T14:42:07Z. `font_revision` gives `9768.61258`, which fontTools stores as a 16.16 Fixed (`head.fontRevision`, rounded to 1/65536, so within 1e-4).
- **What changes when** (the precise form of contracts §6 "changes on every forge"):
  - Name ID 3 differs on every forge, even within the same second, because of the nonce.
  - Name ID 5 differs for stamps at least 1 s apart: one fraction step is 0.864 s, so 1 s always moves `fraction5` by at least 1.
  - `head.fontRevision` differs for stamps at least **2 s** apart. A 16.16 Fixed has 65,536 steps per unit and `fraction5` has 100,000, so two adjacent `fraction5` values can round to the same Fixed (29% of the per-second pairs in a day do); two steps apart never do. It never decreases for a later stamp.
- `unique_id(full, stamp) = f"{full}; FontPlayground {stamp.when:%Y-%m-%dT%H:%M:%SZ}; {stamp.nonce}"`.

**4. `set_names` and `finish`** (reference `merge.py:50-71`, `:112-126`):
- The signature becomes `set_names(font, family, style, sources, stamp)`. `finish` calls it with `clean_name(spec.family_name)` and `clean_name(spec.style_name)` instead of the reference `.strip()` (`merge.py:114`); `set_style_bits(font, spec.style_name)` is unchanged.
- Name ID 3 = `unique_id(full, stamp)`, name ID 5 = `version_string(stamp)`, name ID 6 = `postscript_name(family, style)`.
- `finish(..., stamp)` also sets `font["head"].fontRevision = font_revision(stamp)`.
- Everything else stays as the reference has it: IDs 1/2/4/16/17, Windows (3,1,0x409) records everywhere, and Mac Roman (1,0,0) records only when the value encodes (`_mac_roman_safe`).
- Name ID 0 starts with the reference value, `f"{FORGED_NOTICE} from: " + ", ".join(sources)`. The contributing sources' copyright notices follow it, one per line (WP-110 Design §5a). `FORGED_NOTICE` always starts the record. When no contributing source has a copyright notice, the value is exactly the reference one. `set_names` also takes `notices` and writes IDs 7 and 14 (§5a).
- `forge(spec, output_path, progress=None, *, stamp: ForgeStamp | None = None)` uses `stamp or new_stamp()`. The keyword is optional, so WP-201's call `forge(spec, out, progress)` is unaffected.

**5. Validation** (added to `ForgeSpec.validate`, reference `spec.py:41-69`, after the empty-name checks; exact messages):
- `clean_name(family_name).startswith(".")` → `"Family name can't start with “.”: macOS hides fonts whose names start with a dot."`
- A character in U+0000–U+001F or U+007F in the cleaned family → `"Family name contains a control character."`; the same in the style → `"Style name contains a control character."`

**6. Report names.** `ForgeReport.family_name`, `style_name`, `full_name` and `postscript_name` hold the values written: cleaned family, cleaned style, `f"{family} {style}"`, and name ID 6.

**7. Conformance cases for WP-202** (`spec/fixtures/naming/postscript_names.json`): every row of the table above, plus
- `("", "Regular")` → `ForgedFP55a0a3da-Regular`;
- an NFC/NFD pair of `"Café"`;
- `("\u3000Noto\u00a0", "Regular")` (both stripped, which gives the same result as `("Noto", "Regular")`);
- 20 generated names per script group sample from `scripts.py`.

**8. Reference → destination**

| Reference | Destination |
|---|---|
| `engine/merge.py:32-36` `postscript_name` | `fpengine/naming.py` (merge re-exports it) |
| `engine/merge.py:47` `FORGED_NOTICE` | `fpengine/naming.py` (merge re-exports it) |
| `engine/merge.py:50-71` `set_names` | `fpengine/merge.py` (+ stamp) |
| `ui/install.py:63-75` `is_forged` | `fpengine/naming.py` |
| `tests/test_forge.py:25` | `engine/tests/test_forge.py`: `== postscript_name("Forged Test", "Regular") == "ForgedTestFP373d14cc-Regular"` |
| `tests/test_forge.py:83` | `engine/tests/test_forge.py`: `== postscript_name("合体字体", "Regular") == "ForgedFP01c0f84d-Regular"` |
| `tests/test_install.py:28-37` | `engine/tests/test_naming.py` (the `is_forged` cases) |

### Acceptance criteria
Tests are in `engine/tests/test_naming.py` unless another file is named. Forges use fixture A from `font_dir` unless stated.
- **AC-109-1** `postscript_name` returns exactly the table in Design §2 for every row, and `fnv1a64` matches the two constants. (`test_postscript_name_examples`, `engine/tests/test_naming.py`)
- **AC-109-2** For the 9,000 pairs:
  - families `[f"Family {i}" for i in range(500)]`, `[chr(0x4E00 + i) + "字体" for i in range(500)]`, `[f"Noto {chr(0x4E00 + i)}" for i in range(250)]`, `[f"My Font {i}" for i in range(125)]` and `[f"MyFont {i}" for i in range(125)]`,
  - × styles `["Regular", "Bold", "Bold Italic", "BoldItalic", "粗体", "细体"]`,
  
  all 9,000 PostScript names are distinct, and each matches `^[A-Za-z0-9]+-[A-Za-z0-9]+$` with length ≤ 63. (`test_install_5_postscript_names_are_unique`)
- **AC-109-3 (ENGINE-M3)** Forging fixture A with `family_name="Avenir Next"` writes name ID 6 `"AvenirNextFP76fdbbf4-Regular"`, which is not `"AvenirNext-Regular"`. `ForgeReport.postscript_name` equals it. (`test_engine_m3_ps_name_never_equals_the_plain_system_name`)
- **AC-109-4 (INSTALL-5)** Forging fixture A as `我的字体` and as `你的字体` gives different name ID 6 values. Forging `甲字体` with styles `粗体` and `细体` gives different values. Forging the same `(family, style)` twice gives equal values. (`test_install_5_cjk_families_get_distinct_ps_names`)
- **AC-109-5** Given forges of the same spec (fixture A) with `t1 = ForgeStamp(datetime(2026, 9, 29, 14, 42, 7, tzinfo=timezone.utc), "0a1b2c3d")`:
  - `version_string(t1) == "Version 9768.61258"`.
  - With `t2 = ForgeStamp(t1.when + timedelta(seconds=2), "0a1b2c3d")`: name ID 5, the saved `head.fontRevision` and name ID 3 all differ, and `font_revision(t2) > font_revision(t1)`.
  - With `ForgeStamp(t1.when + timedelta(seconds=1), "0a1b2c3d")`: name ID 5 and name ID 3 differ from `t1`'s.
  - For every whole second `s` of one day (86,400 stamps, pure function, no forge): `version_parts` strictly increases, and `floatToFixed(font_revision(stamp_s), 16)` (`fontTools.misc.fixedTools`) differs from that of `stamp_{s+2}`.
  - With `t1` and `ForgeStamp(t1.when, "ffffffff")`: only name ID 3 differs.
  - The same stamp twice gives equal compiled `name` tables (`font["name"].compile(font)`) and equal `head.fontRevision`.
  - Name ID 5 matches `^Version \d+\.\d{5}$`, and `abs(float(name5[8:]) - head.fontRevision) < 1e-4`.
  
  (`test_version_and_unique_id_change_every_forge`)
- **AC-109-6** `naming.FORGED_NOTICE == "Forged with Font Playground"` and `merge.FORGED_NOTICE is naming.FORGED_NOTICE`. Forged output has name ID 0 starting with it, in the (3,1,0x409) record **and** in the (1,0,0) record when the value is Mac-Roman-safe. (`test_forged_notice_is_unchanged`)
- **AC-109-7** `is_forged` is true for a forged output, and true for the reference fixture with name ID 0 `"Forged with Font Playground from: Fixture A Regular"`. It is false for fixture A, a missing path, a junk file and the non-forged TTC. (`test_is_forged_reads_the_notice_in_name_id_0`)
- **AC-109-8** `validate()` returns the exact messages from Design §5 for the family `".Hidden"`, the family `"Bad\x07Name"` and the style `"Bold\x1b"`, and returns nothing new for `"  Normal "`. Forging with `".Hidden"` raises `ForgeError(stage="validate")`. (`test_name_validation_rules`)
- **AC-109-9** `ForgeReport` `family_name`, `style_name`, `full_name` and `postscript_name` equal the written name IDs (16 or 1, 17 or 2, 4, 6) for a standard style (`Regular`) and a non-standard one (`Semibold Condensed`). (`test_report_carries_written_names`)
- **AC-109-10** The ported `test_forge.py` passes with only the two PostScript-name asserts changed as in the table in Design §8. `make lint` and `make engine-test` pass.

### Verification
```bash
make lint
make engine-test
```

### Notes for the implementer
- Keep `postscript_name` pure and free of I/O. WP-202 and the Swift core rely on it.
- Don't write the stamp into the `head.created`/`modified` fields. fontTools recalculates `modified` on save.
- `ForgeError`'s `code` and `material_index` (S5) are not needed here. Use them if they are already present.
- **Why the installer, not the engine, does the strict "never equal" check.** A reserved-name list in `ForgeRequest` would make the name depend on the catalog, so an Update could change it, and Swift would need the same list. See backbone issues.

---

## WP-110: Licence policy: fsType propagation, licence classes, report notes

**Goal:** the forged font never has looser embedding permissions than its sources. Each face gets a licence class, and the report (and the forged font's name ID 13) say plainly what the licences of the fonts used mean for the result.
**Depends on:** WP-101, WP-106, WP-109 · **Env:** linux · **Size:** S · **Closes findings:** ENGINE-5, CRIT-3

### Scope
- **In:**
  - Classification (`licence_class` at read time).
  - The output fsType rule.
  - Embedding and licence issues.
  - `ForgeReport.fs_type` and `licence_notes`.
  - `as_text` lines.
  - Name ID 13 in the output.
  - The sources' copyright, trademark and licence notices in the output (name IDs 0, 7, 13 and 14; Design §5a).
- **Out:**
  - Showing the notes next to Save/Install (WP-505).
  - README and About text (WP-602).
  - Refusing builds. ADR-0012: the app never refuses for licence reasons.

### Touched paths
- `engine/src/fpengine/licence.py` (edit)
- `engine/src/fpengine/face.py` (edit: `licence_class`, `READER_VERSION`, `source_notices`)
- `engine/src/fpengine/prepare.py` (edit: `PreparedFont.notices`)
- `engine/src/fpengine/merge.py` (edit: fsType, name IDs 0, 7, 13 and 14)
- `engine/src/fpengine/forge.py` (edit: report)
- `engine/src/fpengine/spec.py` (edit: S5 types, `as_text`)
- `engine/src/fpengine/protocol/report.py` (edit, only if WP-201 has landed: delete the `"licence_notes"` key from `INTERIM_REPORT_FIELDS`, helper.md H9)
- `engine/tests/test_licence.py` (new)
- `engine/tests/test_forge.py` (edit: assert the output fsType in the restricted test)
- Earlier engine regression tests (edit only their interim issue/metadata expectations when licence classification lands)

### Design

**1. Output fsType** (`licence.output_fs_type(values: Iterable[int | None]) -> int`):
- Ignore `None`, which means no OS/2 (WP-103 synthesises one with fsType 0).
- The usage part is the first of `0x0002` (restricted), `0x0004` (preview & print) and `0x0008` (editable) set in **any** value, or 0. This is ADR-0012's order, and the same precedence as `_embedding` (`face.py:90-97`).
- OR in bits `0x0100` (no subsetting) and `0x0200` (bitmap embedding only) from every value.
- The inputs are the `fs_type` of the **contributing** materials, those with `p.assignments[i]` non-empty. The `.notdef` taken from material 0 does not count.
- `finish` writes it in place of `os2.fsType = 0` (`merge.py:120`). The output OS/2 is version ≥ 4 (`upgrade_os2`), so exactly one usage bit is set.
- `ForgeReport.fs_type` holds the value.

**2. Licence classification** (`licence.classify_licence`):

```python
SYSTEM_ROOTS: tuple[str, ...] = ("/System/Library/",)
OFFICE_BUNDLE_RE = re.compile(r"/Microsoft [^/]+\.app/Contents/")
OPEN_RE = re.compile(r"open font licen[cs]e|openfontlicense\.org|scripts\.sil\.org/ofl|apache licen[cs]e|apache\.org/licenses", re.I)
MICROSOFT_RE = re.compile(r"microsoft supplied font", re.I)
APPLE_RE = re.compile(r"\bapple (inc|computer)\b", re.I)

def licence_texts(name) -> tuple[list[str], list[str]]:
    """(texts of every decodable record with name ID 13 or 14, texts of every decodable record with name ID 0 or 7)."""

def classify_licence(*, licence_texts: Sequence[str], copyright_texts: Sequence[str], vendor_id: str | None,
                     path: str, forged: bool = False, roots: Sequence[str] | None = None) -> str:
    """roots=None reads the module attribute SYSTEM_ROOTS at call time, so tests can monkeypatch it."""
```

Rules, in order; the first match wins:

| # | Condition | Class |
|---|---|---|
| 0 | `forged`, and any licence text (name ID 13 or 14) contains `LICENCE_NOTES["microsoft-product"]` / `["apple-sla"]` / `["unknown"]` / `OPEN_NOTE` (checked in that order) | that class, or `open` for `OPEN_NOTE`. A forged font keeps its sources' class |
| 1 | `OPEN_RE` matches any licence text | `open` |
| 2 | `MICROSOFT_RE` matches any licence text, or `OFFICE_BUNDLE_RE` matches `path` or `os.path.realpath(path)` | `microsoft-product` |
| 3 | `vendor_id == "APPL"`, or `APPLE_RE` matches any copyright text, or `path` or `os.path.realpath(path)` starts with one of `roots` | `apple-sla` |
| 4 | otherwise | `unknown` |

`read_faces` sets `licence_class = classify_licence(..., path=str(path), forged=is_forged)`. `realpath` is used only for this decision, and the record's `path` is never rewritten (contracts §2). Increment `READER_VERSION`.

**Evidence.**
- **Open fonts under `/System/Library`.** The verifier counted 140 of 398 font files under `/System/Library/Fonts`, `Supplemental` and `AssetsV2` that declare OFL or Apache in name ID 13 or 14 (Noto, STIX, Baloo, Mukta…). A re-count on the audit Mac with `OPEN_RE` (first face of each file, same folders) matched 140 of 417 files, so the pattern finds the same set.
- **Office fonts.** Only 65 of 280 Office `DFonts` files carry the "Microsoft supplied font" wording, so rule 2 needs the bundle path too (CRIT-3).
- **Apple markers.** 37 files have vendor `APPL`, and 72 name Apple Inc. or Apple Computer in ID 0 or 7. PingFang (`DYNA`) and Helvetica Neue (`LINO`) are caught only by the path rule (ENGINE-5).
- **Known imprecision.** ParaType's free licence and other non-OFL/Apache open licences under `/System/Library` classify as `apple-sla`. ADR-0012 limits `open` to OFL and Apache, and the class only informs.

**3. Texts** (exact; `licence.py`):

```python
LICENCE_NOTES = {
    "apple-sla": "Bundled with macOS: licensed for use on this Mac only; do not distribute the forged font.",
    "microsoft-product": "Supplied with a Microsoft product: licensed for use with that product only; do not distribute the forged font.",
    "unknown": "Licence unknown: check the source font's licence before you share the forged font.",
}
OPEN_NOTE = "Made from fonts under the SIL Open Font License or the Apache License: their terms apply to this font."
EMBEDDING_NOTES = {
    0x0002: "source licence forbids embedding (restricted); check before distributing",   # reference forge.py:24, verbatim
    0x0004: "source licence allows preview & print embedding only; check before distributing",
    0x0008: "source licence allows editable embedding only; check before distributing",
}
FS_LABELS = {0: "Installable", 0x0002: "Restricted", 0x0004: "Preview & Print", 0x0008: "Editable"}
```

**4. Report** (`forge._report`). Only contributing materials count, and the codes are in S6:
- **Embedding.** Per material whose usage class (the `_embedding` precedence) is not installable: issue `embedding_restricted`, `embedding_preview_print` or `embedding_editable`, with note `EMBEDDING_NOTES[bit]`. This replaces the reference's restricted-only note, keeping the same text for restricted. Non-contributing materials get no licence or embedding issue; they keep "contributes no characters".
- **Licence class.** Per material whose class is not `open`: issue `licence_apple_sla`, `licence_microsoft_product` or `licence_unknown`, with message `f"{name}: {LICENCE_NOTES[class]}"`. Per S5, these are **not** appended to the warnings. The reference test asserting `materials[0].warnings == ["synthetic bold (+300)"]` must keep passing.
- **Licence notes.** `licence_notes` has one `LicenceNote` per non-open class present, in the fixed order `apple-sla`, `microsoft-product`, `unknown` (the order of ADR-0012 and of ui-shell.md WP-505 D10), with ascending `material_indexes` and `text = LICENCE_NOTES[class]`.
- **Output fsType.** If it is not 0: report-level issue `output_fs_type` with message `f"The forged font is marked “{FS_LABELS[usage]}” (fsType {value}) because that is the most restrictive embedding permission of the fonts it uses."`
- **`as_text()`** (reference `spec.py:120-129`). When `licence_notes` is non-empty, append `""`, `"Licence:"` and one line per note: `f"  - {text} ({', '.join(material names)})"`.

**Integration clarification.** WP-101–107 tests that assert an empty issue list or only their own technical issue now compare the non-licence issues; WP-110 tests separately assert the licence issues, class order, contributor filtering and warning exclusion. The WP-106 APPL vendor fixture changes from its interim `unknown` class to `apple-sla`. These replace interim expectations without changing the earlier technical regressions.

**5. Name ID 13.** `finish(..., licence_description: str | None)`. After `set_names`, if it is not `None`, write name ID 13 in (3,1,0x409), plus (1,0,0) when Mac-Roman-safe.
- The value is the texts of the non-open classes present, joined with one space in the order of §4.
- If every contributing material is `open`, the value is `OPEN_NOTE`.
- The contributing sources' own licence descriptions (§5a) follow that value, one per line. The class notes stay on the first line: rule 0 and `forged_licence_classes` find them there, and `source_notices` skips that line when the forged font is used again.
- If nothing contributes, there is no ID 13.

Rule 0 then keeps the class when a forged font is used as a material again, so re-forging can't launder a licence. A forged font can carry several notes, while rule 0 gives the record one class. So `read_faces` also sets `FontFace.licence_classes` to every non-open class whose note it carries (in §4 order) when there are two or more, and `()` otherwise. `licence_notes`, name ID 13 and the per-material `licence_*` issues use all of them, so re-forging an Apple + unknown font keeps both notes. The face record still carries only `class`: the helper re-reads each material from its file at forge time. (`test_reforging_keeps_every_licence_class`)

**5a. Source notices.** A forged font is a modified copy of its sources. Licences such as the SIL Open Font License (condition 2) and Apache-2.0 (§4(c)) require a modified copy to keep the original copyright notice. Removing copyright management information can also be unlawful in itself (for example US 17 U.S.C. §1202). So the output keeps the notices of every contributing material:

| Name ID | Output value |
|---|---|
| 0 | WP-109 §4's `f"{FORGED_NOTICE} from: {sources}"`, then each carried copyright notice on its own line |
| 7 | The carried trademark notices, one per line. No record when there are none |
| 13 | §5's value, then the carried licence descriptions, one per line |
| 14 | The carried licence URLs, one per line. No record when there are none |

- **Reading.** `face.source_notices(name)` returns `(name ID, text)` pairs in `licence.NOTICE_IDS` order, `(0, 7, 14, 13)`. It takes the preferred record of each ID with the face reader's ranking (`_best_name`, WP-108), and collapses the whitespace of each text to single spaces, so a notice always fits on one line. In a forged font (`_is_forged`), each line of a record is one notice, and the first line of name ID 0 (the marker) and of ID 13 (the class notes) is skipped. Re-forging therefore carries the original notices without nesting the marker, and a font forged by the Windows app carries none.
- `prepare()` reads them from the source file before instancing and subsetting, into `PreparedFont.notices: tuple[tuple[int, str], ...] = ()`, the same way it keeps `aat_losses` (WP-107 §6). `FontFace` and the `FaceRecord` don't change, so neither does `READER_VERSION`.
- **Choosing.** `forge()` calls `_carried_notices(p, prepared, merge.notice_budget(spec, stamp, licence_description))` once, after `prepare`, and passes the kept notices to `finish` and the left-out counts to `_report`. `_carried_notices` goes through `NOTICE_IDS`, and for each ID through the contributing materials (`p.assignments[i]` non-empty) in material order. It keeps each text once per name ID (an exact match after the whitespace collapse).
- **Room.** `name` addresses its strings with 16-bit offsets, so all records together must fit in 64 KB (`merge.NAME_TABLE_LIMIT = 0xFFFF`). A single full licence text in ID 13 can take several kilobytes. `merge.notice_budget` is that limit less the records Font Playground writes itself (WP-109 §4's names and §5's ID 13 value), each measured as its UTF-16 length plus its Mac copy when it has one. Family and source names have no length limit, so a fixed share could still overflow. Each notice costs at most `merge.notice_bytes(text)`: its UTF-16 length, plus one byte per character for the Mac copy, plus 3 for the line breaks. A notice that doesn't fit in what is left is left out whole, never truncated; later, shorter notices can still fit. Copyright notices are taken first, so they are the last to be left out.
- **Report.** Each contributing material with left-out notices gets the issue `notices_left_out` (S6), after its `licence_*` issues: `f"{name}: copyright and licence notices too long to keep in the forged font ({n} left out); keep the source font's own notices and licence with the forged font"`. Like every non-licence issue, it is also in `warnings`.
- **Writing.** `set_names(..., notices)` writes IDs 0, 7 and 14, and `finish` writes ID 13. All four go to (3,1,0x409), plus (1,0,0) when the whole value is Mac-Roman-safe. A Chinese copyright notice therefore leaves ID 0 with only its Windows record, which `is_forged` and the Swift `ForgedMarker` read.
- Rule 0 still classifies a forged font by the class notes on the first line of ID 13. A carried source description can add a class only by quoting one of the notes word for word, and that makes the result stricter, never looser.

**6. Final `finish` signature** (merges WP-109 and WP-110):

```python
def finish(font, spec, base, codepoints, weight_class, *, stamp, fs_type: int, licence_description: str | None,
           notices: Mapping[int, Sequence[str]] | None = None) -> None
```

**7. Reference → destination**

| Reference | Destination | Change |
|---|---|---|
| `engine/merge.py:120` | `fpengine/merge.py` `finish` | `os2.fsType = fs_type` |
| `engine/forge.py:23-24` | `fpengine/forge.py` `_report` | Per-class issues and notes |
| `engine/spec.py:112-129` | `fpengine/spec.py` | `fs_type`, `licence_notes`, `as_text` |
| `tests/test_forge.py:44-48` | `engine/tests/test_forge.py` | + `OS/2.fsType == 2` |

### Acceptance criteria
Tests are in `engine/tests/test_licence.py` unless another file is named. Fixtures are built with the ported `build_font` and S7 `decorate`, in `tmp_path` (never under a real `/System/Library`).
- **AC-110-1 (ENGINE-5)** `output_fs_type` gives:
  - `[0, 8] == 8`, `[4, 8] == 4`, `[2, 4] == 2`, `[6] == 2`, `[12] == 4`, `[0, 0] == 0`, `[None, 8] == 8`;
  - `[0x0108, 0] == 0x0108`, `[0x0200, 4] == 0x0204`.
  
  (`test_engine_5_output_fstype_is_most_restrictive`, `engine/tests/test_licence.py`)
- **AC-110-2 (ENGINE-5)** Given materials:
  - Forging fixture A (fsType 0, `abc1,`) with `build_font(tmp/"P.ttf", "Fixture P", "Regular", cps("x"), fs_type=4)` writes output `OS/2.fsType == 4` and `report.fs_type == 4`. It raises one `embedding_preview_print` issue (`material_index == 1`) and one `output_fs_type` issue whose message contains `“Preview & Print” (fsType 4)`.
  - Fixture A with a `cps("a")` variant of P gives fsType 0 and no embedding issue, because P then contributes nothing.
  - Fixture C alone gives fsType 2, and `"source licence forbids embedding (restricted); check before distributing"` in its warnings.
  
  (`test_engine_5_fstype_propagates_from_contributing_materials`)
- **AC-110-3 (ENGINE-5)** `classify_licence` cases (pure; `path` strings do not need to exist):

  | Inputs | Class |
  |---|---|
  | ID 13 "This Font Software is licensed under the SIL Open Font License, Version 1.1.", path `/System/Library/Fonts/Supplemental/NotoSansX.ttf` | `open` |
  | ID 14 `https://www.apache.org/licenses/LICENSE-2.0`, path `/tmp/x.ttf` | `open` |
  | OFL text + copyright "© 2020 Apple Inc.", vendor `APPL`, path `/System/Library/Fonts/x.ttf` | `open` |
  | ID 13 "Microsoft supplied font. You may use this font…", path `/tmp/x.ttf` | `microsoft-product` |
  | path `/Applications/Microsoft Word.app/Contents/Resources/DFonts/msyh.ttc`, no texts | `microsoft-product` |
  | vendor `APPL`, path `/tmp/x.ttf` | `apple-sla` |
  | copyright "Copyright © 2015 Apple Inc. All rights reserved.", path `/tmp/x.ttf` | `apple-sla` |
  | path `/System/Library/AssetsV2/com_apple_MobileAsset_Font8/x.asset/AssetData/PingFang.ttc`, vendor `DYNA` | `apple-sla` |
  | path `/Users/example/Library/Fonts/x.ttf`, nothing else | `unknown` |
  | `forged=True`, ID 13 = the apple-sla note, path `/Users/example/Library/Fonts/f.ttf` | `apple-sla` |
  | `forged=True`, ID 13 = `OPEN_NOTE`, path `/System/Library/Fonts/f.ttf` | `open` |
  | `forged=False`, ID 13 = the apple-sla note, path `/tmp/x.ttf` (a non-forged font quoting the note) | `unknown` |

  (`test_engine_5_licence_classes`)
- **AC-110-4** With `licence.SYSTEM_ROOTS` monkeypatched to `(os.path.realpath(tmp / "System/Library") + "/",)`, a fixture copied under `tmp/System/Library/Fonts/` reads with `licence_class == "apple-sla"`. (`realpath` keeps this working where the temporary folder is behind a symlink, such as `/var` → `/private/var` on macOS.) A symlink to it from `tmp/user/` also reads as `"apple-sla"`, through `realpath`, and its record `path` is the symlink path, unchanged. The same fixture decorated with the OFL ID 13 text reads as `"open"`. (`test_licence_class_is_read_with_the_face`)
- **AC-110-5 (CRIT-3)** A fixture copied to `tmp/Microsoft Word.app/Contents/Resources/DFonts/x.ttf` reads as `microsoft-product`. Forging it gives a `licence_microsoft_product` issue and a `LicenceNote(licence_class="microsoft-product", material_indexes=(0,), text=LICENCE_NOTES["microsoft-product"])`. (`test_crit_3_office_bundle_font_is_microsoft_product`)
- **AC-110-6** For four contributing fixtures with distinct characters (`a`, `b`, `c`, `d`), classified `[apple-sla (vendor APPL), apple-sla (name ID 0 "Copyright © 2015 Apple Inc."), unknown (nothing), open (OFL name ID 13)]`:
  - `licence_notes == [LicenceNote("apple-sla", (0, 1), …), LicenceNote("unknown", (2,), …)]`;
  - the output name ID 13 equals `LICENCE_NOTES["apple-sla"] + " " + LICENCE_NOTES["unknown"] + "\n" + OFL`: the open material's own description follows on its own line (§5a);
  - `as_text()` contains `"Licence:"` and one line per note.
  
  With only the `open` material, `licence_notes == []` and name ID 13 == `OPEN_NOTE + "\n" + OFL`. (`test_licence_notes_and_name_id_13`)
- **AC-110-7** A font forged from an `apple-sla` material, read back with `read_faces`, has `is_forged is True`, `naming.is_forged(path) is True` (WP-106 and WP-109 agree) and `licence_class == "apple-sla"`, even though its path is outside the roots. (`test_forged_font_keeps_its_licence_class`)
- **AC-110-8** `READER_VERSION` is increased by 1 (reviewer check with `git diff main`, as AC-106-13). The ported `test_forge.py` passes, with `test_forge_restricted_licence_is_a_warning` also asserting `OS/2.fsType == 2`. `make lint` and `make engine-test` pass.
- **AC-110-9** Here `COPYRIGHT_A = "Copyright 2020 The Alpha Project Authors (https://example.org/alpha)"`, `COPYRIGHT_B = "© 2021 Beta Type Foundry. All rights reserved."` and `OFL_URL = "https://openfontlicense.org"`. Forging two fixtures, `a` with name ID 0 `COPYRIGHT_A`, ID 7 (a trademark notice), ID 13 `OFL` and ID 14 `OFL_URL`, and `b` with name ID 0 `COPYRIGHT_B`:
  - writes name ID 0 `f"{FORGED_NOTICE} from: Fixture a Regular, Fixture b Regular\n{COPYRIGHT_A}\n{COPYRIGHT_B}"` in both the (3,1,0x409) and the (1,0,0) record;
  - keeps `a`'s IDs 7 and 14, and writes ID 13 `LICENCE_NOTES["unknown"] + "\n" + OFL`;
  - reads back with `is_forged is True`, `naming.is_forged(path) is True` and `licence_class == "unknown"`.
  
  (`test_forge_keeps_source_copyright_notices`)
- **AC-110-10** A notice that another material repeats with different whitespace is kept once. A material that contributes nothing adds no notice. A Chinese copyright notice is kept; ID 0 then has no (1,0,0) record, and the output still reads as forged. (`test_forge_keeps_each_contributing_notice_once`)
- **AC-110-11** Re-forging the AC-110-9 output with a third fixture `c` (ID 0 `"Copyright 2019 Gamma"`) writes name ID 0 as the new marker line followed by `a`'s, `b`'s and `c`'s notices, with `FORGED_NOTICE` exactly once. IDs 13 and 14 keep the carried OFL description and URL. `source_notices` of the first output is `((0, COPYRIGHT_A), (0, COPYRIGHT_B), (14, OFL_URL), (13, OFL))`. A font forged by the Windows app yields `()`, and a two-line copyright yields one notice on one line. (`test_reforging_carries_source_notices_without_nesting_the_marker`, `test_source_notices_read_one_line_per_notice`)
- **AC-110-12** Three contributing fixtures carry ID 13 texts of 20,000, 15,000 and 1,000 characters, and the first also has a copyright notice. The forge succeeds: ID 0 keeps the copyright notice, and ID 13 keeps the 20,000- and 1,000-character texts. Material 1 gets one `notices_left_out` issue with "(1 left out)", after its `licence_unknown` issue and also in `warnings`. With `merge.notice_budget` returning 10⁹, the same forge fails with `ForgeError(stage="finish")` because the name table overflows. (`test_notices_too_long_for_the_name_table_are_left_out_and_reported`)
- **AC-110-13** Forging a fixture whose ID 0 is 15,900 characters, with a 2,200-character family name, succeeds. ID 0 is only the marker line, and the issues are `licence_unknown` then `notices_left_out`. With a fixed 48,000-byte budget instead, the same forge fails at stage `finish`. (`test_notice_budget_leaves_room_for_long_generated_names`)

### Verification
```bash
make lint
make engine-test
```

### Notes for the implementer
- Only the texts in Design §3 are user-facing. The UI (WP-505) shows `licence_notes[].text` as it is. Keep them in `licence.py`, so a later localisation pass has one place to look.
- Don't read files outside the given path. `realpath` doesn't need the target to exist.
- Don't warn for `open` sources. ADR-0012 shows lines only for non-open classes. In the font, `OPEN_NOTE` in name ID 13 summarises the OFL obligations, and the sources' own copyright notices and licence descriptions follow (§5a).
- Rebase on WP-109 (it lands in wave 3), and on WP-107 if it merges first. Both touch `_report` and `ForgeReport`.

---

## Hand-off to WP-111 (real-font checks)

These are non-binding inputs for the `apple_fonts` matrix in `engine-correctness.md`. Each row is a check that WP-111 can run with `read_faces` or `forge` on real Apple fonts. They were observed on the audit Mac (Apple silicon, macOS 27).

| Font | Expected after WP-106–110 |
|---|---|
| `/System/Library/Fonts/LastResort.otf` | `hidden`, `suspicious_coverage`, `has_os2 is False` |
| `/System/Library/Fonts/Supplemental/NISC18030.ttf` | Read without an error; unsupported "bitmap-only font (no outlines)" |
| SFNS.ttf | `hidden` (PostScript name `.SFNS-…`) |
| GeezaPro.ttc [0] | family `Geeza Pro`; `aat.morx`; `kern_v1`; `arabic` not in `shapes_groups`; about 1,030 `unshaped` code points (1,014 Arabic-script through U1 + 18 through U2) |
| Damascus.ttc [0] | `arabic` in `shapes_groups`; `unshaped == ∅` |
| AlBayan.ttc [0] | family `Al Bayan`; `local_names` contains `البيان` |
| Songti.ttc [4] | family `STSong`; `local_names == ('华文宋体',)` |
| Helvetica Neue + PingFang SC forge | `aat_morx_dropped` for Helvetica Neue; `licence_notes` has `apple-sla`; output fsType 4 (PingFang's preview & print), or 2 if a restricted material contributes |
| Avenir Next + Geeza Pro forge, rule `arabic → 1` | `ForgeError` with code `aat_unsupported_script` |
