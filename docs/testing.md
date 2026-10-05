# Test strategy

CI executes these targets on the Mac mini. See
[self-hosted CI and Codex review](self-hosted-ci.md) for runner operation and
the automatic advisory PR review.

## 1. Make targets (the only commands ACs may rely on)

WP-001 creates these targets. Specs and acceptance criteria refer to them by name. Adding a target is fine; renaming one requires updating every spec that uses it.

| Target | Runs |
|---|---|
| `make setup` | `uv sync --frozen` in `engine/`; checks `xcodegen` and Xcode ≥ 26 and prints how to install what's missing |
| `make lint` | `ruff check` + `ruff format --check` (engine, tools); `swift format lint --strict --recursive` on both packages and `App/Sources` |
| `make engine-test` | `uv run pytest -q` in `engine/`. Tests marked `apple_fonts` are skipped unless `FP_APPLE_FONTS=1` |
| `make engine-apple-fonts` | `FP_APPLE_FONTS=1 uv run pytest -q -m apple_fonts`: the real-Apple-font scenario matrix (WP-111) |
| `make conformance` | regenerates `spec/fixtures/**` with `tools/conformance/generate.py`, after verifying the frozen files listed in `spec/fixtures/FROZEN.sha256` |
| `make conformance-check` | `make conformance`, then fails if `spec/fixtures/` or `Packages/FontPlaygroundKit/Sources/FPCore/Generated/` shows drift or untracked files |
| `make kit-test` | `swift test --package-path Packages/FontPlaygroundKit` |
| `make mac-test` | `swift test --package-path Packages/FontPlaygroundMacKit --skip PerformanceTests`, then the same with `--no-parallel --filter PerformanceTests` (§5) |
| `make test` | `engine-test` + `conformance-check` + `kit-test` + `mac-test` |
| `make app` | `xcodegen generate --spec App/project.yml` + `xcodebuild -scheme FontPlayground -configuration Debug build` |
| `make helper-runtime` | `scripts/build-helper-runtime.sh` → `build/helper/fpengine/` |
| `make self-test` | builds the app if needed and runs `…/Contents/MacOS/Font Playground --self-test` |

**Before the owning WPs land**, WP-001 wires these targets as documented placeholders:
- `conformance` is a no-op until WP-202.
- `helper-runtime` exits 2 until WP-203.
- `self-test` is a stub until WP-601.
- `engine-apple-fonts` runs a wiring placeholder until WP-111.

The Makefile runs on macOS only and stops with an error elsewhere (ADR-0014). `make app` builds into `build/DerivedData`, so the app is at `build/DerivedData/Build/Products/Debug/Font Playground.app`.

The manual acceptance criteria for M3 drive the services through `swift run --package-path Packages/FontPlaygroundMacKit fpmac-harness …`, which WP-401 creates.

## 2. Test layers

| Layer | Where | Framework | What it proves |
|---|---|---|---|
| Repository hygiene | `engine/tests/repo/` | pytest | Layout rules (no `fpengine.catalog`, no Qt imports, no forbidden files); run by `make engine-test` |
| Engine conformance | `engine/tests/conformance/` | pytest | The generator is deterministic and fixtures are current |
| Engine unit | `engine/tests/` | pytest | Each engine behaviour, using **synthetic fonts** built with `fontTools.fontBuilder` (ported from the original app's `tests/fixtures.py`). Every audit bug gets a synthetic regression fixture: a (0,1)-only cmap, a font without OS/2, a malformed `bloc`, shared lookups between features, and so on |
| Engine real fonts | `engine/tests/apple_fonts/` | pytest, `@pytest.mark.apple_fonts` | The scenario matrix on real macOS system fonts (WP-111). Runs only on macOS with `FP_APPLE_FONTS=1`, and skips a scenario whose font is not installed (with the reason) |
| Protocol | `engine/tests/protocol/` | pytest + `jsonschema` | Every event the helper emits validates against `spec/protocol/*.schema.json` |
| Conformance | `spec/fixtures/**` + Swift tests | Swift Testing | The Swift ports (`source_of`, script groups, languages, naming, PS names) give byte-identical answers to Python on shared inputs |
| Core unit | `Packages/FontPlaygroundKit/Tests/FPCoreTests` | Swift Testing | The recipe behaviour, ported test by test from the original app's `tests/test_model.py`, `test_smart.py`, `test_languages.py`, `test_mix.py`, `test_planner.py` (the mapping table is in `docs/specs/core.md`; the sources are in git history before WP-701 and at kciceblue/fontplayground `14b6572`) |
| Client | `Packages/FontPlaygroundKit/Tests/FPEngineClientTests` | Swift Testing | Process handling against a **fake helper** (a small Python or shell script in the test resources) and, when `FP_ENGINE_PYTHON` is set, against the real `fpengine` |
| Integration (headless) | `Packages/FontPlaygroundKit/Tests/FPCTLTests` + `make`-driven | Swift Testing | `fpctl` scan and forge end to end with synthetic fonts and with Apple fonts |
| Mac services | `Packages/FontPlaygroundMacKit/Tests/FPMacServicesTests` | Swift Testing | CoreText enumeration, rendering (glyph and run inspection via `CTLine`), and the installer, against **a temporary fonts folder + `kCTFontManagerScopeProcess`** |
| UI logic | `Packages/FontPlaygroundMacKit/Tests/FPAppUITests` | Swift Testing | `AppModel` and view-model behaviour with fake services; command enablement; keyboard handling in the picker model |
| App smoke | `make self-test` | app flag | Launch headless, scan, forge a bundled fixture recipe through the embedded helper, verify the output with CoreText, and exit 0. Used by CI and release |
| Manual QA | PR description | checklist + screenshots | Visual and interaction criteria that can't reasonably be automated (each UI spec lists them) |

## 3. Markers and environment variables

| Name | Meaning |
|---|---|
| `@pytest.mark.macos` | needs macOS (auto-skip elsewhere) |
| `@pytest.mark.apple_fonts` | needs real Apple system fonts and `FP_APPLE_FONTS=1` |
| `@pytest.mark.slow` | over 10 s. Still run in CI; excluded locally by `-m "not slow"` if the developer wants |
| `FP_ENGINE_PYTHON` | Python that can `import fpengine` (dev and tests). `make` exports `engine/.venv/bin/python` |
| `FP_APPLE_FONTS=1` | enable the real-font suites: pytest `-m apple_fonts`, and the Swift MacKit real-font and performance tests (`FP_APPLE_FONTS=1 make mac-test`) |
| `FP_APPLE_FONTS_TIME_FACTOR` | float, default 1. Scales WP-111 time budgets; set to about 2–3 on virtualized CI runners |
| `FP_PERF_FACTOR` | float, default 1. Scales Swift performance-test thresholds (ui-editing, mac-services); about 3 on virtualized CI. The Mac mini runner is not virtualized and leaves it unset (see below) |
| Swift `.enabled(if:)` traits | Swift tests that need the real helper check `FP_ENGINE_PYTHON`. Tests that need macOS live in MacKit only. MacKit tests build synthetic fonts with a Python script through `FP_ENGINE_PYTHON`, and **fail, not skip**, when it is missing. `make mac-test` exports it |

## 4. Fixtures policy

- **Never commit Apple, Microsoft or other proprietary font files.** Tests build synthetic fonts at runtime, or use real system fonts in place (the `apple_fonts` suite).
- Open-licence fonts may be committed under `engine/tests/data/` only if they are ≤ 200 KB and listed with their licence in `engine/tests/data/README.md`.
- Conformance fixtures are **generated**, never hand-edited. Their generator records its inputs and the `fpengine` version in each file's header object.
- The six fixtures listed in `spec/fixtures/FROZEN.sha256` (`languages/*`, `text/*`, `naming/family-names.json`) were generated from the original app's UI logic and are frozen since WP-701. `make conformance` verifies their SHA-256 before writing anything and never rewrites them; their headers keep the `fpengine` version they were made with. `engine/tests/repo/test_cutover.py` also checks them.

## 5. Safety rules for tests (enforced in review)

- No test writes into the real `~/Library/Fonts`, `/Library/Fonts`, `~/Library/Application Support/io.github.kciceblue.fontplayground` or `~/Library/Caches/io.github.kciceblue.fontplayground`. Services take their folders as parameters, and tests pass temporary directories.
- No persistent or user-scope CoreText registration. Process scope, or URL descriptors only.
- No name-based CoreText lookups of names that are not installed (they can start system downloads).
- No network access in tests.
- No visible windows in automated tests. UI tests create views off-screen, or test view models.
- VoiceOver checks are manual, plus unit tests of the label strings: an off-screen `NSHostingView` does not expose a usable accessibility tree. Colour tests check all four appearance-match/palette mappings with pure functions and resolve dynamic colours under actual Aqua and Dark Aqua appearances; live Increase Contrast switching is checked manually.

Mac CI and release checks set `SWIFT_TEST_FLAGS=--no-parallel` for MacKit.
This prevents concurrent AppKit suites from competing with frame-time and
callback-deadline measurements. Performance thresholds stay unchanged; local
`make mac-test` keeps its normal defaults unless the variable is supplied.
Either way, `make mac-test` runs the frame-time suites (`*PerformanceTests`)
in a second, serial `swift test` pass after the rest. Run in parallel with the
other suites on an idle M-series Mac, the WP503 scroll p95 used 15.5 of its
16.7 ms; on its own it uses about 10.5 ms.

CI doesn't set `FP_PERF_FACTOR`. On the Mac mini runner, CPU-bound timings
(`WP503 rows`, `WP503 open`) match a developer Mac. Its timers are coarse,
though: a 16 ms `Task.sleep` can last over 100 ms there. Timing-sensitive
tests therefore follow two rules:

- **Debounces and throttles run on an injected clock.** A model whose waits
  a test checks takes a `clock: any Clock<Duration>` (`ContinuousClock()` by
  default), as `PickerModel` does. Tests pass `ManualClock` (`FPAppUITests/Support/ManualClock.swift`) and
  advance it explicitly. They check "not yet" and "never" through the clock's
  `waiting` and `cancelled` state. Never assert that something has *not yet*
  happened after a wall-clock sleep. Polling for something that must happen
  (`pickerEventually`) is fine.
- **Frame-time tests don't sleep between samples.** A long gap lets the core
  idle and clock down, which about doubles the next sample. On an M5 Pro the
  WP503 scroll p95 was 9.8 ms with 16 ms gaps and 20.6 ms with 130 ms gaps.
  Yield to the main actor for the frame instead.
