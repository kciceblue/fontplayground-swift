# Traceability: audit findings, parity checklist and acceptance criteria

> Scope: all 37 WPs (001–701) · Env: n/a (reference document; it adds no work) · Architecture refs: docs/architecture.md §1, §8 · Sources: docs/research/macos-audit.md (129 findings), docs/plan.md §3 and §6, docs/specs/*.md

## Context

The audit (`docs/research/macos-audit.md`) lists 129 findings: 119 auditor and verifier findings (`CATALOG-*`, `ENGINE-*`, `INSTALL-*`, `UI-*`, `TOOLING-*`, `NATIVE-*`; `-M` ids were found by a verifier) and 10 critic findings (`CRIT-*`). The plan (`docs/plan.md` §3) assigns findings to WPs, and each WP section in `docs/specs/` lists the ones it closes, with ACs that prove each fix.

This file answers three questions for the maintainer and for WP-701:

1. For **every** finding: what the verified severity is, and which ACs close it. If no AC closes it, the file says why (backlog, won't fix, obsolete in the native app, or informational).
2. For every item of the parity checklist (`docs/plan.md` §6): which ACs prove it.
3. How many WPs and ACs each spec has, and how many ACs are automated or manual.

**Maintenance rule.** This file is derived from the specs. If a PR renames, renumbers or removes an AC, or changes which WP closes a finding, it updates the matching rows here in the same PR. WP-701 (AC-701-1) uses §3 of this file as its evidence index.

## Shared definitions

**Dispositions**

| Disposition | Meaning |
|---|---|
| **Closed** | One or more ACs prove the fix. The first AC listed is the regression test named after the finding (AGENTS.md "Definition of done"), where one exists. |
| **Obsolete** | The problem lives in Qt/PySide6/PyInstaller code that is not ported. The row names the ACs that cover the underlying user need in the native app, if there is one. |
| **Backlog B-n** | Deferred past v1. The id refers to `docs/plan.md` §3 "Backlog". |
| **Not scheduled** | Deferred past v1, but `docs/plan.md` has no backlog id for it yet. A proposed id is given (see §5). |
| **Won't fix** | A deliberate decision, with the reason. |
| **Informational** | An architecture option or a recommendation, not a defect. The row says what was decided. |

**Columns.** *Sev* is the **verified** severity from the audit tables (blocker > major > minor > polish). *Plan WP* is the owner in `docs/plan.md` §3 ("—" means the plan names no owner). *Closing ACs* lists AC ids. Named regression tests are in backticks. `[F]` after AC-111-10 means the parametrised case `test_engine_finding[F]`.

**Counts by verified severity:** 5 blockers, 27 majors, 68 minors, 29 polish = 129.

---

## 1. Finding → WP → AC matrix

### 1.1 Catalog (`CATALOG-*`)

| Finding | Sev | Plan WP | Disposition | Closing ACs |
|---|---|---|---|---|
| CATALOG-1 | blocker | 401 | Closed | AC-401-1 `catalog1CoreTextFilesOutsideTheFoldersAreDiscovered`; AC-401-2 (origin of AssetsV2 / PrivateFrameworks files); AC-401-23 (d) real Mac: PingFang present; AC-401-25 (manual harness, M3 exit) |
| CATALOG-2 | blocker | 106, 401, 503 | Closed | AC-106-5 `test_catalog_2_dot_faces_are_hidden`; AC-106-6 `test_catalog_2_suspicious_coverage_rule`; AC-401-10 `catalog2HiddenFacesAreDroppedAndCounted`; AC-303-3 `catalog2SuspiciousFaceNeverTakesAGroup`; AC-304-3 `catalog2HiddenAndSuspiciousFacesAreNeverSuggested`; AC-503-18 `catalog2SuspiciousAndHiddenFacesAreNeverSuggested`; AC-503-17; AC-111-5 (real `.LastResort` is suspicious) |
| CATALOG-3 | major | 108 | Closed | AC-108-1 `test_catalog_3_mac_roman_english_beats_other_windows_languages`; AC-108-3; AC-108-4 (EPSON cases still pass) |
| CATALOG-M1 | major | 401 | Closed | AC-401-11 `catalogM1DedupeTieBreak`; AC-401-23 (d) "AssetsV2 kept over PrivateFrameworks" |
| CATALOG-4 | minor | 402 | Closed | AC-402-4 `catalog4FileIsDrawnNotTheSameNamedInstalledFont`; AC-504-13 (built-font mode) |
| CATALOG-5 | minor | 404 | Closed | AC-404-1 `catalog5OpensFontBookByBundleIdentifier`; AC-404-2; AC-404-3 (manual); AC-404-5 … AC-404-10 (curated download, enumeration only); no-name-lookup guards AC-402-14, AC-404-10, AC-111-9; AC-501-24 (Get More Fonts… opens Font Book) |
| CATALOG-6 | minor | 401 | Closed | AC-401-18 `catalog6RefreshesOnceAfterDebounce` (incl. real process-scope registration); AC-401-19 (previews register nothing); AC-401-20 (own install) |
| CATALOG-7 | minor | 401, 305 | Closed | AC-401-8 `catalog7Crit6PruneVanishedPathsAfterCompleteRefreshOnly`; AC-305-3 `catalog7DocumentMaterialResolvesByPostScriptNameAfterPathChange`; AC-305-14; AC-303-10; AC-501-15 `catalog7MovedAssetKeepsTheMaterial`; AC-501-16 |
| CATALOG-M2 | minor | 108 | Closed | AC-108-5 `test_catalog_m2_mac_chinese_korean_local_names`; AC-108-6; AC-403-1 (the Swift name reader decodes (1, 25, 33) GB2312) |
| CATALOG-8 | polish | 106 | Closed | AC-106-4 `test_catalog_8_bhed_bitmap_font_is_unsupported_not_unreadable` |
| CATALOG-9 | polish | 401 | Closed | AC-401-4 `catalog9DedupeByFileIdentity` |
| CATALOG-10 | polish | 401 | Closed | AC-401-5 `catalog10UnsupportedFormatsAreCountedNotFailed` (`.dfont` and Type 1 are counted as skipped, never reported unreadable; reading them is not planned) |
| CATALOG-11 | polish | 304, 503 | Closed | AC-304-5 `catalog11PlatformDefaultWinsCoverageTies`; AC-304-6; AC-503-19 `catalog11PlatformFontBreaksTiesAndIsTheInitialRow`; AC-503-20 `catalog11ChineseDefaultIsPingFang` |
| CATALOG-12 | polish | — | Not scheduled (proposed B-10) | Named instances as separate faces are out of scope (mac-services.md WP-401 Scope/Out; the verifier calls it optional). The user can still pick any weight of a variable font: AC-402-7 (preview), AC-002-1 (ported `test_variable_instanced_at_weight`) |
| CATALOG-M3 | polish | 401 | Closed | AC-401-9 `catalogM3CacheLivesInCachesAndIsWrittenAtomically` |

### 1.2 Engine (`ENGINE-*`)

| Finding | Sev | Plan WP | Disposition | Closing ACs |
|---|---|---|---|---|
| ENGINE-1 | blocker | 101, 111 | Closed | AC-101-1 `test_engine_1_mac_unicode_cmap`; AC-101-2; AC-101-4, AC-101-5 (format 4 overflow, N-1); AC-111-10 [ENGINE-1] (AF-01, -09, -10, -21, -22); AC-111-4 (AF-20 Hangul beyond format 4) |
| ENGINE-2 | blocker | 106, 107, 111 | Closed | AC-106-7 `test_engine_2_script_tags_and_aat_flags`; AC-107-3 `test_engine_2_planner_leaves_unshaped_arabic_to_an_opentype_font`; AC-107-4 `test_engine_2_rule_to_aat_arabic_is_refused`; AC-107-5; AC-111-10 [ENGINE-2] (AF-14, -17, -18 refused); AC-111-4 (AF-15, -16 shape like the source); AC-111-5. Swift mirror of the rule: AC-301-18, AC-302-11, AC-303-14, AC-304-4, AC-304-10, AC-502-20, AC-503-21, AC-506-9 |
| ENGINE-3 | major | 104, 111 | Closed | AC-104-2 `test_engine_3_locl_alias_and_aalt_dropped`; AC-104-5 `test_engine_3_hb_repacker_disabled`; AC-104-1, AC-104-3, AC-104-4, AC-104-6; AC-111-3 (glyph-estimate calibration); AC-111-10 [ENGINE-3] |
| ENGINE-4 | major | 105, 304, 111 | Closed | AC-105-1 `test_engine_4_pathops_failure_keeps_glyph`; AC-105-2; AC-105-3; AC-105-5 `test_engine_4_bold_size_doubled_warning`; AC-111-10 [ENGINE-4] (AF-12, AF-13); real heavier face instead of synthetic bold: AC-304-7 `engine4RealSemiboldFaceReplacesSyntheticBold`, AC-304-8, AC-502-25, AC-506-13 |
| ENGINE-5 | major | 110, 111 | Closed | AC-110-1 `test_engine_5_output_fstype_is_most_restrictive`; AC-110-2; AC-110-3 `test_engine_5_licence_classes`; AC-110-6; AC-111-10 [ENGINE-5]; shown to the user: AC-505-21, AC-501-28, AC-502-12 |
| ENGINE-M1 | major | 103, 111 | Closed | AC-103-1 `test_engine_m1_missing_os2_as_main`; AC-103-2 `test_engine_m1_missing_os2_as_secondary`; AC-103-5; AC-103-6; AC-111-10 [ENGINE-M1]; AC-111-5 (Courier `has_os2` false) |
| ENGINE-M3 | major | 109, 111 | Closed | AC-109-3 `test_engine_m3_ps_name_never_equals_the_plain_system_name`; AC-109-1; AC-111-10 [ENGINE-M3] (AF-30, AF-31); AC-304-16 (Swift port); AC-403-5 `postscriptNameOfAnotherFontBlocks` |
| ENGINE-6 | minor | — (B-1) | Backlog B-1 | Optical size and `trak` fidelity are not in v1. Mitigations with ACs: the preview pins opsz to what the engine instantiates, so preview and result agree (AC-402-6, NATIVE-M3); `trak` loss is reported (AC-107-8 `aat_tracking_dropped`); AF-03/AF-13 prove only that variable SF instances (AC-111-2) |
| ENGINE-7 | minor | 107, 111 | Closed | AC-107-7 `test_engine_7_aat_kerning_loss_is_reported`; AC-111-4 (AF-22 Helvetica Neue kerning width); AC-111-10 [ENGINE-7] |
| ENGINE-8 | minor | 303, 111 | Closed | AC-303-8 `engine8ForgeSpecCarriesExpectForStaleDetection`; AC-303-10 `engine8MovedAssetPathIsReresolvedByPostScriptName`; AC-303-11 `engine8VanishedMaterialIsKeptAndReported`; AC-201-10 (`stale_material`); AC-204-16; AC-305-3; AC-111-10 [ENGINE-8] (AF-29) |
| ENGINE-9 | minor | 201, 111 | Closed | AC-201-17 `test_engine_9_cancel_removes_temp_and_partial_output`; AC-201-16; AC-201-20 (orphan watchdog); AC-111-6 (real cancel); AC-111-2 (per-process RSS budgets); AC-204-9; AC-505-7 |
| ENGINE-12 | minor | 102, 111 | Closed | AC-102-2 `test_engine_12_bitmap_strikes_reported`; AC-201-11 (colour font → `unsupported_font`); AC-111-10 [ENGINE-12] (AF-26, AF-27) |
| ENGINE-M2 | minor | 102, 111 | Closed | AC-102-1 `test_engine_m2_malformed_apple_bitmap_tables`; AC-102-3; AC-111-10 [ENGINE-M2] |
| ENGINE-M4 | minor | 108, 111 | Closed | AC-108-2 `test_engine_m4_default_names_are_english`; AC-111-5 (Geeza Pro family is English) |
| ENGINE-10 | polish | 106, 111 | Closed | AC-106-5 `test_engine_10_dot_families_are_hidden`; AC-111-5 (SFNS hidden); AC-401-10 |
| ENGINE-11 | polish | — (B-2) | Backlog B-2 | `vhea`/`vmtx`/`VORG`/`BASE` are dropped in v1, as in the original. No AC |

### 1.3 Install (`INSTALL-*`)

| Finding | Sev | Plan WP | Disposition | Closing ACs |
|---|---|---|---|---|
| INSTALL-1 | blocker | 403 | Closed | AC-403-6 `install1Install9Install12RoundTripInTemporaryFolder`; AC-505-8 (Install from the app); AC-505-M1 (manual, real build); AC-403-21 (manual, real `~/Library/Fonts`, maintainer only) |
| INSTALL-2 | major | 403 | Closed | AC-403-15 `install2Install13EnglishTextMatchesSpec`; the `FontInstalling` seam (contracts.md §7) is driven through `ShellFakeInstaller` by AC-505-8 … AC-505-16; AC-505-12 (installer errors fail plainly) |
| INSTALL-3 | major | 403 | Closed | AC-403-4 `install3Install4Tooling7SystemNamesAreFoundWithoutNameMatching`; AC-403-5 (`systemFontFamilyBlocks`, `localFolderBlocks`); AC-505-14 |
| INSTALL-4 | major | 403 | Closed | AC-403-4; AC-403-5 (`activatedElsewhereBlocks`, `localizedFamilyBlocks`, `postscriptNameOfAnotherFontBlocks`); AC-403-20 (index budget on the real Mac) |
| INSTALL-5 | major | 109, 403 | Closed | AC-109-2 `test_install_5_postscript_names_are_unique`; AC-109-4 `test_install_5_cjk_families_get_distinct_ps_names`; AC-403-5 `install5PostScriptNameOfYourOtherFontBlocks`; AC-403-9 (one file per PS name after Update) |
| INSTALL-7 | major | 403 | Closed | AC-403-19 `install6Install7NoRegistrationInSourcesAndProcessScopeOnlyInTests`; AC-403-6 (copy into the fonts folder); AC-403-21 (manual activation latency) |
| INSTALL-M1 | major | 403 | Closed | AC-403-8 `installM1NeverTouchesFilesThatAreNotOurs`; AC-403-5 `userNonForgedFontBlocks` |
| INSTALL-6 | minor | 403 | Closed | AC-401-20 `install6IncrementalUpdateAfterOwnInstall`; AC-403-19; AC-505-8, AC-505-11, AC-505-15 (`noteInstalled`/`noteRemoved`) |
| INSTALL-8 | minor | 403 | Closed | AC-403-9 `install8Install9Tooling2UpdateWritesANewFileThenTrashesTheOld`; AC-403-11 |
| INSTALL-9 | minor | 403 | Closed | AC-403-6; AC-403-9; AC-505-15 ("it's in the Trash") |
| INSTALL-10 | minor | 403 | Closed | AC-403-5 (`install10ChangedBytesAreNotOurs`, `install10OursDetectedFromManifestAfterRestart`, `userForgedButNotOursBlocks`); AC-403-2 (forged marker); AC-403-13 (manifest) |
| INSTALL-12 | minor | 403 | Closed | AC-403-6 (temporary folder, process scope); AC-403-19 (tests register at process scope only) |
| INSTALL-14 | minor | 403 | Closed | AC-403-16 `install14ReadOnlyFontsFolderFailsPlainly`; unsandboxed Developer ID build: AC-501-2 (no entitlements), AC-601-3, AC-601-16. The pyobjc part is obsolete (Swift) |
| INSTALL-M2 | minor | 403 | Closed | AC-403-10 `installM2OldCopySurvivesAFailedPlacement` |
| INSTALL-M3 | minor | 403 | Closed | AC-403-7 `installM3ValidatesWithCoreTextFirst` |
| INSTALL-11 | polish | 403 | Closed | AC-403-18 `install11Tooling7UserFolderIsRecognisedThroughSymlinks` |
| INSTALL-13 | polish | 403, 505 | Closed | AC-505-14 `install13ConflictTextsUseMacOSWording`; AC-505-16 `install13ShowInFinderRevealsTheFile`; AC-403-15; AC-505-M3 |

### 1.4 UI (`UI-*`)

| Finding | Sev | Plan WP | Disposition | Closing ACs |
|---|---|---|---|---|
| UI-1 | major | 503 | Closed | AC-503-17 `ui1HiddenFacesAreNeverListed`; AC-503-18; AC-401-10; AC-304-3; AC-503-M1 |
| UI-2 | major | 501 | Closed | AC-501-18 `ui2MenuBarHasEveryCommand`; AC-501-19; AC-501-M3 |
| UI-3 | major | 501 | Closed | AC-501-2 `ui3InfoPlistNamesTheApp`; AC-501-1; AC-001-15; AC-601-6 (icon); AC-501-M3 |
| UI-5 | major | — | Obsolete | Qt stylesheets are not ported. The underlying need (native popup buttons and steppers) is covered by AC-502-23 (stock control styles only; no custom `ButtonStyle`/`MenuStyle`/`PickerStyle`) and AC-502-M1 (screenshots) |
| UI-M1 | major | 108 | Closed | AC-108-1 `test_ui_m1_english_and_native_names_are_both_in_the_record`; AC-503-3 (search by English or native name) |
| UI-M2 | major | 107 | Closed | AC-107-8 `test_ui_m2_morx_loss_is_reported`; AC-107-6; the UI says so: AC-502-20, AC-503-21, AC-304-4 |
| UI-4 | minor | 501 | Closed | AC-501-20 `ui4InitialFrameFitsTheVisibleScreen`; AC-501-M1 |
| UI-6 | minor | 507 | Closed | AC-507-3 `ui6NoPCKeyNamesInStrings`; AC-507-7; AC-501-18; AC-503-8 (Mac key bindings in the picker); AC-507-M2 |
| UI-7 | minor | — | Obsolete | The Qt pt/px mix does not exist in SwiftUI/AppKit; text uses system text styles (ui-editing.md Context). Visual check is part of the screenshots of AC-502-M1 and AC-503-M1 |
| UI-8 | minor | — | Obsolete | Native controls follow the system accent and window colours; the only custom palette is colour-by-font. Underlying need: AC-503-22 (native selection highlight), AC-507-6 (dynamic colours per appearance), AC-501-4 (Appearance) |
| UI-10 | minor | 505 | Closed | AC-501-22 `ui10QuitWhileBuildingAsksWithVerbButtons`; AC-505-14 `ui10ConflictPromptsUseVerbButtons`; AC-505-M3; AC-505-M5 |
| UI-11 | minor | 501 | Closed | AC-501-24 `ui11ShowSettingsFolderRevealsIt`; AC-505-16; AC-501-M4 |
| UI-12 | minor | 602 | Closed | AC-602-2 `test_ui_12_no_windows_wording_in_user_docs`, `test_ui_12_readme_commands_exist_in_the_app` |
| UI-13 | minor | 507 | Closed | AC-507-5 `ui13LabelsForCustomControls`; AC-507-4 (lint: no unlabelled images/icon buttons); AC-502-22; AC-503-29; AC-504-28; AC-507-M1 |
| UI-M3 | minor | 505 | Closed | AC-505-4 `uiM3NamesThatMacOSWouldHideAreRejected`, `uiM3SuggestedFileNameNeverStartsWithADot`; AC-303-6; AC-109-8; AC-304-11; AC-403-5 `hiddenNameBlocks` |
| UI-M4 | minor | 507 | Closed | AC-507-6 `uiM4PaletteMeetsTheContrastRules`, `uiM4IncreaseContrastSwitchesThePalette`; AC-501-33; AC-507-M3 |
| UI-M7 | minor | 505 | Closed | AC-505-20 `uiM7OpenInFontBookAfterSaving`; AC-505-M2 |
| UI-9 | polish | 505 | Closed | AC-505-17 `ui9SaveACopyUsesASheetWithTTF`; AC-505-M2 |
| UI-14 | polish | 503 | Closed | AC-503-22 `ui14NativeScrollersAndSelection` |
| UI-15 | polish | 501, 506 | Closed | AC-501-23 `ui15ClosingTheWindowQuitsAndAsksWhileBuilding`; AC-501-26 `ui15DroppingFoldersAddsThem`; AC-506-10 `ui15AdvancedIsAnInspector`; AC-501-M6; AC-506-M2. Dropping single font files only gives a notice (B-5, see CRIT-4) |
| UI-16 | polish | — | Closed (by WP-602) | README is rewritten with macOS examples: AC-602-1, AC-602-2; Windows → macOS equivalents: AC-305-13, AC-602-3 |
| UI-17 | polish | — | Closed (verified, no change needed; release check) | AC-507-M5 (IME release check); AC-504-17 (marked text in the preview); AC-503-M2; AC-504-M2 |
| UI-M5 | polish | — | Closed (by WP-507) | AC-507-4 (lint: no cursor code); AC-507-M4 |
| UI-M6 | polish | 504 | Closed | AC-504-23 `uiM6PinchScrollAndKeysZoom`; AC-501-5 (zoom seams); AC-504-M3 |
| UI-M8 | polish | 505 | Closed | AC-505-23 `uiM8BackgroundBuildBouncesTheDock`; AC-501-33; AC-505-M4 |

### 1.5 Tooling (`TOOLING-*`)

| Finding | Sev | Plan WP | Disposition | Closing ACs |
|---|---|---|---|---|
| TOOLING-1 | major | 601 | Closed | AC-601-3 `test_tooling_1_sign_adhoc.sh`; AC-601-15 `test_tooling_1_release_order`; AC-601-14 (ad hoc DMG dry run); AC-601-16 (notarized, release credential; may be deferred to AC-701-8); AC-601-M3; AC-701-8; AC-701-M1 |
| TOOLING-7 | major | 403 | Closed | AC-403-4 `install3Install4Tooling7SystemNamesAreFoundWithoutNameMatching`; AC-403-18 `install11Tooling7UserFolderIsRecognisedThroughSymlinks` |
| TOOLING-M1 | major | 001 | Closed | AC-001-7 `test_tooling_m1_setup_explains_missing_uv`, `test_tooling_m1_python_version_is_pinned`; AC-001-2 (clean clone `make setup`) |
| TOOLING-M2 | major | 203 | Closed | AC-203-3 (check `tooling_m2_non_editable`) |
| TOOLING-2 | minor | 403 | Closed | AC-403-9 `install8Install9Tooling2UpdateWritesANewFileThenTrashesTheOld` (the old inode is never written); atomic writes elsewhere: AC-201-22, AC-305-8, AC-401-9, AC-403-13, AC-501-12 |
| TOOLING-3 | minor | 002 | Closed | AC-002-4 `test_tooling_3_engine_sources_are_posix_clean` |
| TOOLING-4 | minor | 001 | Closed | `test_tooling_4_ci_runs_the_macos_job` (ADR-0014 replaced AC-001-11's Linux + macOS check); AC-001-3 |
| TOOLING-5 | minor | — | Obsolete | No Qt in the new app. Guards: AC-201-25 (the helper imports no PySide6), AC-002-7 (engine is Qt-free), AC-001-9 (engine dependencies are exactly fontTools and skia-pathops) |
| TOOLING-6 | minor | 001 | Closed | AC-001-10 `test_tooling_6_dev_docs_have_no_windows_only_commands` |
| TOOLING-8 | minor | 601 | Closed | AC-601-5 `test_tooling_8_single_version`, `test_tooling_8_info_plist_release_keys`; AC-001-15; AC-701-6 |
| TOOLING-9 | minor | 601 | Closed | AC-601-6 `test_tooling_9_icon_composer_document`; AC-601-M1 |
| TOOLING-10 | minor | 601 | Closed (arm64 only, by decision) | AC-601-7 `test_tooling_10_arm64_only_build_settings`. universal2 is backlog B-3 |
| TOOLING-11 | minor | 601, 602 | Closed | AC-601-8 `test_tooling_11_licence_collection_is_wired`; AC-602-5 `test_tooling_11_static_licence_texts_exist`; AC-602-6; AC-203-5 (check `licences`); AC-501-27 |
| TOOLING-12 | minor | — | Informational (superseded by ADR-0004) | PyInstaller is not used: the helper is an embedded python-build-standalone runtime. The underlying need (a frozen, non-editable, self-tested runtime) is AC-203-1 … AC-203-6 and AC-601-9 |
| TOOLING-13 | minor | — | Closed (by WP-601) | Developer ID, notarized DMG, no App Store: AC-601-14, AC-601-16, AC-601-M3. Homebrew cask is backlog B-9 |
| TOOLING-14 | minor | 601 | Closed | AC-601-11 `tooling14CancelMustEndTheHelperWithinThreeSeconds`; AC-601-13 (os_log); AC-601-M2; AC-501-22; AC-505-30 |
| TOOLING-15 | minor | — | Obsolete (strings not ported) | Underlying need: AC-507-3 (no PC key names; "⌘Z", "Return"), AC-403-15 (no "Windows" in installer text), AC-505-1 (macOS idle text), AC-602-2 |
| TOOLING-16 | minor | — | Obsolete (Qt offscreen tests) | The macOS behaviour is asserted by the new macOS suites: AC-403-6 (install round-trip, temporary folder, process scope), AC-402-3 … AC-402-13 (CoreText rendering), AC-111-1 (real Apple fonts), AC-001-3 (macOS CI job) |
| TOOLING-17 | minor | 001 | Closed | AC-001-9 `test_tooling_17_engine_pyproject_hygiene` |
| TOOLING-18 | minor | 002 | Closed | AC-002-5 `test_tooling_18_read_faces_keeps_the_given_path`, `test_tooling_18_engine_has_no_discovery_or_cache_io`; AC-401-4; AC-401-8; AC-106-4 |
| TOOLING-19 | minor | — | Obsolete | Qt's 72 vs 96 dpi mismatch does not exist in AppKit. No AC |
| TOOLING-M3 | minor | — | Closed (by WP-401, WP-501) | AC-401-21 (`.noAccess` counted, TOOLING-M3); AC-501-2 (usage descriptions in Info.plist); AC-501-34 (folder issues shown); AC-401-3 (never walks into `~/Library/Containers`) |
| TOOLING-20 | polish | — | Closed (by WP-501, WP-505) | AC-505-16 (reveal the file itself); AC-501-18; AC-501-M3; AC-501-M5 |
| TOOLING-21 | polish | — | Won't fix (done outside the WPs) | This repository is the migration; `.gitattributes` is specified in WP-001's design and checked by review. No AC |
| TOOLING-22 | polish | — | Closed (leading dot) / Won't fix (vendor words) | A default file name never starts with a dot: AC-304-11, AC-505-4. Adding "apple" to the vendor words is not done: the reference naming is kept and locked by conformance fixtures (AC-202-7, AC-304-11) |
| TOOLING-23 | polish | 002 | Closed | AC-002-6 `test_tooling_23_forge_temp_files_live_in_tmpdir` |
| TOOLING-M4 | polish | — | Obsolete | No `QFontDatabase`. Fonts are created from absolute file URLs (AC-402-9), and the helper rejects relative paths (AC-201-12) |
| TOOLING-M5 | polish | — | Closed (by WP-401, 305, 403, 501) | AC-401-9 (cache); AC-305-8 (`AtomicFile`); AC-403-13 (manifest); AC-501-12 (autosave) |

### 1.6 Architecture options (`NATIVE-*`)

| Finding | Sev | Plan WP | Disposition | Closing ACs |
|---|---|---|---|---|
| NATIVE-6 | major | 106 | Closed | AC-106-7 `test_native_6_aat_only_face_flags`; AC-107-3; AC-107-4; AC-107-8; AC-111-10 [ENGINE-2] |
| NATIVE-9 | major | — | Closed (by WP-401, WP-108) | AC-401-1 (CoreText enumeration); AC-401-10 (hidden faces); AC-401-11 (dedupe by PostScript name); AC-108-1 (English names); AC-401-23 (real Mac) |
| NATIVE-M1 | major | 107, 402, 504 | Closed | AC-107-6 `test_native_m1_unshaped_arabic_never_reaches_the_output`; AC-402-5 `nativeM1PreviewShapesExactlyLikeCoreText`; AC-504-14 `nativeM1RunsAreCoreTextWithoutFallback`; AC-504-15 `nativeM1BuiltFontMatchesCoreTextShaping`; AC-402-3 |
| NATIVE-1 | minor | — | Informational | The layer map is realised by architecture §2. Guards: AC-002-7 (engine Qt-free), AC-301-14 (FPCore imports Foundation only), AC-001-13 (`test_kit_is_foundation_only`) |
| NATIVE-2 | minor | — | Won't fix (option not chosen) | ADR-0001 chooses the native shell with the Python engine as a helper |
| NATIVE-3 | minor | 201 | Closed (chosen option) | AC-201-9 `test_native_3_forge_round_trip`; AC-204-16; AC-205-6 |
| NATIVE-4 | minor | — | Won't fix (option not chosen) | ADR-0001 keeps the fontTools engine |
| NATIVE-5 | minor | — | Won't fix (option not chosen) | ADR-0001; no Rust core |
| NATIVE-7 | minor | 201, 204 | Closed | AC-201-16 `test_native_7_sigterm_mid_stage_exits_143_within_1s`; AC-204-9 `native7CancelSendsSigterm`; AC-204-10 `native7EscalatesToSigkillAndCleansLeftovers`; AC-111-6; AC-505-7 |
| NATIVE-8 | minor | — | Closed (by WP-501, WP-601) | No sandbox, no entitlements: AC-501-2, AC-001-15; Developer ID and notarization: AC-601-3, AC-601-16; install copies into the fonts folder: AC-403-6 |
| NATIVE-11 | minor | — | Informational (superseded by ADR-0001) | The phased Qt release is skipped. Its ordering (engine correctness, then the process boundary, then the native shell) is the wave order of docs/plan.md §4 |
| NATIVE-M2 | minor | — | Closed (by WP-402) | AC-402-2 `nativeM2CollectionFacesMapByPostScriptName`; AC-401-11 (faces keyed by PostScript name) |
| NATIVE-M3 | minor | 402 | Closed | AC-402-6 `nativeM3OpticalSizeIsPinnedToTheEngineDefault` |
| NATIVE-M4 | minor | 203 | Closed | AC-203-2 (checks `native_m4_hello`, `native_m4_pipeline`) |
| NATIVE-M5 | minor | — | Obsolete | No PySide6 dependency (see TOOLING-5) |
| NATIVE-M6 | minor | — | Won't fix (non-goal) | iPad and sandboxed App Store builds are v1 non-goals (architecture §1). AC-501-2 asserts the app has no entitlements |
| NATIVE-10 | polish | — (B-6) | Backlog B-6 | No AC |
| NATIVE-M7 | polish | — | Not scheduled (proposed B-11) | Session-scope "try in other apps" is out of WP-402's scope (mac-services.md). No AC |

### 1.7 Completeness critic (`CRIT-*`)

| Finding | Sev | Plan WP | Disposition | Closing ACs |
|---|---|---|---|---|
| CRIT-1 | major | 601 | Closed | AC-601-4 `test_crit_1_check_sdk.sh`; AC-601-11 `crit1NoCompatibilityKeyInInfoPlist`; AC-601-15 `test_crit_1_release_runs_sdk_check`; AC-001-15 (SDK ≥ 26 on the Debug app) |
| CRIT-2 | minor | 305 | Closed | AC-305-12 `crit2WindowsRecipeKeepsFontsThatExistOnBothSystems`; AC-305-9 `crit2FolderValidation`; AC-305-15; AC-305-16; AC-501-3; AC-501-9 `crit2UnresolvedFontsStayAndAreReported`; AC-501-13; AC-602-4 `test_crit_2_migration_note_says_do_not_copy_the_settings_folder`; AC-602-M2 |
| CRIT-3 | minor | 110, 305, 602 | Closed | AC-110-5 `test_crit_3_office_bundle_font_is_microsoft_product`; AC-305-13 `crit3WindowsOnlyFontGetsMacEquivalentSuggestions`; AC-501-9; AC-602-3 `crit3DocTableMatchesEquivalents`, `test_crit_3_windows_font_licence_warning`; the walker does not enter app bundles: AC-401-3; folder inside an app bundle is flagged: AC-305-9 |
| CRIT-4 | minor | — (B-5) | Backlog B-5 | No document types or Open Font… in v1. A dropped font file gives the `fileDropped` notice, which explains what to do (AC-501-26); folders are accepted |
| CRIT-5 | minor | 401 | Closed | AC-401-3 `crit5MacFileSystemConventions` |
| CRIT-6 | minor | 401 | Closed | AC-401-8 `catalog7Crit6PruneVanishedPathsAfterCompleteRefreshOnly` |
| CRIT-7 | minor | — | Closed (by WP-111) | AC-111-1, AC-111-2, AC-111-10 (real Apple fonts); synthetic fixtures with Apple shapes in the normal suite: AC-101-1 (`(0,1)`/`(0,3)` cmaps), AC-102-1 (`bloc`/`bdat`), AC-103-1 (no OS/2), AC-106-7 (`morx`); real-Mac service tests: AC-401-23, AC-402-15, AC-403-20 |
| CRIT-8 | polish | 501 | Closed | AC-501-21 `crit8MinimumWidthAllowsHalfScreenTiling`; AC-501-M2; AC-505-M6; AC-506-M2 |
| CRIT-9 | polish | 401 | Closed | AC-401-13 `crit9FontBookDisabledFontsAreMarked`; AC-401-18 (disable fingerprint triggers a refresh) |
| CRIT-10 | polish | 508 (B-8) | Closed in part (by WP-501, WP-507); Simplified Chinese by WP-508 (v1.1); Traditional Chinese, Japanese and Korean stay Backlog B-8 | The cheap step, `CFBundleAllowMixedLocalizations`, is in the Info.plist table asserted by AC-501-2. Every string is in the String Catalog: AC-507-1, AC-507-2, AC-507-9. Simplified Chinese: AC-508-1 to AC-508-14, AC-508-M1 to AC-508-M4 |

### 1.8 Summary of dispositions

| Disposition | Blocker | Major | Minor | Polish | Total |
|---|---|---|---|---|---|
| Closed (including "closed in part": CRIT-10, TOOLING-22) | 5 | 26 | 52 | 23 | 106 |
| Obsolete | 0 | 1 | 7 | 1 | 9 |
| Backlog B-n | 0 | 0 | 2 | 2 | 4 |
| Not scheduled (proposed backlog id) | 0 | 0 | 0 | 2 | 2 |
| Won't fix | 0 | 0 | 4 | 1 | 5 |
| Informational | 0 | 0 | 3 | 0 | 3 |
| **Total** | **5** | **27** | **68** | **29** | **129** |

- Obsolete: UI-5 (major); UI-7, UI-8, TOOLING-5, TOOLING-15, TOOLING-16, TOOLING-19, NATIVE-M5 (minor); TOOLING-M4 (polish).
- Backlog: ENGINE-6 (B-1), CRIT-4 (B-5) (minor); ENGINE-11 (B-2), NATIVE-10 (B-6) (polish).
- Not scheduled: CATALOG-12, NATIVE-M7. Won't fix: NATIVE-2, NATIVE-4, NATIVE-5, NATIVE-M6 (minor); TOOLING-21 (polish). Informational: TOOLING-12, NATIVE-1, NATIVE-11.

Every blocker and every major finding is closed by at least one automated AC, except UI-5. UI-5 is obsolete (Qt stylesheets), and its underlying need is covered by the automated AC-502-23.

---

## 2. Parity checklist (docs/plan.md §6) → ACs

WP-701 ticks each item on a release build (AC-701-1) and cites the ACs below as evidence. Manual ACs are the screenshot evidence.

| # | Checklist item (short) | Plan WPs | Automated ACs | Manual ACs |
|---|---|---|---|---|
| 1 | Choose main font…: each family in its own face, native names, a sample line per language, only fonts that draw the language well, English or native search, ↑/↓ try, Return uses it, Esc goes back | 503 | AC-503-1, AC-503-2 (draws the language well), AC-503-3 (English/native search), AC-503-7 (titles, main font), AC-503-8 (↑/↓), AC-503-9 and AC-503-10 (Return), AC-503-11 (Esc/Back), AC-503-13 (the candidate is tried), AC-503-23 (flows 1 and 3), AC-503-28 (rows drawn in their own face), AC-503-29 (native name and sample line), AC-504-11 (the preview shows the trial) | AC-503-M1, AC-503-M3 |
| 2 | Next step offered when the text has characters the main font can't draw | 502, 304 | AC-502-6, AC-503-23 (flow 2), AC-304-1, AC-304-2 | AC-503-M1 |
| 3 | ＋ Add a font for another language…; it draws that language even if a font above could | 502, 303 | AC-502-18, AC-303-2 (`addForALanguagePinsItsGroups`), AC-503-23 (flows 2 and 4), AC-302-1 (rules win in the planner) | — |
| 4 | Each card says in plain words what its font draws | 502, 301 | AC-502-10, AC-502-11, AC-301-10 | AC-502-M1 |
| 5 | Size and Weight for fonts below the main font, reflected at once in the preview | 502, 303 | AC-502-9, AC-502-14, AC-502-15, AC-502-25, AC-504-4, AC-504-5 | AC-502-M1 |
| 6 | Colour by font | 504 | AC-504-10, AC-502-21, AC-507-6 | AC-504-M1, AC-507-M3 |
| 7 | Characters no font draws are listed under the preview, with "find a font" | 504, 304 | AC-504-6, AC-504-20, AC-504-21, AC-302-7 | AC-504-M1 |
| 8 | Editable preview of the user's text, drawn exactly as the result will draw | 504, 402 | AC-504-2, AC-504-14, AC-504-15, AC-504-17, AC-504-19, AC-402-3, AC-402-5, AC-402-6 | AC-504-M2, AC-504-M4 |
| 9 | Install for the current user; preview switches to the built font; Update installed font after changes | 505, 403 | AC-505-8, AC-505-9, AC-505-10, AC-504-12, AC-403-6, AC-403-9 | AC-505-M1, AC-504-M5 |
| 10 | Refuses a name the system or user already has; asks before replacing one it made earlier | 505, 403 | AC-403-5, AC-403-8, AC-403-12, AC-505-14 | AC-505-M3 |
| 11 | Save a Copy… | 505 | AC-505-17, AC-505-18, AC-505-19 | AC-505-M2 |
| 12 | Advanced: which font draws each script (editable), line-spacing source, default boldness and size, last build report | 506 | AC-506-2, AC-506-3, AC-506-5, AC-506-6, AC-506-7 | AC-506-M1 |
| 13 | Rescan Fonts, Add Font Folder…, Start Over, Advanced…, Appearance, Show Settings Folder in Finder | 501 | AC-501-14 (Rescan), AC-501-25 (Add Font Folder), AC-501-17 (Start Over), AC-506-10 (Advanced), AC-501-4 (Appearance), AC-501-24 (Show Settings Folder), AC-501-18 (all in the menu bar) | AC-501-M3, AC-501-M4 |
| 14 | Result: one glyph per character, no unused glyphs, hinting removed, OpenType features kept per font, legacy `kern` → GPOS, fresh name table, vertical metrics from the main font | engine; 111 | **AC-111-12** (added by this audit: all seven properties on one synthetic forge, Linux), AC-111-2 (real fonts: glyph ratio, tables ⊆ `KEEP_TABLES`, cmap = total characters), AC-111-4 (real OpenType shaping and kerning kept), AC-002-1 (ported `test_forge_two_materials_end_to_end`, `test_legacy_kern_survives_as_gpos`), AC-109-5, AC-109-6, AC-109-9 (fresh names) | — |
| 15 | Licence notes in the report and the UI | 110, 505 | AC-110-6, AC-501-28, AC-505-21, AC-502-12 | AC-505-M2 |
| 16 | Variable fonts instanced at the chosen weight | engine; 111 | AC-002-1 (ported `test_variable_instanced_at_weight`), AC-111-2 (AF-03 output has no `fvar`; AF-13 instances SF at 700), AC-402-7 and AC-504-5 (the preview uses the same weight) | — |
| 17 | First launch after an update rescans only what changed | 401 | AC-401-7 (a new store on the same cache makes zero scans; only a changed file is re-read), AC-401-6 (a new face reader version rescans everything), AC-401-23 (b) (warm refresh on the real Mac) | — |

Before this audit, item 14 had no AC for "hinting removed" or for "vertical metrics from the main font" with a non-first line-spacing font. AC-111-12 closes that gap. Every other item already had automated coverage.

---

## 3. Statistics

### 3.1 Per spec

"Manual" means an AC marked `(manual…)` (ids `AC-NNN-Mk`, plus AC-203-9, AC-401-25, AC-403-21, AC-404-3, AC-404-11) or a maintainer-only action (AC-701-9). All other ACs are checked by a named test, a Make target or a command with an expected output. Three automated ACs need maintainer resources rather than a Codex agent: AC-111-1 (an Apple silicon Mac with the stock fonts of the reference macOS version) and AC-601-16 and AC-701-8 (the Developer ID and notary credentials).

| Spec | WPs | ACs | Automated | Manual |
|---|---|---|---|---|
| foundation-release.md | 5 (001, 002, 601, 602, 701) | 67 | 59 | 8 |
| engine-correctness.md | 6 (101–105, 111) | 47 | 47 | 0 |
| engine-metadata.md | 5 (106–110) | 50 | 50 | 0 |
| helper.md | 5 (201–205) | 83 | 82 | 1 |
| core.md | 5 (301–305) | 88 | 88 | 0 |
| mac-services.md | 4 (401–404) | 77 | 73 | 4 |
| ui-shell.md | 4 (501, 505, 506, 507) | 107 | 88 | 19 |
| ui-editing.md | 3 (502, 503, 504) | 98 | 86 | 12 |
| localisation.md | 1 (508) | 18 | 14 | 4 |
| **Total** | **38** | **635** | **587** | **48** |

### 3.2 Per WP (automated / manual)

| WP | Auto | Man | WP | Auto | Man | WP | Auto | Man |
|---|---|---|---|---|---|---|---|---|
| 001 | 18 | 1 | 201 | 29 | 0 | 404 | 10 | 2 |
| 002 | 10 | 0 | 202 | 15 | 0 | 501 | 34 | 6 |
| 101 | 8 | 0 | 203 | 9 | 1 | 502 | 25 | 2 |
| 102 | 6 | 0 | 204 | 20 | 0 | 503 | 32 | 4 |
| 103 | 7 | 0 | 205 | 9 | 0 | 504 | 29 | 6 |
| 104 | 7 | 0 | 301 | 19 | 0 | 505 | 31 | 6 |
| 105 | 7 | 0 | 302 | 11 | 0 | 506 | 13 | 2 |
| 106 | 14 | 0 | 303 | 22 | 0 | 507 | 10 | 5 |
| 107 | 11 | 0 | 304 | 16 | 0 | 601 | 16 | 3 |
| 108 | 7 | 0 | 305 | 20 | 0 | 602 | 7 | 2 |
| 109 | 10 | 0 | 401 | 25 | 1 | 701 | 8 | 2 |
| 110 | 8 | 0 | 402 | 16 | 0 | 508 | 14 | 4 |
| 111 | 12 | 0 | 403 | 22 | 1 | | | |

### 3.3 Finding coverage

| | Findings | With ≥ 1 closing AC | Without a closing AC |
|---|---|---|---|
| Blocker | 5 | 5 | 0 |
| Major | 27 | 26 | 1 (UI-5, obsolete; need covered by AC-502-23) |
| Minor | 68 | 52 | 16 (all obsolete, backlog, won't fix or informational; §1) |
| Polish | 29 | 23 | 6 (ENGINE-11, NATIVE-10: backlog; CATALOG-12, NATIVE-M7: not scheduled; TOOLING-21: won't fix; TOOLING-M4: obsolete) |

---

## 4. Conventions checked

- Every AC id cited anywhere in `docs/` resolves to an AC defined in a spec (checked by script when this file was written; no dangling references).
- AC ids are unique across specs.
- Some AC lists are not in numeric order in the file (WP-505 defines AC-505-26 after AC-505-7 and AC-505-27…31 in between; WP-602 defines AC-602-M2 before AC-602-5; WP-201 has AC-201-12b). The ids are stable, so this is harmless; don't renumber.
- Every finding a WP's header says it closes has at least one AC in that WP with a regression test named after the finding (AGENTS.md). The one exception is by design: WP-111's "all ENGINE-*" excludes ENGINE-6 and ENGINE-11, which its Scope/Out defers to B-1 and B-2.

## 5. Plan discrepancies found (for the maintainer; backbone files were not edited)

1. **Findings closed by a WP whose plan row doesn't list them.** docs/plan.md §3 "Findings" could add: NATIVE-9 (major) to WP-401 and WP-108; UI-5 (major, obsolete; need covered in WP-502) to WP-502; CRIT-7 to WP-111; TOOLING-M3 to WP-401 and WP-501; TOOLING-M5 to WP-401; NATIVE-M2 to WP-402; UI-M5 and UI-17 to WP-507; UI-16 and TOOLING-13 to WP-602 and WP-601; INSTALL-6 also to WP-401 and WP-505 (where AC-401-20 and AC-505-8 prove it).
2. **Deferred findings without a backlog id.** CATALOG-12 (named instances as faces; proposed B-10) and NATIVE-M7 (session-scope "try in other apps"; proposed B-11). The specs defer them, but §3 "Backlog" doesn't list them.
3. **WP-111 also needs WP-201.** Its suite drives `python -m fpengine` (engine-correctness.md, WP-111 notes). The plan lists 101–110 only. Wave 5 already runs after WP-201 (wave 4), so the schedule is unaffected.
4. **Parity item 14** now names AC-111-12 as its engine-level proof. No change to the checklist text is needed.
