# Cross-cutting contracts

> Normative. These are the names, data shapes and boundaries that more than one spec depends on. Each spec refines the **details** in its own area (e.g. `helper.md` owns the exact JSON Schemas; `core.md` owns the Swift types). **It must not rename or drop what is fixed here.** Changing a contract means updating this file and every spec that uses it in one PR.

## 1. Glossary

| Term | Meaning | Original (`reference/…`) |
|---|---|---|
| **Face** | One font inside a file: a `.ttf`/`.otf`, or one index of a `.ttc`/`.otc` | `catalog/face.py: FontFace` |
| **FaceKey** | `(path, index)`: runtime identity of a face | `FaceKey = tuple[str, int]` |
| **Material** | A face used in the recipe, with optional per-material weight and scale adjustments | `engine/spec.py: MaterialSpec`, `ui/model.py: MaterialRow` |
| **Main font** | The material that sets line spacing and vertical metrics (the engine's `base_index`) | `base_key` |
| **Script group** | One of 15 fixed ids: `latin, greek, cyrillic, armenian_georgian, hebrew, arabic, indic, southeast_asian, hangul, kana, han, cjk_symbols, symbols, emoji, other` | `engine/scripts.py: GROUPS` |
| **Rule** (pin) | "Group G is drawn by material M", overriding the default top-down priority | `script_rules` / `pins` |
| **Language** | A user-facing language choice (Chinese Simplified, Japanese, Arabic…) mapped to groups and a sample | `ui/languages.py` |
| **Recipe** | The whole editable state: materials, main, rules, adjustments, defaults, names, sample text | `ui/model.py: ForgeModel` state |
| **Plan / source_of** | For each code point, which material draws it | `engine/planner.py` |
| **Forge** | Build the merged `.ttf` from a ForgeSpec | `engine/forge.py: forge()` |
| **Forged font** | A font produced by Font Playground. It carries the forged marker (§6) | `merge.FORGED_NOTICE` |

## 2. JSON conventions (protocol and files)

- UTF-8 JSON, **snake_case keys**. Swift wire and file types declare **explicit snake_case `CodingKeys`** and use a plain `JSONDecoder()`/`JSONEncoder()`. Never combine them with `.convertFromSnakeCase`: that combination fails with `keyNotFound` (verified).
- Paths are absolute POSIX strings, standardised (no `..`, symlinks **not** resolved), as given by the discovering component. The helper never rewrites the paths it is given.
- CoreText may spell a path differently from the file system (e.g. `/tmp` vs `/private/tmp`). Paths from different sources are compared by **file identity** (device + inode, via `URL.resourceValues(.fileResourceIdentifierKey)` or `stat`), never by string.
- Code-point sets travel as **sorted, non-overlapping inclusive ranges** `[[start, end], …]` (as `catalog/cache.py:_ranges` does).
- Unknown keys must be ignored by readers (forward compatibility). Missing optional keys take documented defaults.

## 3. `FaceRecord` (the output of `fpengine scan`, one per face)

`helper.md` owns the exact JSON Schema (`spec/protocol/face-record.schema.json`). These fields are fixed:

| Field | Type | Notes | Source WP |
|---|---|---|---|
| `path`, `index` | string, int | FaceKey | existing |
| `size`, `mtime` | int, number | file stat at scan time | existing |
| `family`, `style`, `full_name` | string | English-preferred names after the WP-108 ranking | existing + 108 |
| `postscript_name` | string \| null | name ID 6 | 106 |
| `local_names` | [string] | native family names, most useful first | existing + 108 |
| `outline` | `"glyf"｜"CFF"｜"CFF2"｜"none"` | | existing |
| `is_collection`, `is_variable` | bool | | existing |
| `axes` | [{`tag`, `min`, `default`, `max`}] | | existing |
| `weight_class`, `italic`, `upem`, `glyph_count` | int, bool, int, int | without OS/2: 700 if `head.macStyle` bit 0 is set, else 400 | existing + 103 |
| `coverage` | ranges | best cmap after WP-101 semantics | existing |
| `group_counts` | {group id: int} | non-empty groups only. After WP-107 these are **plannable** counts over `coverage − unshaped` | existing + 107 |
| `unshaped` | ranges | code points in `coverage` that the face maps but cannot shape (AAT-only complex scripts; ADR-0008). Empty for most faces | 107 |
| `embedding` | `"installable"｜"editable"｜"preview-print"｜"restricted"` | from fsType | existing |
| `fs_type` | int \| null | raw OS/2 fsType; null when there is no OS/2 table | 106 |
| `has_color` | bool | | existing |
| `supported`, `unsupported_reason` | bool, string \| null | WP-106 adds `"no Unicode characters (symbol or empty character map)"` | existing (+106 reasons) |
| `hidden` | bool | family or PostScript name starts with `.` | 106 |
| `suspicious_coverage` | bool | e.g. `.LastResort`: the cmap maps far more code points than there are glyphs; never suggested | 106 |
| `ot_scripts` | {`gsub`: [tag], `gpos`: [tag]} | OpenType ScriptList tags | 106 |
| `aat` | {`morx`, `kerx`, `kern_v1`, `trak`: bool} | Apple Advanced Typography tables present | 106 |
| `shapes_groups` | [group id] | complex groups this face can shape (ADR-0008 rule, computed by the engine) | 107 |
| `licence` | {`class`: `"open"｜"apple-sla"｜"microsoft-product"｜"unknown"`, `vendor_id`: string \| null, `notice`: string \| null (≤ 300 chars)} | ADR-0012 | 110 |
| `has_os2` | bool | | 103 / 106 |
| `is_forged` | bool | carries the forged marker (§6). WP-106 fills the field; WP-109 owns the marker constant and `naming.is_forged` | 106 / 109 |
| `font_revision` | string | `head.fontRevision` formatted `%.3f` | 106 |

Swift: `FPCore.FaceRecord` is `Codable, Sendable, Hashable`, with `var key: FaceKey`. Its display name is `"\(family) \(style)"`.

**Plannable coverage.** Every consumer that decides which face draws a character uses `coverage − unshaped`: the planner (`source_of`, Python and Swift), suggestions, "draws it well", and the missing-character list. A preview that ignored `unshaped` would show shaping the result does not have (NATIVE-M1).

## 4. `ForgeRequest` and `ForgeReport`

`ForgeRequest` (stdin of `fpengine forge`):

```json
{
  "spec": {
    "materials": [{"path": "/…/Helvetica.ttc", "index": 0, "weight": null, "scale": null,
                   "expect": {"postscript_name": "Helvetica", "size": 123, "mtime": 1.0}}],
    "base_index": 0,
    "script_rules": {"han": 1, "kana": null},
    "default_weight": null,
    "default_scale": 1.0,
    "family_name": "Helvetica PingFang",
    "style_name": "Regular"
  },
  "output_path": "/…/Caches/…/builds/forged-<uuid>.ttf"
}
```

- `spec` is the original `ForgeSpec.to_dict()` shape plus the optional per-material `expect`. When `expect` is present and the file's PostScript name, size or mtime differ, the forge fails with error code `stale_material`.
- `script_rules` values are material indexes or `null` (no rule).
- `expect.postscript_name` may be `null` (faces without name ID 6). `mtime` is compared with a tolerance of 1e-3 s, because it round-trips through JSON doubles.

`ForgeReport` (payload of the `forge` `result` event) extends `engine/spec.py: ForgeReport`:

| Field | Type |
|---|---|
| `output_path` | string |
| `family_name`, `style_name`, `postscript_name`, `full_name` | string (the names actually written, after WP-109) |
| `total_codepoints`, `total_glyphs` | int |
| `fs_type` | int (the output fsType after WP-110) |
| `materials` | [{`name`, `path`, `index`, `codepoints`, `groups`: [group id], `warnings`: [string]}] |
| `issues` | [{`code`, `severity`: `"warning"｜"error"`, `material_index`: int \| null, `group`: string \| null, `message`}]: machine-readable warnings (AAT loss, bold fallback, licence…). The `Issue` type and report plumbing are **owned by WP-101**; other WPs reuse them. The v1 codes are listed in engine-correctness.md (Shared definitions) and engine-metadata.md §S6 |
| `licence_notes` | [{`class`, `material_indexes`: [int], `text`}]: the JSON key is `class` (WP-110) |
| `warnings` | [string]: the human-readable lines, same as the original report |
| `duration_s` | number |

## 5. Helper events and error codes

Every stdout line is `{"protocol": 1, "type": <type>, …}`.

| `type` | Commands | Payload |
|---|---|---|
| `hello` | hello | `fpengine_version`, `protocol`, `python`, `fonttools`, `unicode_version`, `face_reader_version` (int; bumped whenever `scan` output changes for an unchanged file, and used as the catalog cache key), `platform`, `capabilities`: [string] |
| `progress` | scan, forge | `stage`, `fraction` (0…1), optional `material_index`, `done`, `total` |
| `face` | scan | `face`: FaceRecord |
| `file_error` | scan | `path`, `code` (`not_found`, `io_error`, `unreadable`, `internal`), `message` |
| `result` | all | command-specific summary (`scan`: counts; `forge`: ForgeReport) |
| `error` | all | `code`, `stage` \| null, `material_index` \| null, `message`, `detail` (traceback; not shown to users) |

Forge `stage` values: `validate, plan, prepare, merge, finish, verify, done`. The plain-language text belongs to the UI (`reference/.../ui/model.py: STAGE_TEXT`).

Error `code`s:

| Code | Meaning |
|---|---|
| `bad_request` | Malformed request |
| `validate` | The spec fails validation |
| `stale_material` | A material's file changed since it was scanned |
| `unsupported_font` | A material can't be used (e.g. colour or CFF2 outlines) |
| `aat_unsupported_script` | A material is assigned a complex group it can't shape (WP-107) |
| `glyph_limit` | The result would exceed 65,535 glyphs |
| `prepare_failed` | Preparing a material failed |
| `merge_failed` | Merging the prepared fonts failed |
| `finish_failed` | Finishing the merged font failed |
| `verify_failed` | The built font failed verification |
| `io_error` | Reading or writing a file failed |
| `internal` | Anything else |

Exit codes:

| Exit code | Meaning |
|---|---|
| 0 | `result` sent |
| 2 | `bad_request` |
| 3 | any other `error` |
| 143 | terminated by SIGTERM (cancel); no terminal event |
| 130 | terminated by SIGINT; no terminal event |
| 141 | the client closed stdout (never observed by clients) |

The engine's `ForgeError` carries an optional `code` and `material_index`, which map straight into the `error` event.

## 6. Forged-font marker and names

- Every forged font starts name ID 0 with `Forged with Font Playground`. That is the original's `FORGED_NOTICE`: keep the exact string for compatibility with fonts forged by the Windows app.
- **PostScript name** (WP-109): ASCII `[A-Za-z0-9-]`, ≤ 63 characters. It is deterministic for the same `(family, style)`, and unique for different ones, including all-CJK names. It must never equal the PostScript name of a non-forged font in the catalog. The algorithm is in `engine-metadata.md`, and conformance fixtures lock it for Swift.
- **Versioning** (WP-109): name ID 3 (unique ID) changes on every forge. Name ID 5 changes for forges at least 1 s apart. `head.fontRevision` (Fixed 16.16) changes for forges at least 2 s apart, and never decreases.
- **Uniqueness by construction:** every forged PostScript name carries an `FP` + 8-hex-digit token, so it can never equal a non-forged font's name. The strict check against installed fonts, including other forged fonts, belongs to the installer's conflict check (WP-403/505). There is deliberately no `reserved_postscript_names` in `ForgeRequest`: that would make names depend on the catalog and break determinism across Updates.

## 7. Swift module boundaries and service protocols

The owning spec defines the exact signatures. The names and responsibilities here are fixed.

| Protocol | Module | Implemented by | Responsibility |
|---|---|---|---|
| `EngineRunning` | FPEngineClient | `EngineClient` | `hello()`, `scan(files:) -> AsyncThrowingStream<ScanEvent, Error>`, `forge(_:) -> AsyncThrowingStream<ForgeEvent, Error>`. Cancellation = cancelling the consuming `Task` |
| `FontCataloging` | FPMacServices | `CatalogStore` | `CatalogSnapshot` (visible `[FaceRecord]` + annotations + counts of hidden, duplicate, unreadable and disabled items), `currentSnapshot`, `refresh(.incremental｜.full)`, `setExtraFolders` (stores only; the caller refreshes), `noteInstalled`/`noteRemoved` (incremental update after the app's own install), `start/stopObservingSystemChanges`, change stream |
| `FontRendering` | FPMacServices | `FontRenderer` | **Synchronous, main-actor callable** (`CTFont` is not `Sendable`). A `CTFont` for a `FaceRenderRequest` (built from a `FaceRecord`: it needs the PostScript name, axes and weight class) or for a built file URL, at a size, with variations pinned (every non-`wght` axis at its fvar default, including `opsz`) and the LastResort cascade; coverage of a built file; glyph-presence checks |
| `FontInstalling` | FPMacServices | `FontInstaller` | `conflict(for:)` → `InstallConflict` (including `.noConflict`), `install(_:expecting:confirmed:)` (confirmed = the conflict the user accepted, re-checked to avoid races; `install(_:expecting:)` is kept as a convenience), `uninstall(_:)` → `UninstallOutcome`, `installedFonts()`. Fonts-folder URL and manifest URL are injectable |

`FPCore` defines value types only (`FaceRecord`, `FaceKey`, `ScriptGroup`, `Language`, `Recipe`, `ForgeSpec`/`ForgeRequest`/`ForgeReport` Codable types, `PortableFaceIdentity`, `RecipeDocument`). `FPAppUI.AppModel` composes the services (ADR-0006).

## 8. Files and folders

| What | Where | Format / owner |
|---|---|---|
| Last recipe (autosave) | `~/Library/Application Support/io.github.kciceblue.fontplayground/last.fontrecipe` | `RecipeDocument` v1 (core.md, WP-305) |
| Installed-fonts manifest | `…/Application Support/io.github.kciceblue.fontplayground/installed.json` | mac-services.md (WP-403) |
| Settings: `appearance`, `extraFolders`, `previewPointSize`, `colourByFont`, `lastSaveDirectory`, `legacyImportDone`, `inspectorPresented`, `showAllScriptGroups`, `donationOffered` (+ window frame) | `UserDefaults` (domain = bundle id) | values: core.md (WP-305 `AppSettings`); storage: ui-shell.md (WP-501) |
| Catalog cache | `~/Library/Caches/io.github.kciceblue.fontplayground/catalog-v<N>.json`; records the helper's `face_reader_version` and is discarded when it differs | mac-services.md (WP-401) |
| Install staging | `~/Library/Fonts/.<stem>.<32 hex>.fpinstall` (dot-files on the same volume, renamed into place) | mac-services.md (WP-403) |
| Build outputs before save or install | `…/Caches/io.github.kciceblue.fontplayground/builds/` | ui-shell.md (WP-505) |
| Helper temporary files | `…/Caches/io.github.kciceblue.fontplayground/tmp/` (the helper's `TMPDIR`; swept at launch) | helper.md |

`RecipeDocument` v1 (`.fontrecipe`, UTI `io.github.kciceblue.fontplayground.recipe`, conforms to `public.json`):

```json
{
  "format": "fontrecipe", "version": 1,
  "materials": [{"face": {"postscript_name": "…", "family": "…", "style": "…", "path": "…", "index": 0},
                 "weight": null, "scale": null}],
  "main": 0,
  "rules": {"han": 1},
  "defaults": {"weight": null, "scale": 1.0},
  "names": {"family": "…", "style": "…", "family_edited": false, "style_edited": false},
  "sample_text": "…"
}
```

Resolution order on load: `path+index` (the PostScript name must match), then `postscript_name`, then `family+style`. Unresolved materials stay in the recipe as **unavailable** (shown on their card with Replace…/Remove) and block forging until resolved (architecture §5).

`RecipeDocument` v1 has no output path. The save location is `AppSettings.lastSaveDirectory` plus `Recipe.suggestedFileName` (core.md WP-305).
