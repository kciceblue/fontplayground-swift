# Product decisions and maintainer prerequisites

The specs take a default for every open product question, so no WP is blocked. This page lists them in one place so the maintainer can **override a default before dispatching the WP that implements it**. To override: edit the owning spec section and this table in one commit, then dispatch. Agents implement what the spec says (AGENTS.md rule 14).

## 1. Maintainer prerequisites

| Needed by | What | Notes |
|---|---|---|
| WP-001 | Codex environment set up as in `docs/dispatch.md`; WP-001 run with network (Codex CLI on the Mac, or agent internet with an allowlist) | `uv lock` resolves PyPI once |
| macos WPs | Xcode 26 or newer selected; `brew install xcodegen uv` | The authoring Mac had no xcodegen, so `App/project.yml` was never run through it; WP-001's ACs check the outcome |
| WP-601 (AC-601-16, AC-601-M3) | Apple Developer Program membership, a **Developer ID Application** certificate, and a notarytool keychain profile or App Store Connect API key (CI secrets named in foundation-release.md) | Without them these ACs move to WP-701 (the spec allows this). Dry-run notarization early: Mach-O files under `Contents/Resources` are expected to pass but are unverified |
| WP-601 | App icon art | The default is a generated geometric mark (no font glyphs). Supply Icon Composer art before WP-601 or WP-701 if you want a designed icon |
| WP-203 | Refresh the python-build-standalone pin (release, 3.12.x, SHA-256) to the newest 3.12 at implementation time | The spec pins release 20260924 / CPython 3.12.14 as an example |
| WP-111, WP-701 | One run of `make engine-apple-fonts` on the oldest supported macOS (14) | Reference numbers were measured on macOS 27 only. **Waived for v1.0.0** by the maintainer (2026-09-30), together with AC-701-M1's macOS 14 run: skipped, not passed. The deployment target stays macOS 14.0 |
| WP-501 | Help menu URL (`FPHelpURL` in Info.plist), e.g. the GitHub README | Empty by default; the bundled user guide from WP-602 is used first |
| WP-401 (optional) | A manual check with a font disabled in Font Book (CRIT-9) | Can't be simulated safely; fakes cover the logic |

## 2. Product defaults (override before the listed WP)

| # | Question | Spec default | Alternative | WP |
|---|---|---|---|---|
| D1 | Copyright holder in `NSHumanReadableCopyright` and About | "Copyright (c) 2026 kciceblue", from LICENSE | another holder string | 501, 601 |
| D2 | A forged font that needs a truncated cmap format 4 (N-1) | a **warning** issue `cmap_format4_partial` in the report | log only | 101 |
| D3 | Synthetic bold that more than doubles the file size | a warning when the **whole file** grows over 2× | per-part threshold (would fire on almost every synthetic bold) | 105 |
| D4 | Forged-font version string | `Version <days since 2000-01-01>.<5-digit day fraction>`, mirrored in `head.fontRevision`: monotonic, unique per forge | a date-like string (can't be unique per forge within Fixed 16.16) | 109 |
| D5 | Licence notes also written into the forged font's name ID 13 | yes, so re-forging a forged font keeps its licence class | report only | 110 |
| D6 | Free, non-OFL/Apache licences under `/System/Library` (e.g. ParaType) | classified `apple-sla` (ADR-0012 limits `open` to OFL and Apache) | widen `open` | 110 |
| D7 | Faces with `suspicious_coverage` (e.g. `.LastResort`-like) | flagged and never suggested, but not refused at forge time | refuse | 106, 304 |
| D8 | Hebrew fonts with points but no `hebr` OpenType tables (Raanana, New Peninim MT, Lucida Grande…) | their Hebrew is `unshaped`, so they contribute no Hebrew | allow unpointed Hebrew letters | 107 |
| D9 | Scripts with no OpenType system alternative (Malayalam has only downloadable assets; Tibetan has none) | the picker says no installed font shapes it and offers "Get more fonts…" | — | 304, 503 |
| D10 | Windows→Mac font equivalents (SimSun→Songti SC, …) on recipe import | offered as one-click suggestions, **never** substituted automatically | auto-substitute with a notice | 305, 502 |
| D11 | Platform preferred font for Latin/Greek/Cyrillic suggestions | Helvetica Neue (a product choice: SF is hidden) | no preference | 304 |
| D12 | Real heavier face instead of synthetic bold (ENGINE-4) | applied automatically after a weight change, with a note and Undo | an opt-in suggestion button | 304, 502, 506 |
| D13 | A rule that assigns a complex script to a font that can't shape it | **blocks** the build (`RecipeProblem.cannotShape`, the same as the engine error) | warn only | 303, 107 |
| D14 | Extra font folders that are missing at launch (e.g. an unplugged drive) | **dropped** from settings (core.md AC-305-10) | keep them and show "Not found" (recommended by two reviewers; change AC-305-10 before dispatching WP-305) | 305, 401, 501 |
| D15 | Installing under a name Apple offers for download but that isn't installed | a warning with "Install Anyway" / "Cancel" (`.ask`) | block | 403, 505 |
| D16 | Forged fonts in `~/Library/Fonts` that aren't in the app's manifest (e.g. installed by hand from Save a Copy, or from the Windows app) | blocked as "You already have…"; never touched | adopt them as ours | 403 |
| D17 | In-app download of a curated list of Apple fonts (WP-404 part B) | optional: decide at dispatch. Otherwise only "Get more fonts…" (Font Book) and backlog B-7 | include part B | 404 |
| D18 | Rescan Fonts | `refresh(.full)`, like the original's cache-ignoring rescan (about 5–15 s) | `refresh(.incremental)`, as the CATALOG-6 verifier recommends | 501 |
| D19 | Start Over | asks for confirmation (there is no undo yet, B-4) | reset immediately, like the original | 501 |
| D20 | Install keyboard shortcut / default button | none; Return in the name field doesn't build | give Install a shortcut | 505 |
| D21 | Picker section headers | sentence case ("All Chinese fonts · 37"); card role titles stay upper case | upper case as in the original | 503 |
| D22 | Size stepper step | 5 (typed values accept any integer 10–1000) | 1, as in the original | 502 |
| D23 | Note on cards for fonts with Apple-only ligatures (morx), e.g. Helvetica as main font | a muted note on the card | report only | 502, 505 |
| D24 | Preview line height | fixed to the main font's metrics, as the result will be (a preview-honesty improvement) | natural line height per run | 504 |
| D25 | Preview of synthetic bold | approximated with a negative stroke width plus kerning from Δ ≥ 50, capped at 500, matching the engine | Qt-like emboldening only above Δ 100, as the original preview did | 504 |
| D26 | ⌘F (Find Font…) | opens the picker for Latin when the recipe is empty, otherwise for "any language" | reopen the last-used language | 503 |
| D27 | Card colour dots | filled when Colour by Font is on, hollow when off | always filled | 502 |
| D28 | The app's Simplified Chinese name (the maintainer asked for "字体合并 or something similar", a name they would pick from the App Store) | **字体混搭** ("mix and match fonts"): `CFBundleDisplayName`/`CFBundleName` in `zh-Hans`, and in every Chinese string that names the app. The bundle file stays `Font Playground.app` | 字体合并 (literal, reads like a utility); keep "Font Playground" | 508 |
| D29 | Terms that read oddly in Chinese | kept in English: weight and style names (Light, Regular, Medium, Semibold, Bold, Heavy), format and technology names (OpenType, PostScript, AAT…), key names (Return, Esc) (localisation.md §L3) | translate weight names (细体, 常规体, 中黑…) | 508 |
| D30 | How users switch language | Settings › Language (System / English / 简体中文) writes `AppleLanguages` into the app's own defaults domain (the same key System Settings' per-app language uses) and offers Quit and Reopen | System Settings only; no in-app control | 508 |
| D31 | Traditional Chinese (zh-Hant, zh-HK) and other unsupported systems | English, unless the user's language list also has Simplified Chinese; they can pick 简体中文 in Settings | serve `zh-Hans` to every Chinese system | 508 |
| D32 | Engine data in the Chinese UI (report warnings, licence note texts, helper and installer error details) | stays English, as in v1; the Chinese user guide says so | map issue codes, licence classes and error codes to catalog strings (backlog B-14) | 508 |
| D33 | How users can donate | a Buy Me a Coffee page (`https://buymeacoffee.com/kciceblue`, Info.plist `FPDonateURL`), or Afdian (`https://afdian.com/a/kciceblue`, the `zh-Hans` value of `FPDonateURL` in `InfoPlist.xcstrings`) when the app runs in Simplified Chinese, opened from Font Playground › Donate… and from an offer shown once per user after the first launch that finishes loading fonts (including people updating from 1.0) | In-App Purchase tips (needs a sandboxed Mac App Store build, which ADR-0010 rules out) | 501 (ui-shell.md D8) |

## 3. Known coordination risks (for the dispatcher)

- **Wave 3/4 engine PRs** all touch `prepare.py`, `forge.py` or `face.py`. Merge them in the order `docs/plan.md` §4 gives. `READER_VERSION` bumps conflict on one line: take the higher number plus one.
- **Wave 10 UI PRs** all extend `AppModel`. WP-501 pre-creates the seams (ui-editing.md §S2.3); merge in the order 502 → 503 → 504 → 505 → 506 if conflicts pile up.
- **Three synthetic-font generators** exist by design: `fpengine.testing.make_fonts` (WP-202), MacKit `TestFixtures/make_fonts.py` (WP-401/402/403) and WP-504's test script. Consolidating them is optional clean-up.
