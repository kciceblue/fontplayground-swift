# Helper: protocol, `fpengine` CLI, conformance fixtures, embedded runtime, `FPEngineClient`, `fpctl`

> Scope: WP-201, WP-202, WP-203, WP-204, WP-205 · Env: linux (201, 202, 204, 205), macos (203) · Architecture refs: docs/architecture.md §2 (components), §3 (process model), §4 (data flow), §6 (layout), §7 (toolchain), §8 (cross-cutting rules) · ADRs: 0001, 0002, 0003, 0004, 0005, 0007 (scan feeds the catalog), 0008 (`aat_unsupported_script`), 0010, 0011 (planner parity fixtures), 0012 (licence report fields)

## Context

**What the original app did.** The forge ran in the GUI process on a `QThread` (`reference/fontplayground-py/fontplayground/ui/workers.py:39-77`). Cancel only set a flag, and the flag was checked in the progress callback, which `forge()` calls between stages (`workers.py:50-60`, `engine/forge.py:37-80`). Progress stages were free strings such as `"prepare:<display name>"` (`engine/forge.py:46`), and the UI turned them into plain words with `STAGE_TEXT` (`ui/model.py:50-63`). Results went to a temporary folder that was cleaned "if the cancel landed between finish and verify" (`ui/model.py:860-869`). The scanner kept failures as `(path, "Type: message")` pairs and went on (`catalog/scanner.py:31-57`). Faces were cached as `face_to_dict` with code points compressed to ranges (`catalog/cache.py:13-31`). `ForgeSpec.from_dict` silently dropped materials it could not find (`engine/spec.py:84-95`).

**What the audit found.**
- `NATIVE-3`: a Swift shell driving a Python helper over JSON Lines works end to end. Engine import costs 0.05–0.06 s warm.
- `NATIVE-7` and `ENGINE-9`: cancel waits for the next stage boundary (17.7 s observed), and a CJK forge peaks at 0.8–0.95 GB. A child process stops mid-prepare within 0.01 s of a signal. Verifier: run out of process, cancel with SIGTERM then SIGKILL, point `TMPDIR` at an app folder that is swept at launch.
- `NATIVE-M4`: a packaged app needs a real module entry point (`-m fpengine`).
- `TOOLING-M2`: editable installs silently produce an app without the package.
- `TOOLING-1`: every Mach-O must be signed, and ad-hoc signatures fail library validation under the hardened runtime.

**Evidence gathered for this spec** (macOS 27 / Apple silicon, 2026-09-29; non-normative):
- A SIGTERM handler that raises a `BaseException` subclass interrupted a pure-Python fontTools loop in **12 ms**. `TemporaryDirectory` and the per-run folder were removed and the exit code was 143.
- `python -I -B` with fontTools, subset, merge, instancer and pathops imports in 0.05–0.06 s warm.
- python-build-standalone `cpython-3.12.14+20260924` trimmed as in WP-203, plus fontTools 4.66, skia-pathops 0.9.2, unicodedata2 18.0 and unchecked-hash `.pyc`, measures **77 MB** after `lipo -thin arm64`, with 10 Mach-O files.
- Ad-hoc `codesign` of a stub app **fails** with the runtime under `Contents/Helpers/fpengine` ("bundle format unrecognized … In subcomponent: …/Contents/Helpers/fpengine/lib/python3.12"). The same runtime under `Contents/Resources/fpengine` signs inside-out, passes `codesign --verify --deep --strict` and runs. foundation-release.md WP-601 therefore puts the runtime in `Contents/Resources/fpengine` with a `Contents/Helpers/fpengine` symlink; ADR-0004 still names `Contents/Helpers` (backbone issue). WP-204 resolves both locations.
- Swift `JSONDecoder` with `.convertFromSnakeCase` **fails** on types whose `CodingKeys` are spelled in snake_case (see H10).
- `uv pip install --target` of a local wheel writes `direct_url.json`, which holds the absolute wheel path, and `uv_cache.json`, which holds a timestamp (WP-203 deletes both).
- The script-group table over all of Unicode is **824 runs**. As a generated Swift array it compiles in 0.3 s.

## Shared definitions

### H1. Names and locations

| Thing | Value |
|---|---|
| Helper command | `<python> -I -B -m fpengine <command>`, where `<command>` ∈ `hello`, `scan`, `forge` |
| Protocol version | `1` (`fpengine.protocol.PROTOCOL_VERSION`, `FPEngineClient.EngineClient.supportedProtocol`) |
| Schemas (normative) | `spec/protocol/*.schema.json`, draft 2020-12, overview in `spec/protocol/README.md` |
| Protocol examples | `spec/protocol/examples/` (WP-201 creates them; they are validated by pytest and decoded by Swift tests) |
| Dev helper | the `FP_ENGINE_PYTHON` environment variable (a Python that can `import fpengine`; `make` exports `engine/.venv/bin/python`) |
| Embedded helper | `<App>.app/Contents/Helpers/fpengine/bin/python3` (ADR-0004). foundation-release.md WP-601 places the runtime in `Contents/Resources/fpengine/` and makes `Contents/Helpers/fpengine` a symlink to `../Resources/fpengine`, because codesign rejects the runtime's non-code files in `Contents/Helpers` (see Context). WP-204 tries both paths, so either layout works |
| Built runtime | `build/helper/fpengine/{bin,lib}` plus `build/helper/fpengine-runtime.json` (WP-203) |
| Helper `TMPDIR` (app) | `~/Library/Caches/io.github.kciceblue.fontplayground/tmp/` (contracts.md §8). Tests pass a temporary folder |
| Conformance fixtures | `spec/fixtures/**` (generated by `tools/conformance/generate.py`) |
| Generated Swift table | `Packages/FontPlaygroundKit/Sources/FPCore/Generated/ScriptGroupTable.swift` |
| Synthetic fonts | `python -m fpengine.testing.make_fonts <dir>` (H11) |
| Example recipes | `examples/latin-cjk.fontrecipe` (macOS fonts), `examples/fixtures/latin-cjk.fontrecipe` (H11 fonts) |

### H2. Transport and framing (normative)

1. The client starts one process per request (ADR-0003). It writes **one** UTF-8 JSON object to stdin and closes stdin. For `hello` only, empty stdin means `{}`.
2. Each stdout line is one JSON object that validates against `event.schema.json`. It is encoded with `json.dumps(obj, ensure_ascii=False, separators=(",", ":"), allow_nan=False)`, then UTF-8, then one `\n`. The line is flushed immediately. There are no blank lines, no BOM and no other output.
3. The helper keeps the real stdout for events and points `sys.stdout` at `sys.stderr`, so a stray `print` from any library cannot corrupt the stream.
4. stderr carries human logs only. Clients must drain it concurrently, because a 64 KiB pipe buffer would otherwise block the helper, and must never parse it.
5. Integer fields accept JSON numbers with no fractional part (`700` or `700.0`), as JSON Schema `integer` does. Booleans are never accepted where a number is expected.
6. Output objects carry exactly the schema's keys. **Key order:** the order of the schema's `required` list, then any optional keys in the order of its `properties` (for `progress`: `protocol, type, stage, fraction, material_index, done, total`). Readers ignore unknown keys and unknown event types (contracts.md §2), and never depend on key order.
7. Paths in requests are echoed unchanged in events. The helper never normalises them; the `face.path` of a scanned face is the request string.

### H3. Events, ordering, terminal event and exit codes

| Command | Event sequence (non-terminal events in this order, then exactly one terminal event) |
|---|---|
| `hello` | `hello`, then `result{command:"hello"}` |
| `scan` | `progress{stage:"scan",done:0}` (only when total > 0). Then for each distinct path, in request order: its `face` events in face-index order, **or** exactly one `file_error`. Throttled `progress{stage:"scan"}` lines are interleaved. Then `progress{done:total}` (only when total > 0), then `result{command:"scan",summary}` |
| `forge` | `progress` for `validate`, `plan`, `prepare`×n (with `material_index` 0…n−1), `merge`, `finish`, `verify` and `done`, then `result{command:"forge",report}` |
| failure | the events so far, then `error{code,stage,material_index,message,detail}` |

| Exit code | Meaning | Terminal event |
|---|---|---|
| 0 | success | `result` |
| 2 | request rejected (`bad_request`, including an unknown or missing command) | `error` |
| 3 | any other error | `error` |
| 143 | cancelled by SIGTERM | none |
| 130 | cancelled by SIGINT (terminal Ctrl-C; not part of the client contract) | none |
| 141 | the client closed stdout (broken pipe; nobody is listening) | none |

`--help` and `--version` print to stdout and exit 0. They are not protocol runs.

### H4. Stages and fractions

| Stage | `fraction` | Emitted by | Notes |
|---|---|---|---|
| `validate` | 0.0 | CLI, before materials are read | new; the original had no validate event |
| `plan` | 0.0 | engine (`reference/.../engine/forge.py:37`) | |
| `prepare` | 0.05 + 0.6·i/n | engine (`forge.py:46`, `"prepare:<name>"`) | the CLI maps it to `stage:"prepare"` with `material_index: i` |
| `merge` | 0.7 | engine (`forge.py:54`) | |
| `finish` | 0.85 | engine (`forge.py:63`) | |
| `verify` | 0.95 | engine (`forge.py:77`) | |
| `done` | 1.0 | **CLI**, after the output file is in place | the engine's own `"done"` (`forge.py:80`) is swallowed |
| `scan` | done/total | CLI | `done` and `total` are always present |

Fractions are rounded to 4 decimals and never decrease within a run. Plain-language stage text belongs to the UI (WP-505) and to `fpctl` (WP-205), with the wording of `reference/.../ui/model.py:50-63`.

### H5. Error codes and file-error codes

`error.code` values are fixed by contracts.md §5. This table says which component produces each code in v1:

| Code | Produced when (v1) | `stage` | `material_index` |
|---|---|---|---|
| `bad_request` | malformed request, unknown or missing command, a material index out of range with no `expect`, output path that is a folder or equal to a material | null | null, or `i` when material `i` is at fault |
| `validate` | `ForgeSpec.validate()` fails (`reference/.../engine/spec.py:41-69`) | `validate` | null |
| `stale_material` | with `expect`: the file is gone, size or mtime differ (|Δmtime| > 1e-3 s), the face index is gone, or the PostScript name differs | `validate` | i |
| `unsupported_font` | the material cannot be parsed as a font, or `face.supported` is false | `validate` | i |
| `aat_unsupported_script` | raised by the engine (WP-107) with `ForgeError.code` | as raised | as raised |
| `glyph_limit` | more than 65,535 glyphs (merge or verify; WP-201 tags both raise sites) | `merge` or `verify` | null |
| `prepare_failed` | `ForgeError(stage="prepare")` without a code | `prepare` | the material being prepared |
| `merge_failed` / `finish_failed` / `verify_failed` | `ForgeError` of that stage without a code | same | null |
| `io_error` | cannot read a material (no `expect`), cannot create the output folder, the rename fails, or a `finish` error caused by an `OSError`. A failed folder fsync **after** a successful rename is not an error: the rename is the commit point, so the result is sent with the report-level warning issue `output_sync_failed` | stage at failure | i or null |
| `internal` | any other exception (traceback in `detail`) | last stage emitted | null |

`file_error.code` (scan only; defined here, since contracts.md leaves it open):

| Code | When | `message` (exact format) |
|---|---|---|
| `not_found` | `FileNotFoundError` from `os.stat` | `File not found.` |
| `io_error` | any other `OSError`, or the path is not a regular file | `Can't read this file ({strerror}).` / `Not a regular file.` |
| `unreadable` | the reader raised a non-`OSError` exception | `Not a font file fontTools can read ({Type}: {msg}).` |
| `internal` | reserved for failures outside the reader (the serialiser raised) | `Unexpected error while reading this file ({Type}: {msg}).` |

### H6. Cancellation and cleanup (both sides)

1. The client sends **SIGTERM** (ADR-0003). If the helper has not exited after `terminationGrace` (2 s), the client sends **SIGKILL**.
2. The helper's SIGTERM handler raises `fpengine.protocol.cancel.Cancelled`, a **`BaseException`** subclass. It interrupts Python at the next bytecode boundary, even in the middle of a stage. It is never swallowed by the engine's `except Exception` blocks (`reference/.../engine/forge.py:52`, `prepare.py:145`). A running C call, such as one skia-pathops operation on one glyph, finishes first.
3. While unwinding, every `with`/`finally` runs. The engine's `TemporaryDirectory` goes (`forge.py:41`). The CLI removes its per-run folder and any partial output (H7). Then the helper exits 143 with **no terminal event**.
4. **Critical sections** (`cancel.critical()`): writing and flushing one event line, and the final "rename output → emit `done` → emit `result`" block. A signal that arrives inside one is recorded and acted on when the section ends. Once the terminal event is written, later signals are ignored and the exit code is the terminal event's. A second SIGTERM during cleanup is ignored.
5. **Orphan watchdog:** a daemon thread polls `os.getppid()` every 1.0 s. If the parent changes (the client died), the helper logs `parent process exited; cancelling` and sends itself SIGTERM.
6. The client treats a consumer-side cancel as a normal end of the stream, not an error (WP-204). After a SIGKILL, the client removes the leftovers that the helper could not remove (H7).

### H7. Temporary files, partial outputs and the sweep

| Item | Name | Created by | Removed by |
|---|---|---|---|
| Per-run folder | `$TMPDIR/fpengine-<pid>-<random>` (`tempfile.mkdtemp(prefix=f"fpengine-{pid}-")`); `tempfile.tempdir` points at it for the run, so the engine's own temporary folders land inside | `forge` | the helper on every exit path; the client after SIGKILL; the app-launch sweep |
| Partial output | `<dir of output_path>/.fpengine-<pid>-<8 hex>.partial.ttf` | `forge` | the helper (rename on success, unlink otherwise); the client after SIGKILL |
| Output | `output_path`: appears only through `os.replace` after fsync, immediately before `done`/`result` | `forge` | the caller (the app's `builds/` folder is owned by WP-505) |

- If `TMPDIR` is set but missing, the helper creates it (`os.makedirs(exist_ok=True)`). If that fails, it logs a warning and uses Python's default.
- **`EngineClient.sweepLeftovers`** (WP-204) is the pid-based sweep of helper leftovers. It removes entries in the temporary folder named `fpengine-<pid>-*` whose process no longer exists (`kill(pid, 0)` fails with `ESRCH`) or that were last modified more than 24 h ago. It removes `.fpengine-<pid>-*.partial.ttf` files in the given output folders by the same rule. It never touches other names.
- **Callers.** At app launch, WP-501 (ui-shell.md D4 step 1) calls `EngineClient.sweepLeftovers(temporaryDirectory: <caches>/tmp, outputDirectories: [<caches>/builds])`; its own `CacheSweeper` separately deletes `forged-*.ttf` files in `builds/` older than 10 minutes. `fpctl` (WP-205), the self-test (WP-601) and tests call `sweepLeftovers` on their own folders.

### H8. Engine API this spec consumes

The layout is WP-002's (foundation-release.md: reference `engine/*.py` → `fpengine/*.py`, `catalog/face.py` → `fpengine/face.py`, `catalog/cache.py` helpers → `fpengine/records.py`), plus the modules engine-metadata.md adds. If a symbol ended up elsewhere, import it from there; do not add aliases.

| Symbol | Module | Reference | Owner / notes |
|---|---|---|---|
| `ForgeSpec`, `MaterialSpec`, `ForgeReport`, `MaterialReport` | `fpengine.spec` | `engine/spec.py` | `ForgeReport` gains `family_name`, `style_name`, `postscript_name`, `full_name` (109), `issues: list[Issue]` (landed by WP-101, engine-correctness.md Shared definitions 3), `fs_type` (110) and `licence_notes: list[LicenceNote]` (110), all with defaults (engine-metadata.md §S5) |
| `ForgeError(stage, material, message, *, code=None, material_index=None)` | `fpengine.spec` | `engine/spec.py:9-13` | keyword fields per engine-metadata.md §S5. WP-201 adds them only if no earlier WP has |
| `Issue` (with `to_dict()`), `LicenceNote` (`licence_class` is serialised as `"class"`) | `fpengine.spec` | — | `Issue`: WP-101 (engine-correctness.md Shared definitions 3, the same type as engine-metadata.md §S5). `LicenceNote`: WP-110 (engine-metadata.md §S5) |
| `forge(spec, output_path, progress)` | `fpengine.forge` | `engine/forge.py:32` | WP-201 adds `code="glyph_limit"` at the `forge.py:60-62` raise |
| `MAX_GLYPHS`, `verify` | `fpengine.merge` | `engine/merge.py:17,129` | WP-201 adds `code="glyph_limit"` at the `merge.py:138-139` raise |
| `source_of`, `plan` | `fpengine.planner` | `engine/planner.py:10,19` | — |
| `GROUPS`, `GROUP_IDS`, `LABELS`, `group_of`, `groups_covered` | `fpengine.scripts` | `engine/scripts.py` | — |
| `FontFace`, `read_faces(path)`, `READER_VERSION` | `fpengine.face` | `catalog/face.py:18,200` | fields from 106–110; WP-201 adds `read_face(path, index)` |
| `face_record(face)`, `FACE_RECORD_KEYS`, `ranges`, `expand` | `fpengine.records` | `catalog/cache.py:13-31` | `face_record` from WP-106: the contracts §3 keys + `unshaped`, with final types from the start |
| `postscript_name(family, style)`, `FORGED_NOTICE` | `fpengine.naming` | `engine/merge.py:32,47` | WP-109 (FNV-1a based; `merge` re-exports both) |
| `fixture_payload()`, `python -m fpengine.shaping write-fixture` | `fpengine.shaping` | — | WP-107 |

### H9. Interim values (report fields whose producer may land after WP-201)

Face fields need no interim values. WP-106 (a dependency of WP-201) makes `fpengine.records.face_record` emit every contract key with its final type, using placeholders until WP-107/109/110 fill them (engine-metadata.md §S2).

`ForgeReport` fields come from WP-101 (`issues`) and WP-109/110 (names, `fs_type`, `licence_notes`). WP-110 lands in wave 4, possibly after WP-201, and WP-101 is not a declared dependency of WP-201. So:
- The names and `fs_type` in the protocol report are **always read back from the built file** (Design §9 of WP-201). They are "the names actually written" whatever the engine version.
- `issues` and `licence_notes` are read from the engine report. **Only when the attribute is absent** does the serialiser use the value in `fpengine.protocol.report.INTERIM_REPORT_FIELDS = {"issues": [], "licence_notes": []}`.

The owning WP (101 for `issues`, 110 for `licence_notes`) deletes its key when it adds the attribute; if the attribute already exists when WP-201 is implemented, WP-201 leaves that key out. WP-111 (M1 exit) asserts the table is empty (engine-correctness.md AC-111-11). No other field may be defaulted.

### H10. Swift wire-type coding rule (normative for FPCore and FPEngineClient)

All protocol and file types decode with a **plain `JSONDecoder()`** (default `keyDecodingStrategy`) and encode with a `JSONEncoder()` whose `keyEncodingStrategy` is the default and whose `outputFormatting` contains `.withoutEscapingSlashes` (`.sortedKeys` may be added, as core.md's `ForgeRequest.encodedJSON()` does). Every wire type declares **explicit snake_case `CodingKeys`** (for example `case fullName = "full_name"`, `case licenceClass = "class"`, `case protocolVersion = "protocol"`).

Why: mixing `.convertFromSnakeCase` with snake_case `CodingKeys` fails with `keyNotFound` (verified). Keys of `[String: X]` maps (`group_counts`, `script_rules`) are data and must stay untouched.

Doubles survive the round trip exactly (Python `repr` ↔ Swift `Double`).

### H11. Synthetic fixture fonts (`python -m fpengine.testing.make_fonts <dir>`)

These are deterministic bytes: `head.created` and `head.modified` are fixed at 3 900 000 000 (seconds since 1904) and `recalcTimestamp = False`. Every glyph is a rectangle, as in `reference/.../tests/fixtures.py:31-95`. Family names start with "Fixture", so they never collide with real fonts. They are never committed; tests generate them.

| File | Face(s): family / style / PostScript | Outline, upem | Coverage (inclusive) | Special |
|---|---|---|---|---|
| `FixtureSans-Regular.ttf` | Fixture Sans / Regular / `FixtureSans-Regular` | glyf, 1000 | U+0020–007E, U+00A0–00FF, U+0391–03A1, U+03A3–03A9, U+03B1–03C9 (240) | weight 400 |
| `FixtureSans-Bold.ttf` | Fixture Sans / Bold / `FixtureSans-Bold` | glyf, 1000 | same (240) | weight 700 |
| `FixtureCJK-Regular.otf` | Fixture CJK / Regular / `FixtureCJK-Regular` | CFF, 1000 | U+0020–007E, U+3000–303F, U+3041–3096, U+30A1–30FA, U+4E00–59FF, U+FF01–FF5E, plus 这说门来 (U+8FD9, U+8BF4, U+95E8, U+6765) (3,505) | covers Chinese (Simplified) and Japanese per `ui/languages.py:111-115` |
| `FixtureHangul-Regular.ttf` | Fixture Hangul / Regular / `FixtureHangul-Regular` | glyf, **2048** | U+0030–0039, U+AC00–B3FF (2,058) | exercises upem scaling |
| `FixtureSerif.ttc` | 0: Fixture Serif / Regular / `FixtureSerif-Regular`; 1: Fixture Serif / Italic / `FixtureSerif-Italic` | glyf, 1000 | U+0020–007E each | face 1: fsSelection bit 0, macStyle bit 1 |
| `FixtureVariable-Regular.ttf` | Fixture Variable / Regular / `FixtureVariable-Regular` | glyf + `fvar` wght 100–400–900 | U+0020–007E | `gvar` as `tests/fixtures.py:89-93` |
| `FixtureColor-Regular.ttf` | Fixture Color / Regular / `FixtureColor-Regular` | glyf + `COLR`/`CPAL` | U+0041–005A | unsupported ("colour fonts are not supported") |
| `FixtureRestricted-Regular.ttf` | Fixture Restricted / Regular / `FixtureRestricted-Regular` | glyf | U+0061–007A | fsType 0x0002 |
| `NotAFont.ttf` | — | — | — | 75 bytes of text; scan gives `file_error` `unreadable` |

`fonts.json` (the manifest, written last):

```json
{"generator": "fpengine.testing.make_fonts", "version": 1, "fpengine_version": "0.1.0",
 "fonts": [{"file": "FixtureSans-Regular.ttf", "expect": "faces",
            "faces": [{"index": 0, "family": "Fixture Sans", "style": "Regular", "postscript_name": "FixtureSans-Regular",
                       "weight_class": 400, "italic": false, "outline": "glyf", "upem": 1000,
                       "coverage": [[32, 126], [160, 255], [913, 929], [931, 937], [945, 969]], "supported": true}]},
           {"file": "NotAFont.ttf", "expect": "file_error:unreadable", "faces": []}]}
```

Reference forge of Sans + CJK + Hangul with rules `{han,kana,cjk_symbols → 1}` on the audit Mac: 0.29 s, 5,698 characters. Sans + CJK alone: **3,650 characters (240 + 3,410)**.

---

## WP-201: Protocol v1 (JSON Schemas) + `python -m fpengine` (`hello`, `scan`, `forge`)

**Goal:** Implement the v1 helper, `python -m fpengine hello|scan|forge`, exactly as `spec/protocol/*.schema.json` and H2–H9 describe. Cancel must be prompt and clean, output atomic, and every emitted event validated by protocol tests.
**Depends on:** WP-002, WP-106 · **Env:** linux · **Size:** M · **Closes findings:** NATIVE-3, NATIVE-7, ENGINE-9

### Scope
- In: the CLI entry point and dispatch; request parsing; event writer; SIGTERM/SIGINT handling and critical sections; orphan watchdog; `hello`, `scan`, `forge`; `stale_material` checks; atomic output; the `face` payload wrapper and the ForgeReport serialiser (with the H9 interim values); error mapping; stderr logging; `read_face`; `ForgeError.code`/`material_index`; glyph-limit tagging; `spec/protocol/examples/`; protocol tests. The schemas in `spec/protocol/` already exist and are normative. WP-201 changes them only to fix a defect found while implementing, and must record it as a spec deviation.
- Out:
  - computing face metadata (WP-106…110)
  - the Swift client (WP-204)
  - the runtime bundle (WP-203)
  - fixtures and `make_fonts` (WP-202)
  - calling the sweep at app launch (WP-501)
  - catalog batching (WP-401)
  - HarfBuzz subsetting (backlog B-6)

### Touched paths
- `engine/src/fpengine/__main__.py` (new)
- `engine/src/fpengine/cli.py` (new)
- `engine/src/fpengine/protocol/__init__.py`, `events.py`, `errors.py`, `cancel.py`, `requests.py`, `records.py`, `report.py`, `rundir.py`, `watchdog.py` (new)
- `engine/src/fpengine/commands/__init__.py`, `hello.py`, `scan.py`, `forge.py` (new)
- `engine/src/fpengine/spec.py` (edit, only if still missing: `ForgeError` keywords)
- `engine/src/fpengine/forge.py` (edit: glyph-limit code)
- `engine/src/fpengine/merge.py` (edit: glyph-limit code)
- `engine/src/fpengine/face.py` (edit: add `read_face`)
- `engine/tests/protocol/__init__.py` (new, empty: `engine/tests` is a package, and `tests/protocol/test_forge.py` must not clash with WP-002's `tests/test_forge.py`)
- `engine/tests/protocol/conftest.py`, `test_schemas.py`, `test_hello.py`, `test_scan.py`, `test_forge.py`, `test_cancel.py`, `test_errors.py` (new)
- `engine/tests/protocol/drivers/slow_forge.py`, `slow_scan.py`, `pause_after_result.py`, `orphan_parent.py` (new; plain scripts, no `__init__.py`, never collected by pytest)
- `spec/protocol/examples/hello-request.json`, `scan-request.json`, `forge-request.json`, `hello.jsonl`, `scan.jsonl`, `forge-ok.jsonl`, `forge-error.jsonl` (new)

### Design

**1. Module layout**

| Module | Responsibility | Key API |
|---|---|---|
| `fpengine/__main__.py` | Entry. Imports only `fpengine.cli` (stdlib-only at import time). A `KeyboardInterrupt` during that import exits 130 | `try: from fpengine.cli import main` / `except KeyboardInterrupt: raise SystemExit(130)`; then `raise SystemExit(main())` |
| `fpengine/cli.py` | Install signals first, isolate stdout, set up logging, parse argv, read stdin, dispatch, map exceptions to events and exit codes, restore global state | `def main(argv: list[str] \| None = None, *, stdin: BinaryIO \| None = None, stdout: BinaryIO \| None = None) -> int` |
| `protocol/__init__.py` | Constants | `PROTOCOL_VERSION = 1`; `CAPABILITIES = ("hello", "scan", "forge", "forge.expect")`; `MAX_REQUEST_BYTES = 64 * 1024 * 1024` |
| `protocol/events.py` | Serialise and write events | `class EventWriter` (below) |
| `protocol/errors.py` | Codes, exit codes, helper error, forge-error mapping | `class ErrorCode(StrEnum)`, `class FileErrorCode(StrEnum)`, `class Stage(StrEnum)`, `EXIT_OK=0, EXIT_BAD_REQUEST=2, EXIT_ERROR=3, EXIT_SIGINT=130, EXIT_CLIENT_GONE=141, EXIT_SIGTERM=143`, `class HelperError(Exception)` with `__init__(self, code: ErrorCode, stage: Stage \| None, material_index: int \| None, message: str, detail: str \| None = None)` (attributes of the same names), `def map_forge_error(err: ForgeError, progress: ForgeProgress, faces: Sequence[FontFace]) -> HelperError` |
| `protocol/cancel.py` | Signal state, handlers, critical sections | `class Cancelled(BaseException)`, `class ClientGone(Cancelled)`, `def install() -> Callable[[], None]`, `def critical() -> ContextManager[None]`, `def checkpoint() -> None`, `def mark_terminal_sent() -> None` |
| `protocol/requests.py` | Typed request parsing that agrees with the request schemas | `parse_hello`, `parse_scan`, `parse_forge`, dataclasses below, `class RequestError(Exception)` |
| `protocol/records.py` | `FontFace` → `face` event payload | `def face_payload(face: FontFace, request_path: str) -> dict` (wraps `fpengine.records.face_record`) |
| `protocol/report.py` | Engine `ForgeReport` → schema dict; read the names back | `INTERIM_REPORT_FIELDS`, `@dataclass OutputNames`, `def read_output_names(path: str) -> OutputNames`, `def forge_report(...) -> dict` |
| `protocol/rundir.py` | Per-run folder and partial path (H7) | `def open_run_dir() -> Path`: `base = os.environ.get("TMPDIR")` (created if missing, H7; if unset or not creatable, `tempfile.gettempdir()`), `tempfile.mkdtemp(prefix=f"fpengine-{os.getpid()}-", dir=base)`, remember the old `tempfile.tempdir` and set `tempfile.tempdir` to the new folder. `def close_run_dir(path: Path) -> None`: restore `tempfile.tempdir`, then `shutil.rmtree(path, ignore_errors=True)`. `def partial_path(output_path: str) -> str`: `os.path.join(dirname(output_path), f".fpengine-{os.getpid()}-{secrets.token_hex(4)}.partial.ttf")` |
| `protocol/watchdog.py` | Orphan watchdog | `def start_parent_watchdog(interval_s: float = 1.0) -> None` |
| `commands/hello.py` | `hello` | `def run(req: HelloRequest, out: EventWriter) -> int` |
| `commands/scan.py` | `scan` | `def run(req: ScanRequest, out: EventWriter) -> int` |
| `commands/forge.py` | `forge` | `def run(req: ForgeRequestData, out: EventWriter) -> int`; `class ForgeProgress` |

**2. Startup sequence (`cli.main`)**
1. `restore = cancel.install()`. This sets SIGTERM and SIGINT handlers before anything heavy is imported. It is the first statement inside the `try` whose `except cancel.Cancelled`/`finally` handle the exit, so a signal during steps 2–3 still exits 143/130 and restores everything. `install()` holds a signal that arrives while the handlers are being installed, and `cancel.checkpoint()` after step 3 acts on it. (`test_sigterm_during_startup_exits_143_and_restores`)
2. `out_stream = stdout or sys.stdout.buffer`. Save `sys.stdout` and set `sys.stdout = sys.stderr` (H2.3). Call `sys.stderr.reconfigure(encoding="utf-8", errors="backslashreplace")` when possible.
3. `configure_logging()` (Design §11).
4. `watchdog.start_parent_watchdog()`. It is skipped when `stdin`/`stdout` are injected, as in in-process tests.
5. Parse argv:
   - `[]` → `RequestError("No command given. Use hello, scan or forge.")`.
   - `["-h"|"--help"]` → usage to `out_stream`, return 0.
   - `["--version"]` → `fpengine <version>`, return 0.
   - `[cmd]` with `cmd ∈ {hello, scan, forge}` → go on.
   - Any other `[cmd]` → `RequestError(f"Unknown command '{cmd}'. Use hello, scan or forge.")`.
   - Extra arguments → `RequestError("Unexpected arguments: …")`.
6. Read stdin (`allow_empty` only for `hello`), parse (Design §3) and run the command (§6–§8). Map exceptions as in the table in §12.
7. `finally`: restore the signal handlers, `sys.stdout` and logging, so in-process tests stay isolated. Return the exit code.

**3. Requests (`protocol/requests.py`)**

```python
@dataclass(frozen=True)
class HelloRequest: ...
@dataclass(frozen=True)
class ScanRequest:
    files: tuple[str, ...]
@dataclass(frozen=True)
class Expect:
    postscript_name: str | None
    size: int
    mtime: float
@dataclass(frozen=True)
class MaterialRequest:
    path: str
    index: int
    weight: int | None = None
    scale: float | None = None
    expect: Expect | None = None
@dataclass(frozen=True)
class ForgeRequestData:
    materials: tuple[MaterialRequest, ...]
    base_index: int = 0
    script_rules: Mapping[str, int | None] = field(default_factory=dict)
    default_weight: int | None = None
    default_scale: float = 1.0
    family_name: str = "Forged"
    style_name: str = "Regular"
    output_path: str = ""
def read_request(stream: BinaryIO, *, allow_empty: bool) -> dict: ...
def parse_hello(obj: dict) -> HelloRequest: ...
def parse_scan(obj: dict) -> ScanRequest: ...
def parse_forge(obj: dict) -> ForgeRequestData: ...
```

Rules. Each failure raises `RequestError`, which becomes `bad_request`.
- Read at most `MAX_REQUEST_BYTES + 1` bytes. More → `Request is too large (over 64 MiB).`. Decode UTF-8 strictly; failure → `Request is not UTF-8.`.
- `json.loads(text, parse_constant=_reject)` rejects `NaN`/`Infinity`: `_reject` raises `RequestError("Request is not valid JSON: NaN and Infinity are not allowed.")`. Other `json.JSONDecodeError`s → `Request is not valid JSON: {e.msg} (line {e.lineno}, column {e.colno}).`. A non-object → `Request must be a JSON object.`.
- Field problems produce `Invalid request: {pointer}: {problem}.` with a dotted pointer such as `spec.materials[1].path` (the first problem found, in document order). The problem strings are:
  - `is required`
  - `must be an integer` (also for a non-integral float and for a boolean)
  - `must be a non-negative integer` (`index`, `expect.size`)
  - `must be a number`
  - `must be a string`
  - `must be an absolute path` (does not start with `/`, or is exactly `/`; this matches `abs_path`'s `pattern` and `minLength: 2`)
  - `must not contain '..'` (a whole `..` path segment, the regex `(^|/)\.\.(/|$)`; `/a/b..c.ttf` is fine)
  - `must be a list`
  - `must have at most 100000 items` (`files`)
  - `must be an object`
  - `is not a script group`
  - `contains an invalid Unicode escape` (a lone surrogate; check with `s.encode("utf-8")`)
- Integers accept integral floats (`700.0` becomes `700`). Booleans are rejected everywhere a number is expected. `null` is accepted exactly where the request schema allows it (`weight`, `scale`, `default_weight`, rule values, `expect.postscript_name`); elsewhere it is a type error. Unknown keys are ignored and logged at DEBUG.
- `script_rules` keys must be in `GROUP_IDS`. Values are an integer (any value; range checks are `validate`'s) or `null`.
- A parser test runs the same good and bad cases through both `parse_*` and `jsonschema` and asserts they agree (AC-201-12).

**4. `EventWriter` (`protocol/events.py`)**

```python
class EventWriter:
    def __init__(self, stream: BinaryIO) -> None: ...
    def emit(self, type_: str, **payload: object) -> None:
        """{"protocol": 1, "type": type_, **payload}: one line, flushed, inside cancel.critical()."""
    def terminal(self, type_: Literal["result", "error"], **payload: object) -> None:
        """emit() + cancel.mark_terminal_sent() in the same critical section. A second call raises RuntimeError."""
    @property
    def terminal_sent(self) -> bool: ...
    @property
    def last_stage(self) -> str | None:
        """Stage of the last progress event written (None before any). Top-level internal errors use it."""
```

- On `BrokenPipeError` or `ValueError: I/O operation on closed file`, raise `cancel.ClientGone`.
- Before exiting 141, the CLI runs `os.dup2(os.open(os.devnull, os.O_WRONLY), fd)` on the stdout fd, so interpreter shutdown prints no "Exception ignored" message.
- If `json.dumps` fails (a bug), log it and emit an `internal` error in its place. An error that fails to serialise is replaced by the fixed line `{"protocol":1,"type":"error","code":"internal","stage":null,"material_index":null,"message":"Unexpected error while reporting an error.","detail":null}`.

**5. Cancellation (`protocol/cancel.py`)**, implementing H6

```python
class Cancelled(BaseException):
    def __init__(self, signum: int) -> None: ...
class ClientGone(Cancelled): ...
_state = SimpleNamespace(critical=0, pending=None, terminal_sent=False, cancelling=False)
def _handler(signum: int, frame) -> None:
    if _state.terminal_sent or _state.cancelling:
        return                               # already done, or already unwinding: ignore
    if _state.critical:
        _state.pending = signum; return      # act when the critical section ends
    _state.cancelling = True
    raise Cancelled(signum)
@contextmanager
def critical():  # re-entrant
    _state.critical += 1
    try:
        yield
    finally:
        _state.critical -= 1
        if not _state.critical and _state.pending is not None and not _state.terminal_sent:
            signum, _state.pending = _state.pending, None
            _state.cancelling = True
            raise Cancelled(signum)
def checkpoint() -> None: ...   # raises Cancelled if a signal is pending (explicit checkpoints in loops)
```

`install()` resets `_state` and registers `_handler` for SIGTERM and SIGINT. It returns a function that restores the previous handlers.

**6. `hello`**

It emits one `hello` event, then `result{command:"hello"}`, and returns 0. The fields are:
- `fpengine_version`: `importlib.metadata.version("fpengine")`, falling back to `fpengine.__version__`.
- `python`: `platform.python_version()`.
- `fonttools`: `fontTools.version`.
- `unicode_version`: `unicodedata2.unidata_version` when importable, else `unicodedata.unidata_version`.
- `platform`: `f"{sys.platform}-{platform.machine()}"`.
- `capabilities`: `list(CAPABILITIES)`.
- `face_reader_version`: `fpengine.face.READER_VERSION` (engine-metadata.md §S3). The catalog (WP-401) keys its cache on it.

`hello` imports `fpengine.face`, but not the forge modules.

**7. `scan` (`commands/scan.py`)**

```
seen = set(); files = [p for p in req.files if not (p in seen or seen.add(p))]; duplicates = len(req.files) - len(files)
n = len(files); faces_sent = errors = 0
if files: emit progress(scan, 0.0, done=0, total=n); last = monotonic()
for k, path in enumerate(files, 1):
    cancel.checkpoint()
    faces = None
    try:
        st = os.stat(path)                                  # follows symlinks
        if not stat.S_ISREG(st.st_mode): raise _NotRegular
        faces = read_faces(path)                            # WP-106 reader
    except Cancelled: raise
    except _NotRegular: file_error(io_error, "Not a regular file.")
    except FileNotFoundError: file_error(not_found, "File not found.")
    except OSError as e: file_error(io_error, f"Can't read this file ({e.strerror or e}).")
    except Exception as e: file_error(unreadable, f"Not a font file fontTools can read ({type(e).__name__}: {e}).")
    else:
        try: records = [face_payload(f, request_path=path) for f in faces]  # all faces of the file, or none
        except Cancelled: raise
        except Exception as e: file_error(internal, f"Unexpected error while reading this file ({type(e).__name__}: {e}).")
        else:
            for r in records: emit face(r); faces_sent += 1
    faces = records = None                                  # never keep FontFace objects across files
    if k == n or monotonic() - last >= 0.25: emit progress(scan, round(k/n, 4), done=k, total=n); last = monotonic()
terminal result(command="scan", summary={"files": n, "faces": faces_sent, "file_errors": errors, "duplicates": duplicates})
# file_error(code, message) = emit file_error{path, code, message}; errors += 1
```

- A file's faces are all serialised before its first `face` event. If serialising any face raises, the file gets **one** `file_error` `internal` and none of its faces are sent.
- Never keep `FontFace` objects beyond the file that produced them. The ENGINE-9 verifier measured more than 1 GB retained by an in-process full scan.
- Output order is deterministic: the same request on the same files gives byte-identical `face`, `file_error` and `result` lines.
- Recommendation for WP-401 (non-normative): at most 500 files per request. After a crash, the first requested file with neither `face` nor `file_error` is the culprit.

**8. `forge` (`commands/forge.py`)**

```
started = monotonic(); out.emit progress(validate, 0.0)
_check_output(req)                     # -> bad_request, stage null:
                                       #   existing directory: "Invalid request: output_path: is a folder."
                                       #   equal to a material (string equality, or os.path.samefile when both exist):
                                       #   "The output file is one of the materials: {path}."
os.makedirs(dirname(output), exist_ok=True)  # OSError -> io_error(validate) "Can't write {dir} ({strerror})."
faces = [_load_material(i, m) for i, m in enumerate(req.materials)]
spec = ForgeSpec(materials=[MaterialSpec(f, m.weight, m.scale) ...], base_index=..., script_rules=dict(...),
                 default_weight=..., default_scale=..., family_name=..., style_name=...)
if problems := spec.validate(): raise HelperError(validate, "validate", None, " ".join(problems))
run_dir = open_run_dir(); partial = partial_path(req.output_path); progress = ForgeProgress(out, len(faces))
try:
    try: engine_report = forge(spec, partial, progress=progress)
    except ForgeError as e: raise map_forge_error(e, progress, faces) from e
    _fsync(partial); names = read_output_names(partial)
    report = forge_report(req, engine_report, names, duration_s=round(monotonic() - started, 3))
    with cancel.critical():
        os.replace(partial, req.output_path)  # OSError -> io_error(verify)
        _fsync_dir(dirname(output))  # OSError -> append warning issue output_sync_failed (report-level) and continue
        out.emit progress(done, 1.0); out.terminal("result", command="forge", report=report)
finally:
    remove partial if it still exists; close_run_dir(run_dir)
```

`_load_material(i, m)`, checked in this order. Messages are exact; `{path}` is `m.path`.

| Check | Condition | Code | Message |
|---|---|---|---|
| 1 | `os.stat` raises `FileNotFoundError` | `stale_material` if `m.expect` else `io_error` | `{path}: the font file is no longer there.` (wording of `ui/model.py:46-47`) |
| 2 | other `OSError` | `io_error` | `Can't read {path} ({strerror}).` |
| 3 | `expect` and `st_size != expect.size` | `stale_material` | `{path} changed since it was scanned (size {old} → {new}).` |
| 4 | `expect` and `abs(st_mtime - expect.mtime) > 1e-3` | `stale_material` | `{path} changed since it was scanned (modified {old:.3f} → {new:.3f}).` |
| 5 | `read_face` raises `IndexError` | `stale_material` if `expect` else `bad_request` | `{path} has no face {index} any more.` / `Invalid request: spec.materials[{i}].index: {path} has {n} faces.` |
| 6a | `read_face` raises `OSError` (for example a permission error while opening) | `io_error` | `Can't read {path} ({strerror}).` |
| 6b | `read_face` raises any other exception | `unsupported_font` | `{path} can't be read as a font ({Type}: {msg}).` |
| 7 | `expect` and `face.postscript_name != expect.postscript_name` | `stale_material` | `{path} face {index} is now '{new}', not '{old}'.` |
| 8 | `not face.supported` | `unsupported_font` | `{display_name}: {unsupported_reason}` (format of `engine/spec.py:50`) |

`material_index` is `i` for all of them. `stage` is `validate`, except for `bad_request`, which always has `stage: null` (H5).

`read_face(path: str, index: int) -> FontFace` goes in `fpengine/face.py`. It returns what `read_faces(path)[index]` returns, but opens only that face: `TTCollection(path, lazy=True).fonts[index]` for `.ttc`/`.otc`, else `TTFont(path, lazy=True)`, raising `IndexError` unless `index == 0`. It uses the same internal `_face` builder and closes the file in `finally`.

`ForgeProgress.__call__(engine_stage: str, fraction: float)` implements H4:
- It calls `cancel.checkpoint()` first.
- `"plan"`, `"merge"`, `"finish"` and `"verify"` are emitted as they are.
- `engine_stage.startswith("prepare")` → `material_index = self._next_prepare`, then increments. If that ever reaches `n`, it logs a warning and clamps to `n-1`.
- `"done"` is recorded, not emitted.
- Anything else is logged at DEBUG and not emitted.
- It keeps `self.stage` (the last protocol stage emitted, initially `"validate"`) and `self.material_index` (set during prepare, `None` otherwise).

`map_forge_error(err, progress, faces) -> HelperError`:

| Rule (first match) | code | stage | material_index |
|---|---|---|---|
| `getattr(err, "code", None)` in `ErrorCode` | that code | `err.stage` if it is an error stage, else `progress.stage` | see below |
| `err.stage == "validate"` | `validate` | `validate` | see below |
| `err.stage == "prepare"` | `prepare_failed` | `prepare` | see below |
| `err.stage == "merge"` | `merge_failed` | `merge` | null |
| `err.stage == "finish"` and `isinstance(err.__cause__, OSError)` | `io_error` | `finish` | null |
| `err.stage == "finish"` | `finish_failed` | `finish` | null |
| `err.stage == "verify"` | `verify_failed` | `verify` | null |
| otherwise | `internal` | `progress.stage` | null |

`material_index` comes from the first of these that applies:
1. `getattr(err, "material_index", None)`.
2. When the stage is `prepare`, `progress.material_index`.
3. The single `i` with `faces[i].display_name == err.material`, if exactly one matches.
4. Otherwise `None`.

`message = err.message`. `detail = "".join(traceback.format_exception(err))`.

The glyph limit: the two raises ported from reference `engine/forge.py:60-62` (the `M.MAX_GLYPHS` check after merging) and `engine/merge.py:138-139` (inside `verify`) pass `code="glyph_limit"`. Find them by their messages in `fpengine/forge.py` and `fpengine/merge.py`; line numbers will have moved after the WP-1xx edits. The ForgeError edit is a keyword-only addition, so every existing call stays valid.

Cancellation safety: `Cancelled` passes through the engine because neither `fpengine` nor fontTools 4.66's `subset`, `merge`, `varLib.instancer`, `ttLib.ttFont` and `glyf` code has a bare `except:` or `except BaseException` (checked). Do not add one.

**9. Report (`protocol/report.py`)**

- `OutputNames` has `family` (name ID 16, else 1), `style` (17, else 2), `postscript` (6), `full` (4) and `fs_type` (`OS/2.fsType`), even when the engine report also carries them (WP-109/110). They are read from the **partial file**, which the engine has already verified, before the rename. `getDebugName` is used and the font is closed in `finally`.
- `forge_report` builds, in schema order:
  - `output_path`: the request's path.
  - The names above.
  - `total_codepoints`, `total_glyphs`: from the engine report.
  - `materials[i]`: `{name: mr.name, path: req.materials[i].path, index: req.materials[i].index, codepoints, groups, warnings}`.
  - `issues`: each `Issue` as `{code, severity, material_index, group, message}`.
  - `licence_notes`: each `LicenceNote` as `{"class": licence_class, "material_indexes": list(...), "text"}`.
  - Both from the engine report's attributes (`dataclasses.asdict`, or a mapping), with keys in schema order. If an attribute is absent, the H9 interim value is used.
  - `warnings`, `duration_s`.

**10. `face` payload (`protocol/records.py`)**

```python
def face_payload(face: FontFace, request_path: str) -> dict:
    record = fpengine.records.face_record(face)        # WP-106: contracts §3 keys + "unshaped", final types
    record["path"] = request_path                       # H2.7: echo the request string, never face.path
    return _clean(record)                               # lone surrogates -> U+FFFD in every string except "path"
```

- `_clean` replaces lone surrogates with `s.encode("utf-16", "surrogatepass").decode("utf-16", "replace")`, recursively in strings, lists and dicts. Key order is kept. `face-record.schema.json` lists the keys in the same order as `FACE_RECORD_KEYS`.
- If `face_record` emits a key the schema lacks, or omits one it requires, the protocol tests fail (AC-201-6). The fix is a schema and spec change in the same PR (AGENTS.md rule 9). Do not filter keys here.

**11. Logging**

- One handler on stderr, format `%(asctime)s fpengine[%(process)d] %(levelname)s %(name)s: %(message)s`.
- Root at WARNING. `fpengine` at the level from the `FPENGINE_LOG` variable (`debug`, `info` or `warning`; default `info`; `-I` does not hide it, because it is not a `PYTHON*` variable). `fontTools` at ERROR, or WARNING when `FPENGINE_LOG=debug`. `logging.captureWarnings(True)`.
- INFO lines:
  - `start {command} python={ver} fonttools={ver}`
  - `finished {command} in {s:.2f}s exit={code}`
  - `cancelled by {SIGTERM|SIGINT} during {stage}`
  - `parent process exited; cancelling`

**12. Top-level mapping in `cli.main`**

| Exception | Event | Exit code |
|---|---|---|
| `RequestError` | `error` `bad_request`, stage null | 2 |
| `HelperError(code=bad_request)` | `error` | 2 |
| `HelperError(other)` | `error` | 3 |
| `Cancelled` from SIGTERM / SIGINT (including `KeyboardInterrupt` raised before `install()`) | none | 143 / 130 |
| `ClientGone` | none | 141 |
| `Exception` | `error` `internal`, `stage=` `EventWriter.last_stage` (`done` is reported as `verify`; null for hello or before any stage), `message=f"Unexpected error: {Type}: {msg}"` (wording of `ui/workers.py:75`), `detail=` traceback | 3 |

**13. Examples (`spec/protocol/examples/`)**

Record them from real runs on synthetic fonts. Replace directories with `/fonts/` and `/builds/`, and set `mtime` to `1790000000.0` and `duration_s` to `1.234`.

| File | Contents |
|---|---|
| `hello.jsonl` | the two hello lines |
| `scan.jsonl` | exactly 8 lines for the request `["/fonts/FixtureSans-Regular.ttf", "/fonts/FixtureSerif.ttc", "/fonts/NotAFont.ttf", "/fonts/Missing.ttf"]`: `progress` 0/4, `face` ×3, `file_error` `unreadable`, `file_error` `not_found`, `progress` 4/4, `result`. Drop any throttled intermediate `progress` line from the recording |
| `forge-ok.jsonl` | FixtureSans-Regular + FixtureCJK-Regular, rules `{"han": 1, "kana": 1, "cjk_symbols": 1}`: 8 `progress` lines, then `result` (`total_codepoints` 3650) |
| `forge-error.jsonl` | the same request with material 1's `expect.size` off by one: `progress` `validate`, then `error` `stale_material`, `stage` `validate`, `material_index` 1 |
| `hello-request.json`, `scan-request.json`, `forge-request.json` | the requests of the `scan` and `forge-ok` runs (`{}` for hello) |

Fonts come from `python -m fpengine.testing.make_fonts` (H11) when it exists. WP-202 runs in the same wave, so if it has not landed, build the four fonts with `tests.fixtures.build_font`/`build_collection` using the H11 families, styles and coverage (sizes and PostScript names may then differ from H11; that is fine, and nobody re-records the examples later). These files are the shared fixtures for WP-204's decoder tests.

### Acceptance criteria

`run_helper(command, request, env=…)` in `engine/tests/protocol/conftest.py` runs `[sys.executable, "-I", "-B", "-m", "fpengine", command]` as a subprocess. It returns `(events, exit_code, stderr, raw_stdout)` and **fails the test** if any of these hold:
- a stdout line does not validate against `event.schema.json`;
- stdout does not end with `\n`;
- there is a blank line;
- there is not exactly one terminal event, last, when the exit code is 0, 2 or 3;
- there is a terminal event when the exit code is 143, 130 or 141.

Every protocol test below uses it. `run_helper(..., driver="slow_forge")` runs `[sys.executable, "-I", "-B", str(DRIVERS / "slow_forge.py"), command]` instead. Each driver imports `fpengine`, applies its patch (below), then calls `raise SystemExit(fpengine.cli.main(sys.argv[1:]))`. Fonts come from the WP-002 port of `reference/.../tests/fixtures.py` (the `font_dir` fixture: `A.ttf`, `B.otf`, `T.ttc` with two faces, …), plus a COLR font built in `conftest.py`.

- **AC-201-1** The protocol schemas are valid draft 2020-12, their `$id`s end with their file names, and all cross-file `$ref`s resolve through a `referencing.Registry`. Verified by `test_schemas_are_valid_draft_2020_12` in `engine/tests/protocol/test_schemas.py`.
- **AC-201-2** Every line of `spec/protocol/examples/*.jsonl` validates against `event.schema.json`, and every `*-request.json` validates against its request schema. The examples contain at least one event of each of the 6 types and each of the 3 `result` commands. Verified by `test_examples_validate`.
- **AC-201-3** `python -I -B -m fpengine hello </dev/null` writes exactly 2 lines, `hello` then `result{command:"hello"}`, and exits 0. `fpengine_version`, `fonttools`, `python` and `face_reader_version` equal `importlib.metadata.version("fpengine")`, `fontTools.version`, `platform.python_version()` and `fpengine.face.READER_VERSION`. Verified by `test_hello_events_and_exit_code` in `test_hello.py`.
- **AC-201-4** A synthetic font whose family is `合体测试` is scanned. The stdout bytes contain `合体测试` UTF-8-encoded (no `\u` escapes), and every line is newline-terminated. Verified by `test_output_framing_utf8_lines`.
- **AC-201-5** Given `files = [A.ttf, T.ttc, /missing/X.ttf, NotAFont.ttf]` (NotAFont.ttf is 75 bytes of text written by the test), `scan` emits, ignoring any throttled `progress` lines between the first and the last:
  1. `progress` done 0 of 4;
  2. `face` A index 0;
  3. `face` T index 0;
  4. `face` T index 1;
  5. `file_error` `not_found` for `/missing/X.ttf`, message `File not found.`;
  6. `file_error` `unreadable` for `NotAFont.ttf`, message starting `Not a font file fontTools can read (`;
  7. `progress` done 4 of 4, fraction 1.0;
  8. `result` with summary `{files:4, faces:3, file_errors:2, duplicates:0}`.

  Every `progress` line has non-decreasing `done`. Exit 0. Verified by `test_scan_streams_faces_in_request_order` in `test_scan.py`.
- **AC-201-6** For every scanned face, `face.path` equals the request string byte for byte, even for a request path containing `//`. Every other key equals `fpengine.records.face_record(read_faces(p)[i])`, and the key list equals `face-record.schema.json`'s `required` list. Verified by `test_scan_face_record_matches_reader`.
- **AC-201-7** A request that repeats a path emits its faces once and reports `duplicates: 1`. `{"files": []}` gives only `result` with zero counts. A directory path gives `file_error` `io_error` "Not a regular file.". Verified by `test_scan_duplicates_empty_and_directory`.
- **AC-201-8** Two identical scans produce identical `face`, `file_error` and `result` lines. Verified by `test_scan_output_is_deterministic`.
- **AC-201-9 (NATIVE-3)** `forge` of A.ttf + B.otf with rules `{"han": 1}`, as in `reference/.../tests/test_forge.py:14-31`:
  - emits progress stages exactly `[validate, plan, prepare, prepare, merge, finish, verify, done]`, with `material_index` `[0, 1]` on the prepares and non-decreasing fractions;
  - ends with a `result` whose `report` has `total_codepoints == 7`, `materials[*].path/index` echoing the request, and `family_name`/`postscript_name`/`full_name`/`fs_type` equal to the output's name table and OS/2;
  - leaves the output at `output_path`, with no `.fpengine-*.partial.ttf` in its folder;
  - exits 0.

  Verified by `test_native_3_forge_round_trip` in `test_forge.py`.
- **AC-201-10** With `expect`, each of these gives `error` `stale_material`, `stage:"validate"`, `material_index` equal to the changed material, exit 3, no output file, and the message format from Design §8: size changed; mtime changed by 2 s; PostScript name differs; file deleted; index 5 in a 2-face TTC. Without `expect`, a deleted file gives `io_error` and index 5 gives `bad_request` (exit 2). Verified by `test_forge_stale_material` (parametrised) and `test_forge_missing_material_without_expect`.
- **AC-201-11** A colour font gives `unsupported_font` with message `Fixture Color Regular: colour fonts are not supported` (or the WP-106 wording of that reason). A text file gives `unsupported_font`. `materials: []` and `scale: 20` give `validate`. All exit 3. Verified by `test_forge_unsupported_and_validate_errors`.
- **AC-201-12** Each malformed request below gives one `error` `bad_request` with `stage: null` and no other event (the output-path case alone is preceded by the `validate` progress event, because it is checked by the command), and exits 2. Cases:
  - not JSON;
  - a JSON array;
  - `NaN`;
  - non-UTF-8 bytes;
  - missing `spec`;
  - missing `output_path`;
  - relative material path;
  - a path with `..`;
  - `weight: true`;
  - `weight: 700.5`;
  - unknown group `klingon` in `script_rules`;
  - `index: -1`;
  - output path equal to a material;
  - unknown command `forgee`;
  - no command.

  `weight: 700.0` is accepted. Exact messages are checked for three cases: `weight: true` gives `Invalid request: spec.materials[0].weight: must be an integer.`, a relative path `a.ttf` gives `Invalid request: spec.materials[0].path: must be an absolute path.`, and `forgee` gives `Unknown command 'forgee'. Use hello, scan or forge.`. Verified by `test_bad_requests` (parametrised) in `test_errors.py`.
- **AC-201-12b** `parse_*` and the request schemas give the same accept/reject verdict for every case that is a JSON object: the object cases of AC-201-12 (missing `spec`, missing `output_path`, relative path, `..` segment, `weight: true`, `weight: 700.5`, `klingon`, `index: -1`), plus these accepted ones: `weight: 700.0`, path `/a/b..c.ttf`, `script_rules: {"han": null, "kana": 7}`, an extra unknown key, `expect` with `postscript_name: null`; plus these scan cases: `{"files": []}` (accepted), `{"files": "x"}`, `{"files": ["/"]}` and 100,001 paths (rejected). Not-JSON, `NaN`, non-UTF-8, the output-path case and the command-line cases are outside the schemas and are not compared. Verified by `test_parser_agrees_with_schema` in `test_errors.py`.
- **AC-201-13** `map_forge_error` follows the Design §8 table for every row, including:
  - `code` attribute precedence;
  - `io_error` from an `OSError` cause at `finish`;
  - prepare `material_index` taken from progress;
  - material lookup by display name, only when unique.

  Verified by `test_map_forge_error` (parametrised) in `test_errors.py`.
- **AC-201-14** With `fpengine.merge.MAX_GLYPHS` monkeypatched to 3 and `cli.main` run in-process on BytesIO, a forge ends in `error` `glyph_limit`. Verified by `test_forge_glyph_limit_code`.
- **AC-201-15** With `fpengine.forge.plan` (the name `forge.py` imported) monkeypatched to raise `RuntimeError("boom")` and `cli.main` run in-process, the result is `error` `internal`, `stage:"plan"`, message `Unexpected error: RuntimeError: boom`, `detail` containing `Traceback`, and return code 3. Verified by `test_forge_internal_error`.
- **AC-201-16 (NATIVE-7)** `drivers/slow_forge.py` patches `fpengine.forge.prepare` (the name `forge.py` imports from `fpengine.prepare`) with a pure-Python busy loop (no sleep, no checkpoints), after first writing one file into `tempfile.gettempdir()` (used by AC-201-17). SIGTERM is sent 0.3 s after the first `prepare` event. The helper then exits **143 within 1.0 s**, emits no terminal event, and every line it wrote is complete JSON. Verified by `test_native_7_sigterm_mid_stage_exits_143_within_1s` in `test_cancel.py`. Measured: 12 ms on an M-series Mac; the margin covers CI containers.
- **AC-201-17 (ENGINE-9)** In the AC-201-16 run, with `TMPDIR=tmp_path/"tmp"` (so the busy loop's file lands in the per-run folder). After exit, `tmp_path/"tmp"` is empty, the output folder has no `.fpengine-*` file, and `output_path` does not exist. Verified by `test_engine_9_cancel_removes_temp_and_partial_output`.
- **AC-201-18** `drivers/pause_after_result.py` sleeps 2 s after `EventWriter.terminal`. SIGTERM is sent after the `result` line is read. The helper exits 0 and the output file exists. Verified by `test_sigterm_after_result_exits_0`.
- **AC-201-19** SIGINT during the slow forge exits 130. `drivers/slow_scan.py` wraps `read_faces` with `time.sleep(0.5)`. SIGTERM after the first `face` event exits 143, and the lines already written are valid events. Verified by `test_sigint_exits_130` and `test_scan_sigterm_between_files`.
- **AC-201-20** `drivers/orphan_parent.py` starts the slow forge (as `run_helper` would, with the forge request on stdin) with `stdout=DEVNULL` and `stderr` redirected to a file, writes the helper's pid to a file the test names, then exits after 0.5 s. Within 5 s, the stderr file contains `parent process exited; cancelling`, the helper pid is gone (`os.kill(pid, 0)` raises `ProcessLookupError`) and `TMPDIR` is empty. The test's teardown sends SIGKILL to that pid if it is still alive. Verified by `test_helper_cancels_when_parent_exits`.
- **AC-201-21** A scan of 3 files through `drivers/slow_scan.py` (0.5 s per file): the client reads the first line, closes its end of stdout and waits. The helper's next write fails, and it exits 141 within 2 s. Its stderr contains neither `Exception ignored` nor `Traceback`. Verified by `test_client_closing_stdout_stops_helper`.
- **AC-201-22** With `fpengine.merge.verify` monkeypatched to raise `ForgeError("verify", None, "x")`, an **existing** `output_path` keeps its old bytes and no partial remains. The same holds for a new output path, which stays absent. Verified by `test_forge_output_is_atomic`.
- **AC-201-23** With `fpengine.forge.plan` wrapped so that it calls `print("noise")` first, an in-process forge still writes only parseable events to the injected stdout, and `noise` appears on stderr (`capsys`). Verified by `test_stray_prints_do_not_corrupt_stdout`.
- **AC-201-24** In-process (`cli.main` on BytesIO, `monkeypatch.setenv("TMPDIR", tmp_path/"a/b")`, a folder that does not exist), with `fpengine.forge.plan` wrapped to record `os.listdir(tmp_path/"a/b")` and `tempfile.gettempdir()` before calling the real `plan`: the folder is created, the recorded listing is exactly one `fpengine-<os.getpid()>-*` entry, `gettempdir()` was that entry, and after `main` returns 0 the folder is empty and `tempfile.tempdir` is back to its old value. Verified by `test_forge_uses_tmpdir_and_cleans_it`.
- **AC-201-25** A subprocess runs `hello`, `scan` and `forge` via `fpengine.cli.main` and then prints the sorted top-level names in `sys.modules`. None of `PySide6`, `objc`, `AppKit`, `jsonschema` or `referencing` appears. Verified by `test_helper_imports_only_engine_modules`.
- **AC-201-26** `set(INTERIM_REPORT_FIELDS) <= {"issues", "licence_notes"}`. An engine report that has the attribute is serialised from it, not from the interim value: `LicenceNote(licence_class="apple-sla", material_indexes=(1,), text="t")` becomes `{"class": "apple-sla", "material_indexes": [1], "text": "t"}`. Verified by `test_report_fields_and_interim_values`.
- **AC-201-27** The values of `ErrorCode`, `FileErrorCode` and `Stage` equal the `error_code`, `file_error_code` and `stage` enums in `defs.schema.json`. `CAPABILITIES` validates against `hello.schema.json`. Verified by `test_enums_match_schemas`.
- **AC-201-28** `make lint` and `make engine-test` pass on Linux, and the new protocol tests take under 60 s in total.

### Verification
```bash
make lint
make engine-test
cd engine && uv run pytest -q tests/protocol -k "native_3 or native_7 or engine_9"
printf '{}' | engine/.venv/bin/python -I -B -m fpengine hello
```

### Notes for the implementer
- Install the signal handlers **before** importing fontTools. Keep `cli.py` free of engine imports at module level; the commands import them lazily.
- `Cancelled` must stay a `BaseException`. Making it an `Exception` lets `reference/.../engine/forge.py:52` wrap a cancel into `ForgeError("prepare", …)`, and the cancel turns into a failure.
- Do not use `ForgeSpec.from_dict` (`engine/spec.py:84-95`): it drops missing materials silently (ENGINE-8). Build the spec from `_load_material` results.
- `read_faces` builds the path with `Path(path)`, which normalises `//`. Always pass the request string as `request_path`.
- `jsonschema` is a **dev** dependency only. If `engine/uv.lock` does not have it, you cannot add it offline. Stop and report it (backbone issue filed).
- Never write into `reference/`. Tests set `sys.dont_write_bytecode = True` before importing anything from it.

---

## WP-202: Conformance fixture generator + fixtures

**Goal:** Build a deterministic generator that turns the Python behaviour the Swift core must reproduce into golden JSON fixtures under `spec/fixtures/`, plus the generated Swift script-group table. Add a synthetic-font generator that Swift tests can call on Linux.
**Depends on:** WP-002, WP-108, WP-109 · **Env:** linux · **Size:** M · **Closes findings:** —

### Scope
- In: `tools/conformance/` (generator, its modules, `swift_tables.py`, README); the generated `spec/fixtures/**` listed below, including `spec/fixtures/README.md`; the generated `ScriptGroupTable.swift`; `fpengine.testing` (`fonts.py`, `make_fonts.py`); generator and `make_fonts` tests.
- Out:
  - the Swift ports and the Swift conformance tests that read these fixtures (WP-301…304, core.md §S5);
  - the PostScript-name algorithm (WP-109, engine-metadata.md);
  - the shaping fixture's content (WP-107 owns `fpengine.shaping` and its writer; this generator only calls it);
  - the protocol (WP-201);
  - deleting `reference/` (WP-701).

### Touched paths
- `tools/conformance/generate.py` (new: CLI entry)
- `tools/conformance/common.py` (new: header, deterministic writer, reference shim)
- `tools/conformance/categories/__init__.py`, `planner.py`, `scripts.py`, `languages.py`, `naming.py`, `text.py`, `shaping.py` (new)
- `tools/conformance/swift_tables.py`, `tools/conformance/README.md` (new)
- `spec/fixtures/**` (generated)
- `Packages/FontPlaygroundKit/Sources/FPCore/Generated/ScriptGroupTable.swift` (generated)
- `engine/src/fpengine/testing/__init__.py`, `fonts.py`, `make_fonts.py` (new)
- `engine/tests/conformance/__init__.py` (new, empty), `engine/tests/conformance/test_generator.py`, `engine/tests/test_make_fonts.py` (new)
- `Makefile` (edit: `conformance-check` also covers the generated Swift folder, below); `docs/specs/helper.md` (clarifications for threshold boundaries and `--only`)

`make conformance` already runs `uv run --project engine --frozen python tools/conformance/generate.py` (foundation-release.md, WP-001). `make conformance-check` diffs `spec/fixtures` and rejects untracked files there. Extend both of its checks to `Packages/FontPlaygroundKit/Sources/FPCore/Generated` as well (`git diff --exit-code -- spec/fixtures Packages/FontPlaygroundKit/Sources/FPCore/Generated`, and the same two paths in `git ls-files --others --exclude-standard`), so a stale `ScriptGroupTable.swift` fails the check (AGENTS.md rule 10). WP-001's `test_conformance_check_detects_fixture_drift` must still pass.

### Design

**1. CLI**

```
python tools/conformance/generate.py [--out spec/fixtures]
                                     [--swift-out Packages/FontPlaygroundKit/Sources/FPCore/Generated]
                                     [--reference-dir reference/fontplayground-py] [--only CATEGORY]
```

- Paths default relative to the repo root, which is found from `__file__`.
- It prints one line per file: `wrote`, `unchanged` or `frozen`. Exit 0 on success; 1 when a category fails, with the traceback printed. `--only` also regenerates the scripts prerequisite, so the Swift table always reads JSON produced by the same run.
- After the JSON categories, it runs `swift_tables.main([<out>/scripts/group-ranges.json, <swift-out>/ScriptGroupTable.swift])` in the same process, so the table and the fixture always change together (AGENTS.md rule 10).

**2. Fixture files** (normative layout, aligned with the consumer contract in core.md §S5; `category` = path without `.json`)

| File | Source | Keys after `header` | Consumer |
|---|---|---|---|
| `scripts/group-ranges.json` | `fpengine.scripts.group_of` over 0…0x10FFFF | `"groups"`: the 15 ids in GROUPS order; `"labels"`: `{id: label}` (`scripts.py:16-32`); `"ranges"`: `[[start, end, "group id"], …]`, maximal runs, contiguous 0…1114111 (824 entries with fontTools 4.66.0); `"samples"`: `[[codepoint, "group id"], …]`; `"groups_covered"`: `[{"codepoints": ranges, "expected": [id…]}]` | WP-301 |
| `planner/cases.json` | `fpengine.planner.source_of` (assignments built exactly as `plan()`, `engine/planner.py:19-27`) | `"cases"`: `[{"name", "coverages": [ranges per material], "rules": {id: int\|null}, "assignments": [ranges per material], "queries": [[cp, index\|null], …]}]` | WP-302 |
| `languages/languages.json` | reference `ui/languages.py` + `fpengine.scripts` | `"languages"`: `[{"id", "label", "short_label", "groups", "min_counts": [[g, n]], "markers", "picker_sample", "text_sample"}]` (LANGUAGES order); `"group_language"`, `"group_phrases"`, `"group_labels"`: objects; `"default_sample"`, `"old_default_sample"`: strings; `"samples"`: `[[id, label, text], …]` (SAMPLES order); `"constants"`: `{"min_share", "max_phrases", "max_role_languages", "any", "draws_nothing"}` | WP-301 |
| `languages/covers-well.json` | reference `covers_well` (`ui/languages.py:111-115`) | `"cases"`: `[{"name", "coverage": ranges, "group_counts": {id: n}, "language", "expected": bool}]` | WP-301 (extra) |
| `languages/phrases.json` | reference `ui/languages.py:118-196` | `"languages_for_missing"`: `[{"codepoints": [cp], "expected": [id]}]`; `"join_labels"`: `[{"languages", "limit", "joiner", "expected"}]`; `"draws_text"` and `"role_title"`: `[{"tally": {id: n}, "expected"}]`; `"sample_has_language"` and `"with_language_line"`: `[{"text", "language", "expected"}]` | WP-301/302 (extra) |
| `text/ignorable.json` | reference `ui/textutil.py:is_ignorable` over 0…0x10FFFF minus surrogates | `"unicode_version"`: `unicodedata.unidata_version` (`"15.0.0"` for 3.12); `"ignorable"`: ranges | WP-301 |
| `text/visible-chars.json` | reference `visible_chars` (`ui/textutil.py:21-23`) | `"cases"`: `[{"text", "visible": [cp…]}]`. Code points, sorted, never strings: Swift `String` equality is canonical-equivalence-based | WP-301 (extra) |
| `naming/family-names.json` | reference `ui/smart.py:97-125` | `"strip_vendor"`: `[[input, output]]`; `"default_family_name"`: `[{"families": [str], "expected"}]`; `"default_style"`: `[[style\|null, expected]]`; `"file_stem"`: `[[family, style, stem]]` (`default_output_path(family, style).stem`) | WP-304 |
| `naming/postscript_names.json` | `fpengine.naming.postscript_name` (engine-metadata.md WP-109 §2, §7) | `"cases"`: `[[family, style, expected], …]` | WP-304 |
| `shaping/ot_alternatives.json` | **written by WP-107's own writer**, `python -m fpengine.shaping write-fixture <path>` | owned by engine-metadata.md WP-107 §8 | WP-301, WP-304 |
| `README.md` | generator template | the layout above, how to regenerate, "never hand-edit" | — |

Rows marked "extra" carry more data than core.md §S5 lists. Consumers may ignore them.

**3. Header** (first key of every file this generator writes; all keys required)

```json
{"header": {"generator": "tools/conformance/generate.py", "generator_version": 1, "category": "planner/cases",
            "fpengine_version": "0.1.0", "fonttools_version": "4.66.0", "unicodedata2_version": "18.0.0",
            "python_unicodedata_version": "15.0.0", "python": "3.12",
            "sources": ["fpengine.planner.source_of", "fpengine.scripts.group_of"],
            "reference": null, "seed": 20260929,
            "note": "Generated by `make conformance`. Never edit by hand."}}
```

- `python` is `major.minor` only, so patch releases cause no drift.
- `reference` is `"reference/fontplayground-py@14b6572"` for reference-sourced files, else null.
- `seed` is null when no randomness is used.
- Bump `generator_version` when any file's shape changes.

**4. Deterministic writer (`common.dump`)**
- `ensure_ascii=False`, 2-space indent, `\n` line ends, trailing newline.
- Objects put one key per line, in insertion order, which the generator fixes.
- Arrays whose elements are all scalars go on one line (`[32, 126]`, `[0, 64, "latin"]`). Other arrays put one element per line.
- Floats use `repr`. No NaN.
- Sets are always sorted before writing, and the output must not depend on `PYTHONHASHSEED`.
- Compare with the existing bytes and do not touch a file whose content is unchanged.
- In each folder it owns (`scripts`, `planner`, `languages`, `text`, `naming`), delete `*.json` files it did not produce, so stale fixtures show up as deletions. It never touches `shaping/` except through WP-107's writer, and never deletes `README.md`.
- **Shaping.** When `importlib.util.find_spec("fpengine.shaping")` is not None, run `[sys.executable, "-m", "fpengine.shaping", "write-fixture", <out>/shaping/ot_alternatives.json]`. Otherwise, before WP-107, print `skipped shaping (fpengine.shaping not present)`.

**5. Reference shim (`common.import_reference`)**

```python
def import_reference(module: str, reference_dir: Path) -> ModuleType:
    """Import a Qt-free module of the original app, running on fpengine's script groups."""
    if not (reference_dir / "fontplayground").is_dir():
        raise ReferenceMissing(reference_dir)
    sys.dont_write_bytecode = True                      # never create __pycache__ under reference/
    if str(reference_dir) not in sys.path:
        sys.path.insert(0, str(reference_dir))
    import fpengine.scripts
    sys.modules["fontplayground.engine.scripts"] = fpengine.scripts   # before any reference import
    mod = importlib.import_module(module)
    assert not any(m.split(".")[0] in {"PySide6", "shiboken6"} for m in sys.modules)
    return mod
```

Only `fontplayground.ui.languages`, `fontplayground.ui.smart` and `fontplayground.ui.textutil` are imported. They are Qt-free: their package `__init__`s are empty, and they import `catalog.face` and `engine.{merge,spec,prepare}`, which need only fontTools and skia-pathops. Faces for `covers_well` are `types.SimpleNamespace(codepoints=frozenset, counts=dict)`, where counts come from `fpengine.scripts.group_of` over every group.

**6. Frozen mode (how WP-701 retires the reference imports)**

When `--reference-dir` does not exist, every reference-sourced file is **frozen**:
- The files are `languages/*`, `text/*` and `naming/family-names.json`.
- The generator prints `frozen (reference/ removed): <file>` and leaves each one byte-identical. Their stale-file deletion is skipped.
- It still regenerates the fpengine-sourced files (`scripts/`, `planner/`, `naming/postscript_names.json`, `shaping/`) and the Swift table, then exits 0.

When `spec/fixtures/FROZEN.sha256` exists, the generator checks every frozen file against it. Its lines are `<sha256>  <relative path>`, sorted, in `shasum -a 256` format. A mismatch or a missing file exits 1 with `conformance: frozen fixture changed: <path> (frozen at WP-701; never hand-edit)`.

WP-701 (foundation-release.md) writes `FROZEN.sha256`, deletes `reference/`, and may remove the generator's then-dead reference code paths. No other generator change is needed. From then on, the frozen files are regression goldens for the Swift code, which becomes the canonical implementation of that UI logic.

*As built at WP-701:* `--reference-dir`, the import shim and the `languages` and `text` categories are gone, and `--only` accepts `scripts`, `planner`, `naming` and `shaping`. Frozen mode is the only mode: the manifest is required, it must list exactly the six frozen files, and the generator prints `frozen: 6 files verified` once instead of one line per file. A missing manifest is reported as `conformance: frozen fixture changed: FROZEN.sha256`.

**7. Case generation** (`seed = 20260929`, a fresh `random.Random(seed)` per category)

- **Planner** (71 or more cases):
  - Port the 6 cases of `reference/.../tests/test_planner.py:9-41` and the one of `test_mix.py:10-16`, by name, as `coverages` + `rules`. Query every code point in the union, plus `한` (none) where the test does.
  - Add 64 random cases:
    - 1–4 materials, each a random subset (p = 0.5) of this 39-code-point alphabet: a–h, 0–3, `,.`, Greek Α–Γ, Cyrillic а–в, 漢字永和, かなカナ, 한글, `，、。`, `→✓☺`, 😀🙂, U+1200.
    - Rules: each group, with p = 0.4, gets a value from `[null, 0…n−1, n, 7, −1]`.
    - Queries: the whole alphabet plus U+E000 and U+10FFFF.
  - `queries[i][1] = source_of(cp, sets, rules)`. `assignments` come from the same loop as `plan()`.
- **Scripts:**
  - One run-length pass over 0…0x10FFFF with `group_of`.
  - `samples`: the 20 pairs of `reference/.../tests/test_scripts.py:6-13`.
  - `groups_covered`: the case of `test_scripts.py:23-24`, plus 16 random subsets of the planner alphabet.
- **Languages:**
  - Tables are copied verbatim from `LANGUAGES`, `SHORT_LABELS`, `GROUP_LANGUAGE`, `GROUP_PHRASES`, `SAMPLES`, the samples and the constants (`ui/languages.py:15-103`). `group_labels` comes from `fpengine.scripts.LABELS`.
  - `covers-well`: the 6 assertions of `tests/test_languages.py:25-33`, by name. Then, for every language with `min_counts`, three faces:
    - `exact`: the first *n* code points of each group in ascending code-point order, plus the markers;
    - `short`: reduce the first group to exactly *n−1* code points, preserving markers (markers outside the first *n* may increase `exact` beyond *n*);
    - `no_marker`: `exact` minus the last marker (only when there are markers).
  - `any` gets one tiny face.
- **Phrases:**
  - Every assertion of `tests/test_languages.py:36-78`, by name.
  - `draws_text` and `role_title` on each group alone at counts `[1, need−1, need]` (need from `min_counts`, else 1).
  - 32 random tallies with 1–6 groups and counts drawn from `{1, 3, 40, 198, 300, 1000, 28195}`.
  - `sample_has_language` and `with_language_line` for every language × the texts `["", "Hello", "Hello\n", "안녕", "x 漢", DEFAULT_SAMPLE]`.
- **Family names** (50 or more cases):
  - Every case of `tests/test_smart.py:128-171`.
  - Extras: `"Microsoft"`, `"  Microsoft   YaHei  "`, a 31-character and a 32-character pair, `"Noto Sans CJK SC"`, control characters and `<>:"/\|?*` in file stems.
  - 50 random `default_family_name` lists: 1–4 families drawn from `["Microsoft YaHei", "MS Gothic", "Adobe Song Std", "Google Sans", "Segoe UI", "Noto Sans", "Noto Serif", "PingFang SC", "Hiragino Sans", "Helvetica Neue", "Source Han Sans HW SC", ".SF Arabic", "Avenir Next"]`.
- **PostScript names:** every input engine-metadata.md WP-109 §7 lists:
  - its worked-example table;
  - `("", "Regular")`;
  - the NFC/NFD pair of `"Café"`;
  - `("　Noto ", "Regular")`;
  - 20 generated names per script group, 300 in all. For group `g`, the alphabet is the first 64 code points `cp >= 0x21`, in ascending order, with `group_of(cp) == g` and `unicodedata.category(chr(cp))[0] in "LNPS"` (stdlib `unicodedata`). A family is 1–3 random alphabet characters (a space between them with p = 0.3); the style is a random choice from `["Regular", "Bold", "Italic", "Bold Italic", "粗体"]`. Groups in `GROUP_IDS` order, one `random.Random(seed)` for the whole category.

  Add these 24 of this spec:
  - `("Forged Test","Regular")`
  - `("合体字体","Regular")`
  - `("合体字体","粗体")`
  - `("中文","Regular")`
  - `("日本語","Regular")`
  - `("한글","Bold")`
  - `("Helvetica Neue PingFang SC","Regular")`
  - `("Avenir Next","Regular")`
  - `("Forged","Regular")`
  - `("","")`
  - `("  ","Regular")`
  - `("A"*80,"Regular")`
  - `("Fixture Sans CJK","Regular")`
  - `("Café Crème","Italic")`
  - `("Segoe UI YaHei","Semibold Italic")`
  - `("123","456")`
  - `("-","-")`
  - `("Noto Sans CJK SC","Black")`
  - `("😀 Emoji","Regular")`
  - `("Fixture Sans","Bold")`
  - `("Fixture Sans","Bold ")`
  - `("Fixture\tSans","Bold")`
  - `("ΑΒΓ","Regular")`
  - `("Кириллица","Bold")`

  Remove duplicate pairs, keeping the first occurrence.
- **Text:**
  - `ignorable` is one pass of `is_ignorable(chr(cp))` over 0…0x10FFFF, skipping U+D800–DFFF. That gives 715 ranges with Python 3.12.
  - The `visible-chars` corpus:
    - every language `picker_sample` and `text_sample`;
    - every SAMPLES text;
    - `"a‍b"`;
    - `"👩‍💻"`;
    - `"❤️"`;
    - `"é"`;
    - `" 　\t\n x"`;
    - `"﻿BOM"`;
    - `"soft­hyphen"`;
    - `"\U000f0000"`;
    - `"\U000e0001tag"`;
    - `"͸"`;
    - `"  "`;
    - `"A͏B"`.

**8. Generated Swift (`tools/conformance/swift_tables.py`, stdlib only)**

It reads `scripts/group-ranges.json` and writes `ScriptGroupTable.swift` deterministically:

```swift
// swift-format-ignore-file
// Generated by tools/conformance/swift_tables.py from spec/fixtures/scripts/group-ranges.json. Do not edit.

/// Script group of every Unicode scalar: `groups[i]` applies from `starts[i]` up to `starts[i + 1] - 1`
/// (the last run ends at U+10FFFF). A group number indexes the fixture's "groups" (GROUPS order, 0 = latin … 14 = other).
enum ScriptGroupTable {
  static let starts: [UInt32] = [
    0x000000, 0x000041, …,
  ]
  static let groups: [UInt8] = [
    14, 0, …,
  ]
}
```

- It writes 8 values per line.
- The file is `internal` to FPCore, uses no FPCore type, and compiles before WP-301 exists. WP-301 maps `groups[i]` with `ScriptGroup.allCases[Int(groups[i])]` (core.md WP-301 §5).
- The first line must be `// swift-format-ignore-file`, which `swift format lint` honours (verified).
- No ignorable-character table is generated: core.md §6 decided that `TextUtil` uses Swift's own Unicode properties at runtime and checks them against `text/ignorable.json`.

**9. `fpengine.testing`** (shipped in the package; WP-203 keeps it in the runtime, where its self-check uses it)

```python
# fonts.py: adapted from reference tests/fixtures.py:19-102 (rectangle glyphs), deterministic
FIXED_TIMESTAMP = 3_900_000_000
def build_font(path: Path, family: str, style: str, codepoints: Iterable[int], *, upem: int = 1000, cff: bool = False,
               weight: int = 400, italic: bool = False, fs_type: int = 0, variable: bool = False,
               color: bool = False) -> Path: ...
def build_collection(path: Path, font_paths: Sequence[Path]) -> Path: ...
# make_fonts.py
@dataclass(frozen=True)
class FixtureFace: index: int; family: str; style: str; postscript_name: str; weight_class: int; italic: bool; outline: str; upem: int; coverage: tuple[tuple[int, int], ...]; supported: bool
@dataclass(frozen=True)
class FixtureFont: file: str; faces: tuple[FixtureFace, ...]; expect: str
FIXTURE_FONTS: tuple[FixtureFont, ...]              # exactly the H11 table
def make_fonts(directory: Path) -> Path: ...        # writes the set + fonts.json, returns the manifest path
def main(argv: list[str] | None = None) -> int: ... # python -m fpengine.testing.make_fonts <dir>; prints the manifest path
```

- Glyph names are `uniXXXX` for BMP code points and `uXXXXX` above.
- The name table (`fb.setupNameTable`) sets family, style, PostScript name, unique ID `<ps>;fixture` and version `Version 1.000`, where `ps = f"{family}-{style}".replace(" ", "")` (the H11 PostScript column). CFF fonts use the same `ps` as the CFF font name.
- OS/2 `fsSelection`: bit 0 (0x01) for italic, bit 5 (0x20) when `weight >= 700`, and bit 6 (0x40, REGULAR) when neither is set. `head.macStyle` gets bit 0 for bold and bit 1 for italic, the same way.
- The colour font gets `setupCPAL([[(1, 0, 0, 1)]])` and `setupCOLR({first glyph: [(first glyph, 0)]})`.
- Timestamps are pinned: `font.recalcTimestamp = False` and `head.created = head.modified = FIXED_TIMESTAMP`. The collection's member fonts also get `recalcTimestamp = False`.
- `NotAFont.ttf` is `b"This is not a font file.\n" * 3`.
- The manifest `coverage` uses the ranges helper of `fpengine.records`.

mac-services.md keeps its own `TestFixtures/make_fonts.py` for CoreText-specific fonts. The two do not share code.

### Acceptance criteria
- **AC-202-1** `make conformance` on a clean checkout produces exactly the files of Design §2, plus `ScriptGroupTable.swift`. `shaping/ot_alternatives.json` is produced only once `fpengine.shaping` exists. Every JSON file this generator writes itself (all but `shaping/ot_alternatives.json`, whose header belongs to WP-107) starts with a `header` holding every key of Design §3, and `category` equals its path without `.json`. Verified by `test_fixture_files_and_headers` in `engine/tests/conformance/test_generator.py`, which runs the generator into `tmp_path`.
- **AC-202-2** Two runs into different temporary folders, with `PYTHONHASHSEED=0` and `PYTHONHASHSEED=1`, give byte-identical trees. After the output is committed, `make conformance-check` passes. Verified by `test_generator_is_deterministic` and by `make conformance-check`.
- **AC-202-3** `scripts/group-ranges.json` `ranges` are maximal runs, contiguous from 0 to 1114111 with no gap or overlap. `group_of(cp)` equals the range's group for **every** code point. `samples` include all 20 pairs of `reference/.../tests/test_scripts.py:6-13`. Verified by `test_script_group_ranges_cover_every_code_point`.
- **AC-202-4** `ScriptGroupTable.swift` starts with `// swift-format-ignore-file`. Its two literal arrays, parsed back in Python, equal the JSON `ranges` (starts, and group indexes into `groups`). `make lint` passes, and `make kit-test` compiles it on Linux. The `conformance-check` recipe in the `Makefile` names `Packages/FontPlaygroundKit/Sources/FPCore/Generated` in both its `git diff` and its untracked-file check, and `make conformance-check` passes on the committed tree. Verified by `test_swift_table_matches_json`, `test_conformance_check_covers_generated_swift` (reads the Makefile text) and the Make targets.
- **AC-202-5** `planner/cases.json` has 71 or more cases, including the 7 ported reference cases by name. Across the file, rules include `null`, out-of-range (`n`, `7`) and negative (`-1`) values. Every case queries a code point no material has. Every query equals `fpengine.planner.source_of`. Every case's `assignments` equal `fpengine.planner.plan` on a spec built from `fake_face`s with those coverages. Verified by `test_planner_cases`.
- **AC-202-6** `languages/languages.json` tables equal the reference objects field by field. `covers-well.json` has `exact`, `short` and `no_marker` cases for every language with `min_counts`: `exact` is true, the other two false. Every assertion of `tests/test_languages.py` is present as a named case with the same expected value. Verified by `test_language_fixtures`.
- **AC-202-7** `naming/family-names.json` contains the 8 `strip_vendor` cases of `tests/test_smart.py:128-137`, the family, style and file-stem cases of `:142-171`, and 50 random lists, 70 or more cases in all. Every expected value equals the reference function. Verified by `test_family_name_fixtures`.
- **AC-202-8** `naming/postscript_names.json` contains every input of Design §7, deduplicated. Every `expected` equals `fpengine.naming.postscript_name` and matches `^[A-Za-z0-9]+-[A-Za-z0-9]+$` with at most 63 characters. The worked-example rows equal the engine-metadata.md table. Verified by `test_postscript_name_fixtures`.
- **AC-202-9** `text/ignorable.json` `ignorable` equals `is_ignorable` over every non-surrogate code point, and `unicode_version == unicodedata.unidata_version`. Each `visible-chars` case's `visible` equals `[ord(c) for c in visible_chars(text)]`, and the corpus includes every string of Design §7. Verified by `test_text_fixtures`.
- **AC-202-10** A generator run leaves the recursive listing of `reference/`, including mtimes, unchanged (no `__pycache__`), and never imports `PySide6`. Verified by `test_generator_does_not_touch_reference`.
- **AC-202-11** With `--reference-dir <tmp>/missing` and a pre-populated output tree, the reference-sourced files are left byte-identical and reported as `frozen`. fpengine-sourced files and the Swift table are regenerated. The exit code is 0. With a `FROZEN.sha256` whose line for `languages/languages.json` is wrong, the run exits 1 with `conformance: frozen fixture changed: languages/languages.json`. Verified by `test_frozen_when_reference_missing`.
- **AC-202-12** A stray `planner/old.json` in the output is deleted by a regeneration. `README.md` and anything in `shaping/` are kept. Verified by `test_generator_removes_stale_files`.
- **AC-202-13** `make_fonts(tmp)` writes the 9 files of H11 and `fonts.json`, and two runs give byte-identical files. For every manifest face, `fpengine.face.read_faces` gives the same family, style, PostScript name, weight, italic flag, outline, upem, coverage and `supported`. `NotAFont.ttf` raises when read. The whole call takes under 5 s. Verified by `test_make_fonts_set_and_manifest` in `engine/tests/test_make_fonts.py`.
- **AC-202-14** `python -m fpengine.testing.make_fonts <tmp>/fonts` exits 0, creates the folder, and prints the absolute manifest path as its only stdout line. A missing argument exits 2 with usage on stderr. Verified by `test_make_fonts_cli`.
- **AC-202-15** `make lint` and `make test` pass on Linux.

### Verification
```bash
make conformance && make conformance-check
make engine-test
make kit-test
engine/.venv/bin/python -m fpengine.testing.make_fonts /tmp/fp-fixture-fonts
```

### Notes for the implementer
- Swift has no Unicode Script property, which is why the script table is **generated data**.
- Swift porters iterate `unicodeScalars`, not `Character`s, because `visible_chars` works on code points. They sort by scalar value.
- The reference modules run against `fpengine.scripts` through the shim, so a future change to `group_of` flows into every category at once.
- The ranges helper is `fpengine.records.ranges` (WP-002; engine-metadata.md WP-106 keeps that name). Do not add an alias.
- Do not add `jsonschema` or any new runtime dependency to the generator; it uses only fpengine's dependencies.
- The generator never reads the committed fixtures to produce new ones. The single exception is `swift_tables.py`, which reads the JSON the same run has just written.

---

## WP-203: Embedded runtime build (`scripts/build-helper-runtime.sh`)

**Goal:** `make helper-runtime` builds `build/helper/fpengine/`: a relocatable, arm64-only, trimmed python-build-standalone CPython 3.12. It has `fpengine` and its locked dependencies installed as non-editable wheels, is precompiled to unchecked-hash `.pyc`, and is self-checked by running the helper.
**Depends on:** WP-201, WP-202 · **Env:** macos · **Size:** M · **Closes findings:** TOOLING-M2, NATIVE-M4

### Scope
- In: the build script, its pin file and its self-check script; the download cache; the strip list; thinning; bytecode compilation; the runtime manifest; hand-off notes for signing.
- Out:
  - copying into the app bundle, signing with Developer ID, notarization and the `--self-test` flag (WP-601);
  - the CI cache configuration (WP-001/WP-601 own the workflows; this WP says what to cache);
  - universal2 (backlog B-3).

### Touched paths
- `scripts/build-helper-runtime.sh` (new, committed executable: git mode `100755`, because the `helper-runtime` Make target tests `-x`)
- `scripts/check-helper-runtime.sh` (new, also `100755`)
- `scripts/python-runtime.pin` (new)
- `Makefile` (edit only if `helper-runtime` does not already call `scripts/build-helper-runtime.sh`)

### Design

**1. Pin file** (`scripts/python-runtime.pin`, sourced by bash; CI hashes it as the cache key)

```bash
# python-build-standalone release used for the embedded helper (ADR-0004). Update all five values together.
PBS_RELEASE=20260924
PBS_PYTHON=3.12.14
PBS_TRIPLE=aarch64-apple-darwin
PBS_FLAVOR=install_only_stripped
PBS_SHA256=c2edb321cd32ec2b170df208db0446dccc4398db602ca27cf2079098fb1f7d9d
```

- The asset name is `cpython-${PBS_PYTHON}+${PBS_RELEASE}-${PBS_TRIPLE}-${PBS_FLAVOR}.tar.gz`.
- The URL is `https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_RELEASE}/cpython-${PBS_PYTHON}%2B${PBS_RELEASE}-${PBS_TRIPLE}-${PBS_FLAVOR}.tar.gz`. `%2B` is the encoded `+`.
- The values above were the newest 3.12 build on 2026-09-29 (release `20260924`, 25,017,789 bytes). Its digest matches the release's `SHA256SUMS` file.
- **The implementer must re-pin to the newest release that ships a 3.12 `aarch64-apple-darwin` `install_only_stripped` asset at implementation time.** Take the digest from that release's `SHA256SUMS`, not from a local download.

**2. `scripts/build-helper-runtime.sh [--out DIR] [--cache DIR] [--python-archive FILE] [--keep-staging]`**

Defaults are `--out build/helper` and `--cache build/cache`, both under the repo root. The script runs with `set -euo pipefail` and has a numbered log prefix `[k/12]`. Steps:

1. **Preconditions.**
   - Run from any folder; find the repo root from the script's location.
   - Require `uname -s` = Darwin and `uname -m` = arm64. Otherwise exit 2 with `build-helper-runtime: needs macOS on Apple silicon`.
   - Require `uv`, `curl`, `shasum`, `tar`, `lipo`, `codesign` and `file`. Otherwise exit 2, naming the missing tool.
2. **Archive.**
   - `--python-archive` given: use that file.
   - Else, if `$CACHE/pbs/<asset>` exists: print `using cached <asset>`.
   - Else: `curl --fail --location --proto '=https' --tlsv1.2 --retry 3 -o "$CACHE/pbs/<asset>.part" "$URL"`, then `mv` it into place.
   - Verify with `shasum -a 256`. On a mismatch, delete the cached file (never a `--python-archive` file) and exit 1 with `SHA-256 mismatch for <file>: expected <pin>, got <actual>`.
3. **Stage.** `mkdir -p "$OUT" "$CACHE/pbs"`, then `STAGE=$(mktemp -d "$OUT/.staging.XXXXXX")` and `tar -xzf` into it. Move `$STAGE/python` to `$STAGE/fpengine`; `RT=$STAGE/fpengine`. A `trap` removes `$STAGE` on any exit unless `--keep-staging` is given. **The previous `$OUT/fpengine` is untouched until step 12.**
4. **Interpreter check.** `"$RT/bin/python3" -I -c 'import sys; assert sys.version_info[:2] == (3, 12)'`.
5. **Engine wheel.** `uv build --project engine --wheel --out-dir "$STAGE/wheels"`. The project is always installed from a wheel (TOOLING-M2).
6. **Locked dependencies.** Export with `uv export --project engine --frozen --no-dev --no-editable --no-emit-project --format requirements-txt -o "$STAGE/requirements.txt"`, which includes hashes. Then install:
   - `uv pip install --python "$RT/bin/python3" --target "$SITE" --no-deps --require-hashes --only-binary :all: --link-mode copy -r "$STAGE/requirements.txt"`
   - `uv pip install --python "$RT/bin/python3" --target "$SITE" --no-deps --link-mode copy "$STAGE"/wheels/fpengine-*.whl`

   `SITE=$RT/lib/python3.12/site-packages`. `--target` avoids the `EXTERNALLY-MANAGED` marker that the runtime ships.
7. **Scrub install metadata.** Delete every `*.dist-info/direct_url.json`, which holds the absolute wheel path (a personal path), and every `*.dist-info/uv_cache.json`, which holds a timestamp. Keep `METADATA`, `RECORD`, `WHEEL`, `INSTALLER` and licence files: `hello` reads `importlib.metadata`, and WP-602 collects licences.
8. **Strip** (paths relative to `$RT`; each `rm -rf`):
   - `include/`, `share/`, `lib/pkgconfig/`, `lib/python3.12/config-3.12-darwin/`, `BUILD`
   - `lib/libtcl*`, `lib/tcl*`, `lib/tk*`, `lib/itcl*`, `lib/thread*`
   - `lib/python3.12/lib-dynload/_tkinter*`, `lib/python3.12/lib-dynload/_dbm*`, `lib/python3.12/lib-dynload/_crypt*`
   - `lib/python3.12/{tkinter,idlelib,turtledemo,ensurepip,lib2to3,pydoc_data,venv,__phello__,test}`, `lib/python3.12/turtle.py`
   - `lib/python3.12/site-packages/pip`, `lib/python3.12/site-packages/pip-*.dist-info`
   - `lib/python3.12/site-packages/bin/`: uv target installs create unused fontTools console wrappers here with absolute staging interpreter paths (TOOLING-M2). The app invokes modules, so these wrappers are removed.
   - in `bin/`, everything except `python3` and `python3.12`
   - every `__pycache__/` and `*.pyc` that came with the archive or the wheels

   Keep `unittest`, `lib/python3.12/LICENSE.txt` and `fpengine/testing` (the self-check uses it).
9. **Thin.** For every Mach-O (`file -b` contains `Mach-O`) whose `lipo -archs` is not exactly `arm64`: `lipo -thin arm64 "$f" -output "$f.thin" && mv "$f.thin" "$f"`. The per-slice linker signature survives (verified). The script does **not** re-sign.
10. **Bytecode.** `"$RT/bin/python3" -I -m compileall -q -j 0 --invalidation-mode unchecked-hash -s "$RT" -p /fpengine "$RT/lib/python3.12"`. A non-zero exit fails the build.
    - `unchecked-hash` means the runtime never checks source mtimes and is reproducible.
    - `-s/-p` keep the builder's path out of `co_filename`. Python fixes `co_filename` at import anyway.
11. **Self-check.** `scripts/check-helper-runtime.sh "$RT"` (§3). A failure fails the build.
12. **Publish atomically.** The runtime and its manifest switch as one recoverable transaction, `scripts/publish-helper-runtime.sh "$OUT" "$RT" "$STAGE/manifest.json"`, so a failed or interrupted publish never leaves a new runtime next to a stale manifest:
    - It stages the manifest as `$OUT/.fpengine-runtime.json.new` and writes `$OUT/.publish-journal`, which records whether a previous runtime and manifest existed.
    - It moves the previous pair to `.fpengine.old` / `.fpengine-runtime.json.old`, moves `$RT` to `$OUT/fpengine`, and renames the staged manifest into place.
    - It then removes the journal, which is the commit point, and the backups. A failed step restores the previous pair and exits 1.
    - `--recover "$OUT"`, which the build also runs at step 1, rolls back any publish whose journal is still present. (`engine/tests/repo/test_publish_runtime.py`)
    - The manifest `$OUT/fpengine-runtime.json` is `{"pbs_release", "python", "sha256", "fpengine", "fonttools", "skia_pathops", "unicodedata2", "size_mb", "macho": ["bin/python3.12", "lib/libpython3.12.dylib", …]}`, with paths relative to the runtime root and sorted. WP-601 finds the Mach-O files to sign with `file -b` (foundation-release.md §S4), which AC-203-5 guarantees is exactly this list; WP-602 reads the versions.
    - Last line: `helper runtime OK: build/helper/fpengine (<N> MB, <M> Mach-O files)`.

**3. `scripts/check-helper-runtime.sh <runtime-dir>`** (standalone; runs the checks in table order, prints `check <name> OK` after each one that passes, and exits 1 on the first failed check, printing `check <name> FAILED: <why>`; `T=$(mktemp -d)` is its scratch folder, removed on exit. Requests are built and event lines parsed with `<rt>/bin/python3 -I -c …`; `jq` is not required)

| Check name | Assertion |
|---|---|
| `native_m4_hello` | `<rt>/bin/python3 -I -B -m fpengine hello </dev/null` prints 2 lines. The first has `"protocol":1` and `fpengine_version` equal to `engine/pyproject.toml` `[project].version` (read with `tomllib` by the runtime itself). Exit 0 |
| `tooling_m2_non_editable` | `fpengine.__file__` is under `<rt>/lib/python3.12/site-packages/fpengine/`. There are no `*.pth`, no `__editable__*`, no `direct_url.json` and no `uv_cache.json` under `<rt>`. `grep -rl --binary-files=text` for the repo root path and for `$HOME` over `<rt>` finds nothing |
| `native_m4_pipeline` | With `TMPDIR=$T/tmp`: `-m fpengine.testing.make_fonts $T/fonts`; `-m fpengine scan` of all 9 files gives 9 `face` events, 1 `file_error` and exit 0; `-m fpengine forge` of FixtureSans-Regular + FixtureCJK-Regular (no `expect`, rules `{"han": 1, "kana": 1, "cjk_symbols": 1}`) into `$T/out.ttf` gives a `result` with `total_codepoints` 3650 and exit 0. Afterwards `$T/tmp` is empty |
| `no_bytecode_writes` | `find <rt> -newer <marker made before the checks> -type f` is empty after all runs |
| `pyc_unchecked_hash` | Every `.py` under `lib/python3.12` has its `__pycache__/<stem>.cpython-312.pyc` with header flags == 1 (hash-based, unchecked) |
| `stripped` | None of the step-8 paths exist |
| `macho` | Every Mach-O is `arm64` only, and `codesign --verify` passes for each. Their count is ≤ 12 (10 measured) |
| `size` | `du -sm <rt>` ≤ 85 (77 measured) |
| `relocatable` | `ditto <rt> "$T/Relocated Copy/fpengine"`, then `hello` from the copy exits 0 |
| `licences` | `lib/python3.12/LICENSE.txt` exists, and a licence file exists in the dist-info of fonttools, skia-pathops and unicodedata2 |

**4. Hand-off to WP-601 (signing; non-normative, from experiments on this Mac)**
- **Location.** A stub app with this runtime in `Contents/Helpers/fpengine/` **failed** ad-hoc `codesign`, because non-code files sit in a code location (`bundle format unrecognized … In subcomponent: …/Contents/Helpers/fpengine/lib/python3.12`). The same runtime in `Contents/Resources/fpengine/` signed inside-out and passed `codesign --verify --deep --strict`, and `bin/python3 -I -B -c 'import fontTools, pathops'` ran from the app. foundation-release.md §S3 therefore places it at `Contents/Resources/fpengine` with a `Contents/Helpers/fpengine` symlink (a backbone issue against ADR-0004). WP-204 resolves both locations.
- **Order and options.** foundation-release.md §S4 is normative: sign each helper Mach-O (the files `fpengine-runtime.json` lists, found with `file -b`), then the app, inside-out, with no `--deep` and no entitlements. With a Team identity every Mach-O gets `--options runtime` (plus `--timestamp` for Developer ID). With **ad-hoc** signing the helper's Mach-Os are signed **without** the hardened runtime, because ad-hoc signatures carry no Team ID and library validation would reject `pathops` (TOOLING-1). No entitlement (in particular not `com.apple.security.cs.disable-library-validation`) is ever used (ADR-0010). Signing must never happen in this script, because thinning happens before it and the tree is copied afterwards.
- The runtime never writes into itself: `-B`, unchecked-hash `.pyc`, and `TMPDIR` outside the bundle. The signature stays valid after runs (verified).

### Acceptance criteria
- **AC-203-1** On macOS arm64, `make helper-runtime` exits 0. It creates `build/helper/fpengine/bin/python3` and `build/helper/fpengine-runtime.json`, and its last stdout line matches `^helper runtime OK: build/helper/fpengine \([0-9]+ MB, [0-9]+ Mach-O files\)$`.
In AC-203-2 to -6, "the check passes" means the output of `make helper-runtime` (which runs `scripts/check-helper-runtime.sh` in step 11) contains the line `check <name> OK`, and a separate run of `scripts/check-helper-runtime.sh build/helper/fpengine` exits 0 with the same line.

- **AC-203-2 (NATIVE-M4)** The checks `native_m4_hello` and `native_m4_pipeline` pass: `-m fpengine` works from the embedded runtime with no source tree, and a scan and a forge complete.
- **AC-203-3 (TOOLING-M2)** The check `tooling_m2_non_editable` passes: the package comes from a wheel, there are no editable hooks, and no builder path is present.
- **AC-203-4** The checks `no_bytecode_writes`, `pyc_unchecked_hash` and `stripped` pass.
- **AC-203-5** The checks `macho`, `size` (≤ 85 MB) and `licences` pass. `fpengine-runtime.json` lists exactly the Mach-O files that `file` finds (compare with `find build/helper/fpengine -type f -exec file {} + | grep -c Mach-O`).
- **AC-203-6** The check `relocatable` passes: the runtime works from a path containing spaces.
- **AC-203-7** `scripts/build-helper-runtime.sh --python-archive <file of 1 KiB random bytes>` exits 1 and prints `SHA-256 mismatch`. A previously built `build/helper/fpengine` is byte-identical afterwards (compare with `shasum` over `find -type f | sort`), and no `.staging.*` folder remains.
- **AC-203-8** A second `make helper-runtime` prints `using cached cpython-3.12.` and does not invoke `curl`: `PATH` with a `curl` shim that exits 99 still succeeds.
- **AC-203-9** (manual, linux) In a Linux container, `bash scripts/build-helper-runtime.sh; echo $?` prints `build-helper-runtime: needs macOS on Apple silicon` on stderr and `2`. Paste the two lines into the PR. (`make helper-runtime` itself is already refused on Linux by WP-001's `_need-macos`.)
- **AC-203-10** `bash -n` passes for both scripts, and `make lint` and `make test` still pass on macOS.

### Verification
```bash
make helper-runtime
scripts/check-helper-runtime.sh build/helper/fpengine
head -c 1024 /dev/urandom > /tmp/bogus.tar.gz && ! scripts/build-helper-runtime.sh --python-archive /tmp/bogus.tar.gz
printf '{}' | build/helper/fpengine/bin/python3 -I -B -m fpengine hello
```

### Notes for the implementer
- Network is allowed in this script only for the pinned archive and for wheels pinned by `engine/uv.lock` (AGENTS.md rule 6). `make setup` has usually filled uv's cache already.
- Do not use `--compile-bytecode` in uv. Compile once in step 10 with the options given, so the `.pyc` are reproducible.
- Keep `fpengine/testing` (about 15 KB). The check `native_m4_pipeline` uses it to make fonts with the runtime itself, and it stays available for diagnostics in the shipped app.
- Build times: about 1 minute with a warm uv cache.
- CI caches `build/cache/pbs` (the download cache). The cache key should hash `scripts/python-runtime.pin`, where the pins live, not only the script.

---

## WP-204: `FPEngineClient` (process, JSON Lines, cancel, timeouts)

**Goal:** A Foundation-only Swift client that runs the helper once per request. It streams decoded events through `AsyncThrowingStream`, cancels by SIGTERM then SIGKILL, enforces timeouts, captures stderr, gates on `hello`, and builds and tests on Linux.
**Depends on:** WP-001, WP-201, WP-202, WP-301 · **Env:** linux · **Size:** M · **Closes findings:** NATIVE-7

### Scope
- In:
  - the `EngineRunning` protocol and `EngineClient`;
  - launch resolution;
  - process and pipe handling;
  - line framing;
  - event decoding;
  - cancellation, timeouts and stderr capture;
  - leftover cleanup and the launch sweep function;
  - the fake helper and the tests;
  - optional real-helper tests gated on `FP_ENGINE_PYTHON`.
- Out:
  - the domain wire types `FaceRecord`, `ForgeRequest` and `ForgeReport` (FPCore, core.md; they must follow H10);
  - catalog batching and caching (WP-401);
  - build-output management and calling the sweep at launch (WP-501/505);
  - os_log forwarding (MacKit).

### Touched paths
- `Packages/FontPlaygroundKit/Sources/FPEngineClient/EngineRunning.swift` (new)
- `Packages/FontPlaygroundKit/Sources/FPEngineClient/EngineTypes.swift` (new)
- `Packages/FontPlaygroundKit/Sources/FPEngineClient/EngineError.swift` (new)
- `Packages/FontPlaygroundKit/Sources/FPEngineClient/EngineConfiguration.swift` (new)
- `Packages/FontPlaygroundKit/Sources/FPEngineClient/EngineClient.swift` (new)
- `Packages/FontPlaygroundKit/Sources/FPEngineClient/HelperRun.swift` (new)
- `Packages/FontPlaygroundKit/Sources/FPEngineClient/LineFramer.swift` (new)
- `Packages/FontPlaygroundKit/Sources/FPEngineClient/EventDecoder.swift` (new)
- `Packages/FontPlaygroundKit/Sources/FPEngineClient/StderrRing.swift` (new)
- `Packages/FontPlaygroundKit/Sources/FPEngineClient/Signals.swift` (new; the only file with `#if canImport(Glibc) … #elseif canImport(Darwin)`)
- `Packages/FontPlaygroundKit/Sources/FPEngineClient/Leftovers.swift` (new)
- `Packages/FontPlaygroundKit/Tests/FPEngineClientTests/*.swift` (new)
- `Packages/FontPlaygroundKit/Tests/FPEngineClientTests/Resources/fake-fpengine.sh` (new)
- `Packages/FontPlaygroundKit/Package.swift` (edit: `resources: [.copy("Resources")]` on `FPEngineClientTests`)
- `Packages/FontPlaygroundKit/Sources/FPEngineClient/FPEngineClientInfo.swift` and `Tests/FPEngineClientTests/PlaceholderTests.swift` (delete: WP-001 placeholders; `EngineClient.supportedProtocol` replaces `FPEngineClientInfo.protocolVersion`)

### Design

**1. Public API** (Swift 6 language mode; everything `Sendable`)

```swift
public protocol EngineRunning: Sendable {
  func hello() async throws -> EngineHello
  func scan(files: [String]) -> AsyncThrowingStream<ScanEvent, any Error>
  func forge(_ request: ForgeRequest) -> AsyncThrowingStream<ForgeEvent, any Error>   // FPCore.ForgeRequest
}

public enum ScanEvent: Sendable, Equatable {
  case progress(EngineProgress)
  case face(FaceRecord)                 // FPCore.FaceRecord
  case fileError(ScanFileError)
  case finished(ScanSummary)            // always the last element of a successful stream
}
public enum ForgeEvent: Sendable, Equatable {
  case progress(EngineProgress)
  case finished(ForgeReport)            // FPCore.ForgeReport; the file is in place
}

public enum EngineStage: String, Sendable, Codable, CaseIterable {
  case validate, plan, prepare, merge, finish, verify, done, scan
}
public struct EngineProgress: Sendable, Equatable, Codable {
  public var stage: EngineStage; public var fraction: Double
  public var materialIndex: Int?; public var done: Int?; public var total: Int?
  // CodingKeys: stage, fraction, material_index, done, total
}
public struct EngineHello: Sendable, Equatable, Codable {
  public var protocolVersion: Int; public var fpengineVersion: String; public var python: String
  public var fonttools: String; public var unicodeVersion: String; public var platform: String; public var capabilities: [String]
  public var faceReaderVersion: Int   // fpengine.face.READER_VERSION; WP-401 keys its catalog cache on it
  // CodingKeys: protocol, fpengine_version, python, fonttools, unicode_version, platform, capabilities, face_reader_version
  // Custom init(from:): face_reader_version and unicode_version use decodeIfPresent (defaults 0 and ""), so the
  // hand-written hello literals of other specs' fakes still decode; every other key is required.
  public init(protocolVersion: Int = 1, fpengineVersion: String, python: String, fonttools: String,
              unicodeVersion: String = "", platform: String, capabilities: [String], faceReaderVersion: Int = 0)
}
public enum FileErrorCode: String, Sendable, Codable { case notFound = "not_found", ioError = "io_error", unreadable, `internal` }
public struct ScanFileError: Sendable, Equatable, Codable { public var path: String; public var code: FileErrorCode; public var message: String }
public struct ScanSummary: Sendable, Equatable, Codable {
  public var files: Int; public var faces: Int; public var fileErrors: Int; public var duplicates: Int   // file_errors
}
public enum HelperErrorCode: String, Sendable, Codable, CaseIterable {
  case badRequest = "bad_request", validate, staleMaterial = "stale_material", unsupportedFont = "unsupported_font"
  case aatUnsupportedScript = "aat_unsupported_script", glyphLimit = "glyph_limit", prepareFailed = "prepare_failed"
  case mergeFailed = "merge_failed", finishFailed = "finish_failed", verifyFailed = "verify_failed", ioError = "io_error", `internal`
}
public struct HelperFailure: Sendable, Equatable, Codable {
  public var code: HelperErrorCode; public var stage: EngineStage?; public var materialIndex: Int?
  public var message: String; public var detail: String?
}
public enum EngineError: Error, Sendable, Equatable {
  case helperNotFound(searched: [String])
  case launchFailed(String)
  case incompatibleHelper(reported: Int, supported: Int)
  case helperFailed(HelperFailure)                                    // the terminal `error` event
  case protocolViolation(String, stderrTail: String)
  case interrupted(exitCode: Int32?, signal: Int32?, stderrTail: String)   // 143/130 exit or TERM/INT/KILL/HUP not sent by us
  case crashed(exitCode: Int32?, signal: Int32?, stderrTail: String)       // any other end without a terminal event
  case timedOut(after: Duration, stderrTail: String)
}

public struct EngineLaunch: Sendable, Equatable {
  public var executableURL: URL
  public var arguments: [String] = ["-I", "-B", "-m", "fpengine"]    // the command is appended
  public var environment: [String: String] = [:]                     // merged over the inherited environment
  public enum Source: Sendable, Equatable { case bundled, environment, explicit }
  public var source: Source = .explicit                              // set by resolve(); the self-test reports it
  public static let bundledHelperCandidates = ["Contents/Helpers/fpengine/bin/python3", "Contents/Resources/fpengine/bin/python3"]
  public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                             bundleURL: URL? = Bundle.main.bundleURL,
                             isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) throws -> EngineLaunch
}
public struct EngineTimeouts: Sendable, Equatable {
  public var hello: Duration = .seconds(30)          // whole run
  public var scanIdle: Duration = .seconds(120)      // no stdout line for this long
  public var forge: Duration = .seconds(900)         // whole run (audit worst case about 60 s on M-series)
  public var terminationGrace: Duration = .seconds(2) // SIGTERM → SIGKILL (ADR-0003)
}
public struct EngineConfiguration: Sendable {
  public var launch: EngineLaunch
  public var temporaryDirectory: URL?                // exported as TMPDIR and created if missing; nil = inherit
  public var timeouts: EngineTimeouts = .init()
  public var stderrCapacity: Int = 65_536
  public var logHandler: (@Sendable (String) -> Void)?   // helper stderr lines and "[EngineClient] …" diagnostics
  public var processObserver: (@Sendable (EngineProcessEvent) -> Void)?  // read-only; diagnostics and tests (AC-204-17)
  public init(launch: EngineLaunch, temporaryDirectory: URL? = nil)
}
public enum EngineProcessEvent: Sendable, Equatable {
  case launched(pid: Int32, command: String)
  case exited(pid: Int32, exitCode: Int32?, signal: Int32?)
}
public final class EngineClient: EngineRunning {
  public static let supportedProtocol = 1
  public init(configuration: EngineConfiguration)
  public convenience init(temporaryDirectory: URL? = nil) throws   // EngineLaunch.resolve()
  public func hello() async throws -> EngineHello
  public func scan(files: [String]) -> AsyncThrowingStream<ScanEvent, any Error>
  public func forge(_ request: ForgeRequest) -> AsyncThrowingStream<ForgeEvent, any Error>
  /// Pid-based H7 sweep of helper leftovers. Called by the app at launch (WP-501), fpctl, the self-test and tests.
  /// Returns the number of entries removed.
  @discardableResult
  public static func sweepLeftovers(temporaryDirectory: URL, outputDirectories: [URL] = [],
                                    now: Date = Date(), fileManager: FileManager = .default) -> Int
}
```

Every public struct above has a `public init` taking its stored properties in declaration order, with the defaults shown (Swift's synthesised memberwise initialiser is `internal`, and FPMacServices, FPAppUI and fpctl construct these values, for example in their fake engines). `EngineLaunch`'s is `public init(executableURL: URL, arguments: [String] = ["-I", "-B", "-m", "fpengine"], environment: [String: String] = [:], source: Source = .explicit)`. `EngineError` and the enums need nothing extra.

**2. Launch resolution** (`EngineLaunch.resolve`)
1. For each entry of `bundledHelperCandidates`, in order, with a non-nil `bundleURL`: if `bundleURL/<candidate>` is executable, use it.
2. Else, if `environment["FP_ENGINE_PYTHON"]` is non-empty and executable, use it.
3. Else, throw `.helperNotFound(searched:)` with every path tried, in order.

The embedded runtime wins over `FP_ENGINE_PYTHON` (architecture §3: "debug builds when no embedded runtime is present"). `fpctl` and tests are not bundles, so they reach step 2.

**3. One run (`HelperRun`, internal, `final class … : @unchecked Sendable` guarded by one `NSLock`)**
1. **Environment.** Start from `ProcessInfo.processInfo.environment` and merge `launch.environment` over it. Set `PYTHONDONTWRITEBYTECODE=1` (harmless; `-B` does the work under `-I`). If `temporaryDirectory` is set, create it with intermediate folders and set `TMPDIR` to its path. A failure is `.launchFailed`.
2. **Process.** `executableURL`, `arguments = launch.arguments + [command]`, `currentDirectoryURL = URL(fileURLWithPath: "/")`, and three `Pipe`s. `terminationHandler` records `(terminationReason, terminationStatus)`, calls `processObserver?(.exited(...))` and wakes the state machine. After `run()` succeeds, call `processObserver?(.launched(pid:command:))`. `try process.run()`; an error becomes `.launchFailed(String(describing: error))`. Do **not** close the child-side pipe ends yourself: Foundation does it on both platforms, and closing a reused fd number is a bug.
3. **Threads** (Foundation `Thread`, named):
   - `fpengine-stdin`: `try write(contentsOf: requestData)`, then `try close()`. Errors such as EPIPE are logged, not thrown; the exit status explains them.
   - `fpengine-stdout`: loops on `availableData`, which blocks; empty means EOF. It feeds `LineFramer` and hands each complete line to the decoder, in order.
   - `fpengine-stderr`: loops on `availableData`, appends to `StderrRing`, and splits lines for `logHandler`. A line longer than 64 KiB is forwarded in chunks, so a newline-free helper log cannot grow the pending buffer without bound. All bytes are forwarded (UTF-8 is decoded lossily per chunk).
4. **SIGPIPE.** The first `EngineClient.init` calls `Signals.ignoreSIGPIPE()` (`signal(SIGPIPE, SIG_IGN)`, once), so a helper that exits early can never kill the app through a write.
   **Signal mask.** `Process.run()` runs inside `Signals.withUnblockedSignals` (`pthread_sigmask` with an empty set, restored afterwards). swift-corelibs-foundation hands the spawning thread's mask to the child, and dispatch worker threads block SIGTERM. Without this, on Linux the helper never sees a graceful cancel and every stop waits for the SIGKILL escalation.
5. **Decoding** (`EventDecoder`, plain `JSONDecoder()`, H10):
   - Decode `Envelope {protocol: Int; type: String}`. Failure → `.protocolViolation("not a JSON event: <first 200 bytes>")`.
   - `protocol != supportedProtocol` → `.incompatibleHelper(reported:supported:)`.
   - Then decode by `type`: `progress` → `EngineProgress`; `face` → `{face: FaceRecord}`; `file_error` → `ScanFileError`; `hello` → `EngineHello`; `result` → `{command, summary?, report?}`; `error` → `HelperFailure`.
   - An unknown `type` is skipped for forward compatibility and logged. Each skip is also counted in `EngineClient.skippedUnknownEventCount`, which is always observable even without a `logHandler` (no silent drops). (`helloFromFakeHelper`, `scanIdleResetsForUnknownLines`)
   - A known type that does not belong to the command (e.g. `face` during `forge`), or a `result` whose `command` differs → `.protocolViolation`.
   - A decoding failure of a known type → `.protocolViolation` naming the type and the `DecodingError`.
6. **Terminal event.** On `result`, yield `.finished(...)`. On `error`, remember `.helperFailed(failure)`. Ignore any later stdout. Then wait for the process to exit; if it does not exit within `terminationGrace`, run the termination sequence (step 8). The terminal event decides the outcome whatever the exit code; a mismatch is only logged.
7. **End of run.** A run is complete when the process has exited **and** stdout has reached EOF. If EOF has not come 1 s after exit (a grandchild holds the pipe), stop waiting and carry on, but **do not close the read handle from another thread**: on Linux `close()` does not wake a thread blocked in `read()`, and the freed fd number could be reused and read by the wrong owner. The reader thread keeps running until its own EOF, discards whatever it reads after the run is complete, and releases its handle when it exits. A buffered partial line at that point is a `.protocolViolation("truncated line")`, unless the run was cancelled. `LineFramer.Error.lineTooLong` is `.protocolViolation("line longer than 32 MiB")`, followed by the termination sequence. Then finish the stream:

   | Situation | Stream ends with |
   |---|---|
   | `result` received | normal finish, after `.finished` |
   | `error` received | `finish(throwing: .helperFailed)` |
   | cancelled by the consumer | normal finish (no error) |
   | timeout fired | `finish(throwing: .timedOut(after:stderrTail:))` |
   | no terminal event, exit 0 | `.protocolViolation("helper exited without a result")` |
   | no terminal event, exit 143 or 130, or signal TERM/INT/KILL/HUP | `.interrupted(...)` |
   | no terminal event, anything else | `.crashed(exitCode:signal:stderrTail:)` |

   `terminationReason == .uncaughtSignal` means `terminationStatus` is the signal number. `stderrTail` is the ring decoded with `String(decoding:as: UTF8.self)`.
8. **Termination sequence** (cancel, timeout, or lingering after the terminal event), once per run:
   - If the process has not exited: `Signals.send(SIGTERM, to: pid)`, then schedule `SIGKILL` after `terminationGrace` if it still has not exited (checked under the lock, so pid reuse cannot hit another process).
   - After the exit, if no terminal event was received:
     - remove `TMPDIR/fpengine-<pid>-*`, if `temporaryDirectory` is set;
     - for `forge`, remove `<dir of output_path>/.fpengine-<pid>-*.partial.ttf`.
   - Never remove `output_path` itself.
9. **Cancellation.** `continuation.onTermination = { if case .cancelled = $0 { run.cancel() } }`. The stream is `.cancelled` both when the consuming `Task` is cancelled and when the iterator or stream is dropped early. `hello()` uses `withTaskCancellationHandler` the same way.
10. **Timeouts.**
    - `hello` and `forge`: one child `Task` sleeps for the whole-run limit.
    - `scan`: the idle deadline is reset on every stdout line.
    - On expiry: mark the run timed out, then run the termination sequence.
11. **Hello gate.** `scan` and `forge` first `await gate.verify(self)`. `gate` is an internal actor that runs `hello()` once per `EngineClient` and caches the outcome:
    - Cached: a success, `.incompatibleHelper`, and a hello without the capabilities `scan` and `forge`, which becomes `.protocolViolation("helper lacks capability 'scan'", stderrTail: "")` (or `'forge'`).
    - Not cached (the next call runs `hello` again): every other error, for example `.timedOut`, `.crashed`, `.interrupted`, `.launchFailed`, `.helperFailed` or a decoding `.protocolViolation`.
    - Concurrent callers share one in-flight hello: the actor keeps the running `Task` and every caller awaits it.
    - A cancelled caller withdraws from the in-flight hello. Once no callers remain, the gate cancels that hello; cancelling one caller does not terminate a hello still needed by another.
    - A successful direct `hello()` call also fills the cache.

    A gate failure is thrown by the stream before any process for the command starts.
12. **Requests.**
    - `scan`: `{"files": [...]}` from an internal `Encodable`.
    - `forge`: `request.encodedJSON()` (FPCore, core.md §8). The materials carry `expect` from their `FaceRecord` (WP-303 `forgeRequest(outputPath:)`).
    - `hello`: `{}`.
    - Encoding failure → `.launchFailed("could not encode the request: …")` before launch.

**4. Helpers**
- `LineFramer`:
  - `mutating func append<D: DataProtocol>(_ chunk: D) throws -> [Data]` returns complete lines without `\n`, drops empty lines, and throws `.lineTooLong` over 32 MiB. Buffer compaction is amortised O(n): keep a read index, and compact when more than half the buffer is consumed.
  - `mutating func finish() -> Data?` returns the pending partial line.
  - A trailing `\r` is left for `JSONDecoder`, which treats it as whitespace.
- `StderrRing(capacity:)`: `append(_:)`, `tail: String`, `byteCount: Int`. It keeps the last `capacity` bytes.
- `Signals` (`enum`): `send(_ signal: Int32, to pid: Int32)`, `isAlive(_ pid: Int32) -> Bool` (`kill(pid, 0) == 0 || errno == EPERM`), `ignoreSIGPIPE()`. This is the only file that imports Glibc or Darwin (AGENTS.md hard rule 2).
- `sweepLeftovers` implements H7 with `FileManager` only. It matches `^fpengine-(\d+)-` and `^\.fpengine-(\d+)-.*\.partial\.ttf$`, and removes an entry when its pid is not alive **or** its modification date is more than 24 h before `now`. Failures are ignored and logged.

**5. Fake helper** (`Tests/FPEngineClientTests/Resources/fake-fpengine.sh`, POSIX `sh`, launched as `EngineLaunch(executableURL: /bin/sh, arguments: [<script path>])`, so no exec bit is needed)

The script reads the scenario from `FAKE_SCENARIO`. When `$FAKE_RECORD` is set it appends three lines to it, `argv:$1`, `tmpdir:$TMPDIR` and `stdin:<request>` (the request read with `cat`), except in the `early_exit` command run, which reads nothing (its `hello` run behaves normally). Scenarios apply to the `scan`/`forge` invocation, with three exceptions that apply to `hello`: those named `hello_*`, `stderr_flood` and `unknown_type`. Any other `hello` invocation prints the `hello_ok` lines and exits 0, so the client's hello gate passes before the scenario runs. It emits lines built from `spec/protocol/examples/*.jsonl` (copied into the script as literals). Long waits use `sleep N >/dev/null 2>&1 & pid=$!; trap 'echo TERM >> "${FAKE_RECORD:-/dev/null}"; kill $pid; exit 143' TERM; wait $pid`, so the pipes are not held by the sleeping child (verified: a background `sleep` that keeps stdout open delays EOF until it ends).

| Scenario | Behaviour |
|---|---|
| `hello_ok` / `hello_v2` | hello lines with protocol 1 / with `"protocol":2` |
| `scan_ok` | `scan.jsonl` |
| `forge_ok` / `forge_error` | `forge-ok.jsonl` / `forge-error.jsonl`, exit 0 / 3 |
| `split` | one event written in 3 `printf` chunks with 0.1 s sleeps, then two events in one `printf`, then `result` |
| `big_line` | a `face` event with a 2 MiB `local_names` array, then `result` |
| `garbage` | `not json` |
| `no_terminal` | one progress line, exit 0 |
| `crash` | one stderr line `fake: about to crash`, then `kill -SEGV $$` |
| `slow` | one progress line, then the TERM-aware wait (60 s) |
| `ignore_term` | `trap '' TERM`; creates `$TMPDIR/fpengine-$$-x/` and `$FAKE_OUTDIR/.fpengine-$$-x.partial.ttf`; one progress line; busy `sleep 0.1` loop for 30 s |
| `stderr_flood` | 1 MiB to stderr (`dd if=/dev/zero bs=1024 count=1024 \| tr '\0' x >&2`), then the hello lines |
| `early_exit` | exits 3 at once without reading stdin |
| `unknown_type` | `{"protocol":1,"type":"future_thing"}` before the normal hello lines |

**6. Test layout**
- A test-side `RepoPaths.root` walks up from `#filePath` until it finds `spec/protocol`. It is used to read `spec/protocol/examples` and `examples/`.
- Real-helper tests use `@Test(.enabled(if: ProcessInfo.processInfo.environment["FP_ENGINE_PYTHON"] != nil))` and get fonts from `"$FP_ENGINE_PYTHON" -m fpengine.testing.make_fonts <tmp>` (WP-202).

### Acceptance criteria
All tests are Swift Testing in `Packages/FontPlaygroundKit/Tests/FPEngineClientTests/`. Time limits assume a Codex Linux container.

- **AC-204-1** `LineFramer` yields the same 3 lines for every split point of a 3-line byte stream (each byte offset, and single-byte chunks). It skips empty lines, `finish()` returns the trailing partial line, and more than 32 MiB throws `.lineTooLong`. Verified by `lineFramerHandlesEverySplitPoint`.
- **AC-204-2** `StderrRing(capacity: 16)` keeps the last 16 bytes of any input and decodes invalid UTF-8 lossily. Verified by `stderrRingKeepsTail`.
- **AC-204-3** Every line of `spec/protocol/examples/*.jsonl` decodes to the expected case, using FPCore's `FaceRecord` and `ForgeReport`. A `protocol: 2` envelope gives `.incompatibleHelper(reported: 2, supported: 1)`, `not json` gives `.protocolViolation`, and an unknown `type` is skipped. Verified by `decodesProtocolExamples`.
- **AC-204-4** Resolution order holds with temporary folders and fake executables:
  - `Contents/Helpers/…` beats `Contents/Resources/…` (`source == .bundled`), which beats `FP_ENGINE_PYTHON` (`source == .environment`);
  - a non-executable file is skipped;
  - with nothing found, `.helperNotFound` lists every path searched.

  Verified by `resolvesBundledHelperFirst`, `fallsBackToFPEnginePython` and `reportsHelperNotFound`.
- **AC-204-5** `hello()` against `hello_ok` returns the example's `EngineHello`, including `faceReaderVersion`. Against `unknown_type` it returns the same value (the unknown line is skipped). Against `hello_v2` it throws `.incompatibleHelper(reported: 2, supported: 1)`. Verified by `helloFromFakeHelper`.
- **AC-204-6** `scan(files:)` against `scan_ok` yields `progress`, `face`, `face`, `face`, `fileError`, `fileError`, `progress`, `finished` in that order. `FAKE_RECORD` shows `argv:hello`, then `argv:scan` with stdin `{"files":[…]}` holding the paths in the given order. Both runs recorded `tmpdir:<the configured temporaryDirectory path>`, a folder that did not exist before and was created by the client. Verified by `scanStreamsEventsInOrder` and `writesRequestArgumentsAndEnvironment`.
- **AC-204-7** `forge` against `forge_ok` ends with `.finished(report)` equal to the example's report. Against `forge_error` it throws `.helperFailed(HelperFailure(code: .staleMaterial, stage: .validate, materialIndex: 1, …))`. Verified by `forgeFinishesOrThrowsHelperFailure`.
- **AC-204-8** `split` and `big_line` decode correctly. Verified by `decodesSplitAndLargeLines`.
- **AC-204-9 (NATIVE-7)** With `slow`, cancelling the consuming `Task` after the first progress event does four things: the stream ends **without throwing**, `FAKE_RECORD` contains `TERM`, the process has exited, and the stream finishes within 0.5 s of the cancel. Verified by `native7CancelSendsSigterm`.
- **AC-204-10 (NATIVE-7)** With `ignore_term`, a `forge` whose `outputPath` is `$FAKE_OUTDIR/out.ttf` (the test sets `FAKE_OUTDIR` through `launch.environment`) and a configured `temporaryDirectory`: a cancel after the first progress event is followed by SIGKILL after `terminationGrace` (2 s). The stream finishes between 1.8 s and 3.5 s after the cancel. Afterwards the fake's `fpengine-<pid>-x` folder and `.fpengine-<pid>-x.partial.ttf` file are gone. Verified by `native7EscalatesToSigkillAndCleansLeftovers`.
- **AC-204-11** A `forge` run on `slow`, with `timeouts.forge = .milliseconds(500)`, throws `.timedOut` within 3.5 s. A `scan` run on `slow`, with `scanIdle = .milliseconds(500)`, does the same. Verified by `timeoutsTerminateTheHelper`.
- **AC-204-12** The end-of-run table holds:
  - `crash` throws `.crashed(exitCode: nil, signal: 11, …)`, with `stderrTail` containing `fake: about to crash`;
  - `no_terminal` throws `.protocolViolation`;
  - `early_exit` with an 8 MiB request (`scan(files:)` with 40,000 paths of 210 bytes each) throws `.crashed(exitCode: 3, …)`, and the test process survives (SIGPIPE ignored);
  - `garbage` throws `.protocolViolation`.

  Verified by `classifiesAbnormalEnds`.
- **AC-204-13** `hello()` against `stderr_flood` returns within 5 s with no deadlock. `logHandler` receives lines, and the ring holds exactly `stderrCapacity` bytes, checked through an internal accessor visible to `@testable import`. Verified by `drainsStderrFlood`.
- **AC-204-14** Two `scan` calls on one client record exactly one `argv:hello`. On a `hello_v2` helper, `scan` throws `.incompatibleHelper` and records no `argv:scan`. Verified by `helloGateRunsOnceAndBlocksIncompatibleHelpers`.
- **AC-204-15** `sweepLeftovers` handles these entries:
  - removes `fpengine-<dead pid>-a` (the pid of a child that already exited) and `.fpengine-<dead pid>-b.partial.ttf` in an output folder;
  - removes an entry for a live pid whose modification date is more than 24 h old (`now` injected);
  - keeps `fpengine-<own pid>-c` and `unrelated.txt`;
  - returns 3.

  Verified by `sweepRemovesOnlyDeadRuns`.
- **AC-204-16** Real helper (`FP_ENGINE_PYTHON` set by `make`):
  - `hello().protocolVersion == 1`;
  - `scan` of the 9 font files listed in `fonts.json` (not `fonts.json` itself) yields 9 `.face` events and one `.fileError(code: .unreadable)` for `NotAFont.ttf`, then `.finished` with `files == 9`;
  - `forge` of FixtureSans-Regular + FixtureCJK-Regular (a `ForgeRequest` built from the scanned `FaceRecord`s, with `expect`), with `han`/`kana`/`cjk_symbols` ruled to material 1, finishes with `report.totalCodepoints == 3650` and material codepoints `[240, 3410]`, and the output file exists;
  - the same forge with material 1's `expect.size` changed throws `.helperFailed` with `code == .staleMaterial` and `materialIndex == 1`.

  Verified by `realHelperEndToEnd`.
- **AC-204-17** With `slow` and a `processObserver`, the observer receives `.launched(pid, "hello")`, `.exited(...)`, `.launched(pid2, "scan")`, and after a cancel `.exited(pid2, exitCode: 143, signal: nil)`, in that order. `Signals.isAlive(pid2)` is false once the stream has ended. Verified by `processObserverReportsLaunchAndExit`.
- **AC-204-18** `grep -rE '^import ' Packages/FontPlaygroundKit/Sources/FPEngineClient` shows only `Foundation` and `FPCore`, plus `Glibc`/`Darwin` in `Signals.swift` inside the allowed `#if canImport` block.
- **AC-204-19** `make lint` and `make kit-test` pass on Linux. The fake-helper tests take under 30 s in total.
- **AC-204-20** The fake's literal lines have not drifted from the examples: running `fake-fpengine.sh` directly (through `Process`) with `hello_ok`, `scan_ok`, `forge_ok` and `forge_error` prints exactly the bytes of `hello.jsonl`, `scan.jsonl`, `forge-ok.jsonl` and `forge-error.jsonl`. Verified by `fakeHelperMatchesProtocolExamples`.

### Verification
```bash
make lint
make kit-test          # FP_ENGINE_PYTHON is exported by make, so realHelperEndToEnd runs too
swift test --package-path Packages/FontPlaygroundKit --filter FPEngineClientTests
```

### Notes for the implementer
- Plan's dependency list is 001 and 201, but the wire types `FaceRecord`, `ForgeRequest` and `ForgeReport` come from FPCore (WP-301), and the real-helper test needs `make_fonts` (WP-202). Dispatch after both are merged (backbone issue filed).
- Use `write(contentsOf:)` and `close()`, which throw. Never use the deprecated `write(_:)`/`closeFile()`: on Darwin they raise uncatchable Objective-C exceptions on EPIPE.
- `Synchronization.Mutex` needs macOS 15, and the deployment target is 14. Use `NSLock` (available on Linux too).
- Never call `Process.terminate()` after an exit. Send signals through `Signals.send` under the lock, and only while the run is not marked exited.
- Do not block Swift-concurrency threads with pipe reads. Use the named `Thread`s.
- Prototype evidence (non-normative, macOS): the `Process` + `Pipe` + `availableData` loop split lines correctly across partial writes; SIGTERM was honoured in about 0 ms; SIGKILL was needed after exactly 2.0 s with `trap '' TERM`; 1 MiB of stderr drained without a stall.

---

## WP-205: `fpctl` headless CLI + example recipes

**Goal:** `fpctl`, a Foundation-only command-line tool with the subcommands `hello`, `scan <files…>` and `forge <recipe.fontrecipe> --out <file>`. It drives the helper through `FPEngineClient` and `FPCore`, and is the end-to-end test of the headless pipeline on Linux. Two example recipes ship with it.
**Depends on:** WP-204, WP-305 · **Env:** linux · **Size:** S · **Closes findings:** —

### Scope
- In:
  - the `fpctl` executable target (hand-rolled argument parsing, no swift-argument-parser, per ADR-0005);
  - text and JSON output;
  - exit codes;
  - SIGINT/SIGTERM handling;
  - recipe loading and material resolution;
  - `examples/latin-cjk.fontrecipe`, `examples/fixtures/latin-cjk.fontrecipe` and `examples/README.md`;
  - `FPCTLTests`.
- Out:
  - the `RecipeDocument` format and its resolution rules (WP-305, core.md);
  - ForgeSpec emission (WP-303);
  - CoreText discovery (WP-401); `fpctl` never uses CoreText.

### Touched paths
- `Packages/FontPlaygroundKit/Sources/fpctl/FPCTL.swift` (rewrite of WP-001's placeholder: `@main`, `run`, `interrupt`, and the only `#if canImport(Glibc) import Glibc #elseif canImport(Darwin) import Darwin #endif` block of the target, for `signal`)
- `Packages/FontPlaygroundKit/Sources/fpctl/main.swift` (delete: `@main` replaces it; an executable target cannot have both)
- `Packages/FontPlaygroundKit/Tests/FPCTLTests/PlaceholderTests.swift` (delete: its `FPCTL.run(_:) -> (status, output)` API is gone; `usageErrorsAndHelp` covers `--version` and unknown arguments, which now exit 2, not 64)
- `Packages/FontPlaygroundKit/Sources/fpctl/CommandLine+Parse.swift` (new)
- `Packages/FontPlaygroundKit/Sources/fpctl/Commands.swift` (new)
- `Packages/FontPlaygroundKit/Sources/fpctl/Output.swift` (new)
- `Packages/FontPlaygroundKit/Sources/fpctl/FontFolders.swift` (new)
- `Packages/FontPlaygroundKit/Tests/FPCTLTests/*.swift` (new)
- `examples/latin-cjk.fontrecipe`, `examples/fixtures/latin-cjk.fontrecipe`, `examples/README.md` (new)

### Design

**1. Entry and testability**

```swift
@main struct FPCTL {
  static let version = "0.1.0"
  static func main() async                   // installs signal sources, calls run, exit(code)
  static func run(_ arguments: [String], environment: [String: String], currentDirectory: String,
                  output: CommandOutput,
                  makeEngine: @escaping @Sendable (_ invocation: Invocation, _ environment: [String: String],
                                         _ output: CommandOutput) throws -> EngineHandle
                    = FPCTL.defaultEngine) async -> Int32
  static func interrupt()                    // cancels the running command's Task (signal sources and tests call it)
  static func defaultEngine(_ invocation: Invocation, _ environment: [String: String],
                            _ output: CommandOutput) throws -> EngineHandle
}
struct EngineHandle: Sendable {
  var engine: any EngineRunning
  var helper: String                         // "<executable path> <arguments…>", shown by `hello`; fakes pass "fake"
  var temporaryDirectory: URL?               // swept with EngineClient.sweepLeftovers after forge; nil for fakes
}
/// Each call prints one line: the string plus "\n". `out` is stdout, `err` is stderr.
struct CommandOutput: Sendable { var out: @Sendable (String) -> Void; var err: @Sendable (String) -> Void }
```

`defaultEngine`:
- `invocation.enginePath` (`--engine <python>`) given: `EngineLaunch(executableURL: URL(fileURLWithPath: <absolute path>))` (`source == .explicit`).
- Otherwise `try EngineLaunch.resolve(environment: environment, bundleURL: nil)`: `fpctl` is not a bundle, so only `FP_ENGINE_PYTHON` is looked at. `.helperNotFound` is thrown on to `run` (exit 3, `fpctl: can't find the font engine; set FP_ENGINE_PYTHON or pass --engine`).
- `temporaryDirectory` = `<NSTemporaryDirectory()>/fpctl`, created if missing. `run` calls `EngineClient.sweepLeftovers(temporaryDirectory:outputDirectories: [<dir of --out>])` once before a forge and once after it (H7).
- `EngineClient(configuration: EngineConfiguration(launch:, temporaryDirectory:))`, with `logHandler` set to `output.err` only when `invocation.verbose` is true (nil otherwise).
- `makeEngine` is not called for `help`, `version` and usage errors.

`interrupt()` cancels the `Task` stored in a lock-protected static box (`final class TaskBox: @unchecked Sendable` with an `NSLock`; Swift 6 rejects a plain mutable `static var`). `run` stores its command `Task` there and sets an `interrupted` flag in the same box. When a stream ends without `.finished` and `interrupted` is set, `run` returns 130. When it ends without `.finished` and the flag is not set (it should not happen: the client only ends silently on cancel), `run` prints `fpctl: the font engine stopped without a result` and returns 3.

`FPCTLTests` uses `@testable import fpctl`, which works for executable targets (verified with SwiftPM on macOS; supported on Linux). It calls `run` with captured output and either a fake `EngineRunning` or the real client. If `@testable import` of the executable fails on the Linux toolchain, split the code into a library target `FPCTLCore` and a thin `fpctl`, and record the deviation.

**2. Command line** (parsed by `static func parse(_ args: [String], currentDirectory: String) throws(UsageError) -> Invocation`)

```swift
struct Invocation: Equatable { var enginePath: String?; var verbose: Bool; var command: Command }
enum Command: Equatable {
  case help, version
  case hello(json: Bool)
  case scan(paths: [String], json: Bool)
  case forge(recipe: String, out: String, fontDirectories: [String], allowMissing: Bool, json: Bool, quiet: Bool)
}
enum UsageError: Error, Equatable {
  case missingCommand, unknownCommand(String), unknownOption(String), missingValue(String)
  case missingArgument(String), unexpectedArgument(String), optionNotAllowed(option: String, command: String)
}
```

- Options may come before or after the command. Both `--opt value` and `--opt=value` are accepted, and `--` ends option parsing.
- `-h`/`--help` anywhere means `.help`. `--version` means `.version`.
- Every path argument becomes absolute and standardised: `URL(fileURLWithPath: arg, relativeTo: URL(fileURLWithPath: currentDirectory)).standardizedFileURL.path`, with no symlink resolution.
- `forge` requires exactly one recipe and `--out`.
- `scan` requires at least one path.
- The usage text (printed by `--help` to stdout, exit 0) is normative:

```
Usage: fpctl [--engine <python>] [--verbose] <command> [options]

Commands:
  hello                        Show the font engine's version.
  scan <file|folder>...        Read fonts and list their faces.
  forge <recipe.fontrecipe> --out <file.ttf>
                               Build the font a recipe describes.

Options:
  --engine <python>            Python that can run fpengine (default: $FP_ENGINE_PYTHON).
  --verbose                    Show the engine's log on stderr.
  --json                       Print JSON instead of text.
  --font-dir <folder>          forge: where to look for fonts the recipe can't find. Repeatable.
  --allow-missing              forge: build without fonts that can't be found.
  --quiet                      forge: don't print progress.
  -h, --help                   Show this help.
  --version                    Show fpctl's version.

Exit status: 0 success, 1 the engine reported an error, 2 usage or input error,
3 the engine could not run, 4 fonts not found, 130 interrupted.
```

A usage error prints `fpctl: <message>` and then `Run 'fpctl --help' for usage.` to stderr, and exits 2.

**3. Exit codes**

| Code | When |
|---|---|
| 0 | success (a `scan` with `file_error`s is still a success; the errors are printed) |
| 1 | `EngineError.helperFailed` (the engine's `error` event) |
| 2 | usage error; unreadable recipe file; not a valid RecipeDocument v1 |
| 3 | `helperNotFound`, `launchFailed`, `incompatibleHelper`, `protocolViolation`, `crashed`, `timedOut`, or `interrupted` not caused by fpctl |
| 4 | recipe materials unresolved and `--allow-missing` not given |
| 130 | SIGINT or SIGTERM received by fpctl: the running task is cancelled, the helper gets SIGTERM, and fpctl exits when the stream ends |

Signals: `signal(SIGINT, SIG_IGN)` and `signal(SIGTERM, SIG_IGN)`, plus a `DispatchSource.makeSignalSource` for each that calls `FPCTL.interrupt()`, which cancels the running command's `Task`. The helper may also receive the terminal's SIGINT; its exit 130 during an fpctl-initiated cancel is expected.

**4. `hello`**
- Text (stdout):

  ```
  fpengine <v> · protocol <n> · Python <v> · fontTools <v> · Unicode <v> · <platform>
  helper: <EngineHandle.helper>
  ```

- `--json`: the `EngineHello`, encoded with H10 keys, as one JSON object.

**5. `scan <file|folder>...`**
- Folders are walked recursively with the URL-based `FileManager.default.enumerator(at:includingPropertiesForKeys:options:errorHandler:)` so unreadable folders are reported rather than silently omitted (architecture §8). It keeps files whose lowercased extension is `ttf`, `otf`, `ttc` or `otc`, and, among the entries it walks, skips any whose name starts with `._` or equals `__MACOSX` or `.Trashes`, together with its contents. Paths named on the command line are never filtered: a file goes to the helper, which reports it if it is not a font, and a folder is walked (`explicitlyNamedPathsAreNeverFilteredOut`). Paths are sorted byte-wise per folder; explicit files keep command-line order. Duplicates are left for the helper, which counts them.
- Folder traversal failures are included as `io_error` entries in `file_errors` and printed to stderr; each adds one to `summary.files` and `summary.file_errors`, including a failed folder with no discovered files. A scan still exits 0.
- Text: one stdout line per face: `<path>#<index>\t<postscript_name or ->\t<family> <style>\t<N> characters\t<group ids, comma-separated>`, plus `\t[unsupported: <reason>]` and `\t[hidden]` when they apply. Each `file_error` goes to stderr as `fpctl: <path>: <message> (<code>)`. Last, stderr gets `Scanned <files> files: <faces> faces, <n> couldn't be read.`
- `--json`: one object, `{"faces": [FaceRecord…], "file_errors": [{path, code, message}…], "summary": {files, faces, file_errors, duplicates}}`. Face records are re-encoded from `FPCore.FaceRecord` (this exercises the Codable round trip).

**6. `forge <recipe> --out <file>`**
1. Read the recipe. A missing file or I/O error → exit 2 with `fpctl: <path>: <reason>`. Decode with `RecipeDocument.decode(_:)` (core.md WP-305). A `RecipeDocumentError` → exit 2 with `fpctl: <path>: not a valid Font Playground recipe (<error>)`.
2. **Candidates, round 1.** `scan` the recipe's material paths that exist on disk.
3. **Resolve.** Drop hidden faces, then build `FaceCatalog(candidates)` in scan order, and call `document.makeRecipe(catalog:)`. It resolves by path+index (PostScript name must match), then PostScript name, then family+style (contracts.md §8). Among candidates with the same PostScript name, the first in scan order wins. The unresolved materials are `report.unresolved` of the returned `(recipe, report)` (the `.notFound` outcomes).
4. **Candidates, round 2** (only if something is unresolved).
   - Scan `--font-dir` folders, walked as in §5. Without `--font-dir`, scan the default folders that exist, in this order:
     1. `/System/Library/Fonts`
     2. `/Library/Fonts`
     3. `$HOME/Library/Fonts`, with `HOME` taken from `run`'s `environment` argument
     4. every `/System/Library/AssetsV2/com_apple_MobileAsset_Font*` folder, sorted

     This is a runtime existence check, not a platform conditional (AGENTS.md hard rule 2).
   - Print `Looking for <n> missing font(s) in <k> folder(s)…` to stderr, then resolve again with round-1 and round-2 candidates.
After the final resolution, print every ignored rule, duplicate material and out-of-range main index to stderr before building (architecture §8, no silent drops).

5. **Still unresolved.**
   - Without `--allow-missing`: print `fpctl: can't find these fonts:` and then one `  <family> <style> (PostScript <name>)` line per material to stderr, and exit 4. No forge runs.
   - With `--allow-missing`: print the same list as `fpctl: warning: building without: …` and go on.
6. With `--allow-missing`, call `recipe.remove(material.key)` (core.md WP-303) for each material whose `availability == .notFound`, the user having asked for exactly that. Then call `recipe.forgeRequest(outputPath:)` with the standardised `--out`, and run `engine.forge`. `fpctl` does not check `recipe.canForge`: the engine validates the request and its `error` event is reported as in step 9.
7. **Progress** (stderr, unless `--quiet`): one line whenever `(stage, materialIndex)` changes, formatted `[<pct>%] <text>`, where `<pct>` is `Int((fraction * 100).rounded())` right-aligned in 3 characters (`[ 70%] Combining the fonts…`). The texts are those of `reference/.../ui/model.py:50-63`, plus `validate`; the display name in `prepare` is `"<family> <style>"` of the recipe material at `materialIndex`:

   | Stage | Text |
   |---|---|
   | validate | `Checking the fonts…` |
   | plan | `Deciding which font supplies each character…` |
   | prepare | `Preparing <material display name>…` |
   | merge | `Combining the fonts…` |
   | finish | `Finishing the font…` |
   | verify | `Checking the result…` |
   | done | `Done.` |

8. **Report.** Text on stdout, modelled on `reference/.../engine/spec.py:120-129`:

   ```
   Output: <path>
   Font: <full_name> (PostScript <postscript_name>)
   Characters: <total_codepoints>   Glyphs: <total_glyphs>

   <material name>: <n> characters  [<group labels, comma-separated, or ->]
       warning: <each material warning>

   Warnings:            (only if any)
     - <line>
   Licence:             (only if any)
     - <licence_notes[i].text>
   Built in <duration_s, 1 decimal> s.
   ```

   Group labels come from FPCore's `EnglishText.groupLabel(_:)` (core.md §9, `reference/.../engine/scripts.py:16-32`) for ids that `ScriptGroup(rawValue:)` knows; an unknown id is printed as is. The `Built in` line is left out when `duration_s` is absent.
   With `--json`: one object, `{"report": ForgeReport, "unresolved": [{"postscript_name", "family", "style"}]}`.
9. **Failure.** `.helperFailed(f)` → stderr `fpctl: forge failed (<code>, <stage or ->): <message>`, exit 1. With `--verbose`, `detail` follows.

**7. Example recipes** (RecipeDocument v1, contracts.md §8; exact content)

`examples/latin-cjk.fontrecipe` (macOS; Helvetica Neue + PingFang SC). The PingFang path deliberately carries a placeholder asset hash. It resolves by PostScript name through the default folders; that is the CATALOG-7/ENGINE-8 path in practice.

```json
{
  "format": "fontrecipe",
  "version": 1,
  "materials": [
    {"face": {"postscript_name": "HelveticaNeue", "family": "Helvetica Neue", "style": "Regular",
              "path": "/System/Library/Fonts/HelveticaNeue.ttc", "index": 0},
     "weight": null, "scale": null},
    {"face": {"postscript_name": "PingFangSC-Regular", "family": "PingFang SC", "style": "Regular",
              "path": "/System/Library/AssetsV2/com_apple_MobileAsset_Font8/0000000000000000000000000000000000000000.asset/AssetData/PingFang.ttc",
              "index": 3},
     "weight": null, "scale": null}
  ],
  "main": 0,
  "rules": {"han": 1, "cjk_symbols": 1},
  "defaults": {"weight": null, "scale": 1.0},
  "names": {"family": "Helvetica Neue PingFang SC", "style": "Regular", "family_edited": false, "style_edited": false},
  "sample_text": "The quick brown fox jumps over the lazy dog 0123456789\n你好，世界！欢迎使用字体游乐场。"
}
```

`examples/fixtures/latin-cjk.fontrecipe` (H11 fonts; the paths deliberately do not exist, so resolution goes by PostScript name through `--font-dir`):

```json
{
  "format": "fontrecipe",
  "version": 1,
  "materials": [
    {"face": {"postscript_name": "FixtureSans-Regular", "family": "Fixture Sans", "style": "Regular",
              "path": "/fixtures/FixtureSans-Regular.ttf", "index": 0}, "weight": null, "scale": null},
    {"face": {"postscript_name": "FixtureCJK-Regular", "family": "Fixture CJK", "style": "Regular",
              "path": "/fixtures/FixtureCJK-Regular.otf", "index": 0}, "weight": null, "scale": null}
  ],
  "main": 0,
  "rules": {"han": 1, "kana": 1, "cjk_symbols": 1},
  "defaults": {"weight": null, "scale": 1.0},
  "names": {"family": "Fixture Sans CJK", "style": "Regular", "family_edited": true, "style_edited": false},
  "sample_text": "Hello 你好 こんにちは"
}
```

`examples/README.md` explains both files and gives the two commands from Verification.

### Acceptance criteria
All tests are Swift Testing in `Packages/FontPlaygroundKit/Tests/FPCTLTests/`. "Real helper" tests are `.enabled(if:)` on `FP_ENGINE_PYTHON`, which `make kit-test` sets. They get fonts from `$FP_ENGINE_PYTHON -m fpengine.testing.make_fonts <tmp>`.

- **AC-205-1** `parse` maps at least these argument lists correctly:
  - `[]` → `.missingCommand`
  - `["frob"]` → `.unknownCommand`
  - `["forge","r.fontrecipe"]` → `.missingArgument("--out")`
  - `["forge","r.fontrecipe","--out"]` → `.missingValue("--out")`
  - `["scan"]` → `.missingArgument`
  - `["hello","--font-dir","x"]` → `.optionNotAllowed`
  - `["--engine=/p","scan","a.ttf","--json"]`
  - `["forge","--out=o.ttf","r.fontrecipe","--font-dir","d1","--font-dir","d2"]`
  - `["scan","--","--weird.ttf"]`
  - `["hello","-h"]` → `.help`

  Relative paths become absolute under `currentDirectory`, and `..` is removed. Verified by `parsesCommandLines` (table-driven).
- **AC-205-2** Every `UsageError` exits 2, and its stderr ends with `Run 'fpctl --help' for usage.`. `--help` prints exactly the usage text of Design §2 and exits 0. `--version` prints `fpctl 0.1.0`. Verified by `usageErrorsAndHelp`.
- **AC-205-3** With a fake `EngineRunning` (an `EngineHandle` with `helper: "fake"`), and `--font-dir <an empty temporary folder>` on every forge so that no default font folder is read (AGENTS.md rule 3):
  - a forge whose recipe cannot be resolved exits 4, lists `Fixture Missing Regular (PostScript FixtureMissing-Regular)`, and makes no `forge` call;
  - `--allow-missing` makes the call with one material;
  - `helperFailed` exits 1 with `fpctl: forge failed (unsupported_font, validate): …`;
  - `.helperNotFound` exits 3;
  - calling `FPCTL.interrupt()` while the fake forge is waiting makes `run` return 130 within 1 s.

  Verified by `forgeFlowsWithFakeEngine`.
- **AC-205-4** Real helper: `hello` exits 0 and its first stdout line starts with `fpengine `. `hello --json` decodes as `EngineHello` with `protocolVersion == 1`. Verified by `helloPrintsEngineVersion`.
- **AC-205-5** Real helper: `scan <fonts dir>` exits 0 with 9 face lines on stdout, and stderr contains `NotAFont.ttf` and `(unreadable)`. `scan --json <fonts dir>` gives a JSON object with 9 `faces`, 1 `file_errors` entry and `summary.files == 9`. Verified by `scanListsFixtureFaces`.
- **AC-205-6** Real helper, end to end on Linux:
  - `forge examples/fixtures/latin-cjk.fontrecipe --font-dir <fonts dir> --out <tmp>/out.ttf --json` exits 0;
  - the report has `total_codepoints == 3650` and materials with `codepoints` `[240, 3410]`;
  - `<tmp>/out.ttf` exists;
  - `scan --json <tmp>/out.ttf` returns one face with family `Fixture Sans CJK`, `is_forged == true` and 3,650 covered code points.

  Verified by `forgeFixtureRecipeEndToEnd`.
- **AC-205-7** Real helper: a recipe written by the test whose only material is `FixtureColor-Regular` at its real path in the fonts folder (so it resolves by path in round 1) exits 1, and stderr contains `fpctl: forge failed (unsupported_font, validate):`. Verified by `engineErrorExits1`.
- **AC-205-8** Both example recipes decode with `RecipeDocument.decode(_:)`. The macOS example's identities are exactly `HelveticaNeue` / `/System/Library/Fonts/HelveticaNeue.ttc#0` and `PingFangSC-Regular` / index 3 (verified against the fonts of a macOS 27 Mac). Verified by `exampleRecipesDecode`. Real helper: `makeRecipe(catalog:)` over a `FaceCatalog` of the scanned H11 folder resolves the fixtures example with outcomes `[.byPostScriptName, .byPostScriptName]` and an empty `report.unresolved`. Verified by `fixtureRecipeResolvesByPostScriptName`.
- **AC-205-9** `grep -rE '^import ' Packages/FontPlaygroundKit/Sources/fpctl` shows only `Foundation`, `FPCore` and `FPEngineClient`, plus Glibc/Darwin inside the allowed `#if canImport` block. `make lint` and `make kit-test` pass on Linux.

### Verification
```bash
make lint
make kit-test
d=$(mktemp -d) && engine/.venv/bin/python -m fpengine.testing.make_fonts "$d/fonts" \
  && swift run --package-path Packages/FontPlaygroundKit fpctl forge examples/fixtures/latin-cjk.fontrecipe \
       --font-dir "$d/fonts" --out "$d/out.ttf"
# M2 milestone check (maintainer, macOS; not an AC of this linux WP): with FP_ENGINE_PYTHON=engine/.venv/bin/python
swift run --package-path Packages/FontPlaygroundKit fpctl forge examples/latin-cjk.fontrecipe --out /tmp/x.ttf   # about 20 s on M-series (audit ENGINE-1 data)
```

### Notes for the implementer
- Plan's dependency list is 204 and 303, but loading `.fontrecipe` needs WP-305's RecipeDocument decoder and resolver (backbone issue filed). Use FPCore's API; never reimplement the format in `fpctl`.
- `fpctl` must not use CoreText or any name-based font lookup. It finds fonts only by scanning files (safety rule: no system font downloads).
- The default-folder scan on a Mac reads about 430 files (about 5 s cold). It only happens when the recipe's paths do not resolve.

---

## Traceability: findings → acceptance criteria

| Finding | WP | Regression evidence |
|---|---|---|
| NATIVE-3 (hybrid helper over JSON Lines) | 201 | AC-201-9 `test_native_3_forge_round_trip`; AC-201-2/-4/-5 (schema-valid streams) |
| NATIVE-7 (cancel waits for a stage boundary; run out of process) | 201, 204 | AC-201-16 `test_native_7_sigterm_mid_stage_exits_143_within_1s`; AC-204-9 `native7CancelSendsSigterm`; AC-204-10 `native7EscalatesToSigkillAndCleansLeftovers` |
| ENGINE-9 (forge in the GUI process; memory and cancel) | 201 | AC-201-17 `test_engine_9_cancel_removes_temp_and_partial_output`; AC-201-20 (orphan watchdog) |
| NATIVE-M4 (frozen-app entry point) | 203 | AC-203-2, checks `native_m4_hello` and `native_m4_pipeline` |
| TOOLING-M2 (editable-install trap) | 203 | AC-203-3, check `tooling_m2_non_editable` |
