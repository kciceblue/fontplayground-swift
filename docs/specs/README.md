# Specs index

Each WP section is self-contained, but it relies on its spec's **Context** and **Shared definitions** (the lines before its first WP) and on `contracts.md`. Line ranges are for `sed -n '<start>,<end>p'` or an editor jump. Regenerate this table whenever a spec changes length.

| Spec | Lines | Shared part (read first) |
|---|---|---|
| [foundation-release.md](foundation-release.md) | 1705 | lines 1–205 |
| [engine-correctness.md](engine-correctness.md) | 916 | lines 1–154 |
| [engine-metadata.md](engine-metadata.md) | 1131 | lines 1–201 |
| [helper.md](helper.md) | 1694 | lines 1–202 |
| [core.md](core.md) | 1558 | lines 1–158 |
| [mac-services.md](mac-services.md) | 1687 | lines 1–438 |
| [ui-shell.md](ui-shell.md) | 2062 | lines 1–623 |
| [localisation.md](localisation.md) | 431 | lines 1–154 |
| [ui-editing.md](ui-editing.md) | 1085 | lines 1–298 |

**38 work packages, 634 acceptance criteria (42 of them `M` manual-QA criteria).** traceability.md counts a few more as manual, because some non-`M` criteria need maintainer resources.

| WP | Title | Spec | Lines | ACs (manual) |
|---|---|---|---|---|
| WP-001 | Repository scaffold, Makefile, Codex setup script, CI (Linux + macOS) | [foundation-release.md](foundation-release.md#wp-001-repository-scaffold-makefile-codex-setup-script-ci-linux--macos) | 206–849 | 19 (1) |
| WP-002 | Import engine as `fpengine` (uv project, Qt-free, tests ported, POSIX-clean) | [foundation-release.md](foundation-release.md#wp-002-import-engine-as-fpengine-uv-project-qt-free-tests-ported-posix-clean) | 850–1045 | 10 |
| WP-101 | Normalise cmap after subsetting | [engine-correctness.md](engine-correctness.md#wp-101-normalise-cmap-after-subsetting) | 155–261 | 8 |
| WP-102 | Drop non-kept and Apple bitmap tables before subsetting | [engine-correctness.md](engine-correctness.md#wp-102-drop-non-kept-and-apple-bitmap-tables-before-subsetting) | 262–323 | 6 |
| WP-103 | Synthesize a missing OS/2 table | [engine-correctness.md](engine-correctness.md#wp-103-synthesize-a-missing-os2-table) | 324–403 | 7 |
| WP-104 | Feature closure: drop `aalt` and lookup-sharing features; disable the HarfBuzz repacker | [engine-correctness.md](engine-correctness.md#wp-104-feature-closure-drop-aalt-and-lookup-sharing-features-disable-the-harfbuzz-repacker) | 404–541 | 7 |
| WP-105 | Robust synthetic bold (per-glyph fallback, report) | [engine-correctness.md](engine-correctness.md#wp-105-robust-synthetic-bold-per-glyph-fallback-report) | 542–624 | 7 |
| WP-106 | Face metadata v2 (script tags, AAT flags, hidden, PS name, licence fields, sanity) | [engine-metadata.md](engine-metadata.md#wp-106-face-metadata-v2-script-tags-aat-flags-hidden-ps-name-licence-fields-sanity) | 202–367 | 14 |
| WP-107 | AAT guard in forge (per-script shaping check, errors and warnings) | [engine-metadata.md](engine-metadata.md#wp-107-aat-guard-in-forge-per-script-shaping-check-errors-and-warnings) | 368–643 | 11 |
| WP-108 | Name reading: Mac Roman English, Mac CJK encodings | [engine-metadata.md](engine-metadata.md#wp-108-name-reading-mac-roman-english-mac-cjk-encodings) | 644–754 | 7 |
| WP-109 | Unique, stable PostScript names; version and unique-ID fields; forged-font marker | [engine-metadata.md](engine-metadata.md#wp-109-unique-stable-postscript-names-version-and-unique-id-fields-forged-font-marker) | 755–938 | 10 |
| WP-110 | Licence policy: fsType propagation, licence classes, report notes | [engine-metadata.md](engine-metadata.md#wp-110-licence-policy-fstype-propagation-licence-classes-report-notes) | 939–1131 | 8 |
| WP-111 | Real-Apple-font regression suite (scenario matrix) | [engine-correctness.md](engine-correctness.md#wp-111-real-apple-font-regression-suite-scenario-matrix) | 625–916 | 12 |
| WP-201 | Protocol v1 (JSON Schemas) + `python -m fpengine` (`hello`, `scan`, `forge`) | [helper.md](helper.md#wp-201-protocol-v1-json-schemas--python--m-fpengine-hello-scan-forge) | 203–658 | 28 |
| WP-202 | Conformance fixture generator + fixtures | [helper.md](helper.md#wp-202-conformance-fixture-generator--fixtures) | 659–943 | 15 |
| WP-203 | Embedded runtime build (`scripts/build-helper-runtime.sh`) | [helper.md](helper.md#wp-203-embedded-runtime-build-scriptsbuild-helper-runtimesh) | 944–1076 | 10 |
| WP-204 | `FPEngineClient` (process, JSON Lines, cancel, timeouts) | [helper.md](helper.md#wp-204-fpengineclient-process-json-lines-cancel-timeouts) | 1077–1386 | 20 |
| WP-205 | `fpctl` headless CLI + example recipes | [helper.md](helper.md#wp-205-fpctl-headless-cli--example-recipes) | 1387–1694 | 9 |
| WP-301 | `FPCore` foundations: `FaceRecord`, `FaceKey`, scripts and language groups, samples, text utils | [core.md](core.md#wp-301-fpcore-foundations-facerecord-facekey-scripts-and-language-groups-samples-text-utils) | 159–536 | 19 |
| WP-302 | `Mix` + planner `source_of` port, missing characters | [core.md](core.md#wp-302-mix--planner-source_of-port-missing-characters) | 537–654 | 11 |
| WP-303 | `Recipe` (port of `ForgeModel`): operations, rules, adjustments, ForgeSpec, glyph estimate | [core.md](core.md#wp-303-recipe-port-of-forgemodel-operations-rules-adjustments-forgespec-glyph-estimate) | 655–948 | 22 |
| WP-304 | Smart: suggestions, naming conformance + PostScript-name port, nearest real weight | [core.md](core.md#wp-304-smart-suggestions-naming-conformance--postscript-name-port-nearest-real-weight) | 949–1158 | 16 |
| WP-305 | Persistence: `.fontrecipe`, settings, portable identity, Windows import + equivalence table | [core.md](core.md#wp-305-persistence-fontrecipe-settings-portable-identity-windows-import--equivalence-table) | 1159–1558 | 20 |
| WP-401 | Font discovery + catalog store (CoreText, folders, cache, dedupe, hidden, change observation) | [mac-services.md](mac-services.md#wp-401-font-discovery--catalog-store-coretext-folders-cache-dedupe-hidden-change-observation) | 439–868 | 26 |
| WP-402 | Font rendering service (URL descriptors, LastResort cascade, opsz pin, built font) | [mac-services.md](mac-services.md#wp-402-font-rendering-service-url-descriptors-lastresort-cascade-opsz-pin-built-font) | 869–1080 | 16 |
| WP-403 | `FontInstaller` + CoreText conflict checker | [mac-services.md](mac-services.md#wp-403-fontinstaller--coretext-conflict-checker) | 1081–1519 | 23 |
| WP-404 | Downloadable fonts (Font Book hand-off; optional curated download) | [mac-services.md](mac-services.md#wp-404-downloadable-fonts-font-book-hand-off-optional-curated-download) | 1520–1687 | 12 |
| WP-501 | App shell: XcodeGen target, `AppModel`, window, menu bar, Settings, About/Acknowledgements | [ui-shell.md](ui-shell.md#wp-501-app-shell-xcodegen-target-appmodel-window-menu-bar-settings-aboutacknowledgements) | 624–1153 | 40 (6) |
| WP-502 | Recipe column (font cards, main font, size/weight, add for language, replace/remove, colour by font) | [ui-editing.md](ui-editing.md#wp-502-recipe-column-font-cards-main-font-sizeweight-add-for-language-replaceremove-colour-by-font) | 299–468 | 27 (2) |
| WP-503 | Font picker | [ui-editing.md](ui-editing.md#wp-503-font-picker) | 469–809 | 36 (4) |
| WP-504 | Preview pane (editable text, runs, missing characters, built-font mode, zoom) | [ui-editing.md](ui-editing.md#wp-504-preview-pane-editable-text-runs-missing-characters-built-font-mode-zoom) | 810–1085 | 35 (6) |
| WP-505 | Build & install flow (name, Save a Copy…, Install/Update, progress/cancel, report, conflicts, Finder) | [ui-shell.md](ui-shell.md#wp-505-build--install-flow-name-save-a-copy-installupdate-progresscancel-report-conflicts-finder) | 1154–1691 | 37 (6) |
| WP-506 | Advanced inspector (scripts table, line spacing, defaults, last report) | [ui-shell.md](ui-shell.md#wp-506-advanced-inspector-scripts-table-line-spacing-defaults-last-report) | 1692–1860 | 15 (2) |
| WP-507 | Accessibility, String Catalog, Increase Contrast, keyboard audit | [ui-shell.md](ui-shell.md#wp-507-accessibility-string-catalog-increase-contrast-keyboard-audit) | 1861–2062 | 15 (5) |
| WP-508 | Simplified Chinese localisation and the language setting | [localisation.md](localisation.md#wp-508-simplified-chinese-localisation-and-the-language-setting) | 155–431 | 18 (4) |
| WP-601 | Bundle, sign, notarize, DMG, `--self-test`, SDK check, release workflow | [foundation-release.md](foundation-release.md#wp-601-bundle-sign-notarize-dmg---self-test-sdk-check-release-workflow) | 1046–1462 | 19 (3) |
| WP-602 | User docs, licences/acknowledgements, Windows-migration notes | [foundation-release.md](foundation-release.md#wp-602-user-docs-licencesacknowledgements-windows-migration-notes) | 1463–1619 | 9 (2) |
| WP-701 | Parity sign-off and cutover (remove `reference/`, freeze fixtures, tag v1.0.0) | [foundation-release.md](foundation-release.md#wp-701-parity-sign-off-and-cutover-remove-reference-freeze-fixtures-tag-v100) | 1620–1705 | 10 (1) |

Also: [contracts.md](contracts.md) (normative cross-spec contracts), [traceability.md](traceability.md) (finding → WP → AC matrix, parity coverage), [_template.md](_template.md) (WP section template), [../decisions.md](../decisions.md) (product defaults you can override).
