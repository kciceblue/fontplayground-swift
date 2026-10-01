# Foundation and release

> Scope: WP-001, WP-002, WP-601, WP-602, WP-701 · Env: linux + macos (WP-001), linux (WP-002), macos (WP-601, WP-602, WP-701) · Architecture refs: docs/architecture.md §2, §3, §6, §7, §8 · ADRs: 0001, 0002, 0003, 0004, 0005, 0010, 0011, 0012

## Context

This spec covers both ends of the plan. **WP-001** and **WP-002** build what every other WP depends on: the Make targets, the engine as a uv project, the two Swift packages, the XcodeGen app shell, the Codex setup script and CI. **WP-601**, **WP-602** and **WP-701** turn the finished app into a signed, notarized DMG with licence texts and user docs, and then cut over: parity sign-off, frozen fixtures, `reference/` removed, tag `v1.0.0`.

**What the original had** (short paths in this spec are relative to `reference/fontplayground-py/`; `engine/…` and `catalog/…` mean `reference/fontplayground-py/fontplayground/engine/…` and `…/catalog/…` unless the path starts with `engine/src` or `engine/tests`). Packaging was a setuptools `pyproject.toml` with a deprecated licence table, the full `PySide6` meta-package, a `dev` extra, and a console-script entry for a GUI (`reference/fontplayground-py/pyproject.toml:1-30`). The README's bootstrap is Windows-only (`README.md:9-20`, `README.md:44-49`). There was no CI, no `.app`, no icon, no Info.plist metadata and no licence texts in any bundle. The test suite relies on Qt offscreen (`tests/conftest.py:7`) and on Qt-specific fixtures (`tests/conftest.py:12-31`). The engine (`fontplayground/engine/*.py`, 812 lines) and `catalog/face.py` are Qt-free. The cache's `face_to_dict`, `face_from_dict` and `_ranges` (`catalog/cache.py:13-40`) define the JSON shape of a face. `scanner.py` and `paths.py` walk Windows-style folder lists (`fontplayground/paths.py:10-22`) and dedupe by lower-cased path (`fontplayground/catalog/scanner.py:27`). In this rebuild Swift owns discovery and the cache (ADR-0007), so those modules are not imported.

**What the audit found** (docs/research/macos-audit.md):

| Finding | Summary | WP |
|---|---|---|
| TOOLING-4 | No CI | 001 |
| TOOLING-6, TOOLING-M1 | Windows-only dev workflow; the README bootstrap fails on a stock Mac (no `python`, `/usr/bin/python3` is 3.9, zsh globs `.[dev]`) | 001 |
| TOOLING-17 | pyproject hygiene: licence table, no dependency groups, console script for a GUI | 001 |
| TOOLING-3 | Suite red on macOS: `test_paths` builds Windows paths with `pathlib.Path` | 002 |
| TOOLING-18 | Catalog assumptions: case-folded dedupe, `bhed` bitmap font unreadable, absolute-path keys, cache location | 002 (engine side only; see WP-002 Scope) |
| TOOLING-23 | Benign platform touchpoints; the engine's temp directories | 002 |
| TOOLING-1 | No distributable build; Gatekeeper; notarization order (verifier: notarize and staple the **app**, then build, sign, notarize and staple the **DMG**) | 601 |
| TOOLING-8, TOOLING-9, TOOLING-10 | Bundle metadata; Icon Composer icon compiled into `Assets.car`; arm64 only | 601 |
| TOOLING-11 | No licence texts in the bundle (verifier adds CPython PSF and whatever python-build-standalone links in) | 601, 602 |
| TOOLING-14 | No diagnostics in a bundled app; quitting during a build could block | 601 |
| CRIT-1 | The main executable's SDK decides the look; it must be ≥ 26 | 601 |
| CRIT-2, CRIT-3 | Windows settings don't migrate; the Windows fonts behind old recipes live only inside Office on the Mac, under Microsoft's licence | 602 |
| UI-12 | Windows wording in strings and README | 602 |

**Evidence gathered while writing this spec** (Apple silicon, macOS 27.0, Xcode 27.0, Swift 6.4, uv 0.12.19, GNU Make 3.81; non-normative, but the design depends on it):

1. **codesign rejects the Python runtime inside `Contents/Helpers`.** A bundle with a python-build-standalone 3.12 runtime at `Contents/Helpers/fpengine/` failed to sign: `bundle format unrecognized, invalid, or unsuitable — In subcomponent: …/Contents/Helpers/fpengine/lib/python3.12`. codesign treats dotted directory names (`python3.12`, `*.dist-info`) in a code location as nested bundles. The same tree at `Contents/Resources/fpengine/` signs, and `codesign --verify --deep --strict` reports `valid on disk` / `satisfies its Designated Requirement` (1,730 files sealed). A relative symlink `Contents/Helpers/fpengine → ../Resources/fpengine` also verifies, and `Contents/Helpers/fpengine/bin/python3 -I -B` runs through it with `sys.prefix` in Resources. This is why §S3 keeps ADR-0004's path as a symlink.
2. **Ad-hoc signing plus the hardened runtime breaks the helper.** With `bin/python3.12` ad-hoc signed with `--options runtime`, `import pathops` fails: `mapping process and mapped file (non-platform) have different Team IDs`. Without `--options runtime` it works. With a real identity (a Team ID) all code shares the team, so the hardened runtime is fine. See §S4.
3. python-build-standalone 3.12.14 (`20260924`): `bin/python3.12` records `minos 11.0, sdk 15.0`. That is irrelevant for CRIT-1, which is about the **main** executable only. Its `libpython3.12.dylib` statically contains OpenSSL 3.5.8, bzip2, XZ/liblzma, SQLite 3.53.1, mpdecimal 4.0.0, Expat 2.8.5, libffi, util-linux libuuid and HACL\*. It links the system's zlib, libedit and ncurses dynamically. It ships Tcl/Tk 9.0 dylibs, which WP-203 strips. fontTools and skia-pathops extensions are universal2; `unicodedata2` is arm64-only.
4. `uv build --offline` and `uv sync --offline` work with `build-backend = "uv_build"`, because uv uses its bundled backend and fetches nothing. That matters because Codex cloud has no network during a task.
5. The reference tests that WP-002 ports are 45 test functions, collected as 69 test items because of parametrisation (`test_fixtures` 2, `test_face` 11 functions / 16 items, `test_forge` 8, `test_planner` 6, `test_prepare` 5, `test_scripts` 3 functions / 22 items, `test_spec` 3, `test_synth_bold` 4, `test_package` 1, two of `test_catalog`). They pass in 0.47 s. With the root `ruff.toml` of WP-001 (ruff 0.16), the renamed copy has 14 findings; `ruff check --fix` plus `ruff format` clears all of them (the only code rewrites are UP035, UP033 and UP037, which keep behaviour). A prototype of the WP-002 port (package rename plus `records.py`) passed its 68 non-version tests. It also produced byte-identical tables (apart from `head` timestamps) for 7 fixture forges against `reference/`.
6. A `@main enum Launcher` that runs `--self-test` before `SwiftUI.App.main()` compiles with `-swift-version 6 -strict-concurrency=complete -warnings-as-errors`. With `--self-test` it exits without ever creating `NSApplication`. The binary records `sdk 27.0`, and a `vtool`-restamped copy reads `sdk 15.0`, which is how the SDK check's negative test works.
7. `xcrun actool AppIcon.icon --compile … --app-icon AppIcon` (Icon Composer document: `icon.json` + one 1024 px PNG layer) emits `Assets.car`, `AppIcon.icns` and a partial plist with `CFBundleIconFile`/`CFBundleIconName = AppIcon`. A `display-p3:` fill colour compiles too.
8. On macOS 27, `hdiutil create/attach/detach` still work but print deprecation warnings. `diskutil image create from --format ULFO --volumeName … <folder> <dmg>` produces a valid image, and `diskutil image create from --help` exits 0 where the verb exists. `diskutil image attach` takes `--readOnly`, `--nobrowse` and `--mountPoint <dir>`; there is no `diskutil image detach` (use `diskutil eject <mount point>`).
9. zsh has a `log` builtin, so scripts call `/usr/bin/log`. `os.Logger` `.notice` messages from a command-line binary appear in `/usr/bin/log show --predicate 'subsystem == "…"'`. Interpolated values are redacted (`<private>`) unless they are logged with `privacy: .public`.
10. `proc_listchildpids(getpid(), …)` plus `proc_pidpath` (both from `import Darwin`, Swift 6 mode) list a process's live children: a running `Process` child appears, and it disappears once the child has exited and been reaped. This is how the self-test observes the helper process without an API in `FPEngineClient` (§S6 `cancel`).
11. The macOS 27 `bsdtar` cannot read `.tar.zst`, and no `zstd` ships with macOS.

## Shared definitions

Normative for all five WPs.

### S1. Pinned tool versions: `scripts/tool-versions.env`

One file, sourced by shell scripts and copied into `$GITHUB_ENV` by CI (`grep -E '^[A-Z_]+=' scripts/tool-versions.env >> "$GITHUB_ENV"`, because `$GITHUB_ENV` does not accept comment lines):

```bash
# Pinned tool versions. Bump UV_VERSION together with the uv_build bound in engine/pyproject.toml.
UV_VERSION=0.12.19
XCODE_MIN_MAJOR=26
XCODEGEN_MIN_VERSION=2.42.0
```

`UV_VERSION` is the uv release that is current when WP-001 is implemented (0.12.19 at the time of writing). The `uv_build` requirement in `engine/pyproject.toml` must be `>=<major>.<minor>,<<major>.<minor+1>` of that version, so uv uses its bundled backend offline (Context 4).

### S2. Build products and paths

| Name | Path |
|---|---|
| Debug app (`make app`, `make self-test`) | `build/DerivedData/Build/Products/Debug/Font Playground.app` |
| Release app (`scripts/release.sh`) | `build/release/Font Playground.app` (copied out of `build/release/DerivedData`) |
| Helper runtime (WP-203) | `build/helper/fpengine/` (`bin/python3`, `lib/python3.12/…`) |
| Release outputs | `dist/FontPlayground-<version>-arm64.dmg` and `dist/FontPlayground-<version>-arm64.dmg.sha256` |
| Main executable | `<app>/Contents/MacOS/Font Playground` |

`build/` and `dist/` are git-ignored (existing `.gitignore`).

### S3. Bundle layout (normative; refines ADR-0004)

```
Font Playground.app/Contents/
  MacOS/Font Playground                  main executable (Swift, SDK ≥ 26, arm64)
  Info.plist
  Resources/
    fpengine/                            the helper runtime, physically here (Context 1)
      bin/python3 -> python3.12, bin/python3.12
      lib/libpython3.12.dylib, lib/python3.12/{stdlib, lib-dynload, site-packages}
    Assets.car, AppIcon.icns             WP-601 (TOOLING-9)
    Acknowledgements.txt                 generated at build (§S5); read by WP-501's About panel
    Licenses/                            generated at build (§S5)
    en.lproj/, zh-Hans.lproj/UserGuide.html  WP-602, localised by WP-508 (read by WP-501's Help command)
    FontPlaygroundMacKit_FPAppUI.bundle/ SwiftPM resources (includes self-test.fontrecipe)
  Helpers/
    fpengine -> ../Resources/fpengine    relative symlink; ADR-0004's launch path stays valid
```

- The engine client launches `Contents/Helpers/fpengine/bin/python3 -I -B -m fpengine` (ADR-0004, architecture §3). The symlink resolves to the physical tree.
- No other code location (`Contents/MacOS`, `Contents/Frameworks`, a real directory under `Contents/Helpers`) may contain a directory whose name contains a dot.
- Nothing writes into the bundle at run time: `-B` plus `PYTHONDONTWRITEBYTECODE=1` (architecture §3). After a self-test run, the signature still verifies (AC-601-12).
- The runtime has none of the paths WP-203 strips (helper.md WP-203 Design step 8), in particular no `include/`, no `share/`, no `lib/libtcl*`/`lib/libtk*`, no `lib/python3.12/{tkinter,idlelib,ensurepip,test}` and no `*.a` anywhere. `scripts/check-bundle.sh` fails if any of these exact paths is present (it does **not** reject other folders named `test` or `tests` inside wheels).

### S4. Signing rules

| Identity | Helper Mach-O files (`*.so`, `*.dylib`, `bin/python3.12`) | Main app bundle |
|---|---|---|
| `-` (ad-hoc: dev, CI) | `codesign --force --sign - --timestamp=none` (**no** `--options runtime`, Context 2) | `--force --sign - --timestamp=none --options runtime` |
| Apple Development (stable local identity; keeps TCC grants, TOOLING-M3) | `--force --sign "$ID" --timestamp=none --options runtime` | same + `--options runtime` |
| Developer ID Application (release) | `--force --sign "$ID" --timestamp --options runtime` | same |

- Sign **inside-out** and never use `--deep` to sign. Order: (1) every non-executable Mach-O (`file -b` says `shared library` or `bundle`), (2) every Mach-O executable under `Contents/Resources`, (3) the app bundle.
- **No entitlements** anywhere (ADR-0010): after `scripts/sign-app.sh`, `codesign -d --entitlements - --xml "<app>"` prints nothing. The only tolerated exception is `com.apple.security.get-task-allow`, which Xcode injects into **Debug** builds so the debugger can attach; `sign-app.sh` re-signs without `--entitlements` (and without `--preserve-metadata=entitlements`), which removes it.
- Only Mach-O files are signed individually. Everything else under `Resources` is sealed by the app signature.
- helper.md's WP-203 hand-off note points here: no entitlement (in particular not `com.apple.security.cs.disable-library-validation`) is ever used. The ad-hoc row above (no hardened runtime on helper code) solves the Team-ID problem (Context 2, ADR-0010).

### S5. Licence bundle

`tools/release/collect_licenses.py` (WP-601; its component data is completed by WP-602) runs as the last build phase. Its output is:

- `Contents/Resources/Licenses/<Component>/<file>`: every licence text. `<Component>` is the component name with spaces replaced by `-`, other characters outside `[A-Za-z0-9._-]` removed.
- `Contents/Resources/Licenses/index.json`:

```json
{
  "format": "fp-licenses",
  "version": 1,
  "components": [
    {"name": "Font Playground", "version": "0.1.0", "license": "MIT", "kind": "app",
     "files": ["Font-Playground/LICENSE.txt"]},
    {"name": "CPython", "version": "3.12.14", "license": "PSF-2.0", "kind": "runtime",
     "files": ["CPython/LICENSE.txt"]},
    {"name": "fonttools", "version": "4.66.0", "license": "MIT", "kind": "wheel",
     "files": ["fonttools/LICENSE", "fonttools/LICENSE.external"]}
  ]
}
```

`kind` ∈ `app | runtime | wheel | static`. `license` is an SPDX expression, or `LicenseRef-see-file` when no SPDX id applies. `files` are paths relative to `Licenses/`, and each file exists and is non-empty.

- `Contents/Resources/Acknowledgements.txt` is regenerated: the committed `App/Resources/Acknowledgements.txt` (the curated introduction, WP-501 then WP-602), then a line `Licence texts`, then for each component `== <name> <version> (<license>) ==` followed by its texts. When the version is empty, omit it and its preceding space: `== <name> (<license>) ==`. WP-501's `AboutCredits` shows this file (ui-shell.md D8).
- `App/Licenses/components.json` (WP-602) lists the **static** components: those not discoverable from wheel metadata, such as the python-build-standalone parts. Each entry:

```json
{"name": "OpenSSL", "license": "Apache-2.0", "files": ["python-build-standalone/OpenSSL-LICENSE.txt"],
 "detect": {"python": "import ssl; print(ssl.OPENSSL_VERSION.removeprefix('OpenSSL ').split()[0])"}}
```

`detect` is optional. `{"python": <code>}` means the component is present if the code runs without an exception in the embedded interpreter; its printed output (stripped) is the version. Print the bare version, never the library's banner: the heading already starts with the name, so `ssl.OPENSSL_VERSION` (`OpenSSL 3.5.8 25 Aug 2026`) headed 1.0.0 (4)'s text `== OpenSSL OpenSSL 3.5.8 …` (WP-701 finding E). `{"bytes": <ascii marker>}` means present if `lib/libpython3.12.dylib` contains the marker; the marker is a presence check, never a version. Components without `detect` are always included. `version` in `index.json` is the output of a successful Python version probe, and `""` for byte-detected static components or components without `detect`. Keep those components and their licence texts even when no version is known. `test_tooling_11_byte_detection_is_presence_not_a_version` checks inclusion/exclusion, empty versions and clean About headings for every byte-detected component, while retaining Python-reported versions. `test_wp701_finding_e_version_probes_print_bare_versions` and `test_wp701_finding_e_acknowledgement_headings_name_each_component_once` check that no heading repeats its component's name.

### S6. Self-test contract (`--self-test`)

The app's main executable accepts:

```
"Font Playground" --self-test [--self-test-report <path>] [--self-test-keep]
                              [--require-embedded-engine] [--self-test-timeout <seconds>]
```

- Runs **headless**. It returns before `NSApplication` is created (WP-001 `Launcher`), so there is no window, no Dock icon and no activation. It never registers fonts, never matches fonts by name in CoreText, never writes to `~/Library/Fonts`, `~/Library/Application Support/io.github.kciceblue.fontplayground` or `~/Library/Caches/io.github.kciceblue.fontplayground`. All files go under `FileManager.default.temporaryDirectory/fp-self-test-<UUID>/`, which holds `tmp/` (the helper's `TMPDIR`) and `out/`.
- **stdout:** JSON Lines, one object per step **that ran**, in the order below, then exactly one summary as the last line (also on exit codes 1, 3 and 4; not on 2). Keys are written in the order shown, with `JSONSerialization`-compatible values. **stderr:** one plain line per step that ran, `self-test: <step> ok (<seconds, 1 decimal> s)` or `self-test: <step> FAILED: <error>`; usage errors print `self-test: <message>` and nothing on stdout.
- Step object: `{"type": "step", "step": "<id>", "ok": true|false, "duration_ms": <int>, "detail": {<string>: <string>}, "error": <string|null>}`.
- Summary object: `{"type": "summary", "result": "passed"|"failed"|"timed_out", "failed_steps": [<id>], "duration_ms": <int>, "app_version": "<CFBundleShortVersionString>", "build": "<CFBundleVersion>", "engine": "embedded"|"dev"|"none", "fpengine_version": "<string|empty>", "macos": "<major.minor.patch>"}`.
- Before the first step, the runner creates the temporary root (`<root>/tmp` and `<root>/out`). If that fails, it prints only the summary (`result: "failed"`, `failed_steps: []`) and exits 3.
- Steps run in this order. The first failure stops the run, except that `cleanup` always runs. A step that exceeds its budget fails with error `step budget of <n> s exceeded` (the budget is a per-step timeout, enforced by cancelling the step):

| Step id | Does | Fails when | Budget |
|---|---|---|---|
| `environment` | read bundle id, `CFBundleShortVersionString`, `CFBundleVersion` (injected `bundleInfo`); macOS version; architecture (`#if arch(arm64)`) | bundle id ≠ `io.github.kciceblue.fontplayground` or arch ≠ arm64 (exit 1) | 1 s |
| `engine` | resolve the helper with WP-204's `EngineLaunch.resolve` (embedded `Contents/Helpers/fpengine/bin/python3`, then `Contents/Resources/fpengine/bin/python3`, then `FP_ENGINE_PYTHON`); build an `EngineClient` whose `temporaryDirectory` is `<root>/tmp`; `hello()` | `.helperNotFound` (**exit 3**); `--require-embedded-engine` and the engine is not embedded (**exit 3**); any `hello()` error, including `.incompatibleHelper` (exit 1) | 20 s |
| `recipe` | `RecipeDocument.decode` (core.md WP-305) of the bundled `self-test.fontrecipe` (WP-601 Design §5) | a `RecipeDocumentError` | 1 s |
| `discover` | `CTFontManagerCopyAvailableFontURLs()` (file URLs only); each document material path (standardised) is in the list | a path missing (`detail.missing` names it) | 10 s |
| `scan` | `scan(files:)` of exactly the document's material paths; `document.makeRecipe(catalog: FaceCatalog(<returned FaceRecords>))` | a `.fileError` event, a thrown error, or a `LoadReport` that is not `isClean` (every outcome must be `.byPath`) | 30 s |
| `forge` | `recipe.forgeRequest(outputPath: "<root>/out/self-test.ttf")` → `forge` | `recipe.analyze().canForge == false`; a thrown error (e.g. `.helperFailed`); `report.totalCodepoints == 0`; the output file missing | 120 s |
| `verify` | CoreText on the output (below) | any check fails | 5 s |
| `cancel` | the same recipe to `<root>/out/cancel.ttf`; after the first `.progress` event, record the helper's pid (below) and cancel the consuming task | no helper child process was seen; the helper is still alive 3 s after the cancel; `cancel.ttf` exists afterwards | 10 s |
| `cleanup` | delete `<root>` unless `--self-test-keep` (then `detail.root` gives the path) | never fails the run (reports `ok: false` with the error, and the exit code stays as it was) | 5 s |

- **Observing the helper for `cancel`** (TOOLING-14; no `FPEngineClient` API needed, Context 10): the injected `helperProcessIDs()` returns the pids of this process's live children (`proc_listchildpids(getpid(), …)`, keeping pids > 0 for which `proc_pidpath` succeeds; iterate the whole buffer, because the return value is a count on some macOS versions and a byte size on others). The runner takes `before = helperProcessIDs()` before starting the cancel run and `during = helperProcessIDs() − before` right after the first `.progress` event (poll every 50 ms for up to 1 s if `during` is empty). Then it cancels, and polls every 100 ms for up to 3 s until `helperProcessIDs() ∩ during` is empty. `detail` records `pids` and `ended_after_ms`.

- `verify` checks, using only URL-based CoreText: `CTFontManagerCreateFontDescriptorsFromURL(outputURL)` returns exactly 1 descriptor. Its `kCTFontNameAttribute` equals the report's `postscript_name`. `CTFontCreateWithFontDescriptor(desc, 24, nil)` maps every UTF-16 unit of the recipe's `sample_text` (minus spaces) to a non-zero glyph (`CTFontGetGlyphsForCharacters`). `CTFontCopyTable(font, CTFontTableTag(kCTFontTableName), [])` contains the UTF-16BE bytes of `Forged with Font Playground` (contracts §6).
- **Exit codes:** `0` passed · `1` a step failed · `2` usage error (an unknown argument starting with `--self-test`, a missing `--self-test-report` value, a missing or non-integer `--self-test-timeout` value, or a timeout outside 10…3600; message on stderr) · `3` environment unusable (temp root not creatable, no helper found, embedded helper required but absent) · `4` overall timeout (`--self-test-timeout <seconds>`, default 180). With `--self-test-report <path>`, the same JSON Lines are also written atomically to `<path>` (parent folders must exist; a write failure is reported on stderr and does not change the exit code).
- Budgets assume Apple silicon, including the 3-core M1 VM of a GitHub `macos-26` runner, taken as about 3× slower than the audit Mac. The audit measured a Latin+CJK forge (Georgia + Songti SC) at 3.2 s (NATIVE-3 verifier) and helper start at 150–400 ms (ADR-0003). The recipe here is Latin + monospace (about 3,200 code points).
- Every summary is also logged, exactly once, as `AppLog.selfTest.notice("self-test: \(result, privacy: .public) (failed: \(failedSteps, privacy: .public), \(durationMs) ms)")`, where `result` is `passed`, `failed` or `timed_out` and `failedSteps` is the comma-joined list or `none` (§S7; Context 9: without `.public` the text is redacted).
- Debug builds only: `FP_SELF_TEST_INJECT_FAILURE=<step id>` makes that step fail with error `injected`. This exists so tests can exercise exit code 1. It is compiled out of Release (`#if DEBUG`).

### S7. `AppLog`

`Packages/FontPlaygroundMacKit/Sources/FPAppUI/Diagnostics/AppLog.swift` (WP-601, unless WP-501 already has an equivalent; then use that and record it):

```swift
import os

public enum AppLog {
    public static let subsystem = "io.github.kciceblue.fontplayground"
    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let engine = Logger(subsystem: subsystem, category: "engine")
    public static let selfTest = Logger(subsystem: subsystem, category: "self-test")
}
```

### S8. Version, single source

- App: `App/Version.xcconfig` holds `MARKETING_VERSION = <x.y.z>` and `CURRENT_PROJECT_VERSION = 1`. Release builds override `CURRENT_PROJECT_VERSION` with the CI run number.
- Engine: `engine/pyproject.toml` `[project] version`. `fpengine.__version__` reads it through `importlib.metadata`.
- Both must be equal (`test_tooling_8_single_version`, WP-601). A release tag `v<x.y.z>` must equal them (`scripts/release.sh`).

### S9. Repository tests (`engine/tests/repo/`)

Checks on the repository itself (Makefile, CI, docs, configuration) are pytest tests in `engine/tests/repo/`. They run in `make engine-test` on Linux and macOS and read files relative to `ROOT = Path(__file__).resolve().parents[3]`. They use only the standard library (`tomllib`, `plistlib`, `json`, `re`, `subprocess`). Any subprocess they run is a `make` or `git` call without side effects outside a `tmp_path`.

---

## WP-001: Repository scaffold, Makefile, Codex setup script, CI (Linux + macOS)

**Goal:** A clean clone runs `make setup test` green on Linux and macOS, every Make target in docs/testing.md exists, and CI runs a Linux job and a macOS job on every PR.
**Depends on:** — · **Env:** linux + macos (needs network: see docs/dispatch.md) · **Size:** M · **Closes findings:** TOOLING-4, TOOLING-6, TOOLING-17, TOOLING-21, TOOLING-M1

### Scope
- In:
  - `Makefile` with exactly the 12 targets of docs/testing.md §1 (placeholders where the owning WP comes later).
  - `engine/` as a uv project with a placeholder `fpengine` package, the **final** dependency set and `uv.lock`.
  - Marker auto-skip.
  - The `apple_fonts` placeholder test.
  - Repository tests (§S9) for the closed findings.
  - Both SwiftPM packages with placeholder targets and one Swift Testing test per test target.
  - `App/project.yml`, `App/Info.plist`, `App/Version.xcconfig` and the minimal app with the `Launcher` entry point and a `--self-test` stub.
  - `.swift-format`, `ruff.toml`, `.python-version`, `.gitattributes`, `scripts/tool-versions.env`, `scripts/check-macos-toolchain.sh`, `scripts/codex-setup.sh`.
  - `.github/workflows/ci.yml`.
  - `docs/development.md` and a "Development" section in `README.md`.
- Out:
  - Engine code (WP-002).
  - The conformance generator (WP-202).
  - The helper runtime (WP-203).
  - Real app UI (WP-501).
  - Signing, notarization, the icon and the full self-test (WP-601).
  - User docs (WP-602).

### Touched paths
- `Makefile` (new)
- `.python-version`, `ruff.toml`, `.swift-format`, `.gitattributes` (new)
- `scripts/tool-versions.env`, `scripts/check-macos-toolchain.sh`, `scripts/codex-setup.sh` (new)
- `engine/pyproject.toml`, `engine/uv.lock`, `engine/README.md` (new)
- `engine/src/fpengine/__init__.py` (new)
- `engine/tests/__init__.py`, `engine/tests/conftest.py`, `engine/tests/test_package.py` (new)
- `engine/tests/apple_fonts/__init__.py`, `engine/tests/apple_fonts/test_wiring.py` (new)
- `engine/tests/repo/__init__.py`, `engine/tests/repo/test_repo_hygiene.py` (new)
- `engine/tests/data/README.md` (new)
- `Packages/FontPlaygroundKit/Package.swift`, `Sources/{FPCore,FPEngineClient,fpctl}/*`, `Tests/{FPCoreTests,FPEngineClientTests,FPCTLTests}/PlaceholderTests.swift` (new)
- `Packages/FontPlaygroundMacKit/Package.swift`, `Sources/{FPMacServices,FPAppUI}/*`, `Tests/{FPMacServicesTests,FPAppUITests}/PlaceholderTests.swift` (new)
- `App/project.yml`, `App/Info.plist`, `App/Version.xcconfig`, `App/Sources/Launcher.swift`, `App/Sources/FontPlaygroundApp.swift` (new)
- `App/Resources/Localizable.xcstrings`, `Packages/FontPlaygroundMacKit/Sources/FPAppUI/Resources/Localizable.xcstrings` (new)
- `.github/workflows/ci.yml` (new)
- `docs/development.md` (new), `README.md` (edit: add "Development")

### Design

**1. Makefile (normative).** It must work with GNU Make 3.81 (macOS `/usr/bin/make`) and 4.x. `.SHELLFLAGS` is ignored by 3.81, so recipes do not rely on `pipefail`. The public targets are exactly those of docs/testing.md §1. Helper targets start with `_`.

```make
# Font Playground: the single entry point for setup, lint, test and build (docs/testing.md §1).
# Works with GNU Make 3.81 (macOS /usr/bin/make) and 4.x (Linux).
SHELL := /bin/bash
.DEFAULT_GOAL := test

UNAME_S := $(shell uname -s)
IS_MACOS := $(filter Darwin,$(UNAME_S))

UV ?= uv
SWIFT ?= swift
XCODEGEN ?= xcodegen
FP_CODESIGN_IDENTITY ?= -
FP_DEVELOPMENT_TEAM ?=
XCODEBUILD_FLAGS ?= -quiet

KIT := Packages/FontPlaygroundKit
MACKIT := Packages/FontPlaygroundMacKit
DERIVED := build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/Font Playground.app
PY_DIRS := engine $(wildcard tools)

export FP_ENGINE_PYTHON ?= $(CURDIR)/engine/.venv/bin/python

.PHONY: setup lint engine-test engine-apple-fonts conformance conformance-check kit-test mac-test test app \
	helper-runtime self-test _need-uv _need-macos

_need-uv:
	@command -v "$(UV)" >/dev/null 2>&1 || { \
	  echo "error: uv not found. Install it with 'brew install uv' (macOS) or" >&2; \
	  echo "       'curl -LsSf https://astral.sh/uv/install.sh | sh' (see https://docs.astral.sh/uv/)." >&2; \
	  exit 1; }

_need-macos:
	@if [ -z "$(IS_MACOS)" ]; then echo "error: 'make $(MAKECMDGOALS)' needs macOS (docs/testing.md)" >&2; exit 2; fi

setup: _need-uv
	cd engine && "$(UV)" sync --frozen
	@if [ -n "$(IS_MACOS)" ]; then scripts/check-macos-toolchain.sh --warn; fi

lint: _need-uv
	"$(UV)" run --project engine --frozen ruff check $(PY_DIRS)
	"$(UV)" run --project engine --frozen ruff format --check $(PY_DIRS)
	"$(SWIFT)" format lint --strict --recursive $(KIT)
	@if [ -n "$(IS_MACOS)" ]; then set -x; "$(SWIFT)" format lint --strict --recursive $(MACKIT) App/Sources; fi

engine-test: _need-uv
	cd engine && "$(UV)" run --frozen pytest -q

engine-apple-fonts: _need-macos _need-uv
	cd engine && FP_APPLE_FONTS=1 "$(UV)" run --frozen pytest -q -m apple_fonts

conformance: _need-uv
	@if [ -f tools/conformance/generate.py ]; then \
	  set -x; "$(UV)" run --project engine --frozen python tools/conformance/generate.py; \
	else echo "conformance: tools/conformance/generate.py does not exist yet (WP-202); nothing to generate"; fi

conformance-check: conformance
	git diff --exit-code -- spec/fixtures
	@untracked="$$(git ls-files --others --exclude-standard -- spec/fixtures)"; \
	if [ -n "$$untracked" ]; then echo "error: new, uncommitted fixtures:" >&2; echo "$$untracked" >&2; exit 1; fi

kit-test:
	"$(SWIFT)" test --package-path $(KIT)

mac-test: _need-macos
	"$(SWIFT)" test --package-path $(MACKIT)

test: engine-test conformance-check kit-test $(if $(IS_MACOS),mac-test)

app: _need-macos
	scripts/check-macos-toolchain.sh
	"$(XCODEGEN)" generate --spec App/project.yml --quiet
	xcodebuild -project App/FontPlayground.xcodeproj -scheme FontPlayground -configuration Debug \
	  -derivedDataPath $(DERIVED) $(XCODEBUILD_FLAGS) build \
	  CODE_SIGN_IDENTITY="$(FP_CODESIGN_IDENTITY)" DEVELOPMENT_TEAM="$(FP_DEVELOPMENT_TEAM)"

helper-runtime: _need-macos
	@if [ -x scripts/build-helper-runtime.sh ]; then scripts/build-helper-runtime.sh; \
	else echo "error: scripts/build-helper-runtime.sh does not exist yet (WP-203)" >&2; exit 2; fi

self-test: app
	"$(APP)/Contents/MacOS/Font Playground" --self-test
```

Notes:
- `conformance-check` also rejects **untracked** new fixture files. `git diff` alone misses them.
- Until WP-202, `conformance` prints the "does not exist yet (WP-202)" line and succeeds. Until WP-203, `helper-runtime` exits 2 with its message. Until WP-601, `self-test` runs the stub (item 7).
- `FP_CODESIGN_IDENTITY="Apple Development"` plus `FP_DEVELOPMENT_TEAM=<team>` gives a stable local signature (TOOLING-M3; see `docs/development.md`).

**2. `scripts/check-macos-toolchain.sh [--warn]`.** It sources `tool-versions.env` and collects problems:
- `xcodebuild -version` first line `Xcode <v>`: missing → `Xcode not found. Install Xcode 26 or newer from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app`. Major < `XCODE_MIN_MAJOR` → `Xcode <v> is too old: Font Playground needs Xcode 26 or newer (docs/architecture.md §7).`
- `xcodegen --version` (`Version: <v>`): missing → `xcodegen not found: brew install xcodegen`. Older than `XCODEGEN_MIN_VERSION` (compared with `sort -V`) → `xcodegen <v> is older than 2.42.0: brew upgrade xcodegen`.
- `swift format --version` fails → `swift-format not found: it ships with Xcode 16 and later; check xcode-select -p`.

It prints each problem to stderr prefixed `warning:` (with `--warn`) or `error:` (without). It exits 0 with `--warn`, and 1 without when anything is wrong. On success it prints `toolchain: Xcode <v>, xcodegen <v>`.

**3. Engine skeleton.** `engine/pyproject.toml` (normative; it already declares the **final** runtime and dev dependencies, because WP-002 runs in Codex cloud with no network and cannot re-lock):

```toml
[build-system]
requires = ["uv_build>=0.12,<0.13"]   # the minor of UV_VERSION (§S1): uv then uses its bundled backend, offline
build-backend = "uv_build"

[project]
name = "fpengine"
version = "0.1.0"
description = "Font Playground engine: read font faces, plan and forge merged fonts with fontTools"
readme = "README.md"
license = "MIT"
requires-python = ">=3.12"
dependencies = [
  "fonttools[unicode]>=4.65",
  "skia-pathops>=0.9",
]

[dependency-groups]
dev = [
  "pytest>=8",
  "jsonschema>=4.23",                                          # WP-201 protocol tests
  "ruff>=0.12",
  "pyobjc-framework-CoreText>=11; sys_platform == 'darwin'",  # WP-111 real-font suite (macOS only)
]

[tool.uv]
required-version = ">=0.12,<0.13"

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-ra --strict-markers"
markers = [
  "macos: needs macOS (skipped elsewhere)",
  "apple_fonts: needs real Apple system fonts and FP_APPLE_FONTS=1",
  "slow: takes over 10 s",
]
```

- The dev group already contains what later WPs need, because linux WPs cannot re-lock offline: `jsonschema` (WP-201) and, for macOS only, `pyobjc-framework-CoreText` (WP-111; engine-correctness.md lists it as a WP-111 edit, which then finds it present and changes nothing). On Linux `uv sync --frozen` skips the darwin-only entry.
- There is no `[project.scripts]` and no `gui-scripts`. The helper runs as `python -m fpengine` (ADR-0003). That, the SPDX `license` string and the `dev` dependency group close TOOLING-17. There is no `license-files`, because the licence text is the repository `LICENSE`, outside the project directory.
- `engine/src/fpengine/__init__.py`:

  ```python
  """Font Playground engine: read faces, plan and forge merged fonts."""
  from importlib.metadata import PackageNotFoundError, version

  try:
      __version__ = version("fpengine")
  except PackageNotFoundError:  # a source tree that is not installed
      __version__ = "0+unknown"
  ```
- `.python-version` at the repository root: `3.12`. uv finds it from `engine/` and from `tools/`.
- `engine/uv.lock` comes from `uv lock` in `engine/` and is committed. **This needs network**; see Notes.
- `engine/tests/conftest.py` (WP-002 adds fixtures to it):

  ```python
  import os
  import sys

  import pytest


  def pytest_collection_modifyitems(config, items):
      """docs/testing.md §3: `macos` needs macOS; `apple_fonts` also needs FP_APPLE_FONTS=1."""
      on_macos = sys.platform == "darwin"
      real_fonts = on_macos and os.environ.get("FP_APPLE_FONTS") == "1"
      for item in items:
          if "macos" in item.keywords and not on_macos:
              item.add_marker(pytest.mark.skip(reason="needs macOS"))
          if "apple_fonts" in item.keywords and not real_fonts:
              item.add_marker(pytest.mark.skip(reason="needs macOS and FP_APPLE_FONTS=1 (make engine-apple-fonts)"))
  ```
- `engine/tests/apple_fonts/test_wiring.py` exists so that `make engine-apple-fonts` collects at least one test. pytest exits 5 when it collects nothing. WP-111 keeps or replaces it.

  ```python
  import sys
  from pathlib import Path

  import pytest

  pytestmark = [pytest.mark.macos, pytest.mark.apple_fonts]


  def test_apple_fonts_suite_is_wired():
      """Placeholder until WP-111: proves the marker, the FP_APPLE_FONTS gate and the macOS skip."""
      assert sys.platform == "darwin" and Path("/System/Library/Fonts").is_dir()
  ```
- `engine/tests/test_package.py`:
  - `test_version_matches_pyproject`: `fpengine.__version__ == tomllib.load(pyproject)["project"]["version"]`.
  - `test_runtime_dependencies_import`: `import fontTools, pathops, unicodedata2` succeeds, and `fontTools.version >= "4.65"` (compared as a version tuple).
- `engine/tests/data/README.md`: the fixtures policy from docs/testing.md §4, and an empty table `| File | Licence | Source | Size |`.
- `engine/README.md`: what `fpengine` is, `uv sync` / `uv run pytest`, and a pointer to docs/architecture.md and helper.md.

**4. Lint configuration.**

`ruff.toml` at the root applies to `engine/` and `tools/`. There is **no** `[tool.ruff]` in `engine/pyproject.toml`, which would override it for engine files.

```toml
line-length = 120
target-version = "py312"
extend-exclude = ["reference", "build", "Packages", "App", "spec"]

[lint]
select = ["E", "W", "F", "I", "UP", "B"]
ignore = ["B905"]   # zip() over lists that are equal-length by construction in the imported engine

[lint.isort]
known-first-party = ["fpengine", "tests"]
```

`.swift-format` at the root (verified with `swift format lint --strict --recursive`, which skips hidden folders such as `.build`):

```json
{
  "version": 1,
  "lineLength": 120,
  "indentation": { "spaces": 4 },
  "maximumBlankLines": 1,
  "respectsExistingLineBreaks": true,
  "lineBreakBeforeEachArgument": false,
  "indentConditionalCompilationBlocks": true,
  "rules": {
    "AllPublicDeclarationsHaveDocumentation": false,
    "AlwaysUseLowerCamelCase": true,
    "NeverForceUnwrap": false,
    "NeverUseForceTry": false,
    "OrderedImports": true,
    "UseLetInEveryBoundCaseVariable": true,
    "ValidateDocumentationComments": false
  }
}
```

`.gitattributes` (TOOLING-21's recommendation):

```
* text=auto eol=lf
*.png binary
*.icns binary
*.car binary
*.ttf binary
*.otf binary
*.ttc binary
*.otc binary
*.dmg binary
```

**5. Swift packages** (tools-version 6.1, `swiftLanguageModes: [.v6]`, `platforms: [.macOS(.v14)]`; verified with `swift test`):

`Packages/FontPlaygroundKit/Package.swift`:
- products: library `FPCore`, library `FPEngineClient`, executable `fpctl`
- targets: `FPCore`; `FPEngineClient` (deps: `FPCore`); `executableTarget fpctl` (deps: `FPCore`, `FPEngineClient`)
- test targets: `FPCoreTests` (FPCore), `FPEngineClientTests` (FPEngineClient), `FPCTLTests` (fpctl)

Placeholders (later WPs delete them):

```swift
// Sources/FPCore/FPCoreInfo.swift
/// Placeholder until WP-301 adds the domain types.
public enum FPCoreInfo { public static let moduleName = "FPCore" }

// Sources/FPEngineClient/FPEngineClientInfo.swift
import FPCore
/// Placeholder until WP-204 adds `EngineClient`.
public enum FPEngineClientInfo {
    public static let moduleName = "FPEngineClient"
    public static let protocolVersion = 1
}

// Sources/fpctl/FPCTL.swift
import FPCore
import FPEngineClient
enum FPCTL {
    static let version = "0.1.0"
    static let usage = "usage: fpctl --version"
    static func run(_ arguments: [String]) -> (status: Int32, output: String) {
        if arguments == ["--version"] { return (0, "fpctl \(version)") }
        return (64, usage)
    }
}

// Sources/fpctl/main.swift
import Foundation
let result = FPCTL.run(Array(CommandLine.arguments.dropFirst()))
print(result.output)
exit(result.status)
```

Tests (Swift Testing, `import Testing`, `@testable import …`):

| File | Test |
|---|---|
| `FPCoreTests/PlaceholderTests.swift` | `moduleIsLinked()`: `#expect(FPCoreInfo.moduleName == "FPCore")` |
| `FPEngineClientTests/PlaceholderTests.swift` | `protocolVersionIsOne()` |
| `FPCTLTests/PlaceholderTests.swift` | `versionFlagPrintsVersion()` (status 0, `"fpctl 0.1.0"`); `unknownArgumentsPrintUsage()` (status 64) |

`Packages/FontPlaygroundMacKit/Package.swift`:
- dependencies: `.package(path: "../FontPlaygroundKit")`
- targets: `FPMacServices` (deps: products `FPCore`, `FPEngineClient`); `FPAppUI` (deps: `FPMacServices`, `FPCore`, `FPEngineClient`)
- tests: `FPMacServicesTests`, `FPAppUITests`

Placeholders:

```swift
// Sources/FPMacServices/FPMacServicesInfo.swift
import CoreText
import FPCore
/// Placeholder until WP-401.
public enum FPMacServicesInfo { public static let moduleName = "FPMacServices" }

// Sources/FPAppUI/RootView.swift
import FPMacServices
import SwiftUI
/// Placeholder window content until WP-501.
public struct RootView: View {
    public init() {}
    public var body: some View { Text("Font Playground").frame(minWidth: 640, minHeight: 400) }
}
```

| File | Test |
|---|---|
| `FPMacServicesTests/PlaceholderTests.swift` | `moduleIsLinked()` |
| `FPAppUITests/PlaceholderTests.swift` | `@MainActor rootViewBuildsOffscreen()`: `NSHostingView(rootView: RootView())` has `fittingSize.width >= 640` and `window == nil` (no window is created) |

The placeholder labels use String Catalogs from the first build (architecture §8): MacKit declares `defaultLocalization: "en"`, processes `FPAppUI/Resources`, and uses `Text("Font Playground", bundle: .module)`. The app processes `App/Resources/Localizable.xcstrings` for its scene title.

**6. App shell (XcodeGen).**

`App/Version.xcconfig`:

```
MARKETING_VERSION = 0.1.0
CURRENT_PROJECT_VERSION = 1
```

`App/project.yml` (normative for WP-001; WP-501 and WP-601 extend it):

```yaml
name: FontPlayground
options:
  bundleIdPrefix: io.github.kciceblue
  deploymentTarget:
    macOS: "14.0"
  developmentLanguage: en
configFiles:
  Debug: Version.xcconfig
  Release: Version.xcconfig
settings:
  base:
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    ARCHS: arm64
    DEAD_CODE_STRIPPING: YES
    ENABLE_USER_SCRIPT_SANDBOXING: NO   # WP-601's build phases read build/helper and write into the bundle
packages:
  FontPlaygroundMacKit:
    path: ../Packages/FontPlaygroundMacKit
targets:
  FontPlayground:
    type: application
    platform: macOS
    sources:
      - path: Sources
    dependencies:
      - package: FontPlaygroundMacKit
        product: FPAppUI
    settings:
      base:
        PRODUCT_NAME: "Font Playground"
        PRODUCT_BUNDLE_IDENTIFIER: io.github.kciceblue.fontplayground
        INFOPLIST_FILE: Info.plist
        GENERATE_INFOPLIST_FILE: NO
        CODE_SIGN_STYLE: Manual
        CODE_SIGN_IDENTITY: "-"
        DEVELOPMENT_TEAM: ""
        ENABLE_HARDENED_RUNTIME: YES
schemes:
  FontPlayground:
    build:
      targets:
        FontPlayground: all
    run:
      config: Debug
      environmentVariables:
        FP_ENGINE_PYTHON: "$(PROJECT_DIR)/../engine/.venv/bin/python"
    archive:
      config: Release
```

There is no entitlements file (ADR-0010). The generated `App/FontPlayground.xcodeproj` is git-ignored (`*.xcodeproj/`).

`App/Info.plist` (WP-001 minimum; WP-501 adds the keys of ui-shell.md D1):

| Key | Value |
|---|---|
| `CFBundleDevelopmentRegion` | `en` |
| `CFBundleExecutable` | `$(EXECUTABLE_NAME)` |
| `CFBundleIdentifier` | `$(PRODUCT_BUNDLE_IDENTIFIER)` |
| `CFBundleInfoDictionaryVersion` | `6.0` |
| `CFBundleName`, `CFBundleDisplayName` | `Font Playground` |
| `CFBundlePackageType` | `APPL` |
| `CFBundleShortVersionString` | `$(MARKETING_VERSION)` |
| `CFBundleVersion` | `$(CURRENT_PROJECT_VERSION)` |
| `LSMinimumSystemVersion` | `$(MACOSX_DEPLOYMENT_TARGET)` |
| `NSHighResolutionCapable` | `true` |

`App/Sources/Launcher.swift`. This is the **only** `@main` in the app target; `FontPlaygroundApp` must not be annotated `@main`:

```swift
import FPAppUI
import Foundation

/// The app's entry point. `--self-test` runs before NSApplication exists, so it is headless:
/// no window, no Dock icon, no activation (docs/testing.md "App smoke"; foundation-release.md §S6).
@main
enum Launcher {
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--self-test") {
            // WP-601 replaces this stub with `exit(await SelfTest.run(arguments:environment:))`.
            print("{\"type\":\"summary\",\"result\":\"passed\",\"failed_steps\":[],\"engine\":\"none\",\"note\":\"shell only (WP-601 adds the pipeline)\"}")
            exit(0)
        }
        FontPlaygroundApp.main()
    }
}
```

`App/Sources/FontPlaygroundApp.swift`:

```swift
import FPAppUI
import SwiftUI

/// Not `@main`: `Launcher` is the entry point. WP-501 replaces the body (ui-shell.md D1).
struct FontPlaygroundApp: App {
    var body: some Scene {
        WindowGroup("Font Playground") { RootView() }
    }
}
```

**7. `scripts/codex-setup.sh`** (bash, idempotent, run by Codex cloud with network before the offline agent phase):

1. `set -euo pipefail`, `cd` to the repository root, `source scripts/tool-versions.env`.
2. uv: if `uv --version` is not exactly `uv ${UV_VERSION}…`, run `python3 -m pip install --disable-pip-version-check "uv==${UV_VERSION}"`. Then recheck the version: if the pinned `uv` is absent or shadowed by an older executable, link `$(python3 -c 'import uv; print(uv.find_uv_bin())')` into `~/.local/bin`, prepend that directory to PATH for this run, and append `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc` once. This keeps system binaries intact and makes the pinned version resolvable from a fresh shell. If pip is unavailable, fall back to `curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh`. If it still fails: `codex-setup: could not install uv ${UV_VERSION}`, exit 1.
3. `make setup` (downloads Python 3.12 if missing, plus every locked package).
4. If `swift` exists: `swift build --package-path Packages/FontPlaygroundKit --build-tests` (warms `.build`). Otherwise print `codex-setup: WARNING: swift not found; use the linux/amd64 image with CODEX_ENV_SWIFT_VERSION=6.2 (docs/dispatch.md)` and continue.
5. Print `uv --version`, `uv run --project engine --frozen python --version`, the first line of `swift --version` (if present), `make --version | head -1` and `git --version`.

**8. CI: `.github/workflows/ci.yml`** (normative shape; use the current major tag of each action at implementation time, for example `actions/checkout@v5` and `astral-sh/setup-uv@v6` or later):

```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request:
  workflow_dispatch:
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
permissions:
  contents: read
jobs:
  linux:
    name: Linux (Swift ${{ matrix.swift }})
    runs-on: ubuntu-24.04
    container: swift:${{ matrix.swift }}-noble
    strategy:
      fail-fast: false
      matrix:
        swift: ["6.1", "6.2"]
    steps:
      - name: Install make, git and curl
        run: apt-get update && apt-get install -y --no-install-recommends make git curl ca-certificates
      - uses: actions/checkout@v7
      - name: Trust the workspace for git
        run: git config --global --add safe.directory "$GITHUB_WORKSPACE"
      - name: Read pinned tool versions
        run: grep -E '^[A-Z_]+=' scripts/tool-versions.env >> "$GITHUB_ENV"
      - uses: astral-sh/setup-uv@v7
        with:
          version: ${{ env.UV_VERSION }}
          enable-cache: true
          cache-dependency-glob: engine/uv.lock
      - run: make setup
      - run: make lint engine-test conformance-check kit-test
      - name: Codex setup script is idempotent and leaves an offline-capable tree (AC-001-17)
        if: matrix.swift == '6.2'
        run: |
          bash scripts/codex-setup.sh
          bash scripts/codex-setup.sh
          UV_OFFLINE=1 make lint engine-test kit-test
  macos:
    name: macOS
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v7
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable
      - name: Read pinned tool versions
        run: grep -E '^[A-Z_]+=' scripts/tool-versions.env >> "$GITHUB_ENV"
      - uses: astral-sh/setup-uv@v7
        with:
          version: ${{ env.UV_VERSION }}
          enable-cache: true
          cache-dependency-glob: engine/uv.lock
      - run: brew install xcodegen
      - run: make setup
      - run: make lint
      - run: make test
      - run: make app
      - run: make self-test
```

If `macos-26` is not available to the repository, use the newest macOS image whose `latest-stable` Xcode is ≥ 26. `make app` fails otherwise, through `check-macos-toolchain.sh`.

**9. Docs.** `docs/development.md` covers:
- Prerequisites per OS: on macOS 14+, Xcode 26+ and `brew install uv xcodegen`; on Linux, a Swift 6.1/6.2 toolchain and uv.
- Macs ship no `python`, and `/usr/bin/python3` (3.9) is too old; uv fetches Python 3.12 from `.python-version`, and no `pip install -e '.[dev]'` is needed (TOOLING-M1).
- `make setup` / `make test` / `make lint` / `make app`, and opening the generated project with `open App/FontPlayground.xcodeproj`.
- `FP_ENGINE_PYTHON`.
- Signing local builds with `make app FP_CODESIGN_IDENTITY="Apple Development" FP_DEVELOPMENT_TEAM=<team>` so privacy grants survive rebuilds (TOOLING-M3).
- The safety rules of docs/testing.md §5.
- Codex environments (link docs/dispatch.md).

`README.md` gets a short "Development" section that links it. There are no `.venv\Scripts` paths and no `run.bat` anywhere (TOOLING-6).

**10. Repository tests** (`engine/tests/repo/test_repo_hygiene.py`, §S9):

| Test | Asserts |
|---|---|
| `test_make_targets_match_testing_md` | The set of targets in the docs/testing.md §1 table (`` `make <t>` `` in the first column) equals the set of public Makefile targets (`^([a-z][a-z0-9-]*):(?!=)`, names not starting with `_`) |
| `test_conformance_check_detects_fixture_drift` | In a temp git repo (commit identity via `-c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false`) with `spec/fixtures/a.json` committed, `make -C <tmp> -f <ROOT>/Makefile conformance-check UV=/usr/bin/true` exits 0. It exits non-zero after `a.json` is edited, and non-zero after an untracked `b.json` is added |
| `test_tooling_m1_setup_explains_missing_uv` | `make -C ROOT setup UV=/nonexistent/uv` exits non-zero, and stderr contains `uv not found` and `brew install uv` |
| `test_tooling_m1_python_version_is_pinned` | `.python-version` contains `3.12`; `requires-python` is `>=3.12` |
| `test_macos_only_targets_refuse_on_linux` (skip on darwin) | `make mac-test`, `make app`, `make helper-runtime` and `make engine-apple-fonts` each exit 2 with `needs macOS` on stderr |
| `test_tooling_17_engine_pyproject_hygiene` | `project.license == "MIT"` (a string); no `project.scripts` / `project.gui-scripts`; `dependency-groups.dev` contains `pytest`, `jsonschema` and `ruff`; the dependencies are exactly `fonttools[unicode]>=4.65` and `skia-pathops>=0.9`; the backend is `uv_build` |
| `test_tooling_6_dev_docs_have_no_windows_only_commands` | `README.md` and `docs/development.md` contain none of `\Scripts\`, `.venv\`, `run.bat`, `pip install -e .[dev]`. `README.md` links `docs/development.md`. `docs/development.md` contains `make setup` and `uv`. (WP-602 rewrites the README; it keeps the link, so this test keeps passing.) |
| `test_tooling_4_ci_runs_linux_and_macos_jobs` | Parsed as text (no YAML library): `ci.yml` contains a job on `ubuntu-` with `swift:` containers `6.1` and `6.2` that runs `make lint engine-test conformance-check kit-test` and `scripts/codex-setup.sh`, and a job on `macos-` that runs `make setup`, `make lint`, `make test` and `make app` |
| `test_kit_is_foundation_only` | No `.swift` file under `Packages/FontPlaygroundKit` has an `import` of `AppKit`, `SwiftUI`, `CoreText`, `CoreGraphics`, `Cocoa`, `UIKit` or `Combine`. `Darwin` and `Glibc` imports appear only inside `#if canImport(Glibc)` / `#elseif canImport(Darwin)` (AGENTS rule 2) |

### Acceptance criteria
- **AC-001-1** `make -pRrq : 2>/dev/null | awk -F: '/^[a-z][a-z-]*:([^=]|$)/ {print $1}' | sort -u` prints exactly `app conformance conformance-check engine-apple-fonts engine-test helper-runtime kit-test lint mac-test self-test setup test`. (`test_make_targets_match_testing_md`)
- **AC-001-2** (linux) In a clean clone in `swift:6.1-noble` and in `swift:6.2-noble` with uv installed: `make setup && make lint engine-test conformance-check kit-test` exits 0. Evidence: the CI `linux` job, both matrix entries green.
- **AC-001-3** (macos) On macOS 14+ with Xcode ≥ 26: `make setup lint test app self-test` exits 0. Evidence: the CI `macos` job green, plus the maintainer's local tail.
- **AC-001-4** `make engine-test` passes `test_version_matches_pyproject`, `test_runtime_dependencies_import` and every test in `engine/tests/repo/test_repo_hygiene.py`. `test_apple_fonts_suite_is_wired` is reported **skipped** with reason `needs macOS…` (linux) or `…FP_APPLE_FONTS=1…` (macos).
- **AC-001-5** (macos) `make engine-apple-fonts` reports `1 passed`.
- **AC-001-6** Before WP-202, `make conformance-check` exits 0 and prints `conformance: tools/conformance/generate.py does not exist yet (WP-202); nothing to generate`. Drift and untracked fixtures make it fail. (`test_conformance_check_detects_fixture_drift`)
- **AC-001-7** TOOLING-M1: `make setup UV=/nonexistent/uv` exits non-zero with the install hint (`test_tooling_m1_setup_explains_missing_uv`), and `.python-version` pins 3.12 (`test_tooling_m1_python_version_is_pinned`).
- **AC-001-8** (linux) The macOS-only targets exit 2 with `needs macOS`. (`test_macos_only_targets_refuse_on_linux`)
- **AC-001-9** TOOLING-17: `test_tooling_17_engine_pyproject_hygiene` passes, and `cd engine && uv build --offline --wheel` produces `dist/fpengine-0.1.0-py3-none-any.whl` without network.
- **AC-001-10** TOOLING-6: `test_tooling_6_dev_docs_have_no_windows_only_commands` passes.
- **AC-001-11** TOOLING-4: `test_tooling_4_ci_runs_linux_and_macos_jobs` passes, and the WP-001 PR shows both CI jobs green.
- **AC-001-12** `make kit-test` runs `moduleIsLinked`, `protocolVersionIsOne`, `versionFlagPrintsVersion` and `unknownArgumentsPrintUsage`, all passing. `swift run --package-path Packages/FontPlaygroundKit fpctl --version` prints `fpctl 0.1.0`.
- **AC-001-13** `test_kit_is_foundation_only` passes.
- **AC-001-14** (macos) `make mac-test` runs `moduleIsLinked` and `rootViewBuildsOffscreen`, both passing.
- **AC-001-15** (macos) After `make app`, for `APP="build/DerivedData/Build/Products/Debug/Font Playground.app"`:
  - `plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist"` prints `io.github.kciceblue.fontplayground`.
  - `plutil -extract CFBundleName raw …` prints `Font Playground`.
  - `plutil -extract LSMinimumSystemVersion raw …` prints `14.0`.
  - `plutil -extract CFBundleShortVersionString raw …` prints `0.1.0`.
  - `lipo -archs "$APP/Contents/MacOS/Font Playground"` prints `arm64`.
  - `otool -l "$APP/Contents/MacOS/Font Playground" | awk '/LC_BUILD_VERSION/{f=1} f&&$1=="sdk"{print $2; exit}'` prints a version ≥ 26.0.
  - `codesign -d --entitlements - --xml "$APP"` prints nothing, or only a dictionary whose single key is `com.apple.security.get-task-allow` (Xcode's Debug injection, §S4).
- **AC-001-16** (macos) `make self-test` exits 0 within 10 s of the build finishing, and its last stdout line parses as JSON with `"result": "passed"`. By review: in `Launcher.swift` the `--self-test` branch calls `exit` before the only call to `FontPlaygroundApp.main()`, so `NSApplication` is never created on that path; the CI `macos` job (no logged-in GUI session) runs it green.
- **AC-001-17** The CI `linux` job (matrix entry 6.2) step "Codex setup script is idempotent…" is green: `bash scripts/codex-setup.sh` exits 0 twice in a row, then `UV_OFFLINE=1 make lint engine-test kit-test` exits 0 (an offline proxy for the agent phase). After merge, the maintainer configures the Codex cloud environment per docs/dispatch.md and pastes the setup log tail into the PR or issue (not a merge blocker).
- **AC-001-18** Lint gates: `make lint` exits 0 on the tree. A file containing `let  x = 1` fails `swift format lint --strict --configuration .swift-format <file>` (non-zero). A Python file with an unused import fails `uv run --project engine ruff check <file>` (non-zero).
- **AC-001-M1** (manual, macos) `open "build/DerivedData/Build/Products/Debug/Font Playground.app"` shows one window titled "Font Playground" with the placeholder text. The screenshot shows the window and the menu bar reading "Font Playground".

| Finding | Regression test / AC |
|---|---|
| TOOLING-4 | `test_tooling_4_ci_runs_linux_and_macos_jobs`; AC-001-2, -3, -11 |
| TOOLING-6 | `test_tooling_6_dev_docs_have_no_windows_only_commands`; AC-001-10 |
| TOOLING-17 | `test_tooling_17_engine_pyproject_hygiene`; AC-001-9 |
| TOOLING-M1 | `test_tooling_m1_setup_explains_missing_uv`, `test_tooling_m1_python_version_is_pinned`; AC-001-7 |

### Verification
```bash
make setup
make lint test
make -pRrq : 2>/dev/null | awk -F: '/^[a-z][a-z-]*:([^=]|$)/ {print $1}' | sort -u
make app self-test                                   # macos
swift run --package-path Packages/FontPlaygroundKit fpctl --version
```

### Notes for the implementer
- **Network.** Creating `engine/uv.lock` needs PyPI, and possibly a Python 3.12 download. Codex cloud has no network during the task. Implement WP-001 with Codex CLI on the Mac, or enable agent internet for this one task with an allowlist (`pypi.org`, `files.pythonhosted.org`, `github.com`, `objects.githubusercontent.com`, `astral.sh`). Every later linux WP runs offline, so **all** runtime and dev dependencies are declared here and no linux WP re-locks. Only macos WPs (which run with network) may re-lock, and only when their spec says so (WP-701's version bump).
- `required-version` in `[tool.uv]` makes `make setup` fail with uv's own message when a developer's uv is outside 0.12.x (for example after `brew upgrade uv`). That is deliberate: `uv_build` must match the running uv for offline builds. Bumping uv means changing `UV_VERSION`, `required-version` and the `uv_build` bound together, then `uv lock`, in one PR. Say this in `docs/development.md`.
- xcodegen was not installed on the Mac used to write this spec, so the `project.yml` above was not run through xcodegen here. The Xcode, swiftc, swift-format, SwiftPM and GNU Make 3.81 parts were verified (Context). If xcodegen rejects a key, fix it and record the deviation.
- `swift format` versions differ between the Linux toolchains (6.1/6.2) and Xcode's. If they disagree on a file in `FontPlaygroundKit`, format it so both accept it. The Linux CI job is authoritative for that package.
- Do not add a `[tool.ruff]` section to `engine/pyproject.toml`. Do not add `license-files` (paths must be inside `engine/`).
- `FontPlaygroundApp` stays un-annotated. If WP-501 later writes `@main struct FontPlaygroundApp`, the build fails with two entry points. The `Launcher` wins (§S6).
- `hdiutil` and `diskutil` are not used here. Don't open windows in any automated test.

---

## WP-002: Import engine as `fpengine` (uv project, Qt-free, tests ported, POSIX-clean)

**Goal:** `engine/src/fpengine` holds the reference engine, `catalog/face.py` and the face-dict helpers under the new package name, with identical behaviour, and the ported tests pass on Linux and macOS.
**Depends on:** WP-001 · **Env:** linux · **Size:** M · **Closes findings:** TOOLING-3, TOOLING-18 (engine side; other sub-items in WP-106/303/305/401), TOOLING-23

### Scope
- In:
  - Copy and rename the engine modules, `face.py` and `records.py`.
  - Port the engine, face, fixture and record tests plus the `font_dir` fixture.
  - Regression tests for the three findings.
  - `tools/reference_parity.py`: a behaviour-preservation check against `reference/`.
  - Lint-clean formatting of the imported code.
- Out:
  - Any behaviour change: every engine fix is a later WP (101–110).
  - `scanner.py`, `paths.py` and `CatalogCache` file IO: Swift owns discovery and the cache (ADR-0007, WP-401).
  - `__main__.py` and the protocol (WP-201).
  - Dependency changes (fixed by WP-001).
  - TOOLING-18's sub-items that belong elsewhere:
    - (a) path dedupe → WP-401 (CATALOG-9)
    - (b) the `bhed` bitmap font → WP-106 (CATALOG-8)
    - (c) absolute-path recipe keys → WP-303/305/401 (ENGINE-8, CATALOG-7)
    - (d) cache location → WP-401 (CATALOG-M3)

### Touched paths
- `engine/src/fpengine/{face,records,scripts,spec,planner,prepare,kern,synth_bold,merge,forge}.py` (new)
- `engine/tests/conftest.py` (edit), `engine/tests/fixtures.py` (new)
- `engine/tests/{test_fixtures,test_face,test_records,test_forge,test_planner,test_prepare,test_scripts,test_spec,test_synth_bold}.py` (new)
- `engine/tests/test_package.py` (edit: add the reference version test), `engine/tests/test_posix_clean.py` (new)
- `tools/reference_parity.py` (new)
- `engine/README.md` (edit: module map)

### Design

**1. Module map** (copy verbatim, then apply only the edits listed):

| Reference | Destination | Edits |
|---|---|---|
| `fontplayground/engine/forge.py` | `fpengine/forge.py` | imports (incl. UP035 `Callable` from `collections.abc`); line 27 reflowed by `ruff format` |
| `fontplayground/engine/kern.py` | `fpengine/kern.py` | imports; line 108 reflowed by `ruff format` |
| `fontplayground/engine/merge.py` | `fpengine/merge.py` | imports |
| `fontplayground/engine/planner.py` | `fpengine/planner.py` | imports |
| `fontplayground/engine/prepare.py` | `fpengine/prepare.py` | imports; line 19 reflowed by `ruff format` |
| `fontplayground/engine/scripts.py` | `fpengine/scripts.py` | UP033 (`functools.cache` for `lru_cache(maxsize=None)`) |
| `fontplayground/engine/spec.py` | `fpengine/spec.py` | imports (incl. the function-local import in `ForgeReport.as_text`); UP037 unquotes `"ForgeSpec"`; line 122 reflowed |
| `fontplayground/engine/synth_bold.py` | `fpengine/synth_bold.py` | — |
| `fontplayground/catalog/face.py` | `fpengine/face.py` | imports; line 189 reflowed by `ruff format` |
| `fontplayground/catalog/cache.py:13-40` (`_ranges`, `_expand`, `face_to_dict`, `face_from_dict`) | `fpengine/records.py` | public names `ranges`, `expand` |
| `fontplayground/catalog/cache.py:43-83` (`CatalogCache`, `SCHEMA`) | — | not imported (WP-401) |
| `fontplayground/catalog/scanner.py`, `fontplayground/paths.py` | — | not imported (WP-401; TOOLING-3, TOOLING-18) |
| `fontplayground/__init__.py`, `__main__.py`, `ui/*` | — | `__version__` already in WP-001; `__main__` is WP-201; UI is Swift |

Rename rules, applied with a scripted rewrite, then reviewed:
- `fontplayground.engine.` → `fpengine.`
- `from fontplayground.engine import merge as M` → `from fpengine import merge as M`
- `fontplayground.catalog.face` → `fpengine.face`
- `fontplayground.catalog.cache` → `fpengine.records`

Keep the docstrings, `FORGED_NOTICE` (contracts §6) and the `TemporaryDirectory(prefix="fontplayground-")` prefix (`engine/forge.py:41`) unchanged. Then run `uv run --project engine --frozen ruff check --fix engine tools` and `… ruff format engine tools`. That is enough to reach zero findings (Context 5). Import order, line breaks, whitespace and quote style may change. The only expression rewrites allowed are the three behaviour-preserving autofixes UP033, UP035 and UP037; undo any other rewrite `--fix` makes (a newer ruff may add rules). If a finding remains that only a code change would fix, add a `# noqa: <code>` with a reason instead of changing the code.

`fpengine/records.py` (normative):

```python
"""FontFace <-> JSON-ready dict. Code points travel as sorted, inclusive ranges (contracts §2)."""
from __future__ import annotations

from collections.abc import Iterable
from dataclasses import asdict

from fpengine.face import FontFace


def ranges(codepoints: Iterable[int]) -> list[list[int]]:
    out: list[list[int]] = []
    for cp in sorted(codepoints):
        if out and cp == out[-1][1] + 1:
            out[-1][1] = cp
        else:
            out.append([cp, cp])
    return out


def expand(rs: Iterable[Iterable[int]]) -> frozenset[int]:
    return frozenset(cp for lo, hi in rs for cp in range(lo, hi + 1))


def face_to_dict(face: FontFace) -> dict:
    d = asdict(face)
    d["codepoints"] = ranges(face.codepoints)
    d["axes"] = [list(a) for a in face.axes]
    return d


def face_from_dict(d: dict) -> FontFace:
    d = dict(d)
    d["codepoints"] = expand(d["codepoints"])
    d["axes"] = tuple(tuple(a) for a in d["axes"])
    d["local_names"] = tuple(d.get("local_names", ()))
    d["group_counts"] = tuple((g, n) for g, n in d.get("group_counts", ()))
    return FontFace(**d)
```

This dict layout is the reference cache layout. WP-106 adds `face_record`/`face_from_record` (the contracts §3 `FaceRecord`) to this module, and WP-201 serialises with those.

**2. Test port map:**

| Reference test file | Destination | Changes |
|---|---|---|
| `tests/conftest.py` | `engine/tests/conftest.py` (append to WP-001's) | Keep only `font_dir` (`conftest.py:34-45`). Drop the `QT_QPA_PLATFORM` line (`:7`), `_collect_cycles` and `_reset_theme` (`:12-31`, Qt-only) |
| `tests/fixtures.py` | `engine/tests/fixtures.py` | `from fpengine.face import FontFace` |
| `test_fixtures.py` (2 functions) | same name | none |
| `test_face.py` (11 functions, 16 items) | same name | imports |
| `test_forge.py` (8) | same name | imports |
| `test_planner.py` (6), `test_prepare.py` (5), `test_scripts.py` (3 functions, 22 items), `test_spec.py` (3), `test_synth_bold.py` (4) | same names | imports |
| `test_catalog.py::test_face_dict_roundtrip`, `::test_face_dict_roundtrip_keeps_local_names_and_group_counts` | `test_records.py` | `from fpengine.records import face_to_dict, face_from_dict` |
| `test_catalog.py` (the other 5: scanner and cache IO) | — | not ported; the behaviours are re-specified for Swift in mac-services.md (WP-401) |
| `test_paths.py` | — | not ported (TOOLING-3: `paths.py` is not imported) |
| `test_package.py` | `engine/tests/test_package.py` | WP-001 already asserts the version; keep the reference name `test_version`, asserting `fpengine.__version__ == importlib.metadata.version("fpengine")` |
| everything else (`test_model.py`, `test_smart.py`, … UI) | — | ported to Swift by core.md and the UI specs |

Test function names and parametrisations stay **identical**, so `tools/reference_parity.py --tests` can check the port mechanically. `tests` stays a package (`engine/tests/__init__.py`), so `from tests.fixtures import …` works as in the reference with pytest's default rootdir import.

**3. New tests** (`engine/tests/test_posix_clean.py`):

```python
WINDOWS_ONLY = [r"[A-Za-z]:\\\\", r"\bWINDIR\b", r"\bLOCALAPPDATA\b", r"\bwinreg\b", r"\bwindll\b",
                r"os\.startfile", r"PureWindowsPath", r"sys\.platform\s*==\s*[\"']win32", r"platform\.startswith\([\"']win"]
```

| Test | Asserts |
|---|---|
| `test_tooling_3_engine_sources_are_posix_clean` | No `engine/src/fpengine/**/*.py` matches any `WINDOWS_ONLY` pattern; `importlib.util.find_spec("fpengine.paths") is None` |
| `test_tooling_18_engine_has_no_discovery_or_cache_io` | `find_spec` is `None` for `fpengine.scanner`, `fpengine.paths`, `fpengine.cache` and `fpengine.catalog`. `records.py` source contains none of `open(`, `.write_text(`, `.read_text(`, `json.dump(`, `.lower()` |
| `test_tooling_18_read_faces_keeps_the_given_path` | A symlink `tmp_path / "Mixed Case Link.TTF"` → `font_dir / "A.ttf"`: `read_faces(link)[0].path == str(link)` and `.key == (str(link), 0)`. The engine neither resolves nor case-folds paths (contracts §2) |
| `test_tooling_23_forge_temp_files_live_in_tmpdir` | With `TMPDIR` set to `tmp_path / "helper-tmp"` and `tempfile.tempdir` reset to `None` (as in a fresh helper process), a forge of `A.ttf`: during stage `merge` that directory holds exactly one entry starting with `fontplayground-`, and after the forge it is empty |
| `test_engine_is_qt_free_and_renamed` | No `.py` file under `engine/src` or `engine/tests` has a line matching `^\s*(from|import)\s+(fontplayground|PySide6|shiboken6|pytestqt)\b` (so string literals, such as this test's own list, don't count) |

**4. `tools/reference_parity.py`** (temporary; deleted at WP-701). It is a script, not a pytest file, because WP-101 onward change engine output on purpose. After those WPs it is expected to report differences.

```
uv run --project engine python tools/reference_parity.py [--tests]
```

- First statement: `sys.dont_write_bytecode = True`, so nothing is written under `reference/`. Then it inserts `<root>/engine` and `<root>/reference/fontplayground-py` at the front of `sys.path`. Imports happen inside functions (no E402).
- `sys.path` order after the inserts is `[<root>/engine, <root>/reference/fontplayground-py, …]`: both trees have a `tests` package, and `tests.fixtures` must resolve to `engine/tests/fixtures.py`.
- It builds the six `font_dir` fixtures exactly as `engine/tests/conftest.py` does (`A.ttf`, `B.otf`, `C.ttf`, `V.ttf`, `T.ttc`, `K.ttf`) in a `tempfile.TemporaryDirectory`.
- **Scan parity:** for each fixture file, `[fontplayground.catalog.cache.face_to_dict(f) for f in reference read_faces(p)] == [fpengine.records.face_to_dict(f) for f in fpengine.face.read_faces(p)]`.
- **Forge parity:** it sets `merge.date` in both packages to a class whose `today()` returns `2026-01-01` (name ID 3 contains the date), then forges each case with both engines:

| Case | Materials `(file, index, weight, scale)` | ForgeSpec kwargs |
|---|---|---|
| `two-materials-han-rule` | A 0, B 0 | `script_rules={"han": 1}, family_name="Forged Test"` |
| `bold-and-scale` | A 0 (700, 0.5) | `style_name="Bold"` |
| `restricted-2048-upem` | C 0 | — |
| `old-os2-kern` | K 0 | — |
| `non-ascii-family` | A 0 | `family_name="合体字体"` |
| `variable-at-900` | V 0 (900) | — |
| `collection-index-1-plus-cff` | T 1, B 0 (scale 1.2) | `default_weight=600, family_name="Mix", style_name="SemiBold Italic"` |

  Outputs are equal when every table except `head` has identical raw bytes (`font.reader[tag]`), `head` compiles identically after setting `created = modified = checkSumAdjustment = 0`, and `dataclasses.asdict(report)` is equal with `output_path` blanked.
- Output: one line per comparison (`same forge <case>` / `DIFF forge <case>: <tags>`), then `parity: 7 forges, 6 scans, 0 differences`. Exit 1 on any difference.
- `--tests` parses (with `ast`) the top-level `def test_*` names of each reference test file in the port map (only the two ported names of `test_catalog.py`) and of its destination. It prints each missing name as `missing: <file>::<name>` and exits 1 if there is one, else prints `tests: 45 reference test functions ported`. It does not import or run anything.

### Acceptance criteria
- **AC-002-1** `make engine-test` passes. The run includes the 69 ported tests (by name), the tests of §3, and WP-001's tests.
- **AC-002-2** `uv run --project engine python tools/reference_parity.py --tests` prints `tests: 45 reference test functions ported` and exits 0. `make engine-test` collects the 69 items of those functions (visible with `uv run --project engine pytest --collect-only -q`).
- **AC-002-3** Behaviour preservation: `uv run --project engine python tools/reference_parity.py` prints `parity: 7 forges, 6 scans, 0 differences` and exits 0. Run in a clean clone, `git status --porcelain --ignored reference/` stays empty afterwards.
- **AC-002-4** TOOLING-3: `test_tooling_3_engine_sources_are_posix_clean` passes, and the CI `linux` and `macos` jobs run the ported suite with 0 failures.
- **AC-002-5** TOOLING-18: `test_tooling_18_read_faces_keeps_the_given_path` and `test_tooling_18_engine_has_no_discovery_or_cache_io` pass.
- **AC-002-6** TOOLING-23: `test_tooling_23_forge_temp_files_live_in_tmpdir` passes.
- **AC-002-7** `test_engine_is_qt_free_and_renamed` passes, and `grep -rn "fontplayground\." engine/src` finds nothing.
- **AC-002-8** `make lint` exits 0 (ruff check and format over `engine` and `tools`).
- **AC-002-9** No dependency change: `git diff --name-only "$(git merge-base HEAD main)" HEAD` (use `origin/main` if no local `main` exists) lists neither `engine/pyproject.toml` nor `engine/uv.lock`.
- **AC-002-10** `fpengine` imports with no Apple frameworks: `uv run --project engine python -c "import fpengine.forge, fpengine.face, fpengine.records"` exits 0 in the `swift:6.2-noble` CI container (the `linux` job's `make engine-test`).

| Finding | Regression test |
|---|---|
| TOOLING-3 | `test_tooling_3_engine_sources_are_posix_clean` (+ green suite on both OSes) |
| TOOLING-18 | `test_tooling_18_read_faces_keeps_the_given_path`, `test_tooling_18_engine_has_no_discovery_or_cache_io` |
| TOOLING-23 | `test_tooling_23_forge_temp_files_live_in_tmpdir` |

### Verification
```bash
make lint engine-test
uv run --project engine python tools/reference_parity.py --tests
uv run --project engine python tools/reference_parity.py
```

### Notes for the implementer
- Codex cloud has no network: never run `uv lock`, `uv add` or `uv sync` without `--frozen`. Everything WP-002 needs is in WP-001's lock.
- Keep behaviour byte-identical. If `ruff check --fix` proposes a rewrite that changes an expression (not only imports or formatting), undo it. `B905` is ignored in `ruff.toml` for this reason.
- The Qt autouse fixtures (`conftest.py:12-31`) exist for Qt objects; the engine tests need none of them.
- The sibling specs (engine-correctness.md §1, engine-metadata.md §S1, helper.md H8) all build on this layout: `fpengine/face.py`, and `fpengine/records.py` with `ranges`, `expand`, `face_to_dict` and `face_from_dict` (WP-106 adds `face_record`/`face_from_record`). Do **not** add `fpengine/catalog/` or alias modules.
- The prototype port took about 10 minutes of mechanical work. The parity check ran in under 2 s.

---

## WP-601: Bundle, sign, notarize, DMG, `--self-test`, SDK check, release workflow

**Goal:** One command produces a notarized, stapled `FontPlayground-<version>-arm64.dmg` whose app runs its headless self-test through the embedded engine, and CI proves the same pipeline ad hoc on every change to main.
**Depends on:** WP-203, WP-305, WP-501 · **Env:** macos · **Size:** L · **Closes findings:** TOOLING-1, TOOLING-8, TOOLING-9, TOOLING-10, TOOLING-11, TOOLING-13, TOOLING-14, CRIT-1

### Scope
- In:
  - Embed `build/helper/fpengine` per §S3 through a `project.yml` build phase.
  - Licence collection (§S5 mechanism).
  - Icon Composer icon.
  - Info.plist completion and checks.
  - The full `--self-test` (§S6), `AppLog` (§S7) and the SDK check.
  - Signing, notarization, DMG and release scripts.
  - `release.yml`, the CI additions, and a maintainer runbook `docs/release.md`.
- Out:
  - Building the runtime (WP-203).
  - The About panel and Help UI (WP-501).
  - Licence **texts** for static components, `Acknowledgements.txt` content and user docs (WP-602).
  - Universal2 (backlog B-3).
  - Homebrew cask (B-9).

### Touched paths
- `App/project.yml` (edit: build phases, icon), `App/Info.plist` (edit: icon keys if missing), `App/Resources/AppIcon.icon/{icon.json,Assets/mark.png}` (new), `App/Resources/Assets.xcassets/AppIcon.appiconset` (delete, if WP-501 created it), `App/Sources/Launcher.swift` (edit)
- `Packages/FontPlaygroundMacKit/Sources/FPAppUI/SelfTest/{SelfTest.swift,SelfTestRunner.swift,SelfTestDeadline.swift,SelfTestOutput.swift,BuiltFontCheck.swift}` (new), `…/FPAppUI/Resources/self-test.fontrecipe` (new), `…/FPAppUI/Diagnostics/AppLog.swift` (new unless WP-501 has one)
- `Packages/FontPlaygroundMacKit/Tests/FPAppUITests/SelfTestTests.swift` (new)
- `scripts/{embed-helper.sh,collect-licenses.sh,sign-app.sh,notarize.sh,make-dmg.sh,check-sdk.sh,check-bundle.sh,release.sh}` (new), `scripts/icon/render-mark.swift` (new), `scripts/tests/{test_crit_1_check_sdk.sh,test_tooling_1_sign_adhoc.sh}` (new)
- `tools/release/collect_licenses.py` (new), `App/Licenses/README.md` (new; WP-602 fills the folder)
- `.github/workflows/ci.yml` (edit), `.github/workflows/release.yml` (new)
- `engine/tests/repo/test_release_config.py` (new)
- `docs/release.md` (new), `docs/development.md` (edit: link to the runbook)

### Design

**1. Embedding the helper (`scripts/embed-helper.sh`, build phase 1).** In `project.yml`, under the `FontPlayground` target:

```yaml
    postBuildScripts:
      - name: Embed fpengine helper runtime
        shell: /bin/bash
        script: '"${SRCROOT}/../scripts/embed-helper.sh"'
        basedOnDependencyAnalysis: false
      - name: Collect licences
        shell: /bin/bash
        script: '"${SRCROOT}/../scripts/collect-licenses.sh"'
        basedOnDependencyAnalysis: false
```

Xcode runs these after Copy Bundle Resources and before its own CodeSign step. `embed-helper.sh` reads Xcode's environment:
1. `src="${FP_HELPER_RUNTIME_DIR:-$SRCROOT/../build/helper/fpengine}"`, `res="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/fpengine"`, `link="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/fpengine"`.
2. If `"$src/bin/python3"` is not executable:
   - `CONFIGURATION == Release` → print `error: helper runtime missing at <src>; run 'make helper-runtime' (WP-203)` and exit 1.
   - Otherwise print `warning: helper runtime not found at <src>; the app will use FP_ENGINE_PYTHON`, remove `res` and `link`, and exit 0.
3. `rsync -a --delete "$src/" "$res/"`.
4. **TOOLING-10:** for every Mach-O under `res` whose `lipo -archs` is not exactly `arm64`, run `lipo -thin arm64 -output <f>.thin <f> && mv <f>.thin <f>`.
5. `mkdir -p "$(dirname "$link")"; ln -sfn ../Resources/fpengine "$link"`.
6. Sign the helper Mach-Os per §S4 with `$EXPANDED_CODE_SIGN_IDENTITY` (ad-hoc when it is `-` or empty), inside-out. Xcode then signs the app and seals everything.
7. Fail (exit 1) if any directory whose name contains a `.` exists under `$CONTENTS_FOLDER_PATH/MacOS` or `…/Frameworks` (§S3).

**2. Licences (`scripts/collect-licenses.sh` → `tools/release/collect_licenses.py`, build phase 2; TOOLING-11).**

```
python3 tools/release/collect_licenses.py --app <app> --repo <root> [--check]
```

- It runs with `<app>/Contents/Resources/fpengine/bin/python3 -I -B` when the runtime is embedded. That way `importlib.metadata.distributions()` sees the bundled wheels, and `detect` snippets run in the bundled interpreter. Without a runtime (Debug with no helper), the shell wrapper copies `LICENSE` and `App/Licenses/*` into `Licenses/` with `ditto` and writes no `index.json`.
- It collects:
  - `LICENSE` → `Font Playground` (MIT, kind `app`, version from `CFBundleShortVersionString`).
  - `<prefix>/lib/python3.12/LICENSE.txt` → `CPython` (`PSF-2.0`, kind `runtime`, version `platform.python_version()`).
  - Every installed distribution except `fpengine` (whose licence is the app's) → name, version, licence (`License-Expression`, else `License`, else a `License :: OSI Approved :: …` classifier mapped to SPDX), and files (`dist.files` under `licenses/` or named `LICENSE*`, `COPYING*`, `NOTICE*`), kind `wheel`.
  - Every entry of `App/Licenses/components.json` (§S5) whose `detect` succeeds, or that has none, kind `static`.
- It writes `Licenses/` and `index.json` and regenerates `Acknowledgements.txt` as §S5 says.
- `--check` (used by `check-bundle.sh --release` and by WP-602) exits 1 and names each problem if: a component that `detect` finds has no files; a listed file is missing or empty; a wheel has no licence file; or `index.json` lacks any of `Font Playground`, `CPython`, `fonttools`, `skia-pathops`, `unicodedata2`.

**3. Icon (TOOLING-9).**
- `App/Resources/AppIcon.icon/icon.json`:

  ```json
  {
    "fill" : { "automatic-gradient" : "display-p3:0.20000,0.38000,0.92000,1.00000" },
    "groups" : [ { "layers" : [ { "image-name" : "mark.png", "name" : "mark" } ] } ],
    "supported-platforms" : { "squares" : "shared" }
  }
  ```
- `Assets/mark.png` (1024×1024, transparent) comes from `swift scripts/icon/render-mark.swift App/Resources/AppIcon.icon/Assets/mark.png`. The script draws a geometric mark with CoreGraphics paths only (two overlapping rounded letter-like forms in white and 60 % white), with **no font glyphs**, so no font licence applies to the icon. The PNG is committed. The maintainer may replace the art later without a spec change.
- Xcode 26+ compiles an `.icon` in the target's resources together with any asset catalog into one `Assets.car`, plus `AppIcon.icns`, and merges `CFBundleIconName`/`CFBundleIconFile` from actool's partial plist. Keep `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`. Remove any empty `AppIcon.appiconset` from `Assets.xcassets`, because two icons named AppIcon collide.
- If the pinned xcodegen treats `AppIcon.icon` as a group (after `make app`, `Contents/Resources` contains `icon.json` or `mark.png` loose, or `Assets.car` has no `AppIcon`), declare it under `options.fileTypes: { icon: { file: true, buildPhase: resources } }`. If that does not work either, exclude it from sources and add a preBuild script running `xcrun actool App/Resources/AppIcon.icon App/Resources/Assets.xcassets --compile "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH" --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist "$DERIVED_FILE_DIR/icon-partial.plist"`, with both icon keys written in `Info.plist`. The ACs check the result, not the route.

**4. Info.plist (TOOLING-8).** WP-501 commits the keys of ui-shell.md D1. WP-601 adds `CFBundleIconFile = AppIcon` if actool's merge does not provide it, and verifies the built bundle with `scripts/check-bundle.sh`:

| Key | Required value in the built app |
|---|---|
| `CFBundleIdentifier` | `io.github.kciceblue.fontplayground` |
| `CFBundleName`, `CFBundleDisplayName` | `Font Playground` |
| `CFBundleExecutable` | `Font Playground` |
| `CFBundlePackageType` | `APPL` |
| `CFBundleShortVersionString` | `MARKETING_VERSION` of `App/Version.xcconfig` (= `fpengine` version, §S8) |
| `CFBundleVersion` | a positive integer string (release: the CI run number) |
| `LSMinimumSystemVersion` | `14.0` |
| `LSApplicationCategoryType` | `public.app-category.graphics-design` |
| `NSHumanReadableCopyright` | the copyright line of `LICENSE` (`Copyright (c) 2026 kciceblue`) |
| `CFBundleIconName`, `CFBundleIconFile` | `AppIcon` |
| `CFBundleDevelopmentRegion` | `en` |
| `NSHighResolutionCapable` | `true` |
| `NSDocumentsFolderUsageDescription`, `NSDesktopFolderUsageDescription`, `NSDownloadsFolderUsageDescription`, `NSRemovableVolumesUsageDescription`, `NSNetworkVolumesUsageDescription` | present, non-empty (ui-shell.md D1; TOOLING-M3) |
| absent | `NSRequiresAquaSystemAppearance`, `UIDesignRequiresCompatibility` (CRIT-1: it would request the old look), `LSUIElement` |

**5. Self-test implementation (§S6; TOOLING-14).**

`Launcher.swift`, replacing WP-001's stub (verified pattern, Context 6):

```swift
if arguments.contains("--self-test") {
    let environment = ProcessInfo.processInfo.environment
    Task.detached {
        exit(await SelfTest.run(arguments: arguments, environment: environment))
    }
    dispatchMain()
}
```

In FPAppUI:

```swift
public enum SelfTest {
    /// Headless. Parses §S6 options, runs `SelfTestRunner` with the live dependencies, prints JSON Lines, returns the exit code.
    public static func run(arguments: [String], environment: [String: String]) async -> Int32
}

struct SelfTestOptions: Equatable, Sendable {
    var reportURL: URL?
    var keepTemporaryFiles = false
    var requireEmbeddedEngine = false
    var timeout: Duration = .seconds(180)
    static func parse(_ arguments: [String]) throws -> SelfTestOptions   // throws SelfTestUsageError(message:)
}

enum SelfTestStep: String, CaseIterable, Sendable { case environment, engine, recipe, discover, scan, forge, verify, cancel, cleanup }

enum EngineKind: String, Sendable { case embedded, dev }   // summary "engine"; "none" when no engine was resolved

struct BundleInfo: Sendable, Equatable {
    var identifier: String?; var shortVersion: String; var build: String
}

struct SelfTestDependencies: Sendable {
    var bundleInfo: @Sendable () -> BundleInfo                           // live: Bundle.main.infoDictionary
    /// live: EngineLaunch.resolve() (helper.md WP-204); kind = .embedded when the resolved executable lies inside
    /// Bundle.main.bundleURL, else .dev; returns EngineClient(configuration: .init(launch:, temporaryDirectory: helperTemp)).
    /// Throws EngineError.helperNotFound when nothing is found.
    var engine: @Sendable (_ helperTemp: URL) throws -> (any EngineRunning, EngineKind)
    var availableFontURLs: @Sendable () -> [URL]                        // live: CTFontManagerCopyAvailableFontURLs()
    var checkBuiltFont: @Sendable (URL, _ postScriptName: String, _ sample: String) throws -> BuiltFontCheck
    var recipeData: @Sendable () throws -> Data                         // live: Bundle.module "self-test.fontrecipe"
    var temporaryRoot: @Sendable () throws -> URL                       // live: temporaryDirectory/fp-self-test-<UUID>
    var helperProcessIDs: @Sendable () -> Set<Int32>                    // live: §S6 "Observing the helper"
    var removeTemporaryRoot: @Sendable (URL) throws -> Void             // default: FileManager.removeItem; injectable cleanup test seam
    var injectedFailure: String?                                        // live: FP_SELF_TEST_INJECT_FAILURE, DEBUG only
}

struct SelfTestSummary: Codable, Equatable, Sendable {   // §S6 summary object; CodingKeys in snake_case
    var result: String; var failedSteps: [String]; var durationMs: Int; var appVersion: String; var build: String
    var engine: String; var fpengineVersion: String; var macos: String
}

struct SelfTestRunner {
    init(options: SelfTestOptions, dependencies: SelfTestDependencies, output: @escaping @Sendable (String) -> Void)
    func run() async -> (summary: SelfTestSummary, exitCode: Int32)
}
```

- Engine resolution and the helper's `TMPDIR` use WP-204's API unchanged (`EngineLaunch.resolve`, `EngineConfiguration(launch:temporaryDirectory:)`, `EngineClient`). The `cancel` step observes the helper through `helperProcessIDs` (§S6), so **no change to FPEngineClient is needed**. The live `helperProcessIDs` lives in `SelfTest.swift` and is the only code in FPAppUI that imports `Darwin` for `proc_listchildpids`/`proc_pidpath`.
- Recipe resolution uses core.md WP-305: `RecipeDocument.decode(data)`, then `document.makeRecipe(catalog: FaceCatalog(faces))` over the `FaceRecord`s of the `scan` step, then `recipe.forgeRequest(outputPath:)` (core.md WP-303). Rules, weights and names come from the document.
- Overall and per-step deadlines use a bounded race, cancelling losers without waiting indefinitely for non-cooperative dependencies. The overall deadline includes temporary-root preparation. Synchronous filesystem/CoreText dependencies run off the coordinator actor. On expiry the runner cancels the running step (which cancels the helper; ADR-0003), fences all late state changes and output, attempts cleanup, emits exactly one final summary with `result: "timed_out"`, and returns 4. Cleanup after an overall timeout has a 1.5-second grace period (instead of its ordinary 5-second budget), preserving the 10-second timeout's under-12-second return requirement. If preparation returns an owned temporary root after finalization, it is removed without emitting late JSON/stderr. A cleanup operation that outlives its grace period can finish removing the root later, but emits no later output.
- `BuiltFontCheck` (`checkBuiltFont` live implementation) does exactly the §S6 `verify` checks, with `CTFontManagerCreateFontDescriptorsFromURL`, `CTFontDescriptorCopyAttribute(_, kCTFontNameAttribute)`, `CTFontCreateWithFontDescriptor`, `CTFontGetGlyphsForCharacters` and `CTFontCopyTable(_, CTFontTableTag(kCTFontTableName), [])`. It never registers the font.

`Sources/FPAppUI/Resources/self-test.fontrecipe` (processed resource; contracts §8 v1). Both fonts ship with every macOS 14+ install, and the file contents were checked for this spec with fontTools. Georgia has GSUB and 1,111 code points; Menlo-Regular (`Menlo.ttc#0`) has `morx`, 2,727 code points and the box-drawing characters, so the forge also exercises ADR-0008's AAT warning on a simple script:

```json
{
  "format": "fontrecipe", "version": 1,
  "materials": [
    {"face": {"postscript_name": "Georgia", "family": "Georgia", "style": "Regular",
              "path": "/System/Library/Fonts/Supplemental/Georgia.ttf", "index": 0}, "weight": null, "scale": null},
    {"face": {"postscript_name": "Menlo-Regular", "family": "Menlo", "style": "Regular",
              "path": "/System/Library/Fonts/Menlo.ttc", "index": 0}, "weight": null, "scale": null}
  ],
  "main": 0,
  "rules": {"symbols": 1},
  "defaults": {"weight": null, "scale": 1.0},
  "names": {"family": "FP Self Test", "style": "Regular", "family_edited": true, "style_edited": true},
  "sample_text": "Hamburgefonstiv 0123 ─│┌┐"
}
```

Checked with the reference engine: Georgia covers `latin` 715, `greek` 72, `cyrillic` 173, `cjk_symbols` 10, `symbols` 140; Menlo covers `latin` 906, `greek` 341, `cyrillic` 183, `armenian_georgian` 87, `symbols` 1,209. U+2500/2502/250C/2510 are in `symbols`. Neither font covers a group in engine-metadata.md's `COMPLEX_GROUPS` (hebrew, arabic, indic, southeast_asian), so WP-107 reports only warnings (Menlo's `morx`), never `aat_unsupported_script`.

`SelfTestTests` (FPAppUITests, with a fake `EngineRunning` from the test support of WP-501/204, or a local one):

| Test | Asserts |
|---|---|
| `passesWithAHealthyFakeEngine` | fakes: `bundleInfo` with the real bundle id, a fake engine whose `scan` yields `FaceRecord`s matching the recipe and whose `forge` yields one progress then a report, `availableFontURLs` containing both recipe paths, `checkBuiltFont` succeeding, a `tmp` root, `helperProcessIDs` returning `[4242]` until the cancel and `[]` 0.2 s after it. Output: 9 step lines in §S6 order, then a summary `passed`; exit 0; every line decodes to the §S6 shapes; the root is deleted |
| `stopsAtFirstFailureButCleansUp` | the fake `forge` throws `EngineError.helperFailed(…)` → `forge` fails, `verify` and `cancel` are not run, `cleanup` runs; exit 1; `failed_steps == ["forge"]` |
| `wrongBundleIdFailsEnvironment` | `bundleInfo.identifier == "com.example.other"` → `environment` fails; exit 1 |
| `requireEmbeddedEngineRejectsDevEngine` | `.dev` engine with `--require-embedded-engine` → exit 3, summary `engine: "dev"` |
| `noEngineIsAnEnvironmentError` | the `engine` dependency throws `EngineError.helperNotFound(searched: [])` → exit 3, summary `engine: "none"` |
| `tooling14CancelMustEndTheHelperWithinThreeSeconds` | `helperProcessIDs` keeps returning the helper pid for 5 s after the cancel → `cancel` fails with exit 1 after about 3 s; ending it 0.5 s after the cancel → passes; never returning a pid → `cancel` fails ("no helper child process was seen") |
| `injectedFailureFailsThatStep` | `injectedFailure = "verify"` → `failed_steps == ["verify"]`, error `injected`, exit 1 |
| `overallTimeoutReturnsFour` | `--self-test-timeout 10` with a fake `forge` that never finishes → exit 4, `result: "timed_out"`, within 12 s |
| `overallDeadlineDoesNotWaitForANonCooperativeHello` | a held hello continuation ignores cancellation; timeout 10 returns 4 within 12 s, cleanup finishes, and releasing hello later emits no output |
| `stepDeadlineDoesNotWaitForASynchronousDependency` | a held synchronous recipe reader cannot block the coordinator: its 1-second budget fails that step, cleans up, and suppresses late completion |
| `overallDeadlineIncludesSetupAndRemovesALateRoot` | a held temporary-root provider cannot block the overall deadline; a root created after timeout is subsequently removed without late output |
| `cleanupCannotExtendAnOverallTimeoutByFiveSeconds` | a held cleanup closure times out after the capped grace, reports cleanup failure without changing exit 4, and may remove the root later without output |
| `tooling14BlockedProcessLookupStillCancelsTheWorker` | a held synchronous PID lookup cannot delay cancellation of the separate forge consumer; the helper is cancelled while the lookup remains blocked |
| `deadlineRaceHandlesCancellationBeforeContinuationInstallation` | 200 immediately cancelled races resume exactly once with cancellation and do not wait for their 60-second work/timers |
| `usageErrors` | `--self-test-timeout abc`, `--self-test-timeout 5` and `--self-test-bogus` → exit 2 |
| `selfTestRecipeDecodes` | the bundled `self-test.fontrecipe` decodes with `RecipeDocument` and names 2 materials, main 0, rule `symbols → 1` |
| `crit1NoCompatibilityKeyInInfoPlist` | the committed `App/Info.plist` (read via `#filePath`) has no `UIDesignRequiresCompatibility` and no `NSRequiresAquaSystemAppearance` |

**6. SDK check (CRIT-1): `scripts/check-sdk.sh <mach-o> [min_major=26]`.**

```bash
sdk="$(otool -l "$bin" | awk '/cmd LC_BUILD_VERSION/{f=1} f&&$1=="sdk"{print $2; exit}')"
```

- Empty → `check-sdk: no LC_BUILD_VERSION in <bin>`, exit 1.
- Major < min → `check-sdk: FAIL <bin> sdk <v> < 26`, exit 1.
- Otherwise `check-sdk: OK <bin> sdk <v>`, exit 0.

`scripts/tests/test_crit_1_check_sdk.sh` compiles `int main(void){return 0;}` with `xcrun clang -x c - -o "$tmp/ok"`. It asserts that check-sdk passes on that binary. It then runs `vtool -set-build-version macos 14.0 15.0 -replace -output "$tmp/old" "$tmp/ok"` and asserts that check-sdk fails with exit 1 and prints `sdk 15.0 < 26`.

**7. `scripts/check-bundle.sh <app> [--release] [--distribution]`** prints one line per check and a final `check-bundle: OK` or `check-bundle: <n> problems`, exiting 0 or 1. Checks:
1. Info.plist values (item 4).
2. Icon: `Contents/Resources/Assets.car` exists, and `xcrun assetutil --info` lists a `"Name" : "AppIcon…"` entry; `Contents/Resources/AppIcon.icns` exists.
3. Main executable: `lipo -archs` is `arm64`; `check-sdk.sh` passes.
4. No Mach-O anywhere in the bundle has an `x86_64` slice (TOOLING-10).
5. Entitlements (§S4): none, or only `com.apple.security.get-task-allow`; with `--distribution`, none at all.
6. If `Contents/Resources/fpengine` exists: `Contents/Helpers/fpengine` is a symlink whose target (`readlink`) is exactly `../Resources/fpengine`; `Contents/Helpers/fpengine/bin/python3 -I -B -c "import fpengine, fontTools, pathops, unicodedata2"` exits 0; none of these paths exist relative to the runtime root: `include`, `share`, `lib/pkgconfig`, `lib/python3.12/config-3.12-darwin`, `lib/python3.12/tkinter`, `lib/python3.12/idlelib`, `lib/python3.12/ensurepip`, `lib/python3.12/test`, `lib/python3.12/turtledemo`, any `lib/libtcl*`, `lib/libtk*`, `lib/python3.12/lib-dynload/_tkinter*`, and no `*.a` file anywhere under it (§S3; the same list as helper.md WP-203 step 8); no directory whose name contains a `.` directly or indirectly under `Contents/MacOS`, `Contents/Frameworks` or a real (non-symlink) directory under `Contents/Helpers`.
7. `--release`: the runtime **must** be embedded, and `collect_licenses.py --check` passes.
8. `--distribution` (after Developer ID signing): `codesign --verify --deep --strict` passes; `codesign -dv --verbose=4` of the app shows `Authority=Developer ID Application` and `Timestamp=`; every Mach-O has the `runtime` flag. Explicit verbosity is required because terse display can omit the authority chain even for a valid Developer ID signature; neither the authority nor timestamp requirement is relaxed.

**8. Signing (`scripts/sign-app.sh <app> <identity>`, TOOLING-1).**
- Implements §S4, then runs `codesign --verify --deep --strict --verbose=2 <app>`.
- Signs through `scripts/codesign-retry.sh`, as does `release.sh` for the DMG. It retries a signature only when codesign reports "The timestamp service is not available" (up to five attempts, 1–4 s apart); any other failure exits at once. *As built at WP-701:* on 2026-09-30 Apple's service refused about one request in fifteen, and the release signs over a hundred files one at a time, so three release attempts in a row failed. `scripts/tests/test_release_codesign_retry.sh` (in CI) checks the retry, the immediate failure, and the five-attempt limit with a fake `codesign`. *As built for the public v1.0.0:* a fleet job's fresh `HOME` keeps no keychain search list (`security list-keychains -d user -s` doesn't stick), so codesign found no identity by name. `codesign-retry.sh` adds `--keychain "$CODESIGN_KEYCHAIN"` when that is set, and release.yml sets it to the imported keychain; the test checks both forms of the command.
- For a non-ad-hoc identity it checks that every Mach-O's `codesign -dv` line `flags=` contains `runtime`.
- Exit 1 on any failure, printing the codesign output.
- `scripts/tests/test_tooling_1_sign_adhoc.sh` (bash, `set -euo pipefail`): requires `build/helper/fpengine` (else exits 2 with `run 'make helper-runtime' first`); runs `make app`; copies the Debug app with `ditto` to `$(mktemp -d)/Font Playground.app`; runs `scripts/sign-app.sh <copy> -`; asserts that `codesign --verify --deep --strict --verbose=2 <copy>` prints `valid on disk` and `satisfies its Designated Requirement`, that `<copy>/Contents/Helpers/fpengine/bin/python3 -I -B -c "import pathops"` exits 0 (Context 2's failure mode), that `codesign -d --entitlements - --xml <copy>` prints nothing, and that `scripts/check-bundle.sh <copy>` exits 0. It removes the temp folder on exit and prints `test_tooling_1_sign_adhoc: OK`.

**9. Notarization (`scripts/notarize.sh <file>`).**
- Auth comes from `NOTARY_KEYCHAIN_PROFILE`, or from `NOTARY_KEY_PATH` + `NOTARY_KEY_ID` + `NOTARY_ISSUER_ID`. With neither: `notarize: no credentials (set NOTARY_KEYCHAIN_PROFILE or NOTARY_KEY_PATH/NOTARY_KEY_ID/NOTARY_ISSUER_ID)`, exit 3.
- A `.app` is zipped first: `ditto -c -k --keepParent <app> <tmp>/app.zip`.
- `xcrun notarytool submit <zip|dmg> --wait --timeout 30m --output-format json <auth> > result.json`.
- `status="$(plutil -extract status raw -o - result.json)"`. If it is not `Accepted`, run `xcrun notarytool log "$(plutil -extract id raw -o - result.json)" <auth> notary-log.json`, print that log, and exit 1.
- Then `xcrun stapler staple <app|dmg>` and `xcrun stapler validate <app|dmg>`.

**10. DMG (`scripts/make-dmg.sh <app> <out.dmg>`).**
- Stage `<tmp>/Font Playground.app` (with `ditto`) and a symlink `<tmp>/Applications → /Applications`.
- The image is created at `<partial>` = `<dir of out>/.<name>.<pid>.partial.dmg`, never at `<out>` (AGENTS.md rule 8).
- If `diskutil image create from --help` exits 0: `diskutil image create from --format ULFO --volumeName "Font Playground" <tmp> <partial>`. Otherwise `hdiutil create -volname "Font Playground" -srcfolder <tmp> -format ULFO -fs APFS <partial>`.
- Then `hdiutil verify <partial>`, fsync it, `os.replace` it onto `<out>`, and fsync the folder.
- A failed or interrupted run removes `<partial>` and leaves the previous `<out>` intact (`engine/tests/repo/test_make_dmg.py`, with stubbed tools).

**11. `scripts/release.sh`** (the only release entry point; TOOLING-1 verifier's order):

```
scripts/release.sh [--adhoc] [--identity <name>] [--version <x.y.z>] [--build-number <n>]
```

Steps, stopping at the first failure:
1. `version` is the value of `--version`, else `MARKETING_VERSION`. It must equal `MARKETING_VERSION` and the `engine/pyproject.toml` version (§S8), otherwise `release: version <v> does not match App/Version.xcconfig (<m>) / engine (<e>)`. The build number is `--build-number`, else `1`. `rm -rf build/release dist`.
2. `make setup`, `make helper-runtime`.
3. `xcodegen generate --spec App/project.yml --quiet`, then `xcodebuild -project App/FontPlayground.xcodeproj -scheme FontPlayground -configuration Release -derivedDataPath build/release/DerivedData ARCHS=arm64 CODE_SIGN_IDENTITY=- CURRENT_PROJECT_VERSION=<n> build`. `ditto` the product to `build/release/Font Playground.app` (= `$APP`).
4. `scripts/check-sdk.sh "$APP/Contents/MacOS/Font Playground"` (CRIT-1) and `scripts/check-bundle.sh "$APP" --release`.
5. `"$APP/Contents/MacOS/Font Playground" --self-test --require-embedded-engine`, which must exit 0.
6. `scripts/sign-app.sh "$APP" "<identity or ->"`.
7. Self-test again on the signed app. This catches hardened-runtime and library-validation problems. Then `codesign --verify --deep --strict "$APP"`, which proves the self-test wrote nothing into the bundle.
8. Unless `--adhoc`: `scripts/check-bundle.sh "$APP" --release --distribution`; `scripts/notarize.sh "$APP"` (notarize and staple the **app**); `spctl --assess --type execute --verbose=4 "$APP"` must print `accepted` and `source=Notarized Developer ID`.
9. `scripts/make-dmg.sh "$APP" "dist/FontPlayground-<version>-arm64.dmg"`.
10. Unless `--adhoc`: `codesign --force --timestamp --sign "<identity>" <dmg>`; `scripts/notarize.sh <dmg>`; `spctl --assess --type open --context context:primary-signature --verbose=4 <dmg>` must print `accepted` and `source=Notarized Developer ID`.
11. Mount the DMG hidden and read-only in `<tmp>/mnt`: `diskutil image attach --readOnly --nobrowse --mountPoint <tmp>/mnt <dmg>` when `diskutil image attach --help` exits 0, else `hdiutil attach -nobrowse -readonly -noautoopen -mountpoint <tmp>/mnt <dmg>`. Check that `<tmp>/mnt` holds exactly `Font Playground.app` and the `Applications` symlink. Run `"<tmp>/mnt/Font Playground.app/Contents/MacOS/Font Playground" --self-test --require-embedded-engine`, then detach with `diskutil eject <tmp>/mnt` (fallback `hdiutil detach <tmp>/mnt`). A `trap` detaches on any failure.
12. `shasum -a 256 <dmg name> > <dmg>.sha256`, run inside `dist/` so the file names the DMG without a folder and `shasum -c` works next to a downloaded copy, then print `release: dist/FontPlayground-<version>-arm64.dmg (<size> MB, <adhoc|notarized>)`.

`--adhoc` signs with `-` and skips steps 8 and 10. It is for dry runs and CI. Its DMG is not for distribution.

**12. CI and release workflows.**

`ci.yml`, in the `macos` job, replaces `make app` / `make self-test` with:

```yaml
      - uses: actions/cache@v4
        with:
          path: build/cache/pbs                         # helper.md WP-203: --cache default build/cache, archive in pbs/
          key: pbs-${{ hashFiles('scripts/python-runtime.pin') }}
      - run: make helper-runtime
      - run: make app
      - run: scripts/check-sdk.sh "build/DerivedData/Build/Products/Debug/Font Playground.app/Contents/MacOS/Font Playground"
      - run: scripts/check-bundle.sh "build/DerivedData/Build/Products/Debug/Font Playground.app"
      - run: make self-test
      - run: scripts/tests/test_crit_1_check_sdk.sh
```

`.github/workflows/release.yml`:
- Triggers: `on: push: tags: ["v*.*.*"]`; `workflow_dispatch` with input `adhoc` (boolean, default `true`); and `pull_request` with `paths: [".github/workflows/release.yml", "scripts/**", "App/project.yml", "tools/release/**"]`. A `pull_request` run is always ad hoc and never reads secrets (so the WP-601 PR itself can show a green dry run; `workflow_dispatch` only works once the file is on `main`). The ad-hoc condition is `github.event_name == 'pull_request' || (github.event_name == 'workflow_dispatch' && inputs.adhoc)`.
- `permissions: contents: write`; one job, `timeout-minutes: 90`. It first ran on `macos-26`; it now runs on the self-hosted Mac mini, `[self-hosted, macOS, ARM64, kcice-ci, kcice-build]` (docs/self-hosted-ci.md).
- Actions are pinned by **full commit SHA**, with the tag in a comment. Resolve each SHA at implementation time with `git ls-remote https://github.com/<owner>/<repo> refs/tags/<tag>` (use the peeled `^{}` line for annotated tags); WP-601 runs on the Mac with network.
- Steps:
  1. Checkout. When not ad hoc, check that all six secrets are non-empty and fail with an `::error::` naming the missing ones, before the long test run; for a tag, also check that `gh` is installed. Then the toolchain check, the tool-versions step and setup-uv.
  2. `make setup`, `make lint test`.
  3. Not ad hoc (tag pushes, or dispatch with `adhoc: false`):
     - **Import certificate.** Create `$RUNNER_TEMP/release.keychain-db` with a random password (`openssl rand -base64 32`, never a secret). Then `security set-keychain-settings -lut 21600`, `security unlock-keychain`. Write `$MACOS_DEVELOPER_ID_P12_BASE64 | base64 --decode` to a temp file and run `security import <p12> -k <kc> -P "$MACOS_DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign`, then `security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k <pw> <kc>` and `security list-keychains -d user -s <kc> <existing…>`. Delete the p12 file.
     - **Notary key.** Decode `$NOTARY_API_KEY_P8_BASE64` to `$RUNNER_TEMP/notary.p8`, and set `NOTARY_KEY_PATH`, `NOTARY_KEY_ID: ${{ secrets.NOTARY_API_KEY_ID }}` and `NOTARY_ISSUER_ID: ${{ secrets.NOTARY_API_ISSUER_ID }}`.
     - `scripts/release.sh --identity "$MACOS_DEVELOPER_ID_IDENTITY" --build-number "$((GITHUB_RUN_NUMBER + BUILD_NUMBER_OFFSET))"` with `CODESIGN_KEYCHAIN="$RUNNER_TEMP/release.keychain-db"`, adding `--version "${GITHUB_REF_NAME#v}"` only for tag pushes. A manual dispatch uses the committed version even when its selected ref is a tag. Only a tag-push event creates a draft GitHub release; a manual ad-hoc run must never publish release assets.
  4. Ad hoc: `scripts/release.sh --adhoc --build-number "$((GITHUB_RUN_NUMBER + BUILD_NUMBER_OFFSET))"`. `BUILD_NUMBER_OFFSET` is 100: the public repository's run numbers restarted at 1, and the signed-off 1.0.0 candidates were builds 1–4 in the private development repository.
  5. `actions/upload-artifact` of `dist/*`.
  6. On tags only: `gh release create "$GITHUB_REF_NAME" dist/*.dmg dist/*.sha256 --draft --verify-tag --title "Font Playground ${GITHUB_REF_NAME#v}"` with `GH_TOKEN: ${{ github.token }}`, plus `--notes-file docs/release/notes/$GITHUB_REF_NAME.md` when that file exists and `--generate-notes` otherwise. The first release's generated notes would list every WP pull request, which tells users nothing.
  7. `if: always()`: `security delete-keychain <kc>`; `rm -f $RUNNER_TEMP/notary.p8`.

Secret names (values never in the repository):

| Secret | Content |
|---|---|
| `MACOS_DEVELOPER_ID_P12_BASE64` | base64 of the exported "Developer ID Application" certificate + key (.p12) |
| `MACOS_DEVELOPER_ID_P12_PASSWORD` | the .p12 export password |
| `MACOS_DEVELOPER_ID_IDENTITY` | the full identity name as `security find-identity -v -p codesigning` prints it |
| `NOTARY_API_KEY_P8_BASE64` | base64 of the App Store Connect API key (.p8) used by notarytool |
| `NOTARY_API_KEY_ID` | its key ID |
| `NOTARY_API_ISSUER_ID` | its issuer ID |

`docs/release.md` (maintainer runbook) covers:
- Joining the Developer Program.
- Creating the Developer ID Application certificate and exporting the .p12.
- Creating an App Store Connect API key.
- Adding the six secrets.
- The local release: `xcrun notarytool store-credentials fp-notary …`, then `NOTARY_KEYCHAIN_PROFILE=fp-notary scripts/release.sh --identity "<Developer ID Application: …>"`.
- The ad-hoc dry run.
- Reading a rejected notarization log.

**13. Repository tests** (`engine/tests/repo/test_release_config.py`, Linux):

| Test | Asserts |
|---|---|
| `test_tooling_8_single_version` | `MARKETING_VERSION` in `App/Version.xcconfig` equals `engine/pyproject.toml` `project.version` |
| `test_tooling_8_info_plist_release_keys` | `plistlib` on `App/Info.plist`: literal values `CFBundleName` = `CFBundleDisplayName` = `Font Playground`, `CFBundlePackageType` = `APPL`, `LSApplicationCategoryType` = `public.app-category.graphics-design`, `NSHumanReadableCopyright` = the line of `LICENSE` that starts with `Copyright`, `CFBundleDevelopmentRegion` = `en`, `NSHighResolutionCapable` is `True`, the five usage descriptions are non-empty strings; build-setting references `CFBundleIdentifier` = `$(PRODUCT_BUNDLE_IDENTIFIER)`, `CFBundleExecutable` = `$(EXECUTABLE_NAME)`, `CFBundleShortVersionString` = `$(MARKETING_VERSION)`, `CFBundleVersion` = `$(CURRENT_PROJECT_VERSION)`, `LSMinimumSystemVersion` = `$(MACOSX_DEPLOYMENT_TARGET)`; `CFBundleIconName` = `AppIcon` (and `CFBundleIconFile` = `AppIcon` if present); `NSRequiresAquaSystemAppearance`, `UIDesignRequiresCompatibility` and `LSUIElement` absent. `App/project.yml` contains `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` |
| `test_tooling_9_icon_composer_document` | `App/Resources/AppIcon.icon/icon.json` parses, and every `image-name` it references exists under `Assets/` as a PNG whose IHDR says 1024×1024 |
| `test_tooling_10_arm64_only_build_settings` | `App/project.yml` sets `ARCHS: arm64`; `scripts/embed-helper.sh` contains `lipo -thin arm64` |
| `test_tooling_1_release_order` | In `scripts/release.sh`, the first `notarize.sh "$APP"` occurs before `make-dmg.sh`, which occurs before `notarize.sh` of the DMG. `sign-app.sh` never passes `--deep` to a signing call (only to `--verify`). `release.yml` references exactly the six secret names |
| `test_tooling_1_distribution_reads_authority_without_relaxing_checks` | Runs the real bundle checker against temporary fake tools whose terse codesign output omits Authority, while verbose output includes it. Developer ID with a timestamp passes; Apple Development, ad-hoc and missing-timestamp signatures fail. No real bundle, certificate or Apple tool is used. |
| `test_crit_1_release_runs_sdk_check` | `scripts/release.sh` and `ci.yml` invoke `check-sdk.sh` |
| `test_tooling_11_licence_collection_is_wired` | `project.yml` has the "Collect licences" build phase after "Embed fpengine helper runtime" |

### Acceptance criteria
- **AC-601-1** With `build/helper/fpengine` present, `make app` produces a Debug app where `scripts/check-bundle.sh "<app>"` prints `check-bundle: OK`. That includes the §S3 layout, the `Helpers/fpengine` symlink and the embedded interpreter importing `fpengine, fontTools, pathops, unicodedata2`.
- **AC-601-2** Without `build/helper/fpengine`: the Debug build succeeds and its log contains `warning: helper runtime not found`. A Release `xcodebuild` fails with `error: helper runtime missing at … run 'make helper-runtime' (WP-203)`.
- **AC-601-3** TOOLING-1 (ad hoc): `scripts/tests/test_tooling_1_sign_adhoc.sh` exits 0: verify passes (`valid on disk`, `satisfies its Designated Requirement`) and `import pathops` works after signing, and `codesign -d --entitlements - --xml` on the signed copy prints nothing (all asserted by the script, which prints `test_tooling_1_sign_adhoc: OK`).
- **AC-601-4** CRIT-1: `scripts/tests/test_crit_1_check_sdk.sh` exits 0, which covers both the pass and the `sdk 15.0 < 26` failure. On the Debug and Release apps, `scripts/check-sdk.sh` prints `check-sdk: OK … sdk <v>` with v ≥ 26.
- **AC-601-5** TOOLING-8: `test_tooling_8_single_version` and `test_tooling_8_info_plist_release_keys` pass, and `check-bundle.sh` item 1 passes on the Release app.
- **AC-601-6** TOOLING-9: `test_tooling_9_icon_composer_document` passes. In the built app, `xcrun assetutil --info "<app>/Contents/Resources/Assets.car" | grep -c '"Name" : "AppIcon'` prints ≥ 1, `AppIcon.icns` exists, and `plutil -extract CFBundleIconName raw` and `… CFBundleIconFile raw` both print `AppIcon`.
- **AC-601-7** TOOLING-10: `test_tooling_10_arm64_only_build_settings` passes. On the Release app, `find "<app>" -type f -exec sh -c 'file -b "$1" | grep -q Mach-O && lipo -archs "$1"' _ {} \; | sort -u` prints only `arm64`.
- **AC-601-8** TOOLING-11: `tools/release/collect_licenses.py --app "<Release app>" --repo . --check` exits 0. `index.json` lists at least `Font Playground`, `CPython`, `fonttools`, `skia-pathops` and `unicodedata2`, each with non-empty files. `Contents/Resources/Acknowledgements.txt` contains `== CPython ` and `== fonttools `. `test_tooling_11_licence_collection_is_wired` passes.
- **AC-601-9** `make self-test` (Debug, embedded runtime) exits 0. stdout has 9 step lines in §S6 order and a summary with `"result": "passed"` and `"engine": "embedded"`, and the whole run takes under 180 s. The same without `build/helper` reports `"engine": "dev"` and passes when `FP_ENGINE_PYTHON` is exported (by `make`).
- **AC-601-10** Exit codes on the real app:
  - `FP_SELF_TEST_INJECT_FAILURE=verify "<Debug app>/Contents/MacOS/Font Playground" --self-test` → 1, with `failed_steps: ["verify"]`.
  - `… --self-test --self-test-bogus` → 2.
  - An app without runtime: `mv build/helper build/helper.off && make app`, then `env -u FP_ENGINE_PYTHON "<Debug app>/Contents/MacOS/Font Playground" --self-test` → 3, and `FP_ENGINE_PYTHON="$PWD/engine/.venv/bin/python" "<Debug app>/…" --self-test --require-embedded-engine` → 3 (summary `engine: "dev"`). Restore with `mv build/helper.off build/helper && make app`.
  - `… --self-test --self-test-timeout 5` → 2, with nothing on stdout.
- **AC-601-11** `make mac-test` passes every `SelfTestTests` test of Design §5, including `tooling14CancelMustEndTheHelperWithinThreeSeconds` and `crit1NoCompatibilityKeyInInfoPlist`.
- **AC-601-12** The self-test writes nothing outside its temporary root. Before and after `make self-test`, `find ~/Library/Caches/io.github.kciceblue.fontplayground "$HOME/Library/Application Support/io.github.kciceblue.fontplayground" ~/Library/Fonts -newer <marker file created before the run> 2>/dev/null` prints nothing. On a signed app, `codesign --verify --deep --strict` still passes after a self-test (release.sh step 7).
- **AC-601-13** TOOLING-14 logging: after a self-test, `/usr/bin/log show --last 5m --style compact --predicate 'subsystem == "io.github.kciceblue.fontplayground" AND category == "self-test"'` contains `self-test: passed`.
- **AC-601-14** TOOLING-1 dry run: `scripts/release.sh --adhoc` exits 0 and produces `dist/FontPlayground-0.1.0-arm64.dmg` (or the current version) plus its `.sha256`. `hdiutil verify` reports the checksum `VALID`. The mounted image holds `Font Playground.app` and an `Applications` symlink. Step 11's self-test from the mounted image passes. The `release.yml` `pull_request` run on the WP-601 PR (ad hoc) is green (link in the PR).
- **AC-601-15** `test_tooling_1_release_order` and `test_crit_1_release_runs_sdk_check` pass, and the updated CI `macos` job is green (it runs `make helper-runtime`, `check-sdk`, `check-bundle`, `make self-test` and `test_crit_1_check_sdk.sh`).
- **AC-601-16** (release credential) With the six secrets set, a `workflow_dispatch` run with `adhoc: false` (or a local run with `NOTARY_KEYCHAIN_PROFILE`) completes:
  - both `notarytool` submissions report `Accepted`
  - `xcrun stapler validate` passes for the app and the DMG
  - `spctl --assess --type execute --verbose=4 "<app>"` prints `accepted` and `source=Notarized Developer ID`
  - `spctl --assess --type open --context context:primary-signature --verbose=4 "<dmg>"` prints the same
  - `check-bundle.sh --release --distribution` passes

  If the Developer ID certificate does not exist yet when WP-601 is implemented, the PR says "AC-601-16 deferred to WP-701" and WP-701 must meet it (AC-701-8). This is the only AC that may be deferred.
- **AC-601-M1** (manual, macos) Icon: a screenshot of Finder's Get Info and the Dock for the Debug app on macOS 26 or later shows the mark full size in the system shape, not a small square on a plate. On macOS 14 or 15, if available, the `.icns` icon shows.
- **AC-601-M2** (manual, macos) TOOLING-14 quit: in a Debug app with the embedded runtime, start an Install of Helvetica Neue + PingFang SC and press ⌘Q during `merge`. The app quits within 3 s, and afterwards `pgrep -f "fpengine"` prints nothing. Paste the timings. This depends on WP-505's quit handling and checks it end to end in the bundle.
- **AC-601-M3** (manual, macos, release credential; may be deferred with AC-601-16) The notarized DMG, downloaded through a browser (so it carries quarantine) and opened on this Mac: dragging the app to Applications and opening it shows only the standard "downloaded from the Internet" confirmation, then the main window. Screenshot.

| Finding | Regression test / AC |
|---|---|
| TOOLING-1 | `test_tooling_1_sign_adhoc.sh`, `test_tooling_1_release_order`; AC-601-3, -14, -16, -M3 |
| TOOLING-8 | `test_tooling_8_single_version`, `test_tooling_8_info_plist_release_keys`; AC-601-5 |
| TOOLING-9 | `test_tooling_9_icon_composer_document`; AC-601-6, -M1 |
| TOOLING-10 | `test_tooling_10_arm64_only_build_settings`; AC-601-7 |
| TOOLING-11 | `test_tooling_11_licence_collection_is_wired`, `collect_licenses.py --check`; AC-601-8 |
| TOOLING-14 | `SelfTestTests.tooling14CancelMustEndTheHelperWithinThreeSeconds`; AC-601-13, -M2 |
| CRIT-1 | `test_crit_1_check_sdk.sh`, `test_crit_1_release_runs_sdk_check`, `SelfTestTests.crit1NoCompatibilityKeyInInfoPlist`; AC-601-4 |

### Verification
```bash
make lint test
make helper-runtime app self-test
scripts/check-sdk.sh "build/DerivedData/Build/Products/Debug/Font Playground.app/Contents/MacOS/Font Playground"
scripts/check-bundle.sh "build/DerivedData/Build/Products/Debug/Font Playground.app"
scripts/tests/test_crit_1_check_sdk.sh
scripts/tests/test_tooling_1_sign_adhoc.sh
scripts/release.sh --adhoc
# with credentials:
NOTARY_KEYCHAIN_PROFILE=fp-notary scripts/release.sh --identity "<Developer ID Application: … (…)>"
```

### Notes for the implementer
- **Do not put the runtime physically under `Contents/Helpers`.** codesign fails on `lib/python3.12` (Context 1). ADR-0004's path survives as the symlink.
- **Do not sign helper code ad hoc with `--options runtime`.** Extension imports then fail with "different Team IDs" (Context 2). Real identities get the hardened runtime everywhere.
- Never pass `--deep` to a signing call (only to `--verify`). Never add entitlements. Never set `UIDesignRequiresCompatibility`: CRIT-1 says it requests the old look, and it is ignored anyway with the 27 SDK.
- Set `ENABLE_DEBUG_DYLIB: NO` on the app target. Xcode 27's generated ad-hoc debug dylib fails hardened library validation after explicit re-signing; compiling Debug code into the main executable preserves the no-entitlements rule. The ad-hoc signing regression also runs the signed app's self-test and verifies its signature afterward.
- `hdiutil create/attach/detach` are deprecated on macOS 27 but still work. The scripts prefer `diskutil image` where it exists (Context 8). Mount images with `nobrowse` only, never visibly.
- Use `/usr/bin/log`, not `log`: zsh has a `log` builtin (Context 9).
- The first launch of a downloaded, quarantined app makes Gatekeeper scan its roughly 1,700 files. That is why the `engine` step's budget is 20 s rather than the 150–400 ms helper start.
- Precompiled `.pyc` files are sealed resources. If WP-203 compiled them with timestamp invalidation and `ditto` preserved the mtimes, Python uses them. If not, Python recompiles in memory (it cannot write with `-B`), which is slower but correct. Prefer `compileall --invalidation-mode unchecked-hash` in WP-203.
- Self-test fonts: the `discover` step uses `CTFontManagerCopyAvailableFontURLs`. It never looks up "Georgia" or "Menlo" by name.
- `release.yml` holds secrets: pin every third-party action to a commit SHA. `ci.yml` is pinned the same way since the repository went public (`test_workflow_actions_are_pinned_to_commits`).

---

## WP-602: User docs, licences/acknowledgements, Windows-migration notes

**Goal:** Users get a macOS README, an offline user guide, complete licence texts in the app, and a migration note for Windows users that includes the font equivalence table and the "don't copy the settings folder" advice.
**Depends on:** WP-601 · **Env:** macos · **Size:** S · **Closes findings:** TOOLING-11, CRIT-3, UI-12, UI-16

### Scope
- In:
  - `README.md` rewritten for users.
  - `App/Resources/en.lproj/UserGuide.html` (moved to `en.lproj` by WP-508; `zh-Hans.lproj` has the Chinese guide), opened by WP-501's Help command.
  - `docs/user/migrating-from-windows.md`.
  - `App/Resources/Acknowledgements.txt` (curated introduction).
  - `App/Licenses/`: the static licence texts and `components.json` (§S5) for python-build-standalone's bundled libraries and other non-wheel notices.
  - Doc tests.
- Out:
  - In-app strings (WP-501–507 own the String Catalog).
  - The import code (WP-305, WP-501).
  - The licence collection mechanism (WP-601).
  - Localised docs (backlog B-8).

### Touched paths
- `README.md` (rewrite; keeps the "Development" link from WP-001)
- `App/Resources/UserGuide.html` (new; moved to `en.lproj/` by WP-508, which adds `zh-Hans.lproj/`), `App/Resources/Acknowledgements.txt` (edit)
- `docs/user/migrating-from-windows.md` (new)
- `scripts/fetch-pbs-licenses.sh` (new)
- `App/Licenses/components.json`, `App/Licenses/python-build-standalone/*.txt`, `App/Licenses/unicode/Unicode-LICENSE.txt`, `App/Licenses/fpengine/otf2ttf-NOTICE.txt`, `App/Licenses/README.md` (new/edit)
- `engine/tests/repo/test_user_docs.py` (new)
- `Packages/FontPlaygroundKit/Tests/FPCoreTests/MigrationDocTests.swift` (new)

### Design

**1. `README.md`** (sections in this order; plain words, the original's tone, macOS terms):
1. **Font Playground**: what it does (the original's first paragraph, `reference/fontplayground-py/README.md:3`, with macOS font examples).
2. **Requirements**: "A Mac with Apple silicon and macOS 14 Sonoma or later." (arm64 only, TOOLING-10.)
3. **Install**: download `FontPlayground-<version>-arm64.dmg` from GitHub Releases, open it, drag Font Playground to Applications. Public releases are notarized by Apple. Before first release sign-off, clearly label local development DMGs as ad-hoc signed and not notarized.
4. **Using Font Playground**: the original's "How it works" (`README.md:22-34`) rewritten with the app's actual command titles in bold (for example **Choose Main Font…**, **Add Font Folder…**, **Save a Copy…**, **Install**, **Show in Finder**, **Rescan Fonts**, **Start Over**, **Settings…**). Use ⌘ shortcuts and Return/Esc, "Settings ▸ Appearance", "installs for you only, in your Fonts folder (~/Library/Fonts)". Apply the UI-12 replacements: no "Windows", no "admin rights", no "Ctrl", no "Enter uses it", no "Open settings folder", no "Show file".
5. **What the result contains**: `README.md:38` adapted. It adds the licence handling of ADR-0012: the output keeps the most restrictive embedding permission of its sources, and notes for fonts bundled with macOS or Microsoft products.
6. **Font licences**: "Fonts you forge keep their sources' licences. Font Playground tells you when a source font is bundled with macOS or a Microsoft product; those licences allow use on your own Mac only. Don't distribute a forged font unless every source font's licence allows it."
7. **Coming from the Windows version**: a link to `docs/user/migrating-from-windows.md`.
8. **Not in this version**: `README.md:42` minus the macOS-install item, plus Apple AAT shaping (ADR-0008 wording).
9. **Privacy**: no network access; the files it writes (contracts §8 in user words).
10. **Uninstall**: drag the app to the Trash; installed fonts are removed with the app's Uninstall or in Font Book.
11. **Acknowledgements and licence**: MIT; Font Playground ▸ About Font Playground lists every bundled component and licence.
12. **Development**: one sentence and a link to `docs/development.md` (WP-001's `test_tooling_6_dev_docs_have_no_windows_only_commands` requires the link).

**2. `App/Resources/en.lproj/UserGuide.html` (moved to `en.lproj` by WP-508; `zh-Hans.lproj` has the Chinese guide).** One self-contained file: inline CSS, `font: -apple-system-body`, a `prefers-color-scheme: dark` block, no scripts and no external resources (no network). It has sections 3–10 of the README. Its bold command names (`<strong>`) are the same set as the README's section 4.

**3. `docs/user/migrating-from-windows.md`** (CRIT-2, CRIT-3). Sections:
- **Your last recipe.** Copy only `forge_last.json` from `%LOCALAPPDATA%\FontPlayground\` on the PC to `~/Library/Application Support/FontPlayground/forge_last.json` on the Mac, before you first open Font Playground. The app imports it once at first launch (ui-shell.md WP-501 launch step (b)) and tells you which fonts it could not find, with Mac suggestions. The text must match what the app actually does; check `legacyWindowsLastRecipe` and the notice strings in the String Catalog.
- **Don't copy the settings folder.** "Don't copy the whole `%LOCALAPPDATA%\FontPlayground` folder. `settings.json` and `catalog.json` describe the PC's fonts and folders (paths like `C:\Windows\Fonts` and `D:\Fonts` mean nothing on a Mac), and Font Playground for Mac keeps its settings elsewhere."
- **Windows fonts on the Mac.** Microsoft's fonts (YaHei, SimSun, DengXian, Meiryo, Malgun Gothic, Calibri, Consolas and others) are not part of macOS. Microsoft Office carries private copies that other apps can't use, licensed for use with Office only. Copying `C:\Windows\Fonts` to a Mac is outside the Windows font licence. Use the Mac equivalents in the table.
- **Table `## Windows fonts and their Mac equivalents`**, columns `| On Windows | On your Mac | Notes |`. The first two columns must equal FPCore `WindowsFonts.equivalents` (core.md WP-305 §5): one row per group, with Windows families comma-separated in the table's order and Mac families comma-separated in order. Notes:
  - SF Pro and SF Mono are the system fonts; they appear in the font list only if you installed them from Apple's developer site.
  - If a Mac font in this column is missing, open Font Book: several are free downloads there.
  - A last row, `| Arial, Georgia, Times New Roman, Verdana, Tahoma, Trebuchet MS, Courier New | the same fonts | ship with macOS |`, is excluded from the test.
  - Calibri: "no close equivalent ships with macOS" (core.md: no Mac equivalent), also excluded.
- **Fonts you forged on Windows.** They keep working on the Mac. Font Playground never replaces a font it did not install itself (ADR-0009). To build one with the same name, first remove the copy with Font Book.
- **What's different on the Mac**: a short version of docs/plan.md §5 in user terms: install location, Appearance, Show in Finder, ⌘ shortcuts, notarized DMG.

**4. Licences (TOOLING-11, completing WP-601).** Obtain the texts from the **pinned** sources:
- python-build-standalone parts: the `full` archive of the same release and target that WP-203 pins contains `python/licenses/` (one text per bundled library) and `python/PYTHON.json`. `scripts/fetch-pbs-licenses.sh` (new; bash, `set -euo pipefail`; network; maintainer-run once per runtime bump, never by `make` or CI):
  1. `source scripts/python-runtime.pin` (helper.md WP-203 §1: `PBS_RELEASE`, `PBS_PYTHON`, `PBS_TRIPLE`).
  2. Asset `cpython-${PBS_PYTHON}+${PBS_RELEASE}-${PBS_TRIPLE}-pgo+lto-full.tar.zst` from `https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_RELEASE}/` (encode `+` as `%2B`), downloaded with `curl --fail --location --proto '=https'` into `build/cache/pbs/`.
  3. Verify it against the line for that asset in the same release's `SHA256SUMS` file (also downloaded). A missing line exits 1 (`fetch-pbs-licenses: <asset> is not listed in SHA256SUMS`).
     - A new download is verified in the staging folder **before** it is copied into the cache. A mismatch exits 1 with `fetch-pbs-licenses: SHA-256 mismatch for <asset>` and caches nothing.
     - A cached archive that fails verification is removed with a message and downloaded again, so a bad file can't break every later run (`engine/tests/repo/test_fetch_pbs_licenses.py`, with stubbed `curl` and `zstd`).
  4. Extract only `python/licenses/` and `python/PYTHON.json` with `zstd -dc <asset> | tar -x -f - -C <tmp> python/licenses python/PYTHON.json`. macOS `tar` cannot read zstd (Context 11): if `zstd` is not on `PATH`, exit 2 with `fetch-pbs-licenses: needs zstd (brew install zstd)`.
  5. Copy the texts for the components of the table below into `App/Licenses/python-build-standalone/`, keeping upstream file names, and print one line per copied file plus the archive SHA-256 to record in `App/Licenses/README.md`.
  If a pinned release no longer has a `pgo+lto-full` asset for the triple, stop and report it; do not take texts from another release.
- HACL\*: from CPython's `Doc/license.rst` of the pinned version when present. CPython 3.12.14 omits that notice, so copy the leading MIT licence comment byte for byte from `Modules/_hacl/Hacl_Hash_SHA2.c` at the same pinned version.
- The build scripts’ MPL-2.0 licence is not in the runtime archive; copy `LICENSE` from the release tag’s exact python-build-standalone commit and record it.
- The Unicode licence (v3): for the Unicode Character Database data inside `unicodedata2`.
- The notice for `cff_to_glyf`, adapted from fontTools' `Snippets/otf2ttf.py` (© 2017 Just van Rossum, MIT; `reference/fontplayground-py/fontplayground/engine/prepare.py:78-83`).

`App/Licenses/components.json` has these static entries at minimum. The detect markers were verified on pbs 3.12.14 (Context 3). The SPDX values are what the upstream texts state at the time of writing; the text file is authoritative, so re-check them when you copy the texts.

| Component | SPDX | detect |
|---|---|---|
| python-build-standalone (build scripts) | MPL-2.0 | — (always) |
| OpenSSL | Apache-2.0 | `{"python": "import ssl; print(ssl.OPENSSL_VERSION.removeprefix('OpenSSL ').split()[0])"}` |
| SQLite | blessing | `{"python": "import sqlite3; print(sqlite3.sqlite_version)"}` |
| mpdecimal (libmpdec) | BSD-2-Clause | `{"python": "import decimal; print(decimal.__libmpdec_version__)"}` |
| Expat | MIT | `{"python": "import pyexpat; print('.'.join(map(str, pyexpat.version_info)))"}` |
| XZ Utils (liblzma) | 0BSD | `{"bytes": "Unrecognized error from liblzma"}` |
| bzip2 | bzip2-1.0.6 | `{"bytes": "bzip2/libbzip2"}` |
| libffi | MIT | `{"bytes": "ffi_prep_cif failed"}` |
| libuuid (util-linux) | BSD-3-Clause | `{"bytes": "/var/lib/libuuid/clock.txt"}` |
| HACL\* | MIT | `{"bytes": "Modules/_hacl/"}` |
| Unicode Character Database (in unicodedata2) | Unicode-3.0 | `{"python": "import unicodedata2; print(unicodedata2.unidata_version)"}` |
| otf2ttf snippet (cff_to_glyf) | MIT | — (always) |

zlib, libedit and ncurses are macOS system libraries (linked from `/usr/lib`), so no text is needed. Tcl/Tk must not be in the bundle (§S3). If a future runtime contains it, `--check` fails until an entry is added.

`App/Resources/Acknowledgements.txt` (the curated introduction; WP-601 appends the texts):
- the app's MIT notice
- the font-licence note of README section 6
- one line per component group: "Python runtime: CPython 3.12 (PSF License) built by python-build-standalone; fontTools (MIT); skia-pathops and Skia (BSD-3-Clause); unicodedata2 (Apache-2.0) with Unicode data (Unicode License v3); OpenSSL, SQLite, … (see below)"
- the `cff_to_glyf` attribution

**5. Tests.**

`engine/tests/repo/test_user_docs.py` (Linux):

| Test | Asserts |
|---|---|
| `test_ui_12_no_windows_wording_in_user_docs` | `README.md`, `App/Resources/en.lproj/UserGuide.html` (moved to `en.lproj` by WP-508; `zh-Hans.lproj` has the Chinese guide) and every `**/*.xcstrings` (source-language values; skip `build/`, `.build/`, `reference/`) contain none of: `Windows already has`, `admin rights`, `Ctrl+`, `Ctrl-`, `Enter uses it`, `Open settings folder`, `Show file`, `.venv\`, `run.bat`, `Explorer`. `README.md` mentions "Windows" only inside the "Coming from the Windows version" section |
| `test_ui_12_readme_commands_exist_in_the_app` | README section 4 uses bold (`**…**`) only for command titles. The set of those bold texts is non-empty, and each one is either in `SYSTEM_TITLES = {"Settings…", "About Font Playground", "Quit Font Playground", "Hide Font Playground"}` (menu items AppKit/SwiftUI supply) or an English title in some `**/Localizable.xcstrings` (skipping `build/`, `.build/`, `reference/`). "English title" means, per entry of `strings`: `localizations.en.stringUnit.value` when present, else the entry key. Titles compare after replacing `...` with `…`. The test must **pass, not skip**: at WP-602 time the String Catalog exists (WP-501/507) |
| `test_user_guide_matches_readme_commands` | the set of `<strong>` texts in `UserGuide.html` equals the README section-4 bold set |
| `test_crit_2_migration_note_says_do_not_copy_the_settings_folder` | the migration doc contains `Don't copy the whole`, `%LOCALAPPDATA%\FontPlayground`, `settings.json`, `catalog.json`, `forge_last.json` and `~/Library/Application Support/FontPlayground/forge_last.json` |
| `test_crit_3_windows_font_licence_warning` | the migration doc contains `C:\Windows\Fonts` and `licen` in the same paragraph, and `Office` |
| `test_tooling_11_static_licence_texts_exist` | every `components.json` entry has a valid SPDX-looking `license`, and non-empty files that exist under `App/Licenses/`; the table rows of Design §4 are all present by name |

`Packages/FontPlaygroundKit/Tests/FPCoreTests/MigrationDocTests.swift` (Linux, Swift Testing):
- `crit3DocTableMatchesEquivalents`: reads `docs/user/migrating-from-windows.md` via `#filePath`. For each table row under `## Windows fonts and their Mac equivalents`, except the two excluded rows, `WindowsFonts.equivalents[w] == macFamilies` for every Windows family `w` in the row. The union of all row families equals `Set(WindowsFonts.equivalents.keys)`.

### Acceptance criteria
- **AC-602-1** `README.md` has the 12 sections of Design §1 in order (headings as named). It no longer says "Status: planning". Section 2 reads exactly "A Mac with Apple silicon and macOS 14 Sonoma or later."
- **AC-602-2** UI-12: `test_ui_12_no_windows_wording_in_user_docs`, `test_ui_12_readme_commands_exist_in_the_app` and `test_user_guide_matches_readme_commands` pass.
- **AC-602-3** CRIT-3: `MigrationDocTests.crit3DocTableMatchesEquivalents` (`make kit-test`) and `test_crit_3_windows_font_licence_warning` pass.
- **AC-602-4** CRIT-2: `test_crit_2_migration_note_says_do_not_copy_the_settings_folder` passes, and the doc's import paragraph names the same folder as FPCore `LegacyImport.legacyFolder(home:)` (core.md WP-305: `~/Library/Application Support/FontPlayground`) and the notice text of ui-shell.md (`shell.notice.imported`).
- **AC-602-M2** (manual, macos) The one-time import works as the doc says. Use a temporary macOS user account (preferred), or first move aside `~/Library/Application Support/io.github.kciceblue.fontplayground/last.fontrecipe` and run `defaults delete io.github.kciceblue.fontplayground`, and move aside any existing `~/Library/Application Support/FontPlayground`. Write this Windows-shaped file (the shape of the original `to_settings()`, `ui/model.py:678-684`; same case as core.md AC-305-12) to `~/Library/Application Support/FontPlayground/forge_last.json`:

  ```json
  {"materials": [{"path": "C:\\Windows\\Fonts\\georgia.ttf", "index": 0, "weight": null, "scale": null},
                 {"path": "C:\\Windows\\Fonts\\simsun.ttc", "index": 0, "weight": null, "scale": 1.05}],
   "base_index": 0, "script_rules": {}, "default_weight": null, "default_scale": 1.0,
   "family_name": "Georgia SimSun", "style_name": "Regular",
   "output_path": "C:\\Users\\Someone\\Documents\\Georgia SimSun-Regular.ttf",
   "pins": {}, "names_edited": {"family": false, "style": false, "output": true}, "sample_text": "Hello 你好"}
  ```

  Launch the Debug app. The screenshot must show the "Imported your last recipe and settings…" notice, Georgia as the main font, and a notice naming SimSun as not found with Songti SC offered. Restore the moved files afterwards.
- **AC-602-5** TOOLING-11: `test_tooling_11_static_licence_texts_exist` passes, and on the Release app of `scripts/release.sh --adhoc`, `collect_licenses.py --check` exits 0 with every detect-found component present. `index.json` contains all 12 static components of Design §4 (plus the 5 of AC-601-8).
- **AC-602-6** `Contents/Resources/Acknowledgements.txt` in the Release app starts with the curated introduction and contains `== OpenSSL `, `== CPython `, `== skia-pathops ` and `== Unicode Character Database`. `grep -c "Copyright (c) 2011 Google Inc." "<app>/Contents/Resources/Acknowledgements.txt"` ≥ 1 (the Skia licence).
- **AC-602-7** `App/Resources/en.lproj/UserGuide.html` (moved to `en.lproj` by WP-508; `zh-Hans.lproj` has the Chinese guide) is bundled (`<app>/Contents/Resources/en.lproj/UserGuide.html` exists (moved by WP-508)), contains no `http://`, `https://` or `<script`, and Help ▸ Font Playground Help is enabled in the Debug app (WP-501's `helpURL`).
- **AC-602-M1** (manual, macos) Font Playground ▸ About Font Playground shows the curated introduction and, when scrolled, the licence texts (screenshot of the top and of the OpenSSL section). Help ▸ Font Playground Help opens the guide in light and in dark appearance (2 screenshots).

| Finding | Regression test |
|---|---|
| TOOLING-11 | `test_tooling_11_static_licence_texts_exist`; `collect_licenses.py --check` (AC-602-5) |
| CRIT-3 | `MigrationDocTests.crit3DocTableMatchesEquivalents`, `test_crit_3_windows_font_licence_warning` |
| UI-12 | `test_ui_12_no_windows_wording_in_user_docs`, `test_ui_12_readme_commands_exist_in_the_app` |

### Verification
```bash
make lint test
scripts/release.sh --adhoc
build/release/Font\ Playground.app/Contents/Resources/fpengine/bin/python3 -I -B tools/release/collect_licenses.py --app "build/release/Font Playground.app" --repo . --check
```

### Notes for the implementer
- Use the app's real command titles. Read them from the String Catalog; the test enforces this.
- Don't paraphrase licence texts. Copy them byte for byte from the pinned sources, and record each source (URL and version or archive SHA-256) in `App/Licenses/README.md`.
- Don't repeat the equivalence table anywhere else. FPCore's table is the source, and the Swift test keeps the doc in step.
- The SPDX guesses in Design §4 (python-build-standalone MPL-2.0, HACL\* MIT) must be confirmed from the texts you copy. If they differ, fix `components.json`; the text file wins.

---

## WP-701: Parity sign-off and cutover (remove `reference/`, freeze fixtures, tag v1.0.0)

**Goal:** Every item of the parity checklist is proven on a release build, the conformance fixtures that depend on the Python reference are frozen, `reference/` is removed without breaking any build, and `v1.0.0` is released.
**Depends on:** all (WP-507, WP-602, WP-111, WP-305, WP-205, WP-404 and their dependencies) · **Env:** macos · **Size:** S · **Closes findings:** —

### Scope
- In:
  - The parity evidence document and the ticks in docs/plan.md §6.
  - The M1–M5 exit check.
  - Freezing reference-derived fixture families.
  - Removing every code dependency on `reference/`, then deleting it, and updating the docs that mention it.
  - The version bump to 1.0.0 and the regenerated fixtures.
  - The tagged release.
  - A cutover guard test.
- Out: new features, and any fix larger than S. A parity gap found here becomes a bug WP, which blocks WP-701.

### Touched paths
- `docs/release/v1.0.0-parity.md` (new), `docs/plan.md` (edit: §6 ticks, milestone status)
- `tools/conformance/**` (edit: freeze), `spec/fixtures/FROZEN.sha256` (new), `spec/fixtures/**` (regenerated headers)
- `tools/reference_parity.py` (delete), `reference/` (delete)
- `AGENTS.md`, `docs/architecture.md` §6, `docs/testing.md`, `docs/dispatch.md`, `.github/pull_request_template.md`, `README.md` (edit: remove or retarget `reference/` mentions; add the citation note)
- `engine/tests/**` (edit: remove or adapt tests that need `reference/`, e.g. WP-202's `test_generator_does_not_touch_reference`)
- `App/Version.xcconfig`, `engine/pyproject.toml`, `engine/uv.lock` (edit: 1.0.0)
- `engine/tests/repo/test_cutover.py` (new)

### Design

**1. Parity sign-off.** `docs/release/v1.0.0-parity.md` has one row per docs/plan.md §6 item (17 rows): `| # | Item | WPs | Evidence | Build | Result |`. Evidence is automated test names and/or manual AC ids with the PR link and screenshot. Build is the release-candidate build number. Every row is verified on the Release app from `scripts/release.sh` (the ad-hoc DMG is enough for rows that don't need notarization). Tick the boxes in docs/plan.md §6 in the same PR. A second table lists M0–M5 with their exit criteria from docs/plan.md §2 and the evidence for each.

**2. Freeze the reference-derived fixtures.**
1. List every place code imports from `reference/`: `git grep -nE "reference/|fontplayground-py|import fontplayground|from fontplayground" -- ':!docs' ':!reference'`. Expected hits: the conformance generator's families built from `ui/{languages,smart,textutil}.py` through `tools/conformance/common.py:import_reference` (helper.md WP-202 §5), and `tools/reference_parity.py`.
2. Run `make conformance-check`; it must be green before anything changes.
3. WP-202 already has a **frozen mode** (helper.md WP-202 Design §6): when `--reference-dir` does not exist, the reference-sourced files (`languages/*`, `text/*`, `naming/family-names.json`) are left byte-identical and reported `frozen (reference/ removed): <file>`, while fpengine-sourced files (`scripts/`, `planner/`, `naming/postscript_names.json`, `shaping/`) and the Swift table are regenerated. WP-701 makes that mode permanent and tamper-evident:
   - Create `spec/fixtures/FROZEN.sha256` listing exactly the reference-sourced files: one `<sha256>  <path relative to spec/fixtures>` line per file, sorted by path, as `cd spec/fixtures && shasum -a 256 <files>` prints them.
   - WP-202's generator already verifies frozen files against `FROZEN.sha256` whenever that file exists, with the message `conformance: frozen fixture changed: <path> (frozen at WP-701; never hand-edit)` (helper.md WP-202 §6, AC-202-11). WP-701 makes the reference-sourced categories import nothing and **only** verify (SHA-256 via `hashlib`); a missing or changed file fails `make conformance` (exit 1) with that message. The generator then prints `frozen: <n> files verified` once, instead of one `frozen (reference/ removed): <file>` line per file.
   - *As built:* the manifest is required and must list exactly the six frozen files; a missing manifest or a dropped line fails with the same message (naming `FROZEN.sha256` or the dropped path), so deleting a line cannot silently unfreeze a file.
4. Remove the `--reference-dir` option, `common.import_reference`, `ReferenceMissing` and every code path that only served the frozen categories. Remove or adapt the generator tests that need `reference/` (for example `test_generator_does_not_touch_reference`), and add `test_frozen_fixture_change_is_rejected` in `engine/tests/conformance/test_generator.py` (copy the tree to `tmp_path`, change one byte of a frozen file, run the generator with `--out` pointing there: exit 1 with the message). Delete `tools/reference_parity.py` (WP-002).

**3. Delete `reference/`.** `git rm -r reference`. Then update the docs:
- AGENTS.md: hard rule 1, the Layout line, and the AGENTS "Commands"/"Layout" mentions.
- docs/architecture.md §6.
- docs/testing.md: the "Core unit" row keeps its porting table, which now points at the git history.
- docs/dispatch.md and `.github/pull_request_template.md`: the checklist items "Nothing under `reference/`".
- README.md: WP-602's rewrite has no `reference/` link; check it and fix any mention left.

Add one sentence to AGENTS.md and docs/architecture.md: "`reference/` was removed at v1.0.0 (WP-701). Citations of the form `reference/fontplayground-py/<path>:<line>` in specs and code comments refer to kciceblue/fontplayground at commit `14b6572e3c229de61063663c5c058a9a57864a3e`." Specs and code comments keep their citations unchanged.

**4. Version 1.0.0.**
- `MARKETING_VERSION = 1.0.0` and `CURRENT_PROJECT_VERSION = 1` in `App/Version.xcconfig`.
- `version = "1.0.0"` in `engine/pyproject.toml`, then `uv lock`.
- `FPCTL.version = "1.0.0"` in `Packages/FontPlaygroundKit/Sources/fpctl/FPCTL.swift`, so `fpctl --version` matches the app and engine, and the version literals in `CommandLineTests` and `engine/tests/protocol/test_hello.py`.
- `make conformance`: the live fixtures' headers record fpengine `1.0.0`; frozen files are unchanged. Commit.
- After merge, the maintainer tags `main` with `git tag -a v1.0.0 -m "Font Playground 1.0.0"` and pushes the tag. `release.yml` builds, notarizes and drafts the GitHub release. The maintainer publishes it after AC-701-9.

**5. Cutover guard** (`engine/tests/repo/test_cutover.py`, Linux):

| Test | Asserts |
|---|---|
| `test_reference_directory_is_gone` | `not (ROOT / "reference").exists()` |
| `test_no_code_references_the_reference_directory` | Over the files `git ls-files` lists (fallback: a walk skipping `.git`, `build`, `.build`, `.venv`, `dist`), limited to `*.py`, `*.swift`, `*.sh`, `*.yml`, `*.yaml`, `*.toml`, `*.json` and `Makefile`, excluding `spec/**`, `docs/**` (prose and the pre-port research prototypes in `docs/research/prototypes/`, which nothing runs) and this test file: after dropping comment lines (a stripped line starting with `#`, or with `//` in `.swift`), no line contains `reference/fontplayground-py`, and no `.py` line matches `^\s*(from|import)\s+fontplayground\b`. Markdown is not scanned: specs, AGENTS.md and code-comment citations keep their `reference/fontplayground-py/<path>:<line>` form (Design §3) |
| `test_frozen_fixtures_match_manifest` | every line of `spec/fixtures/FROZEN.sha256` names an existing file whose SHA-256 matches |

### Acceptance criteria
- **AC-701-1** `docs/release/v1.0.0-parity.md` has all 17 §6 items with evidence and result "pass", and all M0–M5 criteria with evidence. docs/plan.md §6 has 17 ticked boxes and no unticked one (`awk '/^## 6\./{f=1;next} /^## 7\./{f=0} f' docs/plan.md | grep -c '^- \[x\]'` prints 17, and the same with `'^- \[ \]'` prints 0).
- **AC-701-2** Before deletion, `make conformance-check` is green, and the freeze commit adds `spec/fixtures/FROZEN.sha256` with one line per reference-derived fixture file. `make conformance` prints `frozen: <n> files verified` and exits 0. `test_frozen_fixture_change_is_rejected` passes (a changed frozen file fails with the "frozen fixture changed" message).
- **AC-701-3** `test_reference_directory_is_gone`, `test_no_code_references_the_reference_directory` and `test_frozen_fixtures_match_manifest` pass. `tools/reference_parity.py` no longer exists.
- **AC-701-4** From a clean clone of the PR branch: `make setup lint test` is green on Linux (both Swift versions) and macOS, and `make app self-test` is green on macOS (CI links).
- **AC-701-5** AGENTS.md, docs/architecture.md, docs/testing.md, docs/dispatch.md and README.md contain no instruction that requires `reference/`, and each of AGENTS.md and docs/architecture.md contains the citation sentence of Design §3.
- **AC-701-6** `plutil -extract CFBundleShortVersionString raw` on the Release app prints `1.0.0`. `uv run --project engine python -c "import fpengine; print(fpengine.__version__)"` prints `1.0.0`. `test_tooling_8_single_version` passes.
- **AC-701-7** `make conformance-check` is green after the version bump: live fixtures were regenerated and committed, and frozen ones are unchanged.
- **AC-701-8** (post-merge, maintainer) The `release.yml` run for tag `v1.0.0` is green. It produced `FontPlayground-1.0.0-arm64.dmg` and its `.sha256` on a draft release, with the AC-601-16 outputs in its log (`Accepted` ×2, `source=Notarized Developer ID` ×2). This also discharges AC-601-16 and AC-601-M3 if they were deferred.
- **AC-701-M1** (manual, macos) The downloaded v1.0.0 DMG, on a clean macOS 14 install (a VM is fine; **waived for v1.0.0** by the maintainer on 2026-09-30, see docs/decisions.md §1) and on the current macOS: the app opens, `"/Applications/Font Playground.app/Contents/MacOS/Font Playground" --self-test --require-embedded-engine` exits 0 (paste the summary line), and a Latin + CJK Install and Uninstall works. Screenshots for both OS versions (M5).
- **AC-701-9** (post-merge, maintainer) The GitHub release `v1.0.0` is published by the maintainer with the DMG and checksum after AC-701-M1.

### Verification
```bash
make setup lint test
make conformance-check
make app self-test
scripts/release.sh --adhoc
uv run --project engine pytest -q engine/tests/repo/test_cutover.py   # the guard; markdown citations are allowed
```

### Notes for the implementer
- Do the freeze and the deletion in separate commits of the same PR: freeze, then remove imports, then `git rm`, then the doc edits, then 1.0.0. That way each step's CI state is visible.
- Don't hand-edit any fixture. If a frozen family is wrong, that is a bug WP against the Swift port (fixtures are the spec). It is not a reason to regenerate from an engine that no longer has the reference code.
- Tagging and publishing are maintainer actions. The PR stops at "ready to tag"; AC-701-8 and AC-701-9 are checked after merge and recorded in the parity document by a follow-up commit.
- `uv lock` after the version bump needs network; WP-701 runs on the Mac, where it is available.
