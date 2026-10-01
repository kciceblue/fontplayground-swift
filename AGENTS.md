# AGENTS.md

Instructions for coding agents (Codex, Claude, …) and humans working in this repository.

## What this repo is

The native macOS rebuild of Font Playground: a SwiftUI/AppKit/CoreText app with the Python fontTools engine (`fpengine`) as a helper process. Read `docs/architecture.md` before changing anything. Work is organised in **work packages (WPs)**, listed in `docs/plan.md` and specified in `docs/specs/*.md`.

## How to do a work package

1. Read, in this order:
   - this file
   - `docs/architecture.md`
   - the ADRs your WP cites
   - your WP's section in `docs/specs/<spec>.md`
   - `docs/testing.md`
2. Implement **only** the WP's scope. If the spec is wrong or ambiguous, choose the option most consistent with `docs/architecture.md`. Record the decision in the PR description under "Spec deviations". Update the spec text in the same PR.
3. Meet **every** acceptance criterion (AC). Run the WP's verification commands and paste their output tails into the PR.
4. Keep the PR to one WP. Title it `WP-NNN: <title>` and name the branch `wp/NNN-short-slug`. Use `.github/pull_request_template.md`.

## Environment

- **macOS only** (ADR-0014). Every WP needs macOS 14+ on Apple silicon with Xcode 26+, `xcodegen` and `uv` (Homebrew). Work on the maintainer's Mac (Codex CLI or Claude Code); CI runs the same Make targets on a self-hosted Mac.
- `make setup` is the only step that uses the network. Everything after it must work offline.
- Older specs mark WPs `Env: linux`. Read that as "needs no Apple frameworks"; it doesn't mean the WP runs on Linux.

## Layout

```
engine/                         Python engine (uv project). src/fpengine/, tests/
tools/conformance/              fixture generator → spec/fixtures/
spec/protocol/                  JSON Schemas for the helper protocol (normative)
spec/fixtures/                  generated conformance fixtures (never hand-edit; FROZEN.sha256 lists frozen ones)
Packages/FontPlaygroundKit/     FPCore, FPEngineClient, fpctl: Foundation only (no UI, no CoreText)
Packages/FontPlaygroundMacKit/  FPMacServices, FPAppUI: macOS only
App/                            XcodeGen project.yml + app resources (no committed .xcodeproj)
scripts/                        build, sign, notarize, codex setup
docs/                           architecture, plan, specs, ADRs, research
```

`reference/` was removed at v1.0.0 (WP-701). Citations of the form `reference/fontplayground-py/<path>:<line>` in specs and code comments refer to kciceblue/fontplayground at commit `14b6572e3c229de61063663c5c058a9a57864a3e`.

## Commands

Use the Make targets (defined in `docs/testing.md`). Don't invent parallel scripts.

```
make setup          # once
make lint
make test           # engine-test + conformance-check + kit-test + mac-test
make engine-test
make kit-test
make mac-test
make conformance    # regenerate spec/fixtures after changing planner/naming/scripts behaviour
make app            # xcodegen + xcodebuild
make self-test      # headless app smoke test
```

## Hard rules

1. **Never hand-edit `spec/fixtures/`.** Regenerate it with `make conformance`. The files listed in `spec/fixtures/FROZEN.sha256` came from the original app, which is gone, and can't be regenerated: if one is wrong, fix the Swift port in a bug WP.
2. **`FontPlaygroundKit` must not import** AppKit, SwiftUI, CoreText, CoreGraphics or other UI or font frameworks. Put that code in `FontPlaygroundMacKit`. This keeps the recipe logic and helper client testable without UI, and keeps CoreText calls where `NameLookupSafetyTests` checks them (rule 4).
3. **Tests never touch real user font folders** or the app's real Application Support and Caches folders. Pass temporary directories. CoreText registration in tests is process scope only.
4. **Never look up a font by name in CoreText** unless that name is known to be installed. Create fonts from file URLs. Name lookups can trigger system font downloads. There are exactly two allow-listed exceptions, both enforced by `NameLookupSafetyTests`:
   - the LastResort descriptor fallback;
   - WP-404's downloader, after explicit user confirmation.
5. **Never commit font files** except small open-licence fonts listed in `engine/tests/data/README.md`. Never commit Apple or Microsoft fonts.
6. **No network** in tests or build steps. The exceptions are `make setup`, `uv lock` (WP-001 only), `scripts/build-helper-runtime.sh` (pinned URL + SHA-256), the release scripts `scripts/release.sh`/`scripts/notarize.sh` (notarytool), and the maintainer-run `scripts/fetch-pbs-licenses.sh`.
7. **No silent drops.** Anything filtered, skipped, unresolved or failed is counted and surfaced (report, UI, or error).
8. **Atomic file writes** everywhere (temporary file in the same folder, fsync, rename).
9. **Protocol changes** require updating `spec/protocol/*.schema.json`, `docs/specs/helper.md`, both implementations and the protocol tests in one PR.
10. **Behaviour changes to planner, scripts, naming or PostScript names** require `make conformance` and committing the regenerated fixtures.
11. Don't add third-party Swift packages or new Python **runtime** dependencies without an ADR. Dev-only test dependencies declared by WP-001 are allowed (pytest, jsonschema, ruff, and `pyobjc-framework-CoreText; sys_platform == 'darwin'` for the macOS-only real-font suite). They never enter the helper runtime.
12. Don't commit generated artefacts (`*.xcodeproj`, `build/`, `.venv/`, DMGs).
13. **Bump `fpengine.face.READER_VERSION`** in any PR that changes `scan` output for an unchanged font file. The catalog cache is keyed on it (contracts §5).
14. Read `docs/decisions.md` for product decisions taken with defaults. Implement the recorded default unless it says otherwise.

## Code style

- **Python:** ruff (line length 120), type hints on public functions, dataclasses for records, no Qt. Match the style of the imported engine (terse docstrings saying *why*).
- **Swift:** Swift 6 language mode, strict concurrency. Prefer value types in `FPCore`. `@MainActor` for UI state. Protocols at service boundaries. `swift format` (repo `.swift-format`). Name things after the domain (`Recipe`, `Material`, `ScriptGroup`, `FaceRecord`), not after the Python module layout.
- **User-facing text:** plain words, the original app's tone (see its `README.md` at the commit cited under Layout), macOS terminology (Finder, Settings…, Trash). All strings go through the String Catalog.
- **Comments:** explain intent and non-obvious constraints; cite audit IDs (e.g. `// ENGINE-1: fontTools.merge drops (0,1) cmaps`) where a line exists because of a finding.

## Definition of done (every WP)

- [ ] All ACs met; verification commands pasted in the PR.
- [ ] `make lint` and `make test` green on macOS.
- [ ] New behaviour has tests. Every audit finding the WP closes has a regression test named after it (e.g. `test_engine_1_mac_unicode_cmap`).
- [ ] Docs updated: the spec section, if you deviated; `docs/plan.md` status column if the maintainer asks.
- [ ] No TODOs without a WP or backlog reference.
