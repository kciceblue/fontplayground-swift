# macOS services: font catalog, rendering, installer, downloadable fonts

> Scope: WP-401, WP-402, WP-403, WP-404 · Env: macos · Architecture refs: docs/architecture.md §2 (FPMacServices), §3, §4 steps 1–3, 5–7, §5, §8 · ADRs: 0003, 0005, 0006, 0007, 0009, 0010, 0011

## Context

`FPMacServices` is the only place where the app talks to CoreText, fontd and the user's font folders. It has four parts:

- the **catalog**: which font files exist, which faces they hold, and which of them the user can pick;
- the **renderer**: honest `CTFont`s for the preview and the picker;
- the **installer**: copies a forged font into `~/Library/Fonts`, and checks name conflicts first;
- **downloadable fonts**: hand-off to Font Book, plus an optional curated in-app download.

### What the original app did

Reference paths below are relative to `reference/fontplayground-py/fontplayground/` (the tests: `reference/fontplayground-py/tests/`), except the first row, which is written out in full.

| Area | Reference | Behaviour |
|---|---|---|
| Font folders | `reference/fontplayground-py/fontplayground/paths.py:12-24`, `:38-39` | macOS: walks `/System/Library/Fonts`, `/Library/Fonts`, `~/Library/Fonts`; extension filter `.ttf .otf .ttc .otc` |
| File walk | `catalog/scanner.py:19-28` | `rglob`, dedupe by `str(p.resolve()).lower()` |
| Scan | `catalog/scanner.py:31-57` | reads every file in-process (`face.py:200-214`); failures listed as `(path, error)`; progress `(done, total)` |
| Cache | `catalog/cache.py:10`, `:43-83`; stored at `ui/app.py:95` | `catalog.json` in the config dir, keyed by path + size + mtime, `SCHEMA = 3`, never pruned |
| Rescan | `ui/app.py:169`, `:201-202`, `:298-340` | scan at launch and on Rescan (`use_cache=False`); a request during a scan is queued and runs once after it |
| Picker refresh | `ui/picker.py:33` | rows rebuilt at most every 300 ms while a scan runs |
| Preview fonts | `ui/fonts.py:17-42`, `:55-65`, `:73-91`, `:94-113` | Qt `addApplicationFont`, `NoFontMerging`, variable `wght` clamped to the axis, static faces emboldened by Qt past `weight_class + 100`, installed families resolved **by name** |
| Engine instancing | `engine/prepare.py:35-41`, `:160-171`; `engine/synth_bold.py:8-13` | every non-`wght` axis pinned to the fvar default; `wght` clamped; a static face asked ≥ 50 heavier is stroked by `Δ/1000 × 0.2 × upem`, Δ capped at 500 |
| Install | `ui/install.py` | Windows only: registry + GDI + `WM_FONTCHANGE`; `full_name_of` / `is_forged` at `:46-75` (marker `engine/merge.py:47`); copy overwrites in place (`:160-173`) |
| Conflicts | `ui/build.py:31-40`, `:60-72`, `:142-179`, `:209-285` | `block` / `replace` / `none` against catalog faces under `%WINDIR%\Fonts` or the user folder; wording names Windows |

### What the audit found

- **Catalog.** The folder walk misses every CoreText-managed font outside the three folders. That includes PingFang and 28 other AssetsV2 fonts (`CATALOG-1`). Hidden `.`-faces leak in, and `.LastResort` becomes the top suggestion (`CATALOG-2`). A naive CoreText union duplicates PingFang through `PingFangUI.ttc` (`CATALOG-M1`). The catalog never refreshes on font changes (`CATALOG-6`). Paths change on asset updates while the cache never prunes (`CATALOG-7`, `CRIT-6`). Dedupe is case-folded (`CATALOG-9`). `.dfont` files are silently skipped (`CATALOG-10`). The cache lives in Application Support (`CATALOG-M3`). AppleDouble, `__MACOSX` and `.Trashes` are not handled and symlinked folders are skipped (`CRIT-5`). Font Book–disabled fonts are ignored (`CRIT-9`). A cold in-process scan leaves 1,363 MB in the app (`ENGINE-9` verifier).
- **Rendering.** The Qt preview resolved fonts by name (`CATALOG-4`) and shaped with HarfBuzz rather than CoreText (`NATIVE-M1`). CoreText auto-sizes `opsz` while the engine pins it (`NATIVE-M3`). CoreText descriptors carry no TTC index (`NATIVE-M2`). The LastResort cascade is needed on URL descriptors as well (`NATIVE-3` verifier).
- **Install.** On macOS there is no installer (`INSTALL-1`, `-2`). The conflict check is Windows-only and blind to AssetsV2, localized and PostScript names (`INSTALL-3`, `-4`, `-5`, `TOOLING-7`). The prototype installer deleted non-forged user fonts (`INSTALL-M1`) and removed the old copy before the new one was in place (`INSTALL-M2`). Nothing validated the file with CoreText first (`INSTALL-M3`). Update overwrote files in place (`INSTALL-8`, `TOOLING-2`). Uninstall should go to the Trash (`INSTALL-9`). Tracking needs marker + manifest (`INSTALL-10`, ADR-0009). Tests should use a temporary folder and process scope with the singular synchronous API (`INSTALL-7`, `-12`).
- **Downloads.** Apple's downloadable fonts are invisible, and name matching them blocks or downloads (`CATALOG-5`). The first step is Font Book.

### Facts verified while writing this spec (macOS 27, Xcode 27 SDK, Apple M5 Pro)

These results come from experiments run with enumeration APIs only. No name matching was used, and nothing was installed except process-scope registrations of synthetic fonts. They are normative inputs to the design.

| # | Fact | Evidence |
|---|---|---|
| F1 | **`CTFontManagerCopyAvailableFontURLs()` depends on the SDK the binary links against.** A Swift binary linked against the macOS 27 SDK gets 655 URLs in 265 files: only menu-visible faces, with no `.`-faces, no `LastResort`, and none of `Times`, `Hiragino Kaku Gothic Pro` or `STIX`. The same code stamped `sdk 15.0` gets 3,019 URLs in 430 files. The 165 missing files are all under `/System/Library/Fonts` (33) and `/System/Library/Fonts/Supplemental` (132). A walk of the three standard folders plus the CoreText list covers all of them except `HelveLTMM` and `TimesLTMM` (extensionless Type 1, hidden). The app must link against SDK ≥ 26 (ADR-0010). | `swiftc` with and without `-Xlinker -platform_version macos 14.0 15.0` |
| F2 | Every URL carries its face as a fragment, `#postscript-name=<name>`. 24 PostScript names are listed in two files: `AssetsV2/…/PingFang.ttc` and `PrivateFrameworks/FontServices.framework/Resources/Reserved/PingFangUI.ttc`. | pyobjc and Swift |
| F3 | `kCTFontPriorityAttribute` ("the font descriptor's priority when resolving duplicates", `CTFontDescriptor.h:247-251`) on `CTFontCollectionCreateFromAvailableFonts` descriptors is AssetsV2 = 60000, `/System/Library/Fonts` = 10000, PrivateFrameworks = 10000, `~/Library/Fonts` = 40000. The collection lists both PingFang copies, even with `kCTFontCollectionRemoveDuplicatesOption`. The higher priority is the copy CoreText resolves (the audit saw `PingFangSC-Medium` resolve to the AssetsV2 file). | collection over 655 descriptors, 0.026 s |
| F4 | `CTFontManagerCreateFontDescriptorsFromURL` over all 430 files takes 0.06 s. All 952 faces map to exactly one URL descriptor of their own file by `name` ID 6 = `kCTFontNameAttribute`. 31 files return more descriptors than faces (named instances of variable fonts). | fontTools vs CoreText, every file |
| F5 | A URL descriptor copied with `kCTFontCascadeListAttribute = [LastResort]` draws **its own file** even while a different file with the same PostScript name is registered at process scope. Missing characters are drawn by `LastResort`. Without the cascade, CoreText borrows `PingFangSC-Regular` for 永. | synthetic fonts, pyobjc + `swift test` |
| F6 | `LastResort` is at `/System/Library/Fonts/LastResort.otf`. `CTFontManagerCreateFontDescriptorsFromURL` on it gives one descriptor named `LastResort`, and it works as a cascade entry. The name form (`CTFontDescriptorCreateWithNameAndSize("LastResort", 0)`) resolves to the same file. | Swift, SDK 27 |
| F7 | CoreText applies automatic optical size only to fonts with a `STAT` table (synthetic font without STAT: none; with STAT: `opsz` follows point size, and glyph height changes at 96 pt). An explicit variation whose values are all defaults does **not** stop auto-sizing. `kCTFontOpticalSizeAttribute = "none"` together with an explicit variation pins every axis at every size. | synthetic `wght`+`opsz` font, geometry check |
| F8 | With **no GSUB**, CoreText synthesizes Arabic joining from the presentation forms in `cmap`. With a Latin-only GSUB (the shape of forged output), it draws the nominal, unjoined glyphs, which is what the audit saw for Georgia+Baghdad. | synthetic fonts |
| F9 | Process-scope registration posts `CTFontManagerFontChangedNotification` (the value of `kCTFontManagerRegisteredFontsChangedNotification`) on the **local** center only, about 3 ms later. `CTFontManagerRegisterFontURLs(…, enabled: false)` at process scope does **not** produce a disabled descriptor (`kCTFontEnabledAttribute` stays 1), so a Font Book–disabled state cannot be simulated. This Mac has 655 of 655 descriptors enabled. | pyobjc |
| F10 | A name index built purely from enumeration (all CoreText URLs + the three folders, `CTFontCopyTable(name)` per descriptor: 3,019 descriptors, 953 distinct name tables) takes 0.6 s in Python. It finds `Helvetica`, `helvetica`, `Times`, `Hiragino Kaku Gothic Pro`, `Helvetica-Bold`, `Helvetica Bold`, `苹方-简`, `宋体-简`, `华文宋体`, `ヒラギノ角ゴシック` and `البيان` with no name lookup. | pyobjc |
| F11 | The reference `read_faces` over 430 files / 951 faces takes 4.76 s single-process, plus 0.16 s for the extra ScriptList/AAT/licence reads of WP-106. Max RSS is 1,363 MB and stays in the process. Swift `JSONDecoder` decodes a 12.7 MB / 920-face catalog cache in 0.33 s. | `/usr/bin/time -l`, `swiftc -O` |
| F12 | `kCTFontCollectionDisallowAutoActivationOption` exists (`CTFontCollection.h`), and so do `kCTFontCollectionIncludeDisabledFontsOption` and `kCTFontEnabledAttribute`. Font Book's bundle id is `com.apple.FontBook`. | SDK headers, Info.plist |
| F13 | A font registered at **process scope** is listed by `CTFontManagerCopyAvailableFontURLs()`, `CTFontManagerCopyAvailablePostScriptNames()`, `CTFontManagerCopyAvailableFontFamilyNames()` and `CTFontCollectionCreateFromAvailableFonts` (URL attribute present, priority 60000), and is gone from all of them after unregistering. **CoreText may spell its path differently from the URL that was registered:** a file registered as `/private/tmp/…/A.ttf` is listed as `/tmp/…/A.ttf`. A file under `FileManager.default.temporaryDirectory` (`/var/folders/…`) is listed with the same spelling. So paths that come back from CoreText are compared with other paths by **file identity** (S4), never as strings. | Swift, SDK 27 (review re-run; an earlier run that compared path strings wrongly concluded that such fonts are missing from the URL list) |

## Shared definitions

Everything in this section is normative. Where a file is shared by two WPs, the one that merges first creates it exactly as described, and the other keeps what is on `main`.

### S1. Constants and locations

`Packages/FontPlaygroundMacKit/Sources/FPMacServices/Support/MacServicesConstants.swift`, created verbatim by the first of WP-402 / WP-403 to merge (WP-401 creates it if it is still missing):

```swift
public enum MacServicesConstants {
    public static let bundleIdentifier = "io.github.kciceblue.fontplayground"
    public static let forgedNotice = "Forged with Font Playground"          // engine/merge.py:47, contracts §6
    public static let fontBookBundleIdentifier = "com.apple.FontBook"
    public static let lastResortURL = URL(fileURLWithPath: "/System/Library/Fonts/LastResort.otf")
    public static let sfntMagics: Set<UInt32> = [0x0001_0000, 0x4F54_544F /* OTTO */, 0x7472_7565 /* true */,
                                                  0x7474_6366 /* ttcf */]
    public static let fontExtensions: Set<String> = ["ttf", "otf", "ttc", "otc"]              // paths.py:9
    public static let unsupportedFontExtensions: Set<String> = ["dfont", "suit", "pfb", "pfa", "pfm", "fon",
                                                                "fnt", "bdf", "pcf", "woff", "woff2"]
}
```

| What | Default location | Injected as |
|---|---|---|
| Catalog cache | `~/Library/Caches/io.github.kciceblue.fontplayground/catalog-v1.json` (`CATALOG-M3`) | `CatalogConfiguration.cacheDirectory` |
| User fonts folder | `~/Library/Fonts` | `CatalogConfiguration.userFontsFolder`, `FontInstaller(fontsFolder:)` |
| Standard folders walked by the catalog | `/System/Library/Fonts`, `/Library/Fonts`, `~/Library/Fonts` (F1) | `CatalogConfiguration.standardFolders` |
| Installed-fonts manifest | `~/Library/Application Support/io.github.kciceblue.fontplayground/installed.json` (contracts §8) | `FontInstaller(manifestURL:)` |
| Install staging file | `~/Library/Fonts/.<stem>.<32 hex>.fpinstall` (ADR-0009 step 2) | derived from `fontsFolder` |

Resolve the home and library folders with `FileManager.default.homeDirectoryForCurrentUser` and `FileManager.default.urls(for: .cachesDirectory / .applicationSupportDirectory, in: .userDomainMask)`. The app is not sandboxed (ADR-0010). **Only the app and `fpmac-harness` use the defaults. Tests always inject temporary directories** (testing.md §5).

### S2. `SystemFontRegistry` (created by WP-403; consumed by WP-401 and WP-404)

`Packages/FontPlaygroundMacKit/Sources/FPMacServices/Registry/SystemFontRegistry.swift`:

```swift
/// A font file CoreText lists in CTFontManagerCopyAvailableFontURLs(), with the PostScript names of its faces
/// taken from the URL fragments ("postscript-name=<name>"). Linked against SDK ≥ 26 this lists menu-visible faces only (F1).
public struct RegisteredFontFile: Hashable, Sendable {
    public var path: String              // url.standardizedFileURL.path(percentEncoded: false); fragment removed
    public var postscriptNames: [String] // url.fragment(percentEncoded: false) minus "postscript-name="; CoreText order, unique
}

/// One descriptor of CTFontCollectionCreateFromAvailableFonts.
public struct RegisteredFaceInfo: Hashable, Sendable {
    public var postscriptName: String    // kCTFontNameAttribute
    public var path: String?             // kCTFontURLAttribute (standardized path); nil when CoreText gives none
    public var priority: Int             // kCTFontPriorityAttribute; 0 when absent (F3)
    public var enabled: Bool             // kCTFontEnabledAttribute; absent → true
    public var familyName: String        // kCTFontFamilyNameAttribute; absent → "" (pathless disabled faces)
}

public protocol SystemFontRegistry: Sendable {
    func registeredFontFiles() -> [RegisteredFontFile]            // file URLs only (url.isFileURL)
    func menuVisiblePostScriptNames() -> Set<String>              // CTFontManagerCopyAvailablePostScriptNames()
    func registeredFaces(includeDisabled: Bool) -> [RegisteredFaceInfo]
}

public struct CoreTextFontRegistry: SystemFontRegistry { public init() }
```

`registeredFaces` creates the collection with `[kCTFontCollectionDisallowAutoActivationOption: true]` (F12). When `includeDisabled` is true, it adds `kCTFontCollectionIncludeDisabledFontsOption: true`. It reads the attributes with `CTFontDescriptorCopyAttribute`. Its public initializer defaults `familyName` to `""`, preserving callers that only need names and paths; WP-403 uses it for family conflicts on disabled descriptors without a URL.

`registeredFontFiles()` merges two sources:

1. `CTFontManagerCopyAvailableFontURLs()`: path plus fragment.
2. The `(path, kCTFontNameAttribute)` of every `registeredFaces(includeDisabled: false)` descriptor that has a file URL. This is defensive: on the macOS 27 SDK both sources list the same files (F3, F13), but the collection is the documented enumeration and it costs 0.03 s.

Group by path **string**, keep the first-seen order (source 1 first), and drop duplicate PostScript names within a file. Two spellings of one file may therefore appear as two `RegisteredFontFile`s; consumers dedupe by identity (S4). Neither method may call `CTFontDescriptorCreateMatchingFontDescriptors`, `CTFontDescriptorCreateWithNameAndSize` or any other matching API (S5).

`CTFontCollectionCreateMatchingFontDescriptors` on the collection returned by `CTFontCollectionCreateFromAvailableFonts` is an enumeration, not name matching, and is allowed.

### S3. Where a file lives: `FaceOrigin` and `FontDomain`

Each WP classifies with its own pure function over the same table: WP-401 `FaceOrigin.classify(path:isInsideUserFolder:isRegistered:)` (in `Catalog/CatalogModels.swift`, which also declares `FaceOrigin`) and WP-403 `FontDomain.classify(path:isInsideUserFolder:injectedDomain:isRegistered:)` (in `Install/InstallModels.swift`, which also declares `FontDomain`). The callers compute the booleans: `isInsideUserFolder` and `injectedDomain` by identity containment (S4), and `isRegistered` by comparing the file's identity with the identities of `SystemFontRegistry.registeredFontFiles()` paths (never path strings, F13). The remaining rows compare string prefixes of the standardized path. Evaluate top to bottom; the first match wins.

| Test | `FaceOrigin` (catalog, WP-401) | `FontDomain` (installer, WP-403) |
|---|---|---|
| `isInsideUserFolder` | `.user` | `.user` |
| `injectedDomain != nil` (installer only: the file is inside a `FontInstaller(systemFolders:)` folder) | — | that domain |
| prefix `/System/Library/AssetsV2/` | `.systemAsset` | `.system` |
| prefix `/System/Library/` or `/Library/Apple/` | `.system` | `.system` |
| prefix `/Library/Fonts/` | `.local` | `.local` |
| `isRegistered` | `.activated` (font managers, apps; their licences often forbid modification — CATALOG-1 verifier) | `.other` |
| anything else (extra folders) | `.extraFolder` | `.other` |

```swift
public enum FaceOrigin: String, Codable, Sendable, CaseIterable {       // WP-401, Catalog/CatalogModels.swift
    case system, systemAsset = "system_asset", local, user, activated, extraFolder = "extra_folder"
}
public enum FontDomain: String, Codable, Sendable {                     // WP-403, Install/InstallModels.swift
    case system, local, user, other, downloadable                       // .downloadable: WP-404 names only
}
```

### S4. File identity and folder containment

Paths follow contracts §2: absolute, standardized, symlinks **not** resolved. A file's identity is `(st_dev, st_ino)` from `stat(2)` (following symlinks). This is used for:

- deduplicating discovered files (`CATALOG-9`);
- "is `x` **directly** inside folder `F`" (rule 1 of "Ours" in WP-403 §5): the identity of `x`'s parent directory equals that of `F` (`INSTALL-11`, TOOLING-7 verifier). This works through `/tmp` → `/private/tmp` and with case differences on APFS.
- "is `x` inside folder `F`" (S3 `isInsideUserFolder`, `injectedDomain`): the identity of some ancestor directory of `x` (parent, grandparent, … up to `/`) equals that of `F`. Stop at the first match; a `stat` failure on an ancestor means "not inside".
- comparing a path CoreText returns with any other path (F13).

A folder or file whose `stat` fails has no identity and is never "inside" anything.

Each WP keeps its own small private helper for this, so parallel WPs don't collide on a shared file: WP-401 `DiscoveredFileStamp`, WP-402 `FontFileStamp`, WP-403 `InstallerFileStat`.

### S5. Safety rules (enforced by source-audit tests)

Both source-audit tests share one pure scanner, `SourceAudit` in `Tests/FPMacServicesTests/Safety/SourceAudit.swift` (created by WP-402; WP-403 creates it if missing):

```swift
enum SourceAudit {
    struct Violation: Equatable { var file: String; var line: Int; var token: String }
    /// Scans `text` (the contents of `file`, a path relative to the package root) line by line. Lines whose trimmed
    /// text starts with `//`, `///` or `*` are ignored. `allowed(file, token)` returns how many occurrences of `token`
    /// the file may contain (0 = none); extra occurrences are violations.
    static func violations(in text: String, file: String, tokens: [String], allowed: (String, String) -> Int) -> [Violation]
    /// Every `*.swift` file under `root` (recursive), as (path relative to the package root, contents).
    static func swiftFiles(under root: URL) throws -> [(String, String)]
}
```

The package root is found from `#filePath` (as `FixtureFonts.packageRoot`, S6). Files under `Tests/FPMacServicesTests/Safety/` are never scanned, because they contain the forbidden tokens as test data. The self-tests call `violations(in:)` on a synthetic string.

1. **No name-based CoreText lookups** (AGENTS rule 4, architecture §8). `NameLookupSafetyTests` (WP-402) scans every `*.swift` under `Packages/FontPlaygroundMacKit/Sources/` (FPMacServices, FPMacHarness and FPAppUI) and fails when a forbidden token appears outside the allowlist.
   - Forbidden: `CTFontCreateWithName(`, `CTFontCreateWithNameAndOptions(`, `CTFontDescriptorCreateWithNameAndSize(`, `CTFontDescriptorCreateWithAttributes(`, `CTFontDescriptorCreateMatchingFontDescriptors(`, `CTFontDescriptorCreateMatchingFontDescriptor(`, `CTFontDescriptorMatchFontDescriptorsWithProgressHandler(`, `CTFontCollectionCreateWithFontDescriptors(`, `NSFont(name:`, `NSFontDescriptor(name:`, `.font(withFamily:`, `Font.custom(`.
   - Allowlist (paths relative to the package root): `Sources/FPMacServices/Rendering/LastResort.swift` may contain `CTFontDescriptorCreateWithNameAndSize(` once. `LastResort` is a SIP-protected system font that is always installed and never downloadable, so it is the documented fallback. WP-404 part B adds `Sources/FPMacServices/Downloads/CoreTextFontDownloader.swift`, which may contain `CTFontDescriptorCreateWithAttributes(` once and `CTFontDescriptorMatchFontDescriptorsWithProgressHandler(` once; they run only after explicit confirmation. `Sources/FPMacServices/PlatformFontPreferences.swift` belongs to ui-editing.md WP-503 (the CATALOG-11 lookup). It uses `CTFontCreateUIFontForLanguage(.user, …)` and `CTFontCreateForStringWithLanguage`, which are not on the list: they ask for the system's own fallback choice, not for a font by name. The file is scanned like every other source.
2. **No registration in production.** `RegistrationSafetyTests` (WP-403):
   - Under `Sources/`, any call to a function whose name starts with `CTFontManagerRegister` or `CTFontManagerUnregister` is a violation (match the function name followed by `(`, allowing whitespace). Notification constants such as `kCTFontManagerRegisteredFontsChangedNotification` are observations, not registration calls.
   - Under `Tests/`, such a call is allowed only when it calls `CTFontManagerRegisterFontsForURL` or `CTFontManagerUnregisterFontsForURL` **and** the line contains `.process`, and contains none of `CTFontManagerRegisterFontURLs(`, `CTFontManagerRegisterFontDescriptors(`, `CTFontManagerRegisterGraphicsFont(`, `.persistent`, `.user`, `.session`. (`.user` elsewhere, for example `FaceOrigin.user`, is not checked.)
3. **Tests never write** outside temporary directories. They never touch the real Trash (S6 `RecordingTrash`), never open visible windows or launch apps, and never download.
4. **Tests may run in parallel** (Swift Testing). Process-scope registrations are process-wide, so tests use family names with a random 8-hex suffix, assert membership (never exact totals) on real CoreText enumerations, and unregister in `defer`. Suites that register fonts are `@Suite(.serialized)`. A test must not assume that no *other* test registers a font while it runs: never assert that no `kCTFontManagerRegisteredFontsChangedNotification` arrives on a real center.

### S6. Test support (created by the first of WP-402 / WP-403 to merge; WP-401 and WP-404 reuse it)

**`Packages/FontPlaygroundMacKit/TestFixtures/make_fonts.py`.** It lives outside the test target directory, so `Package.swift` needs no `exclude`. Copy it verbatim. It needs fontTools and nothing else, and `engine/.venv` has fontTools.

```python
"""Build synthetic test fonts for FPMacServicesTests (never real fonts).

stdin: {"out_dir": "<dir>", "fonts": [<spec>, ...]}; stdout: {"files": ["<abs path>", ...]}.
<spec>: {"file": "A.ttf", "family": "FP Test A", "style": "Regular", "postscript_name": null, "full_name": null,
         "chars": "abc", "notice": null, "weight_class": 400, "os2": true,
         "axes": [{"tag": "wght", "min": 100, "default": 400, "max": 900}], "stat": true, "fea": null,
         "localized_family": {"0x0804": "测试字体"}}
A spec with "faces": [<spec>, ...] (and "file" ending in .ttc) builds a collection of those faces.
Glyph names are uniXXXX (uXXXXX above the BMP). Glyph i is a rectangle whose width encodes i,
so fonts that share names still differ in outlines.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.fontBuilder import FontBuilder
from fontTools.otlLib.builder import buildStatTable
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._g_v_a_r import TupleVariation
from fontTools.ttLib.ttCollection import TTCollection


def _gname(cp: int) -> str:
    return f"uni{cp:04X}" if cp <= 0xFFFF else f"u{cp:05X}"


def _glyph(i: int):
    pen = TTGlyphPen(None)
    right = 150 + 10 * (i % 30)
    pen.moveTo((100, 0))
    pen.lineTo((100, 700))
    pen.lineTo((right + 100, 700))
    pen.lineTo((right + 100, 0))
    pen.closePath()
    return pen.glyph()


def build_face(spec: dict) -> TTFont:
    chars = spec.get("chars", "abc")
    cps = [ord(c) for c in chars]
    names = [".notdef"] + [_gname(cp) for cp in cps]
    cmap = {cp: _gname(cp) for cp in cps}
    family, style = spec["family"], spec.get("style", "Regular")
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf({n: _glyph(i) for i, n in enumerate(names)})
    fb.setupHorizontalMetrics({n: (600, 100) for n in names})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    ps = spec.get("postscript_name") or f"{family.replace(' ', '')}-{style.replace(' ', '')}"
    name = {
        "familyName": family,
        "styleName": style,
        "psName": ps,
        "fullName": spec.get("full_name") or f"{family} {style}",
        "uniqueFontIdentifier": f"{ps};test",
    }
    if spec.get("notice"):
        name["copyright"] = spec["notice"]  # name ID 0
    fb.setupNameTable(name)
    for lang, text in (spec.get("localized_family") or {}).items():  # e.g. {"0x0804": "测试字体"}: Windows records
        fb.font["name"].setName(text, 1, 3, 1, int(lang, 16))
    if spec.get("os2", True):
        fb.setupOS2(
            usWeightClass=int(spec.get("weight_class", 400)),
            sTypoAscender=800,
            sTypoDescender=-200,
            usWinAscent=800,
            usWinDescent=200,
        )
    fb.setupPost()
    axes = spec.get("axes") or []
    if axes:
        fb.setupFvar([(a["tag"], a["min"], a["default"], a["max"], a["tag"]) for a in axes], [])
        deltas = {"wght": [(0, 0), (0, 0), (200, 0), (200, 0)], "opsz": [(0, 0), (0, 100), (0, 100), (0, 0)]}
        fb.setupGvar(
            {
                n: [
                    TupleVariation({a["tag"]: (0, 1.0, 1.0)}, deltas.get(a["tag"], [(0, 0)] * 4) + [(0, 0)] * 4)
                    for a in axes
                ]
                for n in names
            }
        )
        if spec.get("stat", True):  # CoreText applies automatic optical sizing only to fonts with STAT (F7)
            buildStatTable(
                fb.font,
                [
                    {
                        "tag": a["tag"],
                        "name": a["tag"],
                        "values": [{"value": a["default"], "name": "Default", "flags": 2}],
                    }
                    for a in axes
                ],
            )
    if spec.get("fea"):  # OpenType feature code (feaLib syntax), e.g. a Latin-only GSUB (F8)
        addOpenTypeFeaturesFromString(fb.font, spec["fea"])
    return fb.font


def main() -> int:
    req = json.load(sys.stdin)
    out = Path(req["out_dir"])
    out.mkdir(parents=True, exist_ok=True)
    files = []
    for spec in req["fonts"]:
        path = out / spec["file"]
        if "faces" in spec:
            coll = TTCollection()
            coll.fonts = [build_face(f) for f in spec["faces"]]
            coll.save(str(path))
        else:
            build_face(spec).save(str(path))
        files.append(str(path))
    json.dump({"files": files}, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

(Verified: this script builds a static font, a forged-marker font, a `wght`+`opsz`+STAT variable font, a 2-face TTC, a font without OS/2, a font with a supplementary-plane character, a localized-family font and a Latin-only-GSUB Arabic font. CoreText reads every one; fontTools 4.66; `ruff check` and `ruff format` clean.)

**`Tests/FPMacServicesTests/Support/FixtureFonts.swift`** (the approach was verified with `swift test` on Xcode 27):

```swift
import CoreText
import Foundation

struct FontSpec: Encodable, Sendable {           // JSON keys: snake_case (make_fonts.py)
    struct Axis: Encodable, Sendable { var tag: String; var min: Double; var `default`: Double; var max: Double }
    var file: String
    var family: String
    var style = "Regular"
    var postscriptName: String? = nil
    var fullName: String? = nil
    var chars = "abc"
    var notice: String? = nil
    var weightClass = 400
    var os2 = true
    var axes: [Axis] = []
    var stat = true
    var fea: String? = nil
    var localizedFamily: [String: String] = [:]
    var faces: [FontSpec]? = nil
}

enum TestEnv {
    static var appleFonts: Bool { ProcessInfo.processInfo.environment["FP_APPLE_FONTS"] == "1" }
    static var enginePython: String? { ProcessInfo.processInfo.environment["FP_ENGINE_PYTHON"].flatMap { $0.isEmpty ? nil : $0 } }
    static func tag() -> String { String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)) }
    static func temporaryDirectory() throws -> URL   // FileManager.default.temporaryDirectory/fpmac-<UUID>, created
}

enum FixtureFonts {
    struct Unavailable: Error, CustomStringConvertible { let description: String }
    /// Packages/FontPlaygroundMacKit (this file is Tests/FPMacServicesTests/Support/FixtureFonts.swift).
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    /// FP_ENGINE_PYTHON, else <repo>/engine/.venv/bin/python when it exists.
    static var python: URL? { … }
    /// Builds the fonts into `dir` (default: a fresh temporary directory) and returns their URLs in spec order.
    /// Throws `Unavailable` when no Python is found: callers let it propagate, so the test FAILS rather than skips.
    static func build(_ specs: [FontSpec], in dir: URL? = nil) throws -> [URL]
}

enum ProcessScopeFonts {
    /// CTFontManagerRegisterFontsForURL(url, .process, &error) (INSTALL-7 verifier: singular, synchronous).
    /// Throws unless it succeeds or the error code is CTFontManagerError.alreadyRegistered (105).
    static func register(_ url: URL) throws
    /// CTFontManagerUnregisterFontsForURL(url, .process, nil); ignores CTFontManagerError.notRegistered (201).
    static func unregister(_ url: URL)
}
```

`build` runs `Process` with `python` and `packageRoot/TestFixtures/make_fonts.py`. It writes `{"out_dir", "fonts"}` to stdin (`JSONEncoder` with `.convertToSnakeCase`), reads `{"files"}` from stdout, and throws on a non-zero exit. FaceRecords in MacKit tests are made with the memberwise `FaceRecord.init` of core.md §WP-301 (`FaceRecord(path:index:family:style:coverage:… postscriptName:hidden:…)`).

### S6b. Gating

| Test kind | Condition | Behaviour when not met |
|---|---|---|
| Synthetic fixture fonts | Python found (S6) | **fails**. `make mac-test` exports `FP_ENGINE_PYTHON` (testing.md §3) |
| Real `fpengine` helper | `TestEnv.enginePython != nil` | `.enabled(if:)` skip |
| Real system fonts content, performance budgets | `TestEnv.appleFonts && TestEnv.enginePython != nil` | `.enabled(if:)` skip. Run with `FP_APPLE_FONTS=1 make mac-test`. A font that is not installed (checked with `menuVisiblePostScriptNames()`) skips that assertion and prints the reason |

**Budget machine class:** Apple silicon M1 or newer, 8 GB RAM or more, macOS 14 or newer, internal SSD, a stock macOS font set plus up to 50 user fonts (about 450 files and 1,000 faces). The budgets are derived from F10/F11 and the audit data (`CATALOG-1`: cold 6.47 s / warm 0.50 s in-process on an M-series Mac). They allow a factor of 2 or more for an M1.

### S7. Concurrency conventions

- `CTFont` and `CTFontDescriptor` are not `Sendable` in the Swift 6 SDK overlay (verified). CoreText font objects are immutable and thread-safe, so wrap them in `@unchecked Sendable` value types (`RenderedFont`, `LastResort`) with a comment that says so.
- Mutable shared state uses `OSAllocatedUnfairLock` (macOS 13+). Don't use `Mutex`: `Synchronization.Mutex` needs macOS 15. Otherwise use an `actor`.
- The services are UI-agnostic. `FontRenderer` is synchronous and may be called on the main actor (ui-editing.md S2.2). `CatalogStore` and `FontInstaller` are actors.

### S8. English text (source strings for the String Catalog)

The services return typed values. FPAppUI shows them through `Localizable.xcstrings` (WP-505 / WP-503 / WP-507). The English source text is fixed here. Every typed value has `var englishText: String` for logs, `fpmac-harness` and tests (the same pattern as core.md's `EnglishText`). Every error type in this spec (`CatalogError`, `RenderError`, `InstallError`, `FontBookError`, `DownloadError`) also conforms to `LocalizedError` with `errorDescription == englishText`, because WP-505 shows `error.localizedDescription` after "Couldn't install the font: ". `{…}` are placeholders; the quotes are typographic “ ” and the apostrophes are ASCII `'` (as in the reference strings).

| Value | English text | Origin |
|---|---|---|
| `ConflictReason.systemHas(name)` | `macOS already has a font called “{name}” — choose another name.` | build.py:38 (per-OS wording, INSTALL-13) |
| `.installedForEveryone(name)` | `A font called “{name}” is already installed for everyone on this Mac — choose another name.` | INSTALL-13 |
| `.youHave(name)` | `You already have a font called “{name}” installed — choose another name.` | build.py:39 |
| `.internalNameInUse(ps)` | `Another installed font already uses the internal name “{ps}” — choose another name.` | INSTALL-5 |
| `.internalNameUsedByYourFont(ps, fullName)` | `Your font “{fullName}” already uses the internal name “{ps}” — choose another name.` | INSTALL-5 verifier |
| `.hiddenName` | `Names that start with “.” are hidden by macOS — choose another name.` | UI-M3 |
| `.appleOffersDownload(name)` (ask) | `macOS can download a font called “{name}”. Install yours under this name anyway?` | INSTALL-4 verifier |
| `InstallConflict.replaceOurs(font)` question | `Replace the “{fullName}” you installed earlier?` | build.py:40 |
| install failure wrapper | `Couldn't install the font: {error}` | build.py:32 |
| remove failure wrapper | `Couldn't remove the font: {error}` | build.py:34 |
| `InstallError.previousCopyNotRemoved` | `Installed “{name}”, but couldn't remove “{previous}”: {error}` | build.py:35 |
| `UninstallOutcome.movedToTrash` | `Removed from your fonts — it's in the Trash.` | INSTALL-9 |
| `UninstallOutcome.notInstalled` | `That font was no longer installed.` | build.py:37 |
| `InstallError.invalidQuery` | `the font needs a name` | |
| `InstallError.conflict(c)` | `c`'s text: the reason's text for `.block`/`.ask`, the question above for `.replaceOurs`, `nothing is in the way` for `.noConflict` | |
| `InstallError.sourceMissing` | `the built font file is missing` | |
| `.unreadable` | `macOS can't read this font file` | INSTALL-M3 |
| `.unexpectedName(expected, found)` | `its internal name is “{found}”, not “{expected}”` | INSTALL-M3 |
| `.notForged` | `it wasn't made by Font Playground` | ADR-0009 |
| `.noFreeFileName(stem)` | `there's no free file name for “{stem}” in your Fonts folder` | install.py:25 |
| `.notOurs(name)` | `Font Playground didn't install “{name}”, so it won't remove it` | INSTALL-M1 |
| `.manifestUnsupported` | `the list of fonts Font Playground installed was written by a newer version` | |
| `.fileSystem(_, underlying)` | the underlying error's `localizedDescription` | build.py:265 |
| `CatalogIssue.noAccess(folder)` | `Font Playground has no access to “{folder}”.` | TOOLING-M3 |
| `CatalogError.engineUnavailable(message)` | `Font Playground couldn't start its font reader: {message}` | |
| `RenderError.fileMissing(path)` / `.unreadable` / `.faceNotFound` / `.builtFontInvalid` | `The font file is missing.` / `macOS can't read this font file.` / `This font is no longer in its file.` / `The built font file is not a single font.` | |
| `FontBookError.fontBookMissing` | `Font Book isn't available on this Mac.` | |
| menu item / picker action | `Get More Fonts…` | CATALOG-5 verifier (title case per macOS menus) |
| `DownloadConfirmation.title` / `.message` | `Download “{family}” from Apple?` / `macOS will download this font and make it available in all your apps.` (buttons `Download`, `Cancel`) | CATALOG-5 |
| download progress / done | `Downloading “{family}”… {percent}%` / `“{family}” is ready.` (UI text, WP-503) | |
| `DownloadError.failed(font, message)` / `.notOffered(font)` / `.alreadyInstalled(font)` | `Couldn't download “{family}”: {message}` / `Apple doesn't offer “{family}” for this version of macOS.` / `“{family}” is already installed.` | |

---

## WP-401: Font discovery + catalog store (CoreText, folders, cache, dedupe, hidden, change observation)

**Goal:** Deliver the visible, deduplicated `[FaceRecord]` of every font on the Mac and in the user's extra folders: fast when warm, scanned out of process when cold, and refreshed on its own when fonts change.
**Depends on:** WP-204, WP-301, WP-402, WP-403 · **Env:** macos · **Size:** L · **Closes findings:** CATALOG-1, CATALOG-2, CATALOG-6, CATALOG-7, CATALOG-9, CATALOG-10, CATALOG-M1, CATALOG-M3, CRIT-5, CRIT-6, CRIT-9, NATIVE-9, TOOLING-M5, INSTALL-6

> Also uses `SystemFontRegistry` (S2, WP-403) and the S6 test support (WP-402/403). Both are in wave 6, which lands before this wave-7 WP. If either is missing on `main`, create it exactly as S2/S6 describe. See the plan note in the PR. It also implements the catalog half of `INSTALL-6` (incremental update after the app's own install).

### Scope
- In: `FolderWalker`, `FontDiscovery`, `CatalogCache`, `CatalogBuilder` (filter, annotate, dedupe, count), `CatalogStore` (actor, `FontCataloging`), `FontChangeObserver`, `CatalogReport`, and the `fpmac-harness catalog` command (M3 debug harness).
- Out:
  - Reading faces: `fpengine scan` (WP-106/108/201), reached through `EngineRunning` (WP-204).
  - Persisting extra folders in `UserDefaults` and the Add Font Folder… panel (WP-501).
  - Picker presentation, the footer wording and the show-hidden and show-disabled toggles (WP-503).
  - Resolving recipes by PostScript name (WP-305, `FaceCatalog`).
  - Suggestions and `suspicious_coverage` (WP-304).
  - Downloads (WP-404).
  - FSEvents watching of extra folders (backlog; Rescan Fonts covers it).
  - Named instances as separate faces (`CATALOG-12`, not scheduled).

### Touched paths
- `Packages/FontPlaygroundMacKit/Sources/FPMacServices/Catalog/CatalogModels.swift` (new)
- `…/Catalog/FontCataloging.swift` (new)
- `…/Catalog/FolderWalker.swift` (new)
- `…/Catalog/FontDiscovery.swift` (new)
- `…/Catalog/CatalogCache.swift` (new)
- `…/Catalog/CatalogBuilder.swift` (new)
- `…/Catalog/CatalogStore.swift` (new)
- `…/Catalog/FontChangeObserver.swift` (new)
- `…/Catalog/CatalogReport.swift` (new)
- `Packages/FontPlaygroundMacKit/Sources/FPMacHarness/main.swift` (new; executable product `fpmac-harness`)
- `Packages/FontPlaygroundMacKit/Package.swift` (edit: add the executable target and product `fpmac-harness`, depending on `FPMacServices` and `FPEngineClient`)
- `Packages/FontPlaygroundMacKit/Tests/FPMacServicesTests/Catalog/*.swift` (new; files named in the ACs)
- `Packages/FontPlaygroundMacKit/Tests/FPMacServicesTests/Support/FakeEngine.swift`, `FakeRegistry.swift` (with `PrefixFilteredRegistry`) (new)
- Only if still missing on `main` (they belong to WP-402/403): `Sources/FPMacServices/Support/MacServicesConstants.swift` (S1), `Sources/FPMacServices/Registry/SystemFontRegistry.swift` (S2), `TestFixtures/make_fonts.py` and `Tests/FPMacServicesTests/Support/FixtureFonts.swift` (S6)

### Design

#### 1. Models (`CatalogModels.swift`)

```swift
public struct FaceAnnotation: Hashable, Sendable {
    public var origin: FaceOrigin            // S3
    public var hiddenFromMenus: Bool         // PS name not in menuVisiblePostScriptNames(); false for .extraFolder or nil PS
    public var disabledInFontBook: Bool      // CRIT-9
}
public enum SkipReason: String, Hashable, Sendable, Codable {
    case appleDouble = "apple_double"            // "._name.ttf" (CRIT-5)
    case unsupportedFormat = "unsupported_format"// .dfont, Type 1, WOFF… or not sfnt magic (CATALOG-10)
    case hiddenFile = "hidden_file"              // ".name.ttf"
}
public enum CatalogIssue: Hashable, Sendable {
    case unreadable(path: String, code: String, message: String)   // helper file_error, or code "helper_failed"
    case skipped(path: String, reason: SkipReason)
    case duplicate(kept: FaceKey, dropped: FaceKey, postscriptName: String)
    case noAccess(folder: String)                                   // EACCES/EPERM (TOOLING-M3)
    case folderMissing(folder: String)                              // not absolute, missing, or not a directory
    case folderUnreadable(folder: String, message: String)
    case disabledUnlocated(postscriptName: String)                  // disabled in Font Book, file not revealed
}
public struct CatalogCounts: Hashable, Sendable {
    public var files = 0, faces = 0, hiddenFaces = 0, duplicateFaces = 0, unreadableFiles = 0, skippedFiles = 0
    public var disabledFaces = 0, disabledUnlocated = 0, inaccessibleFolders = 0
}
public enum RefreshMode: Sendable, Equatable { case incremental, full }  // full: ignore the cache (re-read every file)
public struct CatalogProgress: Hashable, Sendable {
    public var filesDone: Int, filesTotal: Int
    public var fraction: Double { filesTotal == 0 ? 1 : Double(filesDone) / Double(filesTotal) }
}
public enum CatalogActivity: Hashable, Sendable { case idle, refreshing(CatalogProgress) }
public struct CatalogSnapshot: Sendable {
    public var generation: Int                              // +1 per publish
    public var faces: [FaceRecord]                          // visible, deduped, sorted (§5)
    public var annotations: [FaceKey: FaceAnnotation]       // one per face in `faces`
    public var counts: CatalogCounts
    public var issues: [CatalogIssue]                       // sorted by path/folder for determinism
    public var isComplete: Bool                             // false while refreshing or after a cancelled refresh
    public var activity: CatalogActivity
    public func face(postscriptName: String) -> FaceRecord? // first in `faces` order
    public static let empty: CatalogSnapshot
}
public enum CatalogError: Error, Equatable, LocalizedError {
    case engineUnavailable(String)       // the helper could not be started at all
    public var englishText: String       // S8
}
```

WP-501 maps this to ui-editing's `CatalogStatus`:

- `isScanning` = activity is `.refreshing`;
- `done`/`total` = progress;
- `faceCount` = `counts.faces`;
- `unreadable` = the `.unreadable` issues;
- `hiddenCount`, `duplicateCount` = the counts.

#### 2. Protocol (`FontCataloging.swift`; contracts §7)

```swift
public protocol FontCataloging: Sendable {
    func currentSnapshot() async -> CatalogSnapshot
    func snapshots() async -> AsyncStream<CatalogSnapshot>     // yields the current snapshot at once, then every publish
    func refresh(_ mode: RefreshMode) async throws -> CatalogSnapshot
    func cancelRefresh() async
    func extraFolders() async -> [URL]
    func setExtraFolders(_ folders: [URL]) async                             // stored; used by the next refresh (starts none)
    func noteInstalled(_ fileURL: URL) async throws -> CatalogSnapshot       // INSTALL-6: this app installed a file
    func noteRemoved(_ fileURL: URL) async -> CatalogSnapshot                // INSTALL-6: this app removed a file
    func startObservingSystemChanges() async                                 // idempotent; the app calls it once at launch
    func stopObservingSystemChanges() async
}

public struct CatalogConfiguration: Sendable {
    public var cacheDirectory: URL
    public var standardFolders: [URL]            // walked recursively (F1)
    public var userFontsFolder: URL              // for origin .user
    public var homeDirectory: URL                // for the Containers exclusions
    public var maxConcurrentScans: Int           // default min(3, max(1, activeProcessorCount / 4))
    public var batchMaxFiles: Int = 48
    public var batchMaxBytes: Int64 = 256 << 20
    public var changeDebounce: Duration = .milliseconds(1500)
    public var publishInterval: Duration = .milliseconds(300)   // picker.py:33 REFRESH_MS
    public init(cacheDirectory: URL, standardFolders: [URL] = [], userFontsFolder: URL, homeDirectory: URL,
                maxConcurrentScans: Int? = nil)                 // nil → the default above; tests set the rest as vars
    public static func standard() -> CatalogConfiguration       // S1 defaults; used only by the app and the harness
}

public actor CatalogStore: FontCataloging {
    public init(engine: any EngineRunning, registry: any SystemFontRegistry = CoreTextFontRegistry(),
                configuration: CatalogConfiguration, notificationCenters: [NotificationCenter]? = nil)
    // nil centers = [NotificationCenter.default, DistributedNotificationCenter.default()] (header CTFontManager.h:563-571)
}
```

`setExtraFolders` only stores the list (in the given order; later duplicates by identity are removed, and folders whose `stat` fails are kept so the next refresh reports them). The caller then calls `refresh(.incremental)`, as ui-shell.md's `addFontFolders`/`removeFontFolder` and launch sequence do, so one user action costs one refresh. `CatalogStore.init` does not observe anything; `startObservingSystemChanges()` does (§9).

`EngineRunning` comes from helper.md (WP-204): `hello() async throws -> EngineHello` and `scan(files: [String]) -> AsyncThrowingStream<ScanEvent, any Error>`, with `ScanEvent` cases `.progress(EngineProgress)`, `.face(FaceRecord)`, `.fileError(ScanFileError)` (`path`, `code: FileErrorCode`, `message`) and `.finished(ScanSummary)` (the protocol's `face`, `file_error`, `progress` and `result` events, contracts §5). A `.fileError` becomes `.unreadable(path:, code: code.rawValue, message:)`. Paths are sent exactly as discovered. The helper never rewrites them (contracts §2). Real engines for tests and the harness are built with `EngineClient(configuration: EngineConfiguration(launch: try EngineLaunch.resolve(environment: ["FP_ENGINE_PYTHON": python], bundleURL: nil), temporaryDirectory: <a temp dir>))`.

#### 3. `FolderWalker` (`CRIT-5`, `CRIT-3` item 2)

```swift
struct FolderWalker {
    init(homeDirectory: URL, maxDepth: Int = 32)
    /// `reportMissingRoot`: false for the standard folders (a Mac without ~/Library/Fonts is normal), true for extra folders.
    func walk(_ root: URL, reportMissingRoot: Bool) -> WalkResult
}
struct WalkResult { var files: [URL]; var skipped: [(url: URL, reason: SkipReason)]; var issues: [CatalogIssue] }
```

Rules, applied while descending (use POSIX `opendir`/`readdir` plus `stat`, because Foundation directory listings hide AppleDouble sidecars that must be counted; `files` are in directory-listing order sorted by name bytes, depth first, so the result is deterministic):

1. A file whose name starts with `._` → skipped `.appleDouble`, whatever its extension. It is never a failure (CRIT-5).
2. Any other name starting with `.`:
   - a directory is pruned (this covers `.Trashes`, `.Trash`, `.fseventsd`, `.Spotlight-V100`, `.TemporaryItems`, `.DocumentRevisions-V100`);
   - a file with a font extension → skipped `.hiddenFile`;
   - any other file is ignored.
3. Directory named `__MACOSX` → pruned.
4. Package directories (extension in `app, bundle, framework, photoslibrary, plugin, kext, xpc, appex`, or `URLResourceValues.isPackage == true`) are pruned unless the directory is the root itself (CRIT-3: Office `DFonts`).
5. `<home>/Library/Containers` and `<home>/Library/Group Containers` are never entered (TCC prompt, CRIT-5).
6. Symlinked directories are followed, but each directory identity `(st_dev, st_ino)` is entered once per walk (cycle protection). Symlinked files are followed too (identity dedupe in §4 removes duplicates). The path keeps the symlink spelling (contracts §2). Maximum depth is 32 below the root; a directory beyond it is not entered and is reported once as `.folderUnreadable(folder:message:)` (review 2026-10-05 L3). Broken links are ignored. Finder alias files are not resolved: one named `*.ttf` fails the sniff in §4 and is skipped as `.unsupportedFormat`.
7. Files by extension (case-insensitive):
   - `fontExtensions` → candidate;
   - `unsupportedFontExtensions` → skipped `.unsupportedFormat`;
   - anything else → ignored (not a font).
8. `EACCES`/`EPERM` on a directory (the root or below it) → issue `.noAccess(folder)` and the walk goes on. Any other error → `.folderUnreadable(folder, strerror text)`. A root that is not absolute, is missing, or is not a directory → `.folderMissing` when `reportMissingRoot`, else nothing.

#### 4. `FontDiscovery` (`CATALOG-1`, `CATALOG-9`, `CATALOG-10`, F1)

`func discover(extraFolders: [URL]) -> DiscoveryResult` gathers candidates in this order. The first path seen for an identity wins, so CoreText's spelling is preferred:

1. `registry.registeredFontFiles()` (keeps `postscriptNames` per file).
2. Paths of `registry.registeredFaces(includeDisabled: true)` with `enabled == false` and `path != nil` (CRIT-9).
3. `FolderWalker` over each `standardFolders` entry, in order (`reportMissingRoot: false`).
4. `FolderWalker` over each extra folder, in the user's order (`reportMissingRoot: true`).

Registry paths (sources 1 and 2) are not filtered by extension: CoreText already accepted them. Their identities also give `isRegistered` for S3.

For each candidate:

- `stat`. It must be a regular file. A candidate that fails is reported once, never dropped silently. It may have vanished, lost access, or stopped being a file between enumeration and this call. The report is `.unreadable(path, code: "not_found", "File not found.")` for `ENOENT`, or `code: "io_error"` with "Not a regular file." or the `strerror` text. The issue goes into the discovery issues and counts in `counts.unreadableFiles` (`registeredPathsThatFailDiscoveryAreReported`).
- Dedupe by identity (S4, `CATALOG-9`). It must survive NFC/NFD spellings and symlinked folders.
- Assign the origin (S3, `FaceOrigin.classify`). A file that is both CoreText-registered and inside an extra folder is `.activated`.
- Record `DiscoveredFile(path, origin, stamp(size, mtime, dev, ino), registeredPostscriptNames)`, where `mtime` = `st_mtimespec` as `Double(tv_sec) + Double(tv_nsec) / 1e9`.

Sniffing (only for files that are not cache hits, §6): read the first 4 bytes big-endian. A value not in `sfntMagics` (including a file shorter than 4 bytes) → skipped `.unsupportedFormat`, never sent to the helper, never counted as unreadable (`CATALOG-10`: `.dfont` suitcases, extensionless Type 1). A file that cannot be opened or read gets no format verdict: it becomes a folder issue `.unreadable(path:code:message:)`, `not_found` for `ENOENT` and `io_error` with the `strerror` text otherwise, the same shape as a failed discovery `stat` (review 2026-10-05 M2). Skipped files are not cached, so they are sniffed again on every refresh (4 bytes each).

```swift
struct DiscoveredFile: Hashable, Sendable {
    var path: String                        // first spelling seen
    var origin: FaceOrigin
    var stamp: DiscoveredFileStamp          // size: Int64, mtime: Double, device: UInt64, inode: UInt64
    var registeredPostscriptNames: [String] // from RegisteredFontFile (all spellings of this identity merged); [] if unregistered
}
struct DiscoveryResult { var files: [DiscoveredFile]; var skipped: [(path: String, reason: SkipReason)]; var issues: [CatalogIssue]
                         var registeredFaces: [RegisteredFaceInfo]; var menuVisible: Set<String> }
```

#### 5. `CatalogBuilder` (pure; `CATALOG-2`, `CATALOG-M1`, `CRIT-9`)

```swift
enum CatalogBuilder {
    static func build(files: [DiscoveredFile], faces: [String: [FaceRecord]],          // keyed by DiscoveredFile.path
                      errors: [String: (code: String, message: String)],
                      skipped: [(path: String, reason: SkipReason)], folderIssues: [CatalogIssue],
                      menuVisible: Set<String>,
                      registeredFaces: [RegisteredFaceInfo],                              // registeredFaces(includeDisabled: true)
                      generation: Int, isComplete: Bool, activity: CatalogActivity) -> CatalogSnapshot
}
```

Faces of a file that is not in `files` are ignored. Path equality between `RegisteredFaceInfo.path` and a face's path is decided by identity (S4), because CoreText may spell a path differently (F13); precompute a `[identity: DiscoveredFile]` map once.

1. **Hidden.** Drop every face with `hidden == true` (the engine's rule: family or PostScript name starts with `.`, contracts §3) and add 1 to `hiddenFaces`. This drops `.LastResort` and `System Font`/`.SFNS-*` (`CATALOG-2`).
2. **Annotate** each remaining face:
   - `origin` = its file's origin;
   - `hiddenFromMenus` = `origin != .extraFolder && ps != nil && !menuVisible.contains(ps)`;
   - `disabledInFontBook`: the face's PS equals the PS of a `RegisteredFaceInfo` with `enabled == false`, and either that info's `path` is the face's file (identity), or the info has no path and the face's file does not list that PS in `registeredPostscriptNames`.
   Count `disabledFaces`. Each disabled PS name that matched no face gives `.disabledUnlocated(ps)` and adds to `disabledUnlocated`.
3. **Dedupe by PostScript name** (`CATALOG-M1`). Group faces with a non-nil `postscriptName` (exact string). Faces with nil PS are never deduped. The winner is the first by this order, each rule a tie-breaker for the one before:
   1. the file lists the PS in `registeredPostscriptNames` (CoreText has it registered from that file);
   2. higher `priority` of the `RegisteredFaceInfo` with the same PS and path, where missing = 0 (F3: 60000 AssetsV2 beats 10000 PrivateFrameworks);
   3. enabled before disabled;
   4. path not under `/System/Library/PrivateFrameworks/`;
   5. origin rank: `system`/`systemAsset` 0, `local` 1, `user` 2, `activated` 3, `extraFolder` 4;
   6. path in byte order, then smaller `index`.

   Each loser adds 1 to `duplicateFaces` and gives `.duplicate(kept:dropped:postscriptName:)`.
4. **Sort** `faces` by:
   1. `family`, compared with `compare(_:options: [.caseInsensitive, .numeric], range: nil, locale: nil)` (locale-independent, so tests are deterministic);
   2. `weightClass`;
   3. `italic` (false first);
   4. `style`;
   5. `path`;
   6. `index`.
5. **Counts:**
   - `faces` = `faces.count` after steps 1–3;
   - `files` = discovered font files (`files.count`, skipped files excluded);
   - `unreadableFiles` = files with an error;
   - `skippedFiles` = skipped count;
   - `inaccessibleFolders` = `.noAccess` issues.

#### 6. `CatalogCache` (`CATALOG-M3`, `CRIT-6`, `CATALOG-7`, TOOLING-M5)

The file is `<cacheDirectory>/catalog-v<N>.json` with `CatalogCache.schemaVersion = N = 1`. N changes only when this file's **layout** changes. Engine changes that alter the `FaceRecord` for unchanged file bytes are caught by `face_reader_version` instead: the engine's `READER_VERSION` (engine-metadata.md §S3), which `fpengine hello` reports (helper.md WP-201, `spec/protocol/hello.schema.json`) and which the store reads once per store lifetime with `engine.hello()` (Swift: `EngineHello.faceReaderVersion`, JSON `face_reader_version`, defined by helper.md WP-204; a helper that doesn't send it decodes as 0). Format:

```json
{
  "format": "fontplayground-catalog-cache",
  "schema": 1,
  "face_reader_version": 5,
  "written_at": "2026-09-29T12:00:00Z",
  "entries": {
    "/System/Library/Fonts/Helvetica.ttc": {
      "size": 5123456, "mtime": 1727600000.123456, "device": 16777232, "inode": 1234567,
      "faces": [ { "path": "/System/Library/Fonts/Helvetica.ttc", "index": 0, "...": "FaceRecord, contracts §3" } ],
      "error": null
    },
    "/Users/<user>/Fonts/broken.ttf": {
      "size": 10, "mtime": 1.0, "device": 1, "inode": 2, "faces": [], "error": {"code": "io_error", "message": "…"}
    }
  }
}
```

- **Load.**
  - Any `catalog-v*.json` other than the current N is deleted.
  - Unreadable JSON, a wrong `format`, a different `schema`, or a `face_reader_version` different from the engine's → an empty cache, which is not an error. The next refresh is cold, and no file is reported unreadable because of it (port of test_catalog.py:75-98). This is what makes "the first launch after an update rescans only what changed" safe (plan §6): an update that changes the reader rescans everything once, any other update rescans nothing.
  - An entry that doesn't decode (for example a `FaceRecord` missing a required key) is dropped and treated as a miss (test_catalog.py:101-134).
- **Hit** when an entry exists for the path string, `size` is equal, and `|mtime - entry.mtime| ≤ 1e-6` (cache.py:75). `device` and `inode` are stored for diagnostics only; they are not part of the hit test (network volumes may renumber inodes). The helper is not called. Cached errors are hits too, so a broken file is not re-read on every launch (the CATALOG-8 note). Entries with code `helper_failed` or `no_faces` are never written.
- An entry holds **every** face the helper returned for the file, hidden ones included, so a file with hidden faces is not re-read (CATALOG-2 recommendation). The builder filters (§5).
- **Store** the discovery stamp. If a helper record's `size` differs from the stamp, the file changed while it was being read: show the faces, but don't write the entry.
- **Save** atomically: write `.<name>.<UUID>.tmp` in the same folder, `FileHandle.synchronize()`, `rename(2)`; on any error remove the temp file and keep the old cache file. `CatalogCache` has an internal test hook `beforeRename: (@Sendable (URL) throws -> Void)?`, run between the fsync and the rename (AC-401-9). Save after every completed or cancelled refresh and after `noteInstalled`/`noteRemoved`. A failed save is logged and never fails the refresh.
- **Prune** (`CRIT-6`): after a refresh that ran to completion, keep only the entries for the paths discovered in that refresh. A cancelled refresh saves its new entries and prunes nothing.
- `FaceRecord` round-trips through JSON unchanged (core.md §WP-301). Encode with a plain `JSONEncoder` (`.sortedKeys` not required).

#### 7. Refresh algorithm (`CatalogStore.refresh`)

1. **Coalescing** (port of app.py:302-340). Only one refresh runs at a time. A call that arrives while one runs is queued. All queued calls collapse into **one** follow-up refresh, which is `.full` if any queued call was `.full`. Every caller gets the snapshot of the first refresh that started after its call. Cancelling a caller's `Task` only ends that caller's wait (it throws `CancellationError`); the refresh goes on for the others. `cancelRefresh()` stops the running refresh **and** discards the queued follow-up; every caller waiting on either throws `CancellationError`. `cancelRefresh()` with nothing running does nothing.
2. **Reader version, fingerprint and discover.** If this store has not done so yet, `try await engine.hello()` and keep `faceReaderVersion`; then load the cache (§6). A `hello()` failure keeps the previous snapshot published (with `activity = .idle`), saves nothing, and throws `CatalogError.engineUnavailable(String(describing: error))`. Compute the change fingerprint (§9) and keep it; it becomes "the fingerprint of the last refresh" when this refresh completes. Then discover (§4). Folder issues go into the snapshot. Publish the previous faces with `activity = .refreshing(0/total)`, where `total` = the number of misses (step 3).
3. **Partition** into hits and misses. With `.full`, everything is a miss. Sniff the misses (§4).
4. **Batch** the misses in discovery order. A batch ends at `batchMaxFiles` files or when adding a file would exceed `batchMaxBytes`. A file larger than the byte cap is a batch on its own.
5. **Scan** the batches with at most `maxConcurrentScans` concurrent `engine.scan(files:)` streams (a `withThrowingTaskGroup` with a sliding window).
   - Collect `face` events per path and `file_error` events per path.
   - When a stream finishes, merge its files into the cache and the working set. A file that got neither faces nor an error → `.unreadable(code: "no_faces")`.
   - Progress counts files done over the misses.
   - While scanning, publish snapshots at most every `publishInterval`, with `isComplete = false`.
6. **Helper failure.**
   - A stream that throws `EngineError.helperNotFound`, `.launchFailed` or `.incompatibleHelper` means the helper can't run at all (it ran for `hello()` a moment ago, but the runtime may have been removed since): cancel the other streams, keep the previous snapshot published (with `activity = .idle`), save nothing, and throw `CatalogError.engineUnavailable(String(describing: error))`.
   - A batch whose stream throws is bisected: each half is rescanned, recursively, down to single files. Faces and errors already received from the failed stream are kept; the halves rescan only the files that got neither. A single file whose scan throws gives `.unreadable(path, "helper_failed", message)` and is not cached.
7. **Build** the snapshot (§5) with `isComplete = true` and `activity = .idle`. Publish it, save the cache (§6), and return it.
8. **Cancel.** Cancel the task group. EngineRunning's cancellation sends SIGTERM (ADR-0003). Save completed entries without pruning. Publish a snapshot built from the previous faces plus the completed files, with `isComplete = false` and `.idle`. That snapshot takes the menu visibility, registered faces, skips and folder issues from this refresh's discovery, which already describe the system (`cancelledFirstScanKeepsTheCurrentDiscovery`), and throw `CancellationError` to every waiting caller (step 1). The fingerprint of the last refresh is not updated.

No scan process is started when there are no misses (the warm path); the only helper run is the one `hello()` per store lifetime. **Memory:** every scan batch runs in a helper process that exits (ADR-0003). The app process keeps only the `FaceRecord`s, not the 1,363 MB that the in-process Python scan retained (F11, ENGINE-9 verifier).

#### 8. Incremental updates (`INSTALL-6` verifier)

- `noteInstalled(url)`: standardize the path; `stat` it (a failure throws `CocoaError(.fileNoSuchFile)`); set the origin with S3 (the user folder check by identity; `isRegistered` from the registered identities kept from the last refresh); on a cache miss, `engine.scan(files: [path])` (a thrown error or `file_error` becomes an `.unreadable` issue, as in §7). Add the file to the working set (replacing any entry with the same identity), add its faces' PostScript names to the stored `menuVisible` set (fontd will activate a file in the user folder, so it must not be marked hidden-from-menus), rebuild, publish, save without pruning. **No discovery or registry call.** If a refresh is running, wait for it to finish first (the note is applied to its result).
- `noteRemoved(url)`: remove the file (matched by path string, else by the identity recorded in its stamp) from the working set and the cache, rebuild, publish, save. No scan call.

#### 9. Change observation (`CATALOG-6`; do not port Qt's app-font signal, INSTALL-6 verifier)

`FontChangeObserver` (`final class`, `@unchecked Sendable`, tokens under a lock) adds an observer for `Notification.Name(kCTFontManagerRegisteredFontsChangedNotification as String)` on every configured center: by default the local center for process scope and the distributed center for session/persistent scope and fontd activity (F9). The callback calls `store.systemFontsChanged()`, which works like this:

- It increments a change generation.
- It sleeps `changeDebounce`.
- If no newer change arrived, it computes a **fingerprint**: SHA-256 (CryptoKit) over the UTF-8 of these lines, joined with `\n`: the sorted `path|size|mtime` of every `registeredFontFiles()` path (`-1|-1` when `stat` fails), then `root|mtime` of every standard-folder and extra-folder root, then the sorted PostScript names of `registeredFaces(includeDisabled: true)` entries with `enabled == false` (so enabling or disabling a font in Font Book counts as a change, CRIT-9).
- It runs `refresh(.incremental)` only if the fingerprint differs from the one kept by the last completed refresh (§7 step 2). Before the first completed refresh, every change runs a refresh. An error thrown by that refresh is logged and dropped (the published snapshot already tells the UI what happened).

The store never observes `NSFontSetChangedNotification` or any per-process font-loading signal. The renderer never registers fonts, so it cannot trigger a refresh storm (§AC-401-19).

#### 10. Harness (`fpmac-harness catalog`) and `CatalogReport`

- `CatalogReport.lines(for snapshot:) -> [String]`: one line per face, `family\tstyle\tpostscript\torigin\tflags\tpath#index`. `flags` is a comma list from `hidden-from-menus`, `disabled`, `forged`. The last line is a summary: `faces=… files=… hidden=… duplicates=… unreadable=… skipped=… disabled=…`.
- `CatalogReport.check(_ snapshot:, menuVisible:) -> [String]` returns the problems:
  - a face whose family or PS starts with `.`;
  - `PingFangSC-Regular` menu-visible but no face with that PS;
  - any PS name that appears twice in `faces`;
  - a `PingFang*` face whose path is under `/System/Library/PrivateFrameworks/` while the same PS exists in AssetsV2.
- `main.swift`: `fpmac-harness catalog [--extra <dir>]… [--cache-dir <dir>] [--python <path>] [--check]` (WP-404 adds `--watch` and the `fontbook` / `downloadable` commands). Arguments are parsed by hand (no third-party packages, AGENTS rule 11); an unknown argument prints a usage line to stderr and exits 2.
  - The engine is the real `EngineClient` (built as in §2) with `--python <path>`, else `FP_ENGINE_PYTHON`, and a fresh temporary `TMPDIR`; with neither, print `Set FP_ENGINE_PYTHON or pass --python.` to stderr and exit 2.
  - It uses `CatalogConfiguration.standard()` with `cacheDirectory` replaced as below, `CoreTextFontRegistry()`, and runs one `refresh(.incremental)`.
  - The default cache dir is a fresh temporary folder, never the real Caches.
  - It prints the report, then `elapsed=<seconds, 2 decimals>`, then with `--check` one `problem: …` line per problem; it exits 1 if `--check` finds problems or the refresh throws, else 0.

### Acceptance criteria

All tests are in `Packages/FontPlaygroundMacKit/Tests/FPMacServicesTests/Catalog/`. Unless stated otherwise they use:

- `FakeEngine` (`Tests/FPMacServicesTests/Support/FakeEngine.swift`, an `actor` conforming to `EngineRunning`): `hello()` returns an `EngineHello` decoded from a JSON literal (`protocol` 1, `face_reader_version` = `readerVersion`, default 1) unless `helloError` is set, and counts its calls; `scan(files:)` yields, per path in the given order, the scripted `[FaceRecord]` as `.face` events or a scripted `.fileError`, each followed by a `.progress`, then `.finished`; a path with no script yields one face `FaceRecord(path:, family: "Stub <file name>", coverage: CodepointSet(ranges: [0x61...0x63]), postscriptName: "Stub-<file stem>")`. Options: `delayPerBatch: Duration`, `throwWhenBatchContains: Set<String>` (throws `FakeEngine.Failure` after yielding the faces of the paths before it), `throwAtStart: (any Error)?` (thrown before any event), and a gate (`blockNextScan()` / `release()`) for coalescing and cancellation tests. It records every `scan(files:)` call, the peak number of concurrent calls and whether each stream saw cancellation. `forge(_:)` finishes throwing `FakeEngine.Failure`.
- `FakeRegistry` (`Tests/FPMacServicesTests/Support/FakeRegistry.swift`, a `final class` with lock-protected scripted `files`, `menuVisible`, `faces`, and a call log per method) and `PrefixFilteredRegistry` (wraps `CoreTextFontRegistry` and keeps only paths under a given folder, compared by ancestor identity).
- Temporary folders (`TestEnv.temporaryDirectory()`), and a fresh temporary `cacheDirectory` per test.
- **Stub font files**: tests that use `FakeEngine` create files whose bytes are `00 01 00 00` followed by the UTF-8 of the file name (so sniffing passes and sizes differ; the fake engine never reads them). Real fixture fonts (S6) are used only where an AC says so.

- **AC-401-1** (CATALOG-1) A file listed only by the fake registry, in a temp folder outside every standard or extra folder, is discovered with origin `.activated` and scanned. A file found by both the registry and the walk appears once, with the registry's path. (`FontDiscoveryTests.catalog1CoreTextFilesOutsideTheFoldersAreDiscovered`)
- **AC-401-2** The origin classifier returns the S3 table for these paths:
  - `/System/Library/AssetsV2/com_apple_MobileAsset_Font8/x.asset/AssetData/PingFang.ttc` → `.systemAsset`;
  - `/System/Library/Fonts/Helvetica.ttc` and `/System/Library/PrivateFrameworks/FontServices.framework/Resources/Reserved/PingFangUI.ttc` → `.system`;
  - `/Library/Fonts/A.ttf` → `.local`;
  - a file inside the injected user folder, reached through a symlinked spelling of that folder → `.user`;
  - registered elsewhere → `.activated`;
  - other → `.extraFolder`.

  (`FontDiscoveryTests.originClassificationFollowsTheTable`)
- **AC-401-3** (CRIT-5) In a temp tree, the walker:
  - skips and counts `._A.ttf` and `sub/._B.ttf` as `.appleDouble`;
  - ignores `__MACOSX/._C.ttf` and `.Trashes/501/D.ttf`;
  - does not enter `Pkg.app/Contents/Resources/E.ttf` (but finds it when `Pkg.app` is itself the root);
  - finds `linked/F.ttf` through a symlinked folder;
  - terminates with a symlink loop `loop -> ..`;
  - never enters `<home>/Library/Containers/x/G.ttf` (home injected);
  - ignores `notes.txt`.

  (`FolderWalkerTests.crit5MacFileSystemConventions`) The port of test_catalog.py:28-32 (a font in a subfolder is found, `junk.fon` is not a candidate) passes. (`FolderWalkerTests.findsFontsInSubfoldersOnly`)
- **AC-401-4** (CATALOG-9) The same stub file reached through its real folder, a symlinked folder, a hard link in another folder, and the NFD vs NFC spelling of a folder named `ゴシック` (NFC ≠ NFD because of the voiced mark; the NFD spelling is passed as an extra folder while the NFC one is a standard folder) gives exactly one `DiscoveredFile`, with the first path seen. Two different files with identical bytes in one folder give two. (`FontDiscoveryTests.catalog9DedupeByFileIdentity`)
- **AC-401-5** (CATALOG-10) `A.dfont`, `B.pfb` and an extensionless registry-listed file with Type 1 magic `%!PS` are reported as `.skipped(.unsupportedFormat)` and counted in `skippedFiles`. They are never passed to `scan(files:)`, and `unreadableFiles` stays 0. A `.ttf` whose first bytes are `not a font` and a 2-byte `.ttf` are `.unsupportedFormat` as well. (`FontDiscoveryTests.catalog10UnsupportedFormatsAreCountedNotFailed`)
- **AC-401-6** (cache format; ports test_catalog.py:75-98 and :101-134) After a refresh:
  - `catalog-v1.json` exists in the injected cache dir, with `format`, `schema: 1`, `face_reader_version` equal to the fake engine's hello value, and `entries` keyed by path, each with `size, mtime, device, inode, faces, error`.
  - A new store whose fake engine reports a different `face_reader_version` rescans every file (and reports none unreadable).
  - A file with `schema: 2`, a bare-dict legacy layout, invalid JSON, or an entry with an undecodable face is discarded (per file or per entry, as in §6). The next refresh re-reads the affected file with no `.unreadable` issue.
  - `catalog-v0.json` next to it is deleted.

  (`CatalogCacheTests.cacheFileFormatAndRejection`)
- **AC-401-7** (port test_catalog.py:45-64) A second refresh with nothing changed makes **zero** `scan` calls and returns faces equal to the first; so does a refresh by a **new** `CatalogStore` on the same cache directory. After `utimes` moves one file's mtime by +100 s, only that file is scanned. A cached `file_error` is not re-read until its file changes. `.full` rescans every file. (`CatalogCacheTests.cacheHitUntilSizeOrMtimeChanges`)
- **AC-401-8** (CRIT-6, CATALOG-7) A stub file in an extra folder at `assets/aaaa.asset/AssetData/X.ttc` (fake face PS `X-Regular`) is refreshed, then moved to `assets/bbbb.asset/AssetData/X.ttc` and refreshed again. The saved cache then holds only the new path, and `snapshot.face(postscriptName: "X-Regular")` returns the face at the new path. Separately, a refresh cancelled with `cancelRefresh()` after its first batch leaves every old entry in the saved cache. (`CatalogCacheTests.catalog7Crit6PruneVanishedPathsAfterCompleteRefreshOnly`)
- **AC-401-9** (CATALOG-M3, TOOLING-M5) `CatalogConfiguration.standard().cacheDirectory.path` ends with `/Library/Caches/io.github.kciceblue.fontplayground` (the value is only compared, never written). `CatalogConfiguration.standard()` creates no folder. A `CatalogCache` save whose `beforeRename` hook throws leaves the previous `catalog-v1.json` byte-identical and no `*.tmp` file in the folder; after a normal save no `*.tmp` remains either. (`CatalogCacheTests.catalogM3CacheLivesInCachesAndIsWrittenAtomically`)
- **AC-401-10** (CATALOG-2) The fake engine returns `.LastResort` (family `.LastResort`, `hidden: true`), `System Font` with PS `.SFNS-Regular` (`hidden: true`) and `Helvetica`. The snapshot holds only Helvetica, `counts.hiddenFaces == 2`, and the saved cache entry still holds all three faces. (`CatalogBuilderTests.catalog2HiddenFacesAreDroppedAndCounted`)
- **AC-401-11** (CATALOG-M1) Table-driven tie-break over pairs of faces that share a PS name, one row per rule 1–6 of §5.3. Row 2 uses priorities 60000 at `/System/Library/AssetsV2/…/PingFang.ttc` vs 10000 at `/System/Library/PrivateFrameworks/…/PingFangUI.ttc` → AssetsV2 kept. Each loser appears in `issues` as `.duplicate`, and `counts.duplicateFaces` equals the number of losers. Faces with nil PS are never merged. (`CatalogBuilderTests.catalogM1DedupeTieBreak`)
- **AC-401-12** A face whose PS is not in `menuVisible` is annotated `hiddenFromMenus = true`. The same face from an extra folder is false. (`CatalogBuilderTests.facesHiddenFromMenusAreMarkedNotDropped`)
- **AC-401-13** (CRIT-9) With the fake registry:
  - a disabled `RegisteredFaceInfo` that has a path makes that file discovered, and its face is annotated `disabledInFontBook = true` and counted;
  - a disabled info without a path, whose PS exists only in a walked, unregistered `~/Library/Fonts`-like temp folder, marks that face;
  - a disabled PS that matches no face gives `.disabledUnlocated` and is counted.

  (`CatalogBuilderTests.crit9FontBookDisabledFontsAreMarked`)
- **AC-401-14** 100 stub files (the fake engine returns one face each) with `batchMaxFiles = 48`, `maxConcurrentScans = 2`, `publishInterval = 20 ms` and `delayPerBatch = 100 ms` give 3 `scan` calls (48, 48, 4 files), never more than 2 at once. Progress fractions of the published snapshots are non-decreasing and end at 1.0. At least one intermediate snapshot has `isComplete == false`, and consecutive intermediate publishes are at least 18 ms apart. The final one has `isComplete == true` and `activity == .idle`. (`CatalogStoreTests.scanRunsInBoundedBatchesWithProgress`) Port of test_catalog.py:35-42: stub files `A.ttf, B.otf, C.ttf, K.ttf, V.ttf` (one face each), `T.ttc` (two faces) and `broken.ttf` (sfnt magic, scripted `file_error` code `io_error`) give 7 faces, exactly one `.unreadable` issue (for `broken.ttf`), and a final progress of 7/7 files. (`CatalogStoreTests.scanReportsFacesFailuresAndProgress`)
- **AC-401-15** A batch of 10 stub files where the fake engine throws whenever `bad.ttf` is in the file list ends with the 9 other files' faces in the snapshot and `bad.ttf` as `.unreadable(path:, code: "helper_failed", message:)`; `bad.ttf` is not in the saved cache. With `helloError` set on a new store whose cache directory holds a valid cache, `refresh` throws `CatalogError.engineUnavailable`, `currentSnapshot()` is still `.empty`'s content (no faces) and the cache file is byte-identical. With `throwAtStart = EngineError.launchFailed("x")` set after a successful first refresh and one stub file touched (so there is a miss), `refresh` throws `CatalogError.engineUnavailable`, the first refresh's faces are still the current snapshot's, and the cache file is byte-identical. With `throwAtStart = FakeEngine.Failure` but `hello()` working, every file ends as `helper_failed` and `refresh` returns normally. (`CatalogStoreTests.helperFailuresAreIsolated`)
- **AC-401-16** While a refresh is blocked inside the fake engine, three more `refresh` calls (`.incremental`, `.full`, `.incremental`) arrive. When it is released, exactly 2 refreshes have run, the second one `.full` (every file re-scanned), and all four calls return. (`CatalogStoreTests.refreshRequestsAreCoalesced`)
- **AC-401-17** `cancelRefresh()` during a 3-batch scan (`maxConcurrentScans = 1`; the fake engine blocks in batch 2 until cancelled) does the following: the batch-2 stream sees cancellation, batch-1 entries are in the saved cache, nothing is pruned, the published snapshot has `isComplete == false`, and the refresh call throws `CancellationError`. A second `refresh(.incremental)` queued behind it also throws `CancellationError`, and no further `scan` call happens. (`CatalogStoreTests.cancelKeepsCompletedWorkAndDoesNotPrune`)
- **AC-401-18** (CATALOG-6) With an injected private `NotificationCenter` and `changeDebounce = 100 ms`:
  - after a first completed refresh, the fake registry lists a new stub file; posting the CoreText notification twice within 50 ms gives exactly 1 refresh (counted with a refresh counter the store exposes to tests via `@testable import`), and a snapshot with that file's face is published within 2 s;
  - posting again with nothing changed gives 0 refreshes within 1 s;
  - marking a fake `RegisteredFaceInfo` `enabled = false` and posting gives exactly 1 refresh (CRIT-9 fingerprint);
  - after `stopObservingSystemChanges()`, posting gives 0 refreshes.

  (`CatalogObservationTests.catalog6RefreshesOnceAfterDebounce`)

  Real CoreText (`CatalogObservationTests.processScopeRegistrationTriggersRefresh`): a store with `notificationCenters: [NotificationCenter.default]`, `changeDebounce = 200 ms`, `startObservingSystemChanges()` and one completed refresh; then `ProcessScopeFonts.register` of a fixture font (unique family) in the test's temporary folder makes the store publish a snapshot containing that family within 3 s (unregister in `defer`). The setup:
  - `PrefixFilteredRegistry` wrapping the real `CoreTextFontRegistry`, keeping only paths inside the test's temporary folder, so no system font is scanned;
  - empty standard folders and no extra folders;
  - the real engine when `FP_ENGINE_PYTHON` is set, else `FakeEngine` scripted with a record for the fixture.

  This depends on F13: CoreText lists process-scope registrations, and the registered path's identity is inside the test folder.
- **AC-401-19** Creating `CTFontManagerCreateFontDescriptorsFromURL` + `CTFontCreateWithFontDescriptor` fonts for 20 fixture files (the renderer's method, with unique families) registers nothing: afterwards `CTFontManagerGetScopeForURL` is `.none` for each file, none of their PostScript names is in `CTFontManagerCopyAvailablePostScriptNames()`, and none of their paths is in `CoreTextFontRegistry().registeredFontFiles()` (identity). So previews cannot cause refresh storms. (A "no notification arrives" assertion is not used: another test may register a font at the same time, S5.4.) (`CatalogObservationTests.urlFontsRegisterNothing`)
- **AC-401-20** (INSTALL-6) After a completed refresh, `noteInstalled(url)` for a new stub file in the injected user folder:
  - calls `scan(files: [path])` exactly once and no `FakeRegistry` method;
  - publishes a snapshot with the face annotated `origin == .user` and `hiddenFromMenus == false`;
  - saves the cache with the new entry and every old entry.

  `noteRemoved(url)` removes it and its cache entry, with no scan call. (`CatalogStoreTests.install6IncrementalUpdateAfterOwnInstall`)
- **AC-401-21** `setExtraFolders([a, b])` starts no refresh (0 `scan` calls); the following `refresh(.incremental)` adds the faces of both. `setExtraFolders([a])` + `refresh(.incremental)` removes b's faces and prunes their cache entries. A relative path or a missing folder gives `.folderMissing`; a missing **standard** folder gives no issue. A folder with mode `000` (restored in `defer`) gives `.noAccess(folder)` and `counts.inaccessibleFolders == 1` (TOOLING-M3). (`CatalogStoreTests.extraFoldersAddRemoveAndReportAccess`)
- **AC-401-22** Real helper (`FP_ENGINE_PYTHON`): refreshing a temp extra folder of 6 fixture fonts (static, TTC with 2 faces, variable, no-OS/2, forged, localized) with an empty `FakeRegistry` and no standard folders gives 7 faces with the fixture PS names. Every child process that appeared during the refresh (`proc_listchildpids(getpid(), …)` before vs. after) has exited within 3 s after `refresh` returned, polled every 100 ms. (`CatalogIntegrationTests.realHelperScansFixturesAndLeavesNoChildren`)
- **AC-401-23** Real Mac (S6b; real registry, real standard folders, real engine, fresh temp cache), all of:
  - (a) cold refresh ≤ 15 s;
  - (b) a warm refresh by a **new** `CatalogStore` on the same cache directory (so loading the cache is included) ≤ 1.5 s, with 0 `scan` calls counted through a counting wrapper of the real engine;
  - (c) the process `phys_footprint` (`task_info(TASK_VM_INFO)`) grows by ≤ 200 MB over the cold refresh, and the child processes that appeared during it have exited within 3 s (as in AC-401-22);
  - (d) `CatalogReport.check` returns no problems (no `.`-faces, PingFang present if installed, AssetsV2 kept over PrivateFrameworks);
  - (e) if `/System/Library/Fonts/Times.ttc` exists, a face with PS `Times-Roman` is present and annotated `hiddenFromMenus` (F1 regression: the standard-folder walk).

  The durations are printed. (`CatalogRealFontsTests.coldWarmBudgetsAndContent`)
- **AC-401-24** `CatalogReportTests.checkFindsEachProblem`: each of the 4 problem kinds in §10 is detected on a hand-built snapshot, and a clean snapshot gives `[]`.
- **AC-401-25** (manual, macos; M3 exit) With `FP_ENGINE_PYTHON` exported, `swift run --package-path Packages/FontPlaygroundMacKit fpmac-harness catalog --check` exits 0. The PR includes the tail of the output: the summary line, and `grep -c '^\.'` of the face lines = 0. A face line for `PingFang SC` is present when PingFang is installed on that Mac.
- **AC-401-26** `make lint` and `make test` pass on macOS, including every test above (the gated ones where their conditions hold).

### Verification
```bash
make lint
make mac-test
FP_APPLE_FONTS=1 make mac-test          # real-Mac budgets and content (AC-401-23)
swift run --package-path Packages/FontPlaygroundMacKit fpmac-harness catalog --check   # AC-401-25 (manual)
```

### Notes for the implementer
- **F1 is the trap.** Linked against the current SDK, CoreText's URL list omits every font hidden from menus: Times, Courier, Hiragino Kaku Gothic Pro/ProN, STIX, Noto Sans rare scripts and others. The standard-folder walk brings them back. Don't "optimise" it away.
- Never use `CTFontDescriptorCreateWithNameAndSize(ps)` → URL to find "the file CoreText resolves" (the CATALOG-M1 recommendation). That is a name lookup. Use `kCTFontPriorityAttribute` (F3).
- `CatalogStore` is an actor, and `EngineRunning` streams are consumed inside it. Don't hold the actor across long awaits in a way that blocks `currentSnapshot()`: keep scan work in child tasks and merge results back on the actor.
- The engine's `FaceRecord.hidden` is authoritative for the `.` rule. Don't re-implement it with CoreText names.
- CoreText may return a different spelling of a path than the one you walked or registered (`/tmp` vs `/private/tmp`, F13). Compare paths from CoreText by identity (S4), never as strings.
- Use `CTFontManagerCompareFontFamilyNames` only if you want Apple's order in the UI (WP-503). The catalog order in §5 exists for determinism.
- Reread audit `CATALOG-1`, `CATALOG-M1`, `CATALOG-6` (verifier), `CRIT-5`, `CRIT-6`, `CRIT-9` and `ENGINE-9` (verifier, memory).

---

## WP-402: Font rendering service (URL descriptors, LastResort cascade, opsz pin, built font)

**Goal:** Provide `CTFont`s that draw exactly what every Mac app draws from the face's own file: never registered, never looked up by name, never falling back to another font, with variations pinned as the engine instances them.
**Depends on:** WP-301 · **Env:** macos · **Size:** M · **Closes findings:** CATALOG-4, NATIVE-M1, NATIVE-M2, NATIVE-M3

> Also implements the TTC-index mapping of `NATIVE-M2` (not listed in the plan's findings column; see the backbone note).

### Scope
- In: `FontRenderer` (`FontRendering`, contracts §7), `LastResort`, `RunInspector`, `NameLookupSafetyTests` (S5.1), and the S6 test support if this WP merges before WP-403.
- Out:
  - Attributed-string building, `.strokeWidth`/`.kern` application and TextKit (WP-504).
  - The picker's row font cache (WP-503, `RowFontCache`).
  - Session-scope "try in other apps" (`NATIVE-M7`, backlog).

### Touched paths
- `Packages/FontPlaygroundMacKit/Sources/FPMacServices/Rendering/FontRendering.swift` (new)
- `…/Rendering/FontRenderer.swift` (new)
- `…/Rendering/LastResort.swift` (new)
- `…/Rendering/RunInspector.swift` (new)
- `…/Support/LRUCache.swift` (new)
- `…/Support/MacServicesConstants.swift` (new, S1, if absent)
- `Packages/FontPlaygroundMacKit/TestFixtures/make_fonts.py`, `Tests/FPMacServicesTests/Support/FixtureFonts.swift` (new, S6, if absent)
- `Packages/FontPlaygroundMacKit/Tests/FPMacServicesTests/Rendering/*.swift` (new)
- `Packages/FontPlaygroundMacKit/Tests/FPMacServicesTests/Safety/SourceAudit.swift` (new, S5), `…/Safety/NameLookupSafetyTests.swift` (new)

### Design

#### 1. API (`FontRendering.swift`)

```swift
public struct FaceRenderRequest: Hashable, Sendable {
    public var face: FaceRecord
    public var pointSize: CGFloat          // before scale
    public var weight: Int?                // MixFont.weight; nil = as it is
    public var scale: Double               // MixFont.scale
    public init(face: FaceRecord, pointSize: CGFloat, weight: Int? = nil, scale: Double = 1)
}
public struct SyntheticBold: Hashable, Sendable {
    public var delta: Int                  // min(weight - weightClass, 500)
    public var strokeWidthPercent: Double  // delta / 1000 × 0.2 × 100 → the preview applies .strokeWidth = -value
    public var extraAdvance: CGFloat       // delta / 1000 × 0.2 × effective point size → the preview applies .kern
}
public enum RenderWeightNote: Hashable, Sendable { case cannotLighten }   // prepare.py:170-171. Not `WeightNote`: FPCore (WP-304) has a `WeightNote`, and FPAppUI imports both modules
public struct RenderedFont: @unchecked Sendable {  // CTFont is immutable and thread-safe (S7)
    public let ctFont: CTFont
    public let fileURL: URL
    public let postscriptName: String
    public let pointSize: CGFloat          // effective: request.pointSize × scale
    public let variation: [String: Double] // tag → value requested (every fvar axis); [:] for static faces
    public let syntheticBold: SyntheticBold?
    public let weightNote: RenderWeightNote?
}
public enum RenderError: Error, Hashable, LocalizedError {   // englishText: S8
    case fileMissing(path: String)
    case unreadable(path: String)                                  // CoreText returned no descriptors
    case faceNotFound(path: String, index: Int, postscriptName: String?)
    case builtFontInvalid(path: String, faceCount: Int)            // a built file must hold exactly one face
    public var englishText: String
}
public protocol FontRendering: Sendable {
    func font(for request: FaceRenderRequest) throws -> RenderedFont
    func builtFont(at url: URL, pointSize: CGFloat) throws -> RenderedFont
    func hasGlyph(for scalar: Unicode.Scalar, in font: RenderedFont) -> Bool
    func missingScalars(in text: String, for font: RenderedFont) -> [Unicode.Scalar]   // unique, in text order
    func coverage(of font: RenderedFont) -> CodepointSet            // from CTFontCopyCharacterSet (ui-editing S2.2 (c))
    func invalidate(path: String)
    func invalidateAll()
}
public final class FontRenderer: FontRendering, @unchecked Sendable {
    public init(lastResort: LastResort = .shared, descriptorCacheCapacity: Int = 512, fontCacheCapacity: Int = 4096)
}
```

The contract names "a FaceKey". The request carries the whole `FaceRecord`, because the renderer needs `postscriptName`, `axes` and `weightClass` without a catalog lookup.

#### 2. `LastResort` (`LastResort.swift`; F5, F6, ADR-0011)

```swift
public struct LastResort: @unchecked Sendable {
    public let descriptor: CTFontDescriptor
    public static let shared: LastResort = .make()
    static func make(fileURL: URL = MacServicesConstants.lastResortURL) -> LastResort
}
```

`make` works in two steps:

1. `CTFontManagerCreateFontDescriptorsFromURL(fileURL)`, taking the descriptor whose `kCTFontNameAttribute == "LastResort"`.
2. Only if that fails: `CTFontDescriptorCreateWithNameAndSize("LastResort" as CFString, 0)`. This is the single allowlisted name form (S5.1). LastResort is a SIP-protected system font, always installed and never downloadable.

Don't look for it in `CTFontManagerCopyAvailableFontURLs()`: it is not listed with SDK ≥ 26 (F1).

#### 3. Descriptor resolution (`NATIVE-M2`, F4)

Per file, cache `CTFontManagerCreateFontDescriptorsFromURL(url)` in an LRU keyed by `FontFileStamp(path, dev, ino, size, mtime)`. The stamp comes from `stat` on every call; a replaced file gets a new stamp. Resolve `(path, index, postscriptName)`:

1. `stat` fails → `.fileMissing`. No descriptors → `.unreadable`.
2. Descriptors whose `kCTFontNameAttribute == postscriptName`: exactly one → use it; several → the first without `kCTFontVariationAttribute`, else the first.
3. No PS name, or no match:
   - If the file starts with `ttcf`, read `numFonts` (big-endian `UInt32` at byte offset 8). If `descriptors.count == numFonts` and `0 <= index < numFonts`, use `descriptors[index]`.
   - If the file is not a collection and `index == 0`, use `descriptors[0]`.
4. Otherwise throw `.faceNotFound`.

Never map by position when the counts differ: variable TTCs expand into named instances (PingFangUI: 268 descriptors, 32 faces).

#### 4. Attributes

The base descriptor is copied with `CTFontDescriptorCreateCopyWithAttributes` (`CTFontDescriptor.h:358`: variation dictionaries are merged, so give every axis):

- `kCTFontCascadeListAttribute: [LastResort.shared.descriptor]`. This applies to every face and every built font (ADR-0011, NATIVE-3 verifier, F5).
- `kCTFontOpticalSizeAttribute: "none"` on every face (F7; harmless for static faces).
- For a face with `isVariable` and non-empty `axes` (the engine instances exactly these, `engine/prepare.py:142`): `kCTFontVariationAttribute: [NSNumber(value: tagCode): value]` for **every** axis, where `tagCode` is the 4 ASCII bytes big-endian (`wght` = 0x77676874 = 2003265652, `opsz` = 0x6F70737A = 1869640570). The value is `min(max(Double(weight), axis.min), axis.max)` for `wght` when `weight != nil`, else `axis.default`. This matches `engine/prepare.py:35-41` exactly, and pins `opsz` at the fvar default (NATIVE-M3, ADR-0011 note on B-1). `RenderedFont.variation` records the same dictionary keyed by tag string.
- A face **without a `wght` axis** (`!face.hasWeightAxis`: a static face, or a variable face whose axes lack `wght`) with `weight != nil`: `delta = weight - weightClass` (the engine's condition, `engine/prepare.py:165`).
  - If `delta >= 50`, return `syntheticBold` with `delta' = min(delta, 500)`, `strokeWidthPercent = Double(delta') * 0.02` and `extraAdvance = CGFloat(delta') / 1000 * 0.2 * effectivePointSize`. This matches `prepare.py:165-169` and `synth_bold.py:8-13`, and ui-editing AC-504-5 (−6.0 and 1.8 at 30 pt for +300).
  - If `delta <= -50`, `weightNote = .cannotLighten` (no synthetic bold).
  - Otherwise (`-50 < delta < 50`) both are nil.
  - The engine's threshold replaces the Qt preview's `SYNTHETIC_STEP = 100` (`ui/fonts.py:14`) on purpose: the preview must match the build.
- `weight == nil`, or a face with a `wght` axis: `syntheticBold == nil`, `weightNote == nil`.
- The effective size is `pointSize × scale`, and `CTFontCreateWithFontDescriptor(desc, effectiveSize, nil)`.

#### 5. Built fonts (CATALOG-4 verifier, ADR-0011)

`builtFont(at:pointSize:)` uses the same path with a descriptor count of exactly 1 (else `.builtFontInvalid`), no variation and no synthetic bold. It never registers anything. A newer build and an installed older build can share a PostScript name; the URL descriptor still draws the new file (F5).

#### 6. Caching and thread safety

- **Descriptor LRU**: default 512 files.
- **Font LRU**: default 4096 entries, keyed by `(FontFileStamp, index, postscriptName, weight, effectivePointSize rounded to 1/64 pt, face.axes)`. The same request returns the same `CTFont` object (`===`). The font is created, and `pointSize` and the synthetic-bold advance are computed, at that rounded size. So two requests sharing a key get the same result whichever comes first (`fontsAreBuiltAtTheQuantizedSizeTheyAreCachedUnder`).
- State is behind `OSAllocatedUnfairLock`. No CoreText calls are made while the lock is held. Compute outside it, then insert.
- `invalidate(path:)` drops every entry for the path. `invalidateAll()` clears both caches.

`LRUCache<Key: Hashable, Value>` (`Support/LRUCache.swift`) is a dictionary plus a doubly linked list with O(1) get and put. It is not thread-safe: callers lock.

#### 7. Glyph presence and coverage

- `hasGlyph`: encode the scalar as UTF-16 (1 or 2 units), then `CTFontGetGlyphsForCharacters(font, units, &glyphs, count)`. True when it returns true and `glyphs[0] != 0`.
- `missingScalars`: unique scalars in text order, skipping U+0020 and U+000A.
- `coverage`: `CFCharacterSetCreateBitmapRepresentation(nil, CTFontCopyCharacterSet(font))`. Parse plane 0 as the first 8192 bytes (bit `n` of byte `i` = code point `i×8+n`). Each further block is 8193 bytes: a plane byte, then that plane's bitmap. Merge into `CodepointSet(ranges:)`. This was verified with a fixture holding U+0061, U+6C38 and U+20000. CoreText's set may contain control characters the cmap doesn't map (U+0000, U+0008–U+000A, U+000D and U+001D seen on `Helvetica.ttc`). Callers ignore ignorable scalars (FPCore `TextUtil`).

#### 8. `RunInspector` (tests, WP-504/505, self-test)

```swift
public enum RunInspector {
    public struct Run: Hashable, Sendable {
        public var range: NSRange; public var postscriptName: String; public var fileURL: URL?
        public var glyphs: [CGGlyph]          // CTRunGetGlyphs: visual order (right to left inside an RTL run)
        public var stringIndices: [Int]       // CTRunGetStringIndices: the UTF-16 index of each glyph's character
    }
    public static func runs(of string: NSAttributedString) -> [Run]
}
```

It calls `CTLineCreateWithAttributedString`, then `CTLineGetGlyphRuns`. For each run, it reads `kCTFontAttributeName` from `CTRunGetAttributes` (the key equals `NSAttributedString.Key.font.rawValue`, verified), `CTFontCopyPostScriptName`, `CTFontCopyAttribute(font, kCTFontURLAttribute)`, `CTRunGetGlyphs`, `CTRunGetStringIndices` and `CTRunGetStringRange`. Runs are returned in `CTLineGetGlyphRuns` order.

### Acceptance criteria

The tests are in `Packages/FontPlaygroundMacKit/Tests/FPMacServicesTests/Rendering/`. Fixtures come from S6. "The run fonts" means `RunInspector.runs` over an attributed string whose font attribute is `RenderedFont.ctFont`.

- **AC-402-1** `LastResort.shared` gives a font whose PS name is `LastResort` and whose URL is `/System/Library/Fonts/LastResort.otf`. `LastResort.make(fileURL:)` with a missing file still gives a `LastResort` font (the name fallback). (`LastResortTests.lastResortIsFoundByURLWithNameFallback`)
- **AC-402-2** (NATIVE-M2) For the 2-face fixture TTC (`FPColl-Regular` covers "ab", `FPColl-Bold` covers "abc"):
  - a request for index 1 with PS `FPColl-Bold` has a glyph for "c" and a run PS of `FPColl-Bold`;
  - index 1 with PS `nil` uses the position fallback (count 2 == numFonts) and gives the same result;
  - index 5 with an unknown PS throws `.faceNotFound`.

  Real (S6b): every face named in the `#postscript-name=` fragments of `/System/Library/Fonts/Helvetica.ttc` resolves to a font with that PS name. (`FontRendererTests.nativeM2CollectionFacesMapByPostScriptName`)
- **AC-402-3** (no fallback) With fixture A (covers "abc"), rendering "ab永한ب😀Ж" gives runs from only two fonts, `FPTestA…` and `LastResort`. Every run whose range covers a missing scalar is `LastResort`. (`RenderHonestyTests.missingCharactersShowLastResortNeverAnotherFont`)
- **AC-402-4** (CATALOG-4) Two fixtures share family, style and PS name: `old.ttf` covers "ab", `new.ttf` covers "abc". With `old.ttf` registered at process scope (`ProcessScopeFonts`, deferred unregister), both `font(for:)` on a `FaceRecord` for `new.ttf` and `builtFont(at: new.ttf)` draw "c" with a non-zero glyph, run URL `new.ttf`. Rendering `old.ttf` by URL gives run URL `old.ttf`, with "c" as `LastResort`. (`RenderHonestyTests.catalog4FileIsDrawnNotTheSameNamedInstalledFont`)
- **AC-402-5** (NATIVE-M1, F8) Fixture `ArLatn` covers U+0628, U+063A, U+062F, U+FE91, U+FED0, U+FEAA and "ab", with a GSUB for `DFLT`/`latn` only (`fea`: `languagesystem DFLT dflt; languagesystem latn dflt; feature aalt { sub uni0061 from [uni0061 uni0062]; } aalt;`). Rendering "بغد" gives one run whose glyph for string index 0, 1, 2 (paired through `Run.stringIndices`; the glyphs themselves come in visual order) is the nominal glyph of U+0628, U+063A, U+062F (from `CTFontGetGlyphsForCharacters`), and none of the presentation-form glyphs: unjoined, as TextEdit draws it (verified: glyphs `[3, 2, 1]`, indices `[2, 1, 0]`). Control: fixture `ArNoGSUB` (same characters, no GSUB) gives the presentation-form glyphs of U+FE91, U+FED0, U+FEAA for indices 0, 1, 2 (CoreText's own joining fallback; verified glyphs `[6, 5, 4]`). This proves the renderer adds no shaping of its own and uses no fallback font. (`RenderHonestyTests.nativeM1PreviewShapesExactlyLikeCoreText`)
- **AC-402-6** (NATIVE-M3, F7) Fixture `Var`: `wght` 100/400/900 and `opsz` 8/28/144, with STAT.
  - For `font(for:)` with `weight: nil` at 12, 28 and 96 pt: `CTFontCopyVariation` has no `opsz` key, or `opsz == 28`, and the glyph bounding-box height per em of glyph 1 (`CTFontCreatePathForGlyph`) is equal at all three sizes (±0.001).
  - Control: a plain `CTFontManagerCreateFontDescriptorsFromURL` font of the same file at 96 pt has `opsz == 96` and a different height per em.

  (`VariationPinTests.nativeM3OpticalSizeIsPinnedToTheEngineDefault`)
- **AC-402-7** For fixture `Var`: weight 700 → `CTFontCopyVariation[wght] == 700` and `RenderedFont.variation == ["wght": 700, "opsz": 28]`; weight 1200 → 900; weight 50 → 100; weight nil → `wght` absent or 400. (`VariationPinTests.weightIsClampedLikeTheEngine`)
- **AC-402-8** For static fixture A (`weight_class` 400) at 30 pt:
  - weight 700 → `syntheticBold == (300, 6.0, 1.8)`;
  - weight 700 with scale 0.8 → `extraAdvance` 1.44;
  - weight 430 → nil;
  - weight 1000 → delta 500, stroke 10.0;
  - weight 300 → `weightNote == .cannotLighten` and no synthetic bold.

  (`FontRendererTests.syntheticBoldHintFollowsTheEngineRule`)
- **AC-402-9** `builtFont(at:)` for a fixture works, and `CTFontManagerGetScopeForURL(url) == .none` afterwards: nothing is registered. A junk file gives `.unreadable`, a missing file `.fileMissing`, and a 2-face TTC `.builtFontInvalid(faceCount: 2)`. (`FontRendererTests.builtFontIsLoadedByURLOnly`)
- **AC-402-10** The same request twice returns the identical `CTFont` (`===`). After the file is replaced at the same path by a fixture covering one more character (built in another folder, then `rename(2)`d over it, so the inode changes), the next call sees the new glyph. `invalidate(path:)` forces new objects. (`FontRendererTests.cacheFollowsFileIdentity`)
- **AC-402-11** For fixture `Han` (covers "a", U+6C38, U+20000):
  - `missingScalars(in: "ab永😀𠀀")` == [`b`, `😀`];
  - `hasGlyph(U+20000)` is true;
  - `coverage` contains U+0061, U+6C38 and U+20000, and not U+0062.

  (`FontRendererTests.glyphPresenceAndCoverage`)
- **AC-402-12** 8 concurrent tasks × 200 random requests over 6 fixtures complete without a crash, and equal requests give equal PS names and variations. (`FontRendererTests.concurrentRequestsAreSafe`)
- **AC-402-13** `RunInspector.runs` over "ab永" drawn with fixture A gives exactly 2 runs: `FPTestA…` with range `{0,2}` and 2 non-zero glyphs, and `LastResort` with range `{2,1}`. Both have a non-nil `fileURL` (`A.ttf` and `LastResort.otf`). (`RunInspectorTests.runsReportFontFileAndGlyphs`)
- **AC-402-14** (S5.1) `NameLookupSafetyTests.sourcesContainNoNameLookups` passes over the real `Sources/` tree and scans at least the files this WP added (the test asserts that `Rendering/FontRenderer.swift` was among the scanned files). Self-tests on synthetic input (`NameLookupSafetyTests.scannerDetectsForbiddenCall`): `let f = CTFontCreateWithName("X" as CFString, 12, nil)` in `Sources/FPMacServices/Catalog/X.swift` is a violation; the same line prefixed with `// ` is not; one `CTFontDescriptorCreateWithNameAndSize(` in `Sources/FPMacServices/Rendering/LastResort.swift` is allowed and two are a violation.
- **AC-402-15** Performance (S6b): `font(for:)` for one `FaceRecord` per registered file, taking the first PS name from `registeredFontFiles()` or, without WP-403's registry, from the `#postscript-name=` fragments of `CTFontManagerCopyAvailableFontURLs()`, completes in ≤ 1.5 s cold and ≤ 0.1 s warm for all of them. The time is printed. (`RenderPerformanceTests.allSystemFacesColdAndWarm`)
- **AC-402-16** `make lint` and `make test` pass on macOS.

### Verification
```bash
make lint
make mac-test
FP_APPLE_FONTS=1 make mac-test
```

### Notes for the implementer
- Never call `CTFontManagerRegister*` and never build a descriptor from a name, except in `LastResort.make`'s fallback. `NSFont(ctFont)` bridging is fine: `CTFont` and `NSFont` are toll-free bridged.
- An all-default variation dictionary does **not** stop CoreText's automatic optical sizing (F7). Always add `kCTFontOpticalSizeAttribute: "none"`.
- The synthetic fixtures need STAT to exercise auto-`opsz` (F7). Without it the NATIVE-M3 test would pass vacuously. The control assertion in AC-402-6 guards against that.
- Faces disabled in Font Book may fail to render from their URL. `RenderError` is then returned, and the picker shows a placeholder (WP-503).
- Reread audit `NATIVE-3` (verifier), `NATIVE-M1`, `NATIVE-M2`, `NATIVE-M3`, `CATALOG-4` (verifier).

---

## WP-403: `FontInstaller` + CoreText conflict checker

**Goal:** Install a forged font for the current user by copying it into `~/Library/Fonts` atomically, after CoreText validation. Refuse names macOS or the user already use, and remove only files this app provably wrote.
**Depends on:** WP-301, WP-109 · **Env:** macos · **Size:** L · **Closes findings:** INSTALL-*, TOOLING-2, TOOLING-7

> INSTALL-13 is shared: this WP fixes the conflict and error wording (S8), and WP-505 adds Show in Finder. INSTALL-14 (distribution) is WP-601; this WP only guarantees that no entitlement or registration is needed.

### Scope
- In:
  - `SystemFontRegistry` (S2);
  - `NameTable` and `ForgedMarker`;
  - the system-wide name index (`FontNameIndex`, `SystemFontNameSource`) and `ConflictChecker`;
  - `InstallManifest`, `InstallFileSystem` and `TrashCan`;
  - `FontInstaller` (`FontInstalling`, contracts §7);
  - the S6 test support if this WP merges before WP-402;
  - `RegistrationSafetyTests`.
- Out:
  - The build/install/update flow, controller state ("this session installed it") and dialogs (WP-505).
  - Show in Finder (WP-505).
  - Catalog refresh after install (WP-401 `noteInstalled`, called by WP-505).
  - Downloadable names (WP-404 plugs in through `FontNameSource`).
  - PostScript-name generation (WP-109).

### Touched paths
- `Packages/FontPlaygroundMacKit/Sources/FPMacServices/Registry/SystemFontRegistry.swift` (new, S2)
- `…/Install/InstallModels.swift` (new)
- `…/Install/NameTable.swift` (new)
- `…/Install/ForgedMarker.swift` (new)
- `…/Install/FontNameIndex.swift` (new)
- `…/Install/SystemFontNameSource.swift` (new)
- `…/Install/ConflictChecker.swift` (new)
- `…/Install/InstallManifest.swift` (new)
- `…/Install/InstallFileSystem.swift` (new)
- `…/Install/TrashCan.swift` (new)
- `…/Install/InstallFileName.swift` (new)
- `…/Install/FontInstaller.swift` (new)
- `…/Support/MacServicesConstants.swift` (new, S1, if absent)
- `Packages/FontPlaygroundMacKit/TestFixtures/make_fonts.py`, `Tests/FPMacServicesTests/Support/FixtureFonts.swift` (new, S6, if absent)
- `Packages/FontPlaygroundMacKit/Tests/FPMacServicesTests/Support/RecordingTrash.swift` (new)
- `Packages/FontPlaygroundMacKit/Tests/FPMacServicesTests/Install/*.swift`, `…/Registry/SystemFontRegistryTests.swift` (new)
- `…/Safety/SourceAudit.swift` (new, S5, if absent), `…/Safety/RegistrationSafetyTests.swift` (new)

### Design

#### 1. Models (`InstallModels.swift`)

```swift
public struct InstallQuery: Hashable, Sendable {        // from ForgeReport: family_name, style_name, postscript_name, full_name
    public var family: String, style: String, postscriptName: String, fullName: String
    public init(family: String, style: String, postscriptName: String, fullName: String? = nil) // fullName ?? "\(family) \(style)" trimmed
}
public struct InstalledFont: Hashable, Sendable, Codable {
    public var fileURL: URL
    public var family: String, style: String, fullName: String, postscriptName: String
    public var sha256: String, size: Int64, installedAt: Date
}
public enum ConflictReason: Hashable, Sendable {
    case systemHas(name: String), installedForEveryone(name: String), youHave(name: String)
    case internalNameInUse(postscriptName: String), internalNameUsedByYourFont(postscriptName: String, fullName: String)
    case hiddenName, appleOffersDownload(name: String)
    public var englishText: String                       // S8
}
public enum InstallConflict: Hashable, Sendable {
    case noConflict                                      // not `none`: `InstallConflict?` would make `.none` ambiguous
    case replaceOurs(InstalledFont)                      // ask first: "Replace the … you installed earlier?"
    case ask(ConflictReason)                             // may proceed after confirmation; nothing is replaced
    case block(ConflictReason)
}
public enum InstallError: Error, Hashable, LocalizedError {
    case invalidQuery
    case sourceMissing, unreadable, unexpectedName(expected: String, found: String), notForged
    case conflict(InstallConflict)                       // .block, or a confirmable conflict that was not confirmed
    case noFreeFileName(stem: String)
    case notOurs(name: String)
    case previousCopyNotRemoved(installed: InstalledFont, previous: InstalledFont, message: String)
    case manifestUnsupported
    case fileSystem(operation: String, message: String) // message = underlying localizedDescription
    public var englishText: String                       // S8 (the fragment after "Couldn't install the font: ")
}
public enum UninstallOutcome: Hashable, Sendable { case movedToTrash(URL?), notInstalled }
public struct FontNameEntry: Hashable, Sendable {
    public var path: String?                             // nil for downloadable names
    public var domain: FontDomain                        // S3
    public var postscriptName: String
    public var familyKeys: Set<String>                   // folded (§3)
    public var fullNameKeys: Set<String>
    public var displayFamily: String, displayStyle: String, displayFullName: String
}
public protocol FontNameSource: Sendable { func nameEntries() -> [FontNameEntry] }   // WP-404 plugs in here
public protocol FontInstalling: Sendable {
    func conflict(for query: InstallQuery) async throws -> InstallConflict
    func install(_ source: URL, expecting query: InstallQuery, confirmed: InstallConflict?) async throws -> InstalledFont
    func uninstall(_ font: InstalledFont) async throws -> UninstallOutcome
    func installedFonts() async throws -> [InstalledFont]          // sorted by fullName
}
extension FontInstalling {                                          // the contracts §7 spelling
    public func install(_ source: URL, expecting query: InstallQuery) async throws -> InstalledFont {
        try await install(source, expecting: query, confirmed: nil)
    }
}
```

#### 2. `NameTable` and `ForgedMarker`

```swift
public enum NameTableError: Error, Equatable { case malformed }
public struct NameRecord: Hashable, Sendable { public var platformID, encodingID, languageID, nameID: UInt16; public var value: String }
public struct NameTable: Sendable {
    public let records: [NameRecord]
    public init(data: Data) throws                   // NameTableError.malformed: < 6 bytes, format not 0/1, or stringOffset past the end
    public func strings(nameID: UInt16) -> [String]  // record order, unique
    public func preferred(nameID: UInt16) -> String? // (3,1,0x409) > (3,10,0x409) > (1,0,0) > first
    /// One table per distinct face: CTFontManagerCreateFontDescriptorsFromURL → CTFontCreateWithFontDescriptor(d, 0, nil)
    /// → CTFontCopyTable(font, CTFontTableTag(kCTFontTableName), []), deduplicated by Data equality (named instances).
    public static func tables(forFontAt url: URL) -> [NameTable]
}
public enum ForgedMarker {
    /// True when some name-ID-0 record of the file starts with MacServicesConstants.forgedNotice (install.py:63-75).
    public static func isForged(fileAt url: URL) -> Bool   // missing, unreadable or non-font → false
}
```

Parsing the name table:

- Header: `format` u16 (0 or 1), `count` u16, `stringOffset` u16, then `count` records of 6 × u16 (`platformID, encodingID, languageID, nameID, length, offset`). Format 1's language-tag records are ignored.
- Every offset and length is bounds-checked; a bad record is skipped, not thrown.
- Decoding:
  - platform 0 (any encoding) and platform 3 (encodings 0, 1, 10) → UTF-16BE;
  - platform 1 encodings 0, 1, 2, 3, 25 → `CFStringEncodings` `.macRoman`, `.macJapanese`, `.macChineseTrad`, `.macKorean`, `.macChineseSimp`, through `CFStringConvertEncodingToNSStringEncoding`. The GB2312 bytes of 华文宋体 decode with `.macChineseSimp` (verified).
  - Anything else is skipped. Empty strings are dropped.

#### 3. System-wide name index (`INSTALL-3`, `INSTALL-4`, `INSTALL-5`, `TOOLING-7`, F10)

`SystemFontNameSource(registry:folders:userFontsFolder:)` implements `FontNameSource`; `FontNameIndex` (an internal `final class`, lock-protected) caches its entries for the installer.

- `folders: [(URL, FontDomain)]` is `FontInstaller`'s `systemFolders` (default `[(/System/Library/Fonts, .system), (/Library/Fonts, .local)]`); `userFontsFolder` is the installer's `fontsFolder` (domain `.user`).
- **Files** are the union of `registry.registeredFontFiles()` paths, the paths of `registry.registeredFaces(includeDisabled: true)` (disabled fonts count too, CRIT-9), and a recursive `FileManager.default.enumerator(at:includingPropertiesForKeys:options:)` walk of every folder in `folders` and of `userFontsFolder` (options `.skipsHiddenFiles`, `.skipsPackageDescendants`; extensions in `MacServicesConstants.fontExtensions`, case-insensitive). Dedupe by identity (S4), keeping the first spelling; a path whose `stat` fails is dropped.
- **Domain** of a file: `FontDomain.classify` (S3) with `isInsideUserFolder` = inside `userFontsFolder`, `injectedDomain` = the domain of the first `folders` entry that contains the file, `isRegistered` = its identity is among the registry's.

For each file, `CTFontManagerCreateFontDescriptorsFromURL` gives one `FontNameEntry` per descriptor (a file with no descriptors gives none):

- `postscriptName` = `kCTFontNameAttribute`;
- the descriptor's own name table: `CTFontCreateWithFontDescriptor(d, 0, nil)` → `CTFontCopyTable(font, CTFontTableTag(kCTFontTableName), [])` → `NameTable(data:)`, memoized by `Data` equality (named instances of one face share a table); a missing or malformed table gives no name-ID keys;
- `familyKeys` = fold(`kCTFontFamilyNameAttribute`) ∪ fold(every record of name IDs 1, 16 and 21);
- `fullNameKeys` = fold(`kCTFontDisplayNameAttribute`) ∪ fold(every record of name ID 4);
- `displayFamily` / `displayStyle` / `displayFullName` = `kCTFontFamilyNameAttribute` / `kCTFontStyleNameAttribute` / `kCTFontDisplayNameAttribute` (empty string when absent);
- `path` = the file's path, `domain` as above.

A disabled `RegisteredFaceInfo` whose path is nil adds one entry with `path == nil`, `domain == .other`, `postscriptName` = its name, and `familyKeys` = fold(`kCTFontFamilyNameAttribute`) read from the collection descriptor with `CTFontDescriptorCopyAttribute` (empty when absent).

**No name-based matching is used** (S5.1). The prototype's `CTFontDescriptorCreateMatchingFontDescriptors({family: …})` could auto-activate and download a font the user merely typed (CATALOG-5).

**Folding:** `fold(s) = s.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: nil)`. An empty folded string is never a key.

**Caching:** the entries are built lazily on the first `conflict(for:)` and kept. Before each query the index computes a fingerprint (the sorted `path|size|mtime` of `registeredFontFiles()`, then `folder|mtime` of every folder root and of `userFontsFolder`, then the sorted PS names of disabled `registeredFaces(includeDisabled: true)`) and rebuilds when it differs. The installer also invalidates it after its own install or uninstall. Budget: build ≤ 1.5 s and a warm query (fingerprint + lookup) ≤ 50 ms on the S6b machine class.

#### 4. `ConflictChecker` (a pure decision; ports `ui/build.py:142-179`)

```swift
enum ConflictChecker {
    static func decide(query: InstallQuery, entries: [FontNameEntry],
                       ours: (String) -> InstalledFont?,        // path → our font, per §5 "Ours"; nil = not ours
                       fileExists: (String) -> Bool) -> InstallConflict
}
```

A **hit** is an entry that matches the query by family (`fold(query.family) ∈ familyKeys`), by full name (`fold(query.fullName) ∈ fullNameKeys`) or by PostScript name (`postscriptName` equals `query.postscriptName` compared case-insensitively). The **reason for a set of hits** in one domain is built from the kind of match: if any of them matches by family, use the domain's reason with `name: query.family`; else if any matches by full name, the domain's reason with `name: query.fullName`; else (PostScript-name hits only) `.internalNameInUse(postscriptName: query.postscriptName)`.

Evaluate in this order; the first rule that applies decides:

0. `query.family` or `query.postscriptName` starts with `.` (after trimming) → `.block(.hiddenName)` (UI-M3).
1. Collect the hits. Drop hits whose `path != nil && !fileExists(path)`: vanished files never count (build.py:162, :175).
2. Hits in `.system` → `.block(reason)`, with `.systemHas(name:)` as the domain reason.
3. Hits in `.local` → `.block(reason)`, with `.installedForEveryone(name:)`.
4. Hits in `.other`, or `.user` hits with `ours(path) == nil` (including `path == nil`) → `.block(reason)`, with `.youHave(name:)`. This covers non-forged user fonts, forged fonts not in the manifest, and fonts activated elsewhere (build.py:166-168, :176-177, INSTALL-M1).
5. A `.user` hit that matches by PostScript name and whose `ours(path)!.fullName` differs (folded) from `query.fullName` → `.block(.internalNameUsedByYourFont(postscriptName: query.postscriptName, fullName: thatFont.fullName))` (INSTALL-5 verifier).
6. `.user` hits whose `ours(path)` has the same folded full name as the query → `.replaceOurs(f)`, where `f` is the one with the latest `installedAt` (ties: the path in byte order) (build.py:170, :178).
7. The remaining `.user` hits are our own fonts of the same family with another style (they match by family only): no conflict (build.py:169, test_build.py:318-321).
8. Hits in `.downloadable` (WP-404) → `.ask(.appleOffersDownload(name: query.family))`.
9. Otherwise `.noConflict`.

#### 5. Manifest (`InstallManifest.swift`; ADR-0009, contracts §8)

```json
{
  "format": "fontplayground-installed-fonts",
  "version": 1,
  "fonts": [
    {"file_name": "Test Mix-Regular.ttf", "family": "Test Mix", "style": "Regular", "full_name": "Test Mix Regular",
     "postscript_name": "TestMix-Regular", "sha256": "<64 lowercase hex>", "size": 12345,
     "installed_at": "2026-09-29T10:00:00Z"}
  ]
}
```

- `file_name` is relative to the fonts folder, so the manifest holds no home path.
- A missing file reads as an empty manifest. Unknown keys are ignored.
- `version > 1` → `.manifestUnsupported`. The installer then refuses to install or uninstall, and never overwrites the manifest.
- Invalid JSON: rename the file to `installed.json.corrupt-<yyyyMMdd-HHmmss>` and treat the manifest as empty. Our earlier fonts then stop counting as ours, which is safe.
- Writes are atomic (`InstallFileSystem.writeAtomically`: temp in the same folder, `fsync`, `rename`), with parent folders created.

**Ours** (ADR-0009, INSTALL-10, INSTALL-M1): `ours(path)` returns an `InstalledFont` only when **all** of these hold:

1. the file's parent directory has the identity of `fontsFolder` (S4);
2. the manifest has an entry whose `file_name` equals the file's name (both compared after `precomposedStringWithCanonicalMapping`);
3. the file exists with `size` and SHA-256 equal to the entry's;
4. `ForgedMarker.isForged` is true;
5. the file's single URL descriptor has `kCTFontNameAttribute == entry.postscript_name`.

The SHA-256 of a file is cached by `(path, size, mtime)`.

#### 6. File system and Trash seams

```swift
public protocol InstallFileSystem: Sendable {
    /// Creates `staged` with O_EXCL, copies `source` in 1 MiB chunks while hashing (CryptoKit SHA256), fsyncs.
    func copyAndSync(from source: URL, to staged: URL) throws -> (size: Int64, sha256: String)
    /// renamex_np(from, to, RENAME_EXCL): never replaces an existing file; EEXIST → POSIXError(.EEXIST).
    /// On ENOTSUP (a volume without RENAME_EXCL), link(2) + unlink(2) of `from` instead (link also fails with EEXIST).
    func renameExclusive(_ from: URL, to: URL) throws
    func removeFile(_ url: URL) throws                      // unlink(2); ENOENT is success. Staging files only (§8)
    func writeAtomically(_ data: Data, to url: URL) throws
    func sha256(of url: URL) throws -> String
}
public struct PosixInstallFileSystem: InstallFileSystem {
    public init()
    init(beforeRename: @escaping @Sendable (URL) throws -> Void)   // tests only: runs after the temp file of
}                                                                   // writeAtomically is written and fsynced, before rename(2)
public protocol TrashCan: Sendable { func moveToTrash(_ url: URL) throws -> URL? }
public struct FinderTrash: TrashCan { public init() }   // FileManager.default.trashItem(at:resultingItemURL:)
```

Tests use `RecordingTrash` (`Tests/FPMacServicesTests/Support/RecordingTrash.swift`, created by this WP), which moves files into a temporary "Trash" folder, records them, and can be told to throw for chosen file names. The real Trash is never touched (S5.3).

#### 7. File name (`InstallFileName.swift`)

`InstallFileName.stem(family:style:)` ports `ui/smart.py:122-125` with the macOS refinement of core.md WP-304 §3 (`fileName`):

1. `f` = `family` with Python `str.strip()` whitespace removed from both ends (the exact scalar set of core.md `Naming.cleanName`: U+0009–U+000D, U+001C–U+001F, U+0020, U+0085, U+00A0, U+1680, U+2000–U+200A, U+2028, U+2029, U+202F, U+205F, U+3000); `"Forged"` if that is empty (`ui/smart.py:21`). The same for `style` with `"Regular"`.
2. `raw = "\(f)-\(s)"`; replace every maximal run of `[<>:"/\\|?*]` and U+0000–U+001F with one `-` (`ui/smart.py:27`).
3. Remove leading `.` characters and then leading whitespace (same set); an empty result becomes `Forged-Regular` (UI-M3).

This is the same rule as core.md `Naming.fileName(family:style:)` minus `.ttf` (which ui-shell.md WP-505 uses for Save a Copy…). WP-304 lands after this WP, so the equality is tested by ui-shell.md AC-505-31. Declare `InstallFileName` `public`. Candidate file names are `<stem>.ttf`, `<stem>-1.ttf` … `<stem>-99.ttf` (`ui/install.py:25`, `:160-173`).

#### 8. `FontInstaller` (actor)

```swift
public actor FontInstaller: FontInstalling {
    public init(fontsFolder: URL, manifestURL: URL, registry: any SystemFontRegistry = CoreTextFontRegistry(),
                systemFolders: [(URL, FontDomain)] = FontInstaller.defaultSystemFolders,
                extraNames: (any FontNameSource)? = nil, fileSystem: any InstallFileSystem = PosixInstallFileSystem(),
                trash: any TrashCan = FinderTrash(), now: @escaping @Sendable () -> Date = Date.init)
    public static let defaultSystemFolders: [(URL, FontDomain)]   // /System/Library/Fonts .system, /Library/Fonts .local
    public static func standard() -> FontInstaller               // S1 locations; the app only
}
```

**`conflict(for:)`**: `query.family` and `query.postscriptName` must not be empty after trimming, else throw `.invalidQuery`. Read the manifest (a `version > 1` manifest makes every `ours` nil, so our fonts then block as `.youHave`; `install` refuses separately). Then `ConflictChecker.decide` over the index entries plus `extraNames?.nameEntries()`, with `ours` from §5 and `fileExists` = `FileManager.default.fileExists(atPath:)`.

**`install(source, expecting: q, confirmed:)`**. Steps (INSTALL-M1/M2/M3, INSTALL-8, TOOLING-2). There is no `await` between step 0 and step 10, so installs and uninstalls on one actor never interleave:

0. Read the manifest (§5). `version > 1` → throw `.manifestUnsupported`.
1. Sweep the fonts folder for stale staging files: remove files matching `^\..+\.[0-9a-f]{32}\.fpinstall$` with an mtime older than 10 minutes. Nothing else is touched.
2. **Validate** (INSTALL-M3):
   - the source must exist, else `.sourceMissing`;
   - `CTFontManagerCreateFontDescriptorsFromURL(source)` must return exactly 1 descriptor, else `.unreadable`;
   - its `kCTFontNameAttribute` must equal `q.postscriptName`, else `.unexpectedName`;
   - `ForgedMarker.isForged(source)`, else `.notForged`.
3. If the source is already inside `fontsFolder` and `ours(source)` matches `q`, return that font. Installing from the fonts folder itself is a no-op (port of test_install.py:72-77).
4. **Conflict check:** `c = conflict(for: q)`.
   - `.block` → throw `.conflict(c)`.
   - `.replaceOurs` or `.ask` → proceed only if `confirmed == c` (Equatable), else throw `.conflict(c)`. A stale confirmation fails, which avoids TOCTOU.
5. **Stage** (ADR-0009 step 2): create `fontsFolder` if missing (`createDirectory(withIntermediateDirectories: true)`), then `copyAndSync(source → fontsFolder/.<stem>.<uuid32>.fpinstall)`, where `uuid32` is `UUID().uuidString` lowercased without dashes. This is a dot-file on the same volume, so the rename is atomic, and fontd ignores dot-files.
6. **Place** (ADR-0009 step 3, INSTALL-8): for each candidate name in order, `renameExclusive(staged, candidate)`. On EEXIST, try the next; any other error removes the staged file and throws `.fileSystem(operation: "place", …)` at once. The file name in use by our previous copy is taken, so an Update writes a **new** file and never overwrites in place (TOOLING-2). No name left → remove the staged file and throw `.noFreeFileName(stem)`.
7. **Manifest #1:** remove any entry whose `file_name` (NFC) equals the placed name, then add the new entry (keeping the previous one) and write it. The exclusive rename proves no file had that name, so such an entry is stale. It is left behind when a step-9 write failed and a later Update reuses the freed name, and `ours` would otherwise match it first and disown the new copy (`reusedFileNameReplacesAStaleManifestEntry`). If that fails, remove the new file, keep the previous copy, and throw `.fileSystem("manifest", …)`.
8. **Remove the previous copies** (ADR-0009 step 4, INSTALL-M2): only when `c` was `.replaceOurs`, and only after the new file is in place. The previous copies are every manifest entry other than the new one whose file passes `ours` and whose folded full name equals `q.fullName` (normally one: `prev`; more after an earlier step-8 failure). Each goes to the Trash with `trash.moveToTrash`, like Font Book's duplicate resolution (INSTALL-9 verifier: the macOS backend always uses the Trash). A file that is no longer ours is left alone. If a move fails, continue with the others, then throw `.previousCopyNotRemoved(installed: new, previous: <the first that failed>, message:)`; the manifest keeps the entries that failed, so the next Update retries (they are ours with the same full name, so it gets `.replaceOurs` again).
9. **Manifest #2:** remove the entries of the trashed copies and prune entries whose file no longer exists. A failure here is only logged. A stale entry for a missing file is harmless until its name is reused, and step 7 drops it then.
10. Invalidate the name index, and return the new `InstalledFont`.

On any throw after step 5, remove the staged file if it still exists. **No CoreText registration** (INSTALL-7, ADR-0009): fontd activates the file and posts the distributed notification itself. There is nothing to broadcast (INSTALL-6).

**`uninstall(font)`** (INSTALL-9, INSTALL-M1):

0. Read the manifest; `version > 1` → throw `.manifestUnsupported`.
1. If the file doesn't exist → drop its manifest entry and return `.notInstalled`.
2. If `ours(font.fileURL.path) == nil` → throw `.notOurs(name: font.fullName)`. The file is untouched.
3. `trash.moveToTrash`; a failure → `.fileSystem("trash", …)`.
4. Remove the manifest entry, invalidate the index, and return `.movedToTrash(resultURL)`.

**`installedFonts()`**: the manifest entries that pass `ours`, sorted by full name.

**Errors** map to S8 (`englishText`). POSIX failures become `.fileSystem(operation:, message: String(cString: strerror(code)))` (for example `Permission denied`), and Cocoa errors `.fileSystem(operation:, message: error.localizedDescription)`. `operation` is one of `stage`, `place`, `manifest`, `trash`, `read`. The installer never throws a raw `NSError` (INSTALL-2 verifier: every backend error maps to one type).

### Acceptance criteria

The tests are in `Packages/FontPlaygroundMacKit/Tests/FPMacServicesTests/Install/` (except `Registry/SystemFontRegistryTests.swift` and `Safety/RegistrationSafetyTests.swift`). `fontsFolder`, the manifest and the Trash (`RecordingTrash`) are temporary. When a test needs CoreText to "see" an installed file (fontd's job in production), it registers it with `ProcessScopeFonts` and unregisters it in `defer`. Families carry a random tag (S5.4). Tests that need no system names construct the installer with `systemFolders: []` and `registry: EmptyRegistry()` (a test-local `SystemFontRegistry` stub in `Install/InstallTestSupport.swift` that returns nothing), so they don't build the real index; the rows marked "real" below use the defaults.

- **AC-403-1** `NameTableTests.parsesPlatformsAndEncodings`:
  - a fixture with `localized_family {"0x0804": "测试字体"}` gives `strings(nameID: 1) ⊇ ["FP Local <tag>", "测试字体"]`, and `preferred(1)` is the English name;
  - a hand-built table with a (1, 25, 33) record holding the GB2312 bytes `BB AA CE C4 CB CE CC E5` decodes to "华文宋体";
  - a (1, 0, 0) Mac Roman record decodes;
  - truncated data (a count larger than the records, an offset past the end) returns the valid records and doesn't crash.
- **AC-403-2** (port test_install.py:28-37) `ForgedMarkerTests.isForgedReadsNameID0`: a fixture with `notice: "Forged with Font Playground from: A"` → true; fixture A → false; a missing path → false; a file with the bytes "not a font" → false.
- **AC-403-3** `SystemFontRegistryTests.enumeratesWithoutNameLookups` (real CoreText):
  - `registeredFontFiles()` contains a path ending in `/Helvetica.ttc` with `Helvetica` among its PS names, with every path absolute and fragment-free;
  - `menuVisiblePostScriptNames()` contains `Helvetica` and not `LastResort`;
  - `registeredFaces(includeDisabled: true)` is non-empty, and every element with a path has `priority > 0`;
  - all three calls together take < 0.5 s;
  - after `ProcessScopeFonts.register` of a fixture (random tag) in `TestEnv.temporaryDirectory()`, `registeredFontFiles()` contains a file with the fixture's identity (S4; compare identities, not strings, F13) listing its PS name, and after `unregister` it does not;
  - the same holds for a fixture in a folder created under `/private/tmp` (CoreText lists it as `/tmp/…`, F13).
- **AC-403-4** (INSTALL-3/4, TOOLING-7, F1, F10) `FontNameIndexTests.install3Install4Tooling7SystemNamesAreFoundWithoutNameMatching`: over `SystemFontNameSource(registry: CoreTextFontRegistry(), folders: FontInstaller.defaultSystemFolders, userFontsFolder: <temp>).nameEntries()`, looking names up with `fold` in `familyKeys` / `fullNameKeys` / `postscriptName`:
  - `Helvetica` and `hELVETICA` → a `.system` entry;
  - PS `Helvetica-Bold` and full name `Helvetica Bold` → `.system`;
  - `Times` (hidden from menus; present only through the `/System/Library/Fonts` walk under SDK ≥ 26) → `.system`.

  With S6b: `苹方-简` and `宋体-简` → `.system`, if `PingFangSC-Regular` / `STSongti-SC-Regular` are menu-visible.
- **AC-403-5** `ConflictTests`: the table below, each row a named test. It ports test_build.py:293-355. `F` is a random-tag family, and "ours" means installed by the installer under test.

  | Test | Setup | `conflict(for:)` |
  |---|---|---|
  | `noConflictForANewName` | nothing named F | `.noConflict` |
  | `systemFontFamilyBlocks` (real) | query family `hELVETICA` | `.block(.systemHas(name: "hELVETICA"))` |
  | `localFolderBlocks` | a fixture named F in a temp folder injected as `(dir, .local)` | `.block(.installedForEveryone(name: F))` |
  | `activatedElsewhereBlocks` (real registry) | a fixture F registered at process scope from a temp dir outside every folder | `.block(.youHave(name: F))` |
  | `localizedFamilyBlocks` (real registry) | a fixture with `localized_family {"0x0804": "测试<tag>"}` registered as above; query family `测试<tag>` | `.block(.youHave(name: "测试<tag>"))` |
  | `userNonForgedFontBlocks` (INSTALL-M1) | a non-forged fixture F Regular copied into the user folder | `.block(.youHave(name: F))` |
  | `userForgedButNotOursBlocks` (INSTALL-10) | a forged fixture copied into the user folder, not in the manifest | `.block(.youHave(name: F))` |
  | `install10ChangedBytesAreNotOurs` | ours F Regular, then one byte of the installed file is changed by the test | `.block(.youHave(name: F))` |
  | `oursSameFullNameAsksToReplace` | ours F Regular; query F Regular | `.replaceOurs(font)` |
  | `oursOtherStyleIsNoConflict` | ours F Bold; query F Regular | `.noConflict` |
  | `vanishedFileIsNoConflict` | ours F Regular, then its file is deleted by the test | `.noConflict` |
  | `install5PostScriptNameOfYourOtherFontBlocks` | ours `甲<tag>` Regular with PS `X<tag>-Regular`; query `乙<tag>` with the same PS | `.block(.internalNameUsedByYourFont(postscriptName: "X<tag>-Regular", fullName: "甲<tag> Regular"))` |
  | `postscriptNameOfAnotherFontBlocks` (real) | query PS `Helvetica` with family F | `.block(.internalNameInUse(postscriptName: "Helvetica"))` |
  | `hiddenNameBlocks` | query family `.F` | `.block(.hiddenName)` |
  | `downloadableNameAsks` | `extraNames` returns a `.downloadable` entry F | `.ask(.appleOffersDownload(name: F))` |
  | `install10OursDetectedFromManifestAfterRestart` | ours F Regular, then a **new** `FontInstaller` on the same folder and manifest | `.replaceOurs` (test_build.py:341-355) |
- **AC-403-6** `FontInstallerTests.install1Install9Install12RoundTripInTemporaryFolder` (ports test_install.py:91-119; INSTALL-1, INSTALL-9, INSTALL-12):
  - installing a forged fixture F gives `fontsFolder/F-Regular.ttf` with the same bytes, and a manifest entry with the correct `sha256`, `size` and relative `file_name`;
  - `installedFonts()` lists it;
  - after `ProcessScopeFonts.register`, `CTFontManagerCopyAvailableFontFamilyNames()` contains F;
  - `uninstall` → `.movedToTrash`, the file is in `RecordingTrash`, and the manifest has no entry;
  - a second `uninstall` → `.notInstalled`;
  - no `*.fpinstall` file is left.
- **AC-403-7** (INSTALL-M3) `FontInstallerTests.installM3ValidatesWithCoreTextFirst`: a junk `.ttf` → `.unreadable`; a forged fixture whose PS differs from the query → `.unexpectedName`; a non-forged fixture → `.notForged`; a missing source → `.sourceMissing`. In each case the fonts folder is unchanged (the listing is compared before and after) and the manifest is untouched.
- **AC-403-8** (INSTALL-M1) `FontInstallerTests.installM1NeverTouchesFilesThatAreNotOurs`:
  - with a non-forged `F Regular` and a forged-but-unlisted `G Regular` in the fonts folder, installing F or G throws `.conflict(.block(.youHave))`;
  - `uninstall(InstalledFont(fileURL: that file, …))` throws `.notOurs`;
  - both files keep their bytes and inode.
- **AC-403-9** (INSTALL-8, INSTALL-9, TOOLING-2) `FontInstallerTests.install8Install9Tooling2UpdateWritesANewFileThenTrashesTheOld`:
  - Update of ours F Regular (a rebuilt forged fixture with the same names and different bytes) with `confirmed: .replaceOurs(old)` gives the new file `F-Regular-1.ttf`; `F-Regular.ttf` is gone from the fonts folder and recorded by `RecordingTrash`; the old file's inode was never written to (its bytes in the Trash folder equal the original); the manifest lists only the new file;
  - a second Update goes back to `F-Regular.ttf`;
  - after each Update, exactly one file with F's PS name is in the folder.
- **AC-403-10** (INSTALL-M2) `FontInstallerTests.installM2OldCopySurvivesAFailedPlacement`:
  - with an `InstallFileSystem` wrapper whose `renameExclusive` throws `POSIXError(.EXDEV)`, the Update throws `.fileSystem`, the old file is still present with its bytes, the manifest equals the one before, and no staging file is left;
  - with a `RecordingTrash` that throws for `F-Regular.ttf`, the Update throws `.previousCopyNotRemoved`, both files exist, and the manifest lists both. A retry with a working trash (same source; `confirmed:` = the conflict now reported, a `.replaceOurs`) ends with exactly one file with F's PS name in the folder and one manifest entry.
- **AC-403-11** (port test_install.py:49-61, the macOS form) `FontInstallerTests.foreignFileHoldingTheNameGetsANumberedName`: a non-forged file named `F-Regular.ttf` whose family is `Other` (so there is no conflict) → the install gives `F-Regular-1.ttf`, and the foreign file is untouched. With all 100 candidate names occupied → `.noFreeFileName(stem: "F-Regular")`.
- **AC-403-12** `FontInstallerTests.confirmationIsRequiredAndMustBeCurrent`:
  - `.replaceOurs` or `.ask` with `confirmed: nil` → `.conflict(c)` and nothing is written;
  - a `confirmed` value for a different font → `.conflict`;
  - `.block` with any confirmation → `.conflict(.block…)`.
- **AC-403-13** `InstallManifestTests.manifestIsAtomicVersionedAndRecovers`:
  - an interrupted write (`PosixInstallFileSystem(beforeRename:)` throws) leaves the previous manifest byte-identical and leaves no temp file behind;
  - `version: 2` → install and uninstall throw `.manifestUnsupported` and the file is unchanged;
  - invalid JSON → renamed to `installed.json.corrupt-…` and treated as empty;
  - unknown keys are tolerated.
- **AC-403-14** `InstallFileNameTests.stemFollowsTheReference`:
  - (`Test Mix`, `Regular`) → `Test Mix-Regular`;
  - (`a/b:c`, `B?`) → `a-b-c-B-`;
  - (`  `, ``) → `Forged-Regular`;
  - (`..Hidden`, `Bold`) → `Hidden-Bold`;
  - (`\u{3000}宋体\u{1C}`, `Regular`) → `宋体-Regular` (Python whitespace set, not Foundation's).
- **AC-403-15** (INSTALL-2, INSTALL-13) `InstallTextTests.install2Install13EnglishTextMatchesSpec`: every `ConflictReason`, `InstallConflict` question, `InstallError` and `UninstallOutcome` case renders exactly the S8 text, placeholders filled, and `(error as Error).localizedDescription == englishText` for every `InstallError`. No text contains "Windows".
- **AC-403-16** (INSTALL-14) `FontInstallerTests.install14ReadOnlyFontsFolderFailsPlainly`: with the fonts folder at mode `0555`, `install` throws `.fileSystem(operation: "stage", message: "Permission denied")`; no file and no manifest change. The mode is restored in `defer`.
- **AC-403-17** `FontInstallerTests.staleStagingFilesAreSwept`: `.x.<32 hex>.fpinstall` with an mtime 1 hour old is removed on the next install. `.x.<32 hex>.fpinstall` from 1 minute ago, `.DS_Store` and `._A.ttf` are untouched.
- **AC-403-18** (INSTALL-11, TOOLING-7) `FontInstallerTests.install11Tooling7UserFolderIsRecognisedThroughSymlinks`: (a) the fonts folder is created as `/private/tmp/fpmac-<UUID>/Fonts` and passed with that spelling; after installing F and registering the installed file at process scope, CoreText lists it as `/tmp/…` (F13), and still `conflict(for: F Regular)` is `.replaceOurs` (the entry is `.user` and `ours` is found). (b) The fonts folder is passed as a symlink `<tmp>/link` → `<tmp>/real`: `installedFonts()` lists F and `uninstall` works. The `/private/tmp` folder is removed in `defer`.
- **AC-403-19** (S5.2, INSTALL-6, INSTALL-7) `RegistrationSafetyTests.install6Install7NoRegistrationInSourcesAndProcessScopeOnlyInTests` passes over the real `Sources/` and `Tests/` trees. Self-tests on synthetic input (`RegistrationSafetyTests.scannerDetectsForbiddenRegistration`): `CTFontManagerRegisterFontURLs(urls, .process, true, nil)` in a test file is a violation; `CTFontManagerRegisterFontsForURL(url as CFURL, .user, &e)` in a test file is a violation; `CTFontManagerRegisterFontsForURL(url as CFURL, .process, &e)` in a test file is not; the same line in a `Sources/` file is; `let o: FaceOrigin = .user` anywhere is not.
- **AC-403-20** Performance (S6b): building the name index over the real Mac ≤ 1.5 s, and `conflict(for:)` on a warm index ≤ 50 ms (median of 20). The times are printed. (`FontNameIndexTests.indexBudgets`)
- **AC-403-21** (manual, macos, opt-in, touches the real `~/Library/Fonts`) Run by the maintainer only:
  1. Build a fixture with `family "FP fontd probe"` and the forged notice using `make_fonts.py`.
  2. Run a scratch Swift snippet (never committed) that calls `FontInstaller.standard().install(url, expecting: InstallQuery(family: "FP fontd probe", style: "Regular", postscriptName: "FPfontdprobe-Regular"))`.
  3. Open TextEdit → Format › Font › Show Fonts. Take a screenshot that shows "FP fontd probe" listed within 10 s.
  4. Call `uninstall`, and take a screenshot of the Trash containing the file.
  5. Empty nothing.

  Record the observed activation latency in the PR (the open question for INSTALL-7/8). A Codex agent never runs this AC; it leaves it unticked with "maintainer to verify".
- **AC-403-22** `make lint` and `make test` pass on macOS.
- **AC-403-23** (port test_install.py:72-77) `FontInstallerTests.installingFromTheFontsFolderIsANoOp`: calling `install` with the URL of our installed `F-Regular.ttf` itself returns the same `InstalledFont`, writes nothing (folder listing, inodes and manifest bytes unchanged) and trashes nothing.

### Verification
```bash
make lint
make mac-test
FP_APPLE_FONTS=1 make mac-test
```

### Notes for the implementer
- The audit prototype (`install_macos.py`) is **not** a model to copy. It name-matches (`find_family`), treats any name-ID-4 match as ours (INSTALL-M1), and unlinks the old copy before the rename (INSTALL-M2).
- Only `.process` registration, and only in tests, with the singular synchronous API (the INSTALL-7 verifier: the block API's handler may be called several times).
- Don't add a `to_trash` switch. Uninstall and the removal of the previous copy on Update both use the Trash (INSTALL-9 verifier: "the simplest sound option is for the macOS backend to always move to the Trash", as Font Book does when it resolves duplicates). `removeFile` is only for the app's own staging files and a just-placed file whose manifest write failed.
- WP-109 makes forged PostScript names unique and never equal to a non-forged font's. The checker still blocks collisions, because older forged files (for example from the Windows app, `Forged-Regular`) exist in the wild.
- `CTFontManagerCreateFontDescriptorsFromURL` on a dot-file works. fontd ignores dot-files, so staging never exposes a half-written font (ADR-0009).
- Reread audit `INSTALL-1` … `INSTALL-14`, `INSTALL-M1` … `INSTALL-M3` (the verifier lines win), and `TOOLING-2` and `TOOLING-7`.

#### Reference test porting map (WP-403)

| Reference test | New test | Note |
|---|---|---|
| test_install.py:17-19 `module_does_not_need_qt` | — | n/a (Swift) |
| :22-25 `full_name_comes_from_the_name_table` | `NameTableTests.parsesPlatformsAndEncodings` | full name = `preferred(4)` |
| :28-37 `is_forged_reads_the_notice_in_name_id_0` | `ForgedMarkerTests.isForgedReadsNameID0` | |
| :40-46 registry / LOCALAPPDATA | — | Windows only |
| :49-61 `copy_falls_back_to_numbered_name_when_locked` | `…foreignFileHoldingTheNameGetsANumberedName` | macOS: foreign file, not a lock |
| :64-69 `copy_overwrites_an_unlocked_earlier_copy` | `…install8Install9Tooling2UpdateWritesANewFileThenTrashesTheOld` | never overwrite in place (INSTALL-8) |
| :72-77 `copy_from_the_font_folder_itself_is_a_no_op` | `FontInstallerTests.installingFromTheFontsFolderIsANoOp` (AC-403-23) | |
| :80-88 `not_supported_elsewhere` | — | the package is macOS only |
| :91-119, :122-136 real install | `…install1Install9Install12RoundTripInTemporaryFolder` | temp folder + process scope |
| :139-142 `install_missing_file_raises` | `…installM3ValidatesWithCoreTextFirst` | `.sourceMissing` |
| test_build.py:283-355 conflicts | `ConflictTests.*` (AC-403-5) | |
| test_build.py:178-213 update/uninstall | AC-403-9/10 (installer part) | controller part is WP-505 |

#### Finding → regression test (WP-403)

| Finding | AC | Test |
|---|---|---|
| INSTALL-1, INSTALL-9, INSTALL-12 | AC-403-6 | `install1Install9Install12RoundTripInTemporaryFolder` |
| INSTALL-2, INSTALL-13 (wording) | AC-403-15 | `install2Install13EnglishTextMatchesSpec` |
| INSTALL-3, INSTALL-4, TOOLING-7 | AC-403-4, AC-403-5 | `install3Install4Tooling7SystemNamesAreFoundWithoutNameMatching`, `ConflictTests.*` |
| INSTALL-5 | AC-403-5 | `install5PostScriptNameOfYourOtherFontBlocks` |
| INSTALL-6, INSTALL-7 | AC-403-19 | `install6Install7NoRegistrationInSourcesAndProcessScopeOnlyInTests` |
| INSTALL-8, INSTALL-9, TOOLING-2 | AC-403-9 | `install8Install9Tooling2UpdateWritesANewFileThenTrashesTheOld` |
| INSTALL-10 | AC-403-5 | `install10OursDetectedFromManifestAfterRestart`, `install10ChangedBytesAreNotOurs` |
| INSTALL-11, TOOLING-7 | AC-403-18 | `install11Tooling7UserFolderIsRecognisedThroughSymlinks` |
| INSTALL-14 | AC-403-16 | `install14ReadOnlyFontsFolderFailsPlainly` |
| INSTALL-M1 | AC-403-8 | `installM1NeverTouchesFilesThatAreNotOurs` |
| INSTALL-M2 | AC-403-10 | `installM2OldCopySurvivesAFailedPlacement` |
| INSTALL-M3 | AC-403-7 | `installM3ValidatesWithCoreTextFirst` |

---

## WP-404: Downloadable fonts (Font Book hand-off; optional curated download)

**Goal:** Let users get Apple's downloadable fonts through Font Book, with the catalog updating automatically. Optionally, download a small curated set in the app, and only after explicit confirmation.
**Depends on:** WP-401 · **Env:** macos · **Size:** S–M · **Closes findings:** CATALOG-5

The WP has two parts:

- **Part A (required):** Font Book hand-off.
- **Part B (optional, marked "(B)" below):** the curated in-app download.

The WP is complete with Part A alone, or with A + B. Part B is never done partially: if it is not implemented, none of its files exist, and the PR says "Part B not included". Without Part B, in-app download beyond Font Book stays backlog B-7.

**Selected scope (D17): Part A only. Part B not included.** The app hands off to Font Book; curated in-app downloading remains backlog B-7.

### Scope
- In:
  - (A) `FontBookLauncher`, `fpmac-harness fontbook` and `fpmac-harness catalog --watch` (A2);
  - (B) `DownloadableFonts.curated`, `DownloadableFontList` (also a `FontNameSource` for WP-403), `FontDownloading` / `CoreTextFontDownloader`, `fpmac-harness downloadable`, and the allowlist entry in `NameLookupSafetyTests`.
- Out:
  - The menu item, the picker button and the confirmation and progress UI (WP-501/503 call these services; S8 text).
  - Parsing Apple's private MobileAsset XML (never: CATALOG-5 verifier).
  - Catalog refresh itself (WP-401 observes the change notification; the download completion also calls a refresh closure).

### Touched paths
- `Packages/FontPlaygroundMacKit/Sources/FPMacServices/Downloads/FontBookLauncher.swift` (new)
- (B) `…/Downloads/DownloadableFonts.swift` (new), `…/Downloads/DownloadableFontList.swift` (new), `…/Downloads/FontDownloading.swift` (new), `…/Downloads/CoreTextFontDownloader.swift` (new)
- `Packages/FontPlaygroundMacKit/Sources/FPMacHarness/main.swift` (edit: `fontbook`, `catalog --watch`, (B) `downloadable`)
- `Packages/FontPlaygroundMacKit/Tests/FPMacServicesTests/Downloads/*.swift` (new)
- `Packages/FontPlaygroundMacKit/Package.swift` (edit: harness test target), `…/Sources/FPMacHarness/CatalogWatch.swift` and `…/Tests/FPMacHarnessTests/*.swift` (new: deterministic harness coverage)
- (B) `Packages/FontPlaygroundMacKit/Tests/FPMacServicesTests/Safety/NameLookupSafetyTests.swift` (edit: the S5.1 allowlist entry, if WP-402 did not already add it, and the AC-404-10 self-test)

### Design

#### A1. Font Book hand-off

```swift
public protocol ApplicationOpening: Sendable {
    func applicationURL(bundleIdentifier: String) -> URL?      // NSWorkspace.shared.urlForApplication(withBundleIdentifier:)
    func openApplication(at url: URL) async throws             // NSWorkspace.shared.openApplication(at:configuration:)
}
public struct WorkspaceApplicationOpener: ApplicationOpening { public init() }
public enum FontBookError: Error, Hashable, LocalizedError { case fontBookMissing; public var englishText: String }   // S8
public struct FontBookLauncher: Sendable {
    public static let bundleIdentifier = MacServicesConstants.fontBookBundleIdentifier   // "com.apple.FontBook" (F12)
    public init(opener: any ApplicationOpening = WorkspaceApplicationOpener())
    public func open() async throws        // resolve, else .fontBookMissing; then open with a default OpenConfiguration
}
```

After Font Book downloads, installs or enables a font, fontd posts `kCTFontManagerRegisteredFontsChangedNotification`. WP-401's observer refreshes the catalog with no private-file parsing (CATALOG-5 verifier, first step). The UI label is `Get More Fonts…` (S8).

#### A2. Harness commands (`Sources/FPMacHarness/main.swift`, edit)

- `fpmac-harness fontbook`: `FontBookLauncher().open()`; prints `opened Font Book` and exits 0, or prints the error's `englishText` to stderr and exits 1.
- `fpmac-harness catalog --watch` (added to WP-401's `catalog` command): after the first refresh, `startObservingSystemChanges()`, then for every later published snapshot with `isComplete == true` print one line per face added (`+ family\tstyle\tpostscript`) and removed (`- …`), compared by `FaceKey`, until SIGINT. Incomplete snapshots do not replace the comparison baseline. SIGINT stops observation, cancels any refresh and exits 130 after returning through harness cleanup.
- (B) `fpmac-harness downloadable`: prints `DownloadableFontList().offers()` as `postscript\tfamily\tlanguage` lines. `--get <PS>` without `--yes-download` prints `Refusing to download without --yes-download.` to stderr and exits 2, starting nothing. `--get <PS> --yes-download` looks the PS up in `DownloadableFonts.curated` (unknown → exit 2), then streams `CoreTextFontDownloader().download(confirmation)`, printing one line per event, and exits 0 on `.finished`, else 1.

#### B1. Curated list (`DownloadableFonts.swift`)

```swift
public struct DownloadableFont: Hashable, Sendable, Codable {
    public var postscriptName: String, family: String, language: LanguageID
}
public enum DownloadableFonts { public static let curated: [DownloadableFont] }
```

The data is a Swift literal, so no resource or `Package.swift` change is needed. The PostScript names were read (read-only) from Apple's MobileAsset font catalog on the audit Mac (macOS 27), for the CJK families the CATALOG-5 verifier named. They are best-effort: a name Apple doesn't offer on a given macOS fails with `.notOffered` at download time.

| `language` (core.md `LanguageID` raw) | PostScript name → family |
|---|---|
| `chinese_s` | `SIL-Hei-Med-Jian` → Hei; `SIL-Kai-Reg-Jian` → Kai |
| `chinese_t` | `LiHeiPro` → LiHei Pro; `LiGothicMed` → Apple LiGothic; `LiSungLight` → Apple LiSung; `HiraginoSansTC-W3`, `HiraginoSansTC-W6` → Hiragino Sans TC |
| `japanese` | `BIZUDGothic-Regular`, `BIZUDGothic-Bold` → BIZ UDGothic; `BIZUDMincho-Regular` → BIZ UDMincho; `TsukuARdGothic-Regular`, `TsukuARdGothic-Bold` → Tsukushi A Round Gothic; `TsukuBRdGothic-Regular`, `TsukuBRdGothic-Bold` → Tsukushi B Round Gothic; `Osaka` → Osaka; `ToppanBunkyuMinchoPr6N-Regular` → Toppan Bunkyu Mincho |
| `korean` | `JCkg` → GungSeo; `JCfg` → PilGi; `NanumMyeongjo`, `NanumMyeongjoBold` → NanumMyeongjo; `NanumBrush` → Nanum Brush Script; `NanumPen` → Nanum Pen Script |

#### B2. Availability without name lookups (`DownloadableFontList.swift`)

```swift
public struct DownloadableFontList: FontNameSource {
    public init(registry: any SystemFontRegistry = CoreTextFontRegistry(), fonts: [DownloadableFont] = DownloadableFonts.curated)
    public func offers() -> [DownloadableFont]       // fonts whose PS is not in registry.menuVisiblePostScriptNames()
    public func nameEntries() -> [FontNameEntry]     // one .downloadable entry per offer: path nil, family keys = fold(family)
}
```

The only CoreText call is the enumeration `CTFontManagerCopyAvailablePostScriptNames()` (through the registry). **Never** match a catalog-only name to find out whether it is installed: that can block for 90 s or more and start a download (CATALOG-5).

#### B3. Download after confirmation (`FontDownloading.swift`, `CoreTextFontDownloader.swift`)

```swift
public struct DownloadConfirmation: Hashable, Sendable {
    public let font: DownloadableFont
    public var title: String { get }                 // S8
    public var message: String { get }               // S8
    init(font: DownloadableFont)                      // internal: only confirmation(for:) creates one
}
public enum DownloadEvent: Hashable, Sendable { case started, progress(Double), matched, finished }
public enum DownloadError: Error, Hashable, LocalizedError {
    case notOffered(DownloadableFont), failed(DownloadableFont, message: String), alreadyInstalled(DownloadableFont)
    public var englishText: String                   // S8
}
public protocol FontDownloading: Sendable {
    func confirmation(for font: DownloadableFont) -> DownloadConfirmation
    /// Starts only with a confirmation the UI showed and the user accepted. Cancelling the consuming Task cancels the download.
    func download(_ confirmation: DownloadConfirmation) -> AsyncThrowingStream<DownloadEvent, Error>
}
public struct MatchingUpdate: Hashable, Sendable {  // Sendable projection of the CoreText progress dictionary
    public var state: CTFontDescriptorMatchingState; public var percentage: Double?
    public var matchedCount: Int; public var errorDescription: String?
}
public struct CoreTextMatcher: Sendable {          // declared in CoreTextFontDownloader.swift (the allowlisted file, S5.1)
    public var start: @Sendable (_ postscriptName: String, _ handler: @escaping @Sendable (MatchingUpdate) -> Bool) -> Bool
    public init(start: @escaping @Sendable (String, @escaping @Sendable (MatchingUpdate) -> Bool) -> Bool)
    public static let live: CoreTextMatcher
}
public struct CoreTextFontDownloader: FontDownloading {
    public init(matcher: CoreTextMatcher = .live, registry: any SystemFontRegistry = CoreTextFontRegistry(),
                onInstalled: @escaping @Sendable () async -> Void = {})   // the app passes { try? await catalog.refresh(.incremental) }
}
```

- **`CoreTextMatcher.live`** (the only place allowed to name-match, S5.1):
  1. `let d = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: ps] as CFDictionary)`.
  2. `CTFontDescriptorMatchFontDescriptorsWithProgressHandler([d] as CFArray, nil) { state, params in … }`. The handler runs on a private serial queue (`CTFontDescriptor.h`: "called on a private serial queue on OS X 10.15 … and later"). It converts `params` to a `MatchingUpdate`: `kCTFontDescriptorMatchingPercentage`, the count of `kCTFontDescriptorMatchingResult`, and the `localizedDescription` of `kCTFontDescriptorMatchingError`.
  3. It returns the handler's Bool (false cancels).
- **`download`** returns an `AsyncThrowingStream` built with `makeStream()`; the matcher is started from a detached task, never on the main thread:
  - If the PS is already in `menuVisiblePostScriptNames()` → the stream throws `.alreadyInstalled(font)` and the matcher is never started.
  - States map to events: the first `.didBegin` or `.willBeginDownloading` → `.started` (once); `.downloading` with a percentage → `.progress(percentage / 100)`; `.didMatch` with `matchedCount > 0` → `.matched` (once); `.didFailWithError` → finish throwing `.failed(font, message: errorDescription ?? "unknown error")`. Other states yield nothing.
  - On `.didFinish` (if the stream has not finished yet): if `.matched` was yielded, yield `.finished`, `await onInstalled()`, then finish; otherwise finish throwing `.notOffered(font)`.
  - The handler returns `false` (which tells CoreText to stop) once the stream has finished or its consumer was cancelled (`continuation.onTermination`); every later call also returns `false` and yields nothing. `onInstalled` is never called after a cancellation.
  - `start` returning false → finish throwing `.failed(font, message: "couldn't start")`.
- **Confirmation first.** The UI (WP-503) shows `confirmation.title` and `.message` with the buttons `Download` and `Cancel`, and calls `download` only on `Download`. Downloading installs system-wide Apple assets (CATALOG-5), so it is never automatic, never in tests, and never on the main thread.
- **Conflict hook.** The app passes `DownloadableFontList()` as `extraNames` to `FontInstaller` (WP-403). A forged font named like an offered family then gets `.ask(.appleOffersDownload)` rather than silently colliding after a later download (INSTALL-4 verifier: a warning is enough).

### Acceptance criteria

The tests are in `Packages/FontPlaygroundMacKit/Tests/FPMacServicesTests/Downloads/`.

- **AC-404-1** (A, CATALOG-5) `FontBookLauncherTests.catalog5OpensFontBookByBundleIdentifier`: with a recording fake `ApplicationOpening`, `open()` asks for `com.apple.FontBook` and opens the returned URL once. With the fake returning nil → `FontBookError.fontBookMissing`, `englishText == "Font Book isn't available on this Mac."`, and nothing opened.
- **AC-404-2** (A) `FontBookLauncherTests.fontBookResolvesOnThisMac`: `WorkspaceApplicationOpener().applicationURL(bundleIdentifier: "com.apple.FontBook")` is non-nil and ends with `Font Book.app`. It resolves only and launches nothing.
- **AC-404-3** (A, manual, macos, opt-in, touches the real `~/Library/Fonts` through Font Book; run by the maintainer only, a Codex agent leaves it unticked with "maintainer to verify") Run `swift run --package-path Packages/FontPlaygroundMacKit fpmac-harness fontbook`: Font Book comes to the front (screenshot). Then run `fpmac-harness catalog --watch` (A2). Build a synthetic font with `make_fonts.py` (family `FP Watch Probe`), double-click it and click Font Book's Install button. Within 5 s the harness prints a `+` line for `FP Watch Probe`. Remove it in Font Book: a `-` line follows. Attach screenshots of both harness lines.
- **AC-404-4** (B) `DownloadableFontsTests.curatedListIsWellFormed`:
  - every entry's PS name matches `^[A-Za-z0-9-]{1,63}$`;
  - its family is non-empty;
  - its `language` ∈ {`chinese_s`, `chinese_t`, `japanese`, `korean`};
  - PS names are unique;
  - the list equals the B1 table.
- **AC-404-5** (B) `DownloadableFontListTests.availabilityUsesEnumerationOnly`: with a `FakeRegistry` whose menu-visible set contains `Osaka` but not `BIZUDGothic-Regular`, `offers()` contains the latter and not the former. `nameEntries()` gives `.downloadable` entries with `path == nil`. The fake registry saw only `menuVisiblePostScriptNames()` calls.
- **AC-404-6** (B) `FontDownloaderTests.progressMapsAndCompletes`: with a fake `CoreTextMatcher` replaying `didBegin, willBeginDownloading, downloading(25), downloading(100), didFinishDownloading, didMatch(1), didFinish`, the stream yields `[.started, .progress(0.25), .progress(1.0), .matched, .finished]` and `onInstalled` is called once. Replaying `didBegin, didFinish` with no match → throws `.notOffered(font)`. `didBegin, didFailWithError("x"), didFinish` → throws `.failed(font, message: "x")`, and the handler returns `false` for the `didFinish` call.
- **AC-404-7** (B) `FontDownloaderTests.cancellationStopsCoreText`: cancelling the consuming task after `.started` makes the fake handler's next call return false, and `onInstalled` is not called. An already-installed PS (in the fake registry's menu-visible set) → `.alreadyInstalled(font)`, and the matcher is never started.
- **AC-404-8** (B) `FontDownloaderTests.confirmationIsRequiredAndWorded`: `confirmation(for: BIZ UDGothic)` has `title == "Download “BIZ UDGothic” from Apple?"` and the S8 message. `DownloadConfirmation`'s initializer is not public: a source check (`SourceAudit`, S5) asserts that `Sources/FPMacServices/Downloads/FontDownloading.swift` contains `init(font: DownloadableFont)` and no `public init(` inside `struct DownloadConfirmation`, and that no other file under `Sources/` declares an extension of `DownloadConfirmation`.
- **AC-404-9** (B) `ConflictTests.downloadableNameAsks` (WP-403) passes with `DownloadableFontList` backed by a fake registry, for query family `BIZ UDGothic` → `.ask(.appleOffersDownload(name: "BIZ UDGothic"))`.
- **AC-404-10** (B) `NameLookupSafetyTests.sourcesContainNoNameLookups` passes with the allowlist entry for `Sources/FPMacServices/Downloads/CoreTextFontDownloader.swift`. A self-test (`NameLookupSafetyTests.downloaderAllowlistIsFileSpecific`) feeds `CTFontDescriptorMatchFontDescriptorsWithProgressHandler(` as the text of `Sources/FPMacServices/Downloads/FontDownloading.swift` and gets a violation, and as the text of `CoreTextFontDownloader.swift` once and gets none.
- **AC-404-11** (B, manual, optional, downloads from Apple, run only by the maintainer; a Codex agent never runs it) `fpmac-harness downloadable` lists the curated offers not installed on this Mac. `fpmac-harness downloadable --get <PS> --yes-download` downloads one (for example `Osaka` if offered) and prints progress to `finished`. A following `fpmac-harness catalog` lists the family. The PR includes the output tail.
- **AC-404-12** `make lint` and `make test` pass on macOS.

### Verification
```bash
make lint
make mac-test
swift run --package-path Packages/FontPlaygroundMacKit fpmac-harness fontbook          # AC-404-3 (manual)
```

### Notes for the implementer
- Don't parse `/System/Library/AssetsV2/com_apple_MobileAsset_Font8/*.xml` at runtime. It is undocumented, and its schema changes (the `FontInfo4` key today).
- `kCTFontCollectionDisallowAutoActivationOption` protects enumeration only. It does not make name matching safe.
- The download handler is `@Sendable` and runs off the main thread. Hop to the stream continuation only, never to UI state.
- Reread audit `CATALOG-5` (the verifier lines) and `INSTALL-4` (verifier).
