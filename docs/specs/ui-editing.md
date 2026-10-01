# UI editing surfaces: recipe column, font picker, preview

> Scope: WP-502, WP-503, WP-504 · Env: macos · Architecture refs: docs/architecture.md §1 (goal 2, preview honesty), §2, §4 (steps 4–6), §5, §8 · ADRs: 0005, 0006, 0007, 0008, 0011, 0012

## Context

The original app is a one-screen mixer (`reference/fontplayground-py/fontplayground/ui/app.py:1-6`). The left column is either the **recipe** ("Your font") or, while the user chooses a font, the **font picker**. The right side is the **preview** of the user's own text, drawn the way the result will draw it. The three surfaces never keep state of their own: they read `ForgeModel` and every action goes back through it (`ui/recipe.py:1-9`).

| Surface | Original | What it does |
|---|---|---|
| Recipe column | `ui/recipe.py` (676 lines), wording in `ui/languages.py:128-181` | Empty state with two steps. Then one card per material, top to bottom, main font first: colour dot, role ("MAIN FONT", "FOR CHINESE"), name drawn in the font itself, native name, Style, Size and Weight (not on the main font), a plain-words "Draws …" line, a licence line. The ⋯ menu has Make main font, Move up, Move down and Remove. A next-step prompt appears when exactly one font cannot draw the sample. "＋ Add a font for another language…" opens a language menu. |
| Font picker | `ui/picker.py` (757 lines) | Replaces the recipe column. Title, search ("English or native name"), "Show fonts for" language filter, "Suggested for your text" then "All <language> fonts · n". Each family row is drawn in its own face with its native name and the language's sample line. ↑/↓ moves and the preview tries the current row after 120 ms. Return uses it. Esc, Back or Cancel goes back. |
| Preview | `ui/preview_pane.py` (263), `ui/preview.py` (322), `ui/mix.py` | Editable plain text. A `QSyntaxHighlighter` gives every character the format of the font that draws it (`Mix.source_of`, the build's own rule). Characters no font draws get a "missing" background and are listed under the preview with a button that finds a font. Also: Colour by font, a size slider (10–96 pt), Sample ▾ presets, a trial banner while picking, and the built font after a build. |

What the audit found, and how this spec answers it:

- **UI-1, CATALOG-2** (major/blocker): hidden `.`-prefixed faces, `System Font` and `.LastResort` were listed, sorted first, preselected and suggested. The catalog store (WP-401) drops them already. The picker drops them again with its own rule (defence in depth) and never suggests a face with `suspicious_coverage` (WP-503).
- **CATALOG-11** (polish): suggestions passed over the platform's own font for a language (PingFang SC for zh-Hans). WP-503 looks up CoreText's choice once per launch and passes it to WP-304's tie-breaker. It also makes it the initial row when nothing is suggested.
- **UI-14** (polish, verifier: no change needed): overlay scrollers over the selected row are native behaviour. WP-503 uses a stock `NSTableView` with system scrollers and selection drawing, and adds no custom inset.
- **UI-M6** (polish): no pinch or ⌘-scroll zoom. WP-504 adds pinch, ⌘-scroll and ⌘+/⌘−/⌘0 on top of the slider.
- **NATIVE-M1** (major): Qt shaped with its bundled HarfBuzz, so even the built-font preview could differ from what Mac apps draw. WP-504 draws with CoreText (TextKit 2 → CoreText) from URL-created fonts with the LastResort cascade. Tests inspect the runs with `CTLine` (ADR-0011).
- **UI-5** (major; not assigned to a WP in `docs/plan.md`): partial stylesheets drew broken combo and spin boxes. WP-502 uses stock SwiftUI/AppKit controls only, so the defect cannot occur. See the WP-502 ACs.
- **UI-M2 / ADR-0008**: AAT-only fonts shape in a CoreText preview but not in the result. The engine refuses complex groups a material cannot shape (WP-107). The picker hides those fonts for complex languages and offers a toggle that shows them greyed, with the reason (WP-503). A card says so when the plan gives such a font a complex group anyway (WP-502).
- **UI-6, UI-12, UI-13, UI-17, UI-7**: Mac key words ("Return uses it", "⌘Z"), Mac key bindings through `doCommand(by:)`, and VoiceOver labels on every control. The type scale follows system text styles. IME works because AppKit text input is used everywhere. WP-507 audits all of this later; these WPs build it in from the start.

Differences from the original that are deliberate:

| Original | Here | Why |
|---|---|---|
| Plan debounced 150 ms; cards showed "…" until it caught up (`ui/model.py:31`, `ui/recipe.py:38`) | Plan recomputed synchronously; cards are always current | ADR-0006 |
| Picker headers upper-case ("SUGGESTED FOR YOUR TEXT") | Sentence case ("Suggested for your text", "All Chinese fonts · 37"), drawn as native group rows | macOS list conventions; the upper case came from the Windows styling |
| Fonts loaded into Qt by family name (`ui/fonts.py:55-65`) | `CTFont` from the file URL, LastResort cascade, opsz pinned (WP-402) | CATALOG-4, NATIVE-3, NATIVE-M3 |
| Qt emboldening when weight > weight class + 100 (`ui/fonts.py:14,87-90`) | Stroke-and-advance approximation of the engine's synthetic bold, from Δ ≥ 50 (`engine/prepare.py:165-171`, `engine/synth_bold.py:11-13`) | Closer to the result |
| Line height of each preview line = tallest font on it | Fixed line height from the base (line-spacing) material | The result takes its vertical metrics from the base font (parity checklist, "vertical metrics from the main font") |
| ⋯ menu on the preview with app commands | Menu bar (WP-501) | UI-2 |
| "Enter uses it", "Ctrl+Z" | "Return uses it", "⌘Z" | UI-6, UI-12 |

**Evidence from experiments run for this spec** (Apple M5 Pro, macOS 27, Swift 6.4; `-O` unless marked debug). The audit Mac had 411 font files and 422 families. This Mac has 246 visible families, so the performance harnesses below use 420 synthetic rows mapped onto installed files.

| Measurement | Result |
|---|---|
| `CTFontManagerCopyAvailableFontURLs` / descriptors for every file via `CTFontManagerCreateFontDescriptorsFromURL` | 655 URLs, 265 files in 0.040 s / 0.106 s for all files |
| One picker row: fonts at 13 and 18 pt from a URL descriptor + 2 `CTLine`s | 0.48 ms cold, 0.15 ms warm |
| Georgia with `"Hamburg 你好"`: default cascade / cascade `[LastResort]` | `[Georgia×8, STSongti-SC-Regular×2]` / `[Georgia×8, LastResort×2]` (reproduces NATIVE-3) |
| Off-screen view-based `NSTableView`, 420 rows × 64 pt, cells drawing 2 `CTLine`s, fonts created on first draw | first reload + draw 41 ms debug (31 ms `-O`); 83 half-page scroll steps: p95 13.7 ms, max 16.6 ms debug (p95 8.4, max 15.3 `-O`) |
| TextKit 2 `NSTextView`, fonts re-applied to the edited paragraph in `textStorage(_:didProcessEditing:…)` | 2,000 UTF-16 units in 50 lines: keystroke p95 0.69 ms (restyle 0.05 ms). One 2,000-unit paragraph: keystroke p95 22 ms (restyle 1.7 ms; the rest is TextKit layout). Full restyle + layout of 2,200 units: 6 ms |
| Marked text (IME) during `setAttributes` restyles | Marked range kept, commit works, committed character gets the right font |
| `readablePasteboardTypes = [.string]` with RTF + string on the pasteboard | Plain text inserted; only the typing attributes, then the restyle, apply |
| `CTFont` under Swift 6 language mode | Not `Sendable` → font creation stays on the main actor (see S6) |
| `@MainActor` class conforming to `NSTextStorageDelegate` (Swift 6 mode) | Compile error (conformance crosses into main-actor code) → S6 rule 5 |
| `CTFontCreateForStringWithLanguage` base font | `.system` UI font → private `.PingFangUITextSC-Regular`, `.HiraKakuInterface-W4`…; `.user` font (Helvetica) → `PingFangSC-Regular`, `HiraginoSans-W3`, `AppleSDGothicNeo-Regular` (WP-503) |
| Fixture fonts without U+0020 | CoreText draws their spaces with the `[LastResort]` cascade → fixtures map U+0020 (S5) |
| Arabic letters + presentation forms, **no GSUB** / GSUB with only `latn` | CoreText joins through the presentation forms / draws unjoined (nominal glyphs) → AC-504-15 |

---

## Shared definitions

### S1. Where the code goes (ownership inside FPAppUI)

All paths are under `Packages/FontPlaygroundMacKit/`. One WP owns each file. The only exceptions are the WP-501 seams in S2.3 and the shared file in S3.

```
Sources/FPAppUI/Editing/
  EditingShared.swift            S3 (exact content; WP-501 or the first of 502–504 to land)
  SidebarView.swift              seam (WP-501); WP-503 edits it to show the picker
  Recipe/                        WP-502
    RecipeColumn.swift           SwiftUI column (replaces the WP-501 placeholder body)
    FontCardView.swift
    RecipeColumnState.swift      pure presentation state + RecipeAction
    RecipeText.swift             strings and pure helpers (port of recipe.py helpers)
    ShapingRule.swift            complex-shaping check shared by card lines (see S2.1)
  AppModel+Recipe.swift          WP-502: perform(_ action: RecipeAction)
  Picker/                        WP-503
    FontPickerView.swift         SwiftUI shell (replaces the WP-501 placeholder body)
    PickerModel.swift            @Observable picker state, rows, keyboard, candidate
    PickerRows.swift             pure row building (port of picker.py _build_rows/_pick_row)
    PickerText.swift             strings (titles, statuses, section titles, trial banner)
    FontListView.swift           NSViewRepresentable around PickerTableView (NSTableView)
    FontRowCellView.swift        NSTableCellView drawing CTLines
    RowFontCache.swift           LRU + per-turn budget of CTFonts for rows
    SearchFieldView.swift        NSViewRepresentable around NSSearchField (key commands)
  AppModel+Picker.swift          WP-503: openPicker, usePickedFace, cancelPicker, findFont
  Preview/                       WP-504
    PreviewPane.swift            SwiftUI pane (replaces the WP-501 placeholder body)
    PreviewTextEditor.swift      NSViewRepresentable + Coordinator
    PreviewTextView.swift        NSTextView subclass (TextKit 2): paste, zoom gestures
    PreviewStyler.swift          NSTextStorageDelegate: fonts per run
    PreviewRuns.swift            pure: sources per paragraph, run grouping
    PreviewConfiguration.swift   pure-ish: what is drawn (empty/mix/trial/built), fonts, missing
    PreviewText.swift            strings (missing note, size text, badge)
    PreviewController.swift      handle for menu commands (zoom, samples, focus)
  AppModel+Preview.swift         WP-504: zoom and sample commands, missing-note action
Sources/FPMacServices/PlatformFontPreferences.swift   WP-503 (CATALOG-11 lookup)
Tests/FPAppUITests/            RecipeColumn*Tests.swift (502), Picker*Tests.swift (503), Preview*Tests.swift (504)
Tests/FPMacServicesTests/PlatformFontPreferencesTests.swift  (503)
```

### S2. Interfaces this spec consumes

Other specs own these names. If the owning spec spells a name differently, use its spelling and keep the behaviour described here. Don't invent parallel APIs.

#### S2.1 FPCore (core.md)

The names below are core.md's spelling (checked against core.md WP-301–304). Where this spec's body uses a shorter informal form, the right-hand column of the spelling map at the end of this section is authoritative.

| Name (core.md spelling) | Owner | Meaning (reference) |
|---|---|---|
| `FaceRecord`, `FaceKey`; `face.key`, `.family`, `.style`, `.postscriptName`, `.localNames`, `.weightClass`, `.italic`, `.isVariable`, `.axes`, `.supported`, `.hidden`, `.suspiciousCoverage`, `.embedding`, `.aat.morx`, `.otScripts.gsub`, `.shapesGroups` (`Set<ScriptGroup>?`, nil = unknown), `.unshaped`, `.coverage.contains(_ cp: UInt32)`, `.plannableCoverage` (core.md S7) | WP-301, contracts §3 | one face (`catalog/face.py:18-88`) |
| `ScriptGroup` (15 ids), `ScriptGroup.of(_ cp: UInt32)` / `.of(_ scalar: Unicode.Scalar)`, `group.language: LanguageID?`, `group.needsShaping` (the complex groups: hebrew, arabic, indic, southeast_asian) | WP-301 | `engine/scripts.py:16-62`, `ui/languages.py:66-71`, ADR-0008 |
| `LanguageID` (raw values are the reference ids: `"latin"`, `"chinese_s"`, …, `"any"`), `Language` (`id`, `groups`, `minimums`, `markers`, `pickerSample`, `textSample`), `Languages.all`, `Languages.language(_ id: LanguageID)`, `Languages.language(rawID:) -> Language?`, `Languages.coversWell(_ face:, _ language:)` | WP-301 | `ui/languages.py:23-60,106-115` |
| `Languages.languagesForMissing(_ scalars: [Unicode.Scalar]) -> [Language]`, `Languages.namedGroups(_ tally:)`, `Languages.roleTitle(_ tally: [ScriptGroup: Int]) -> RoleTitle`, `Languages.withLanguageLine(_ text:, _ language:)`, `Languages.languageOfTally(_ tally:) -> LanguageID`, `Samples.presets` (`id`, `text`) | WP-301 (parity item "Each card says in plain words what its font draws (502, 301)") | `ui/languages.py:66-71,91-103,118-196`, `ui/recipe.py:147-157` |
| Wording: `EnglishText.languageLabel(_ id:)`, `.languageShortLabel(_ id:)`, `.joinLabels(_ ids:limit:joiner:)`, `.draws(_ groups:)`, `.roleTitle(_ RoleTitle)`, `.samplePresetLabel(_ id:)`, `.groupLabel(_:)` | WP-301 | FPCore has no display strings on its types. FPAppUI calls these in v1 and WP-507 swaps them for catalog-backed `ModelText` (ui-shell.md §S8) |
| `TextUtil.isIgnorable(_ scalar:)`, `TextUtil.visibleScalars(in text:) -> [Unicode.Scalar]` (sorted, unique, **scalars, not grapheme clusters**) | WP-301 | `ui/textutil.py:7-23` |
| `Mix` (`fonts: [MixFont]` with `face`, resolved `weight: Int?`, resolved `scale: Double`, `isAvailable`; `rules`; `baseIndex`), `mix.source(of: UInt32)` / `source(of: Unicode.Scalar) -> Int?`, `mix.runs(in:) -> [MixRun]` (`utf16Range`, `scalarRange`, `source`), `mix.missingCharacters(in:)` | WP-302 | `ui/mix.py:18-43`, `engine/planner.py:10-16` |
| `Recipe` (value type): `init()`, `materials` (`face`, `weight`, `scale`, `availability`, `isAvailable`, `key`), `main: FaceRecord?`, `keys`, `baseIndex: Int?`, `sampleText` (read-only; write with `setSampleText(_:)`), `analyze() -> RecipeAnalysis` (`tallies: [[ScriptGroup: Int]]` per material, `problems`, `missingSampleCharacters`), `missingSampleCharacters()`, `mix()`, `mix(trying:replacing:for:)`, `add(_:for:)`, `replace(_:with:keepAdjustments:)`, `remove(_:)`, `move(_:to:)`, `setAdjustments(for:weight:scale:)`, `setBase(_ key: FaceKey?)` (nil = back to the main font), `forgeSpec()` | WP-303 | `ui/model.py:303-405,495-572` |
| `RecipeProblem.cannotShape(index:group:)` (a rule that gives a complex group to a face that can't shape it, core.md S7) | WP-303 | ADR-0008, engine `aat_unsupported_script` |
| Conformances this spec relies on: `FaceKey: Hashable, Sendable`; `FaceRecord: Hashable, Sendable`; `Mix: Equatable` (for `PreviewTrial` and `PreviewMode`); `ForgeSpec: Equatable` | WP-301, WP-302 | ADR-0006 (value types) |
| `recipe.suggestions(for: LanguageID, in: FaceCatalog, limit:, preferences: PlatformPreferences)` (CATALOG-11 tie-breaker; build the catalog with `FaceCatalog(catalogFaces)` and the preferences as `PlatformPreferences([id: names.map { .postscriptName($0) }]).appending(.macOS)`), `Smart.defaultFace(_ faces:, main:)`, `Recipe.applyRealWeights(in:) -> [WeightSwap]` | WP-304 | `ui/model.py:503-512`, `ui/smart.py:41-53,157-193` |

Shaping rule (used by WP-502 and WP-503): a face **can shape** language L when every group `g` in `L.groups` with `g.needsShaping` is in `face.shapesGroups` (a nil `shapesGroups` counts as "can shape": unknown never blocks, core.md S7). With plannable coverage (core.md S7) a card's tally **never** holds characters its face can't shape, because the planner gives them to another font or to nobody, so WP-502 finds shaping problems from `face.unshaped`, the sample text and `RecipeProblem.cannotShape`, never from the tally.

**Spelling map** (informal name in this spec's body → core.md name):

| Body text says | Use |
|---|---|
| `Language(id: x)` | `Languages.language(rawID: x)` |
| `language.label`, `language.shortLabel` | `EnglishText.languageLabel(language.id)`, `EnglishText.languageShortLabel(language.id)` |
| `language.coversWell(face)` | `Languages.coversWell(face, language)` |
| `Languages.drawsText(tally)` | `EnglishText.draws(Languages.namedGroups(tally))` |
| `Languages.roleTitle(tally)` (as text) | `EnglishText.roleTitle(Languages.roleTitle(tally))` |
| `Languages.groupLanguage[G]` | `G.language` |
| `joinLabels(langs)` | `EnglishText.joinLabels(langs.map(\.id))` |
| `recipe.mix(with:replacing:for:)` | `recipe.mix(trying:replacing:for:)` |
| `setAdjustment` | `setAdjustments(for:weight:scale:)` |
| `recipe.tallies` | `model.analysis.tallies` (WP-501's `AppModel.analysis`, recomputed on every recipe change, ui-shell.md §S3), or `recipe.analyze().tallies` inside pure helpers that get only a `Recipe` (compute `analyze()` once per state build) |
| `recipe.isEmpty` | `recipe.materials.isEmpty` |
| `recipe.sampleText = x` | `recipe.setSampleText(x)` |
| `mix.sourceOf(_:)` | `mix.source(of:)` |
| `recipe.suggestions(for:limit:preferredPostScriptNames:)` | `recipe.suggestions(for:in:limit:preferences:)` as in the table above |
| `complexShapingGroups`, `ScriptGroup.requiresShaping` | `ScriptGroup.needsShaping` |

#### S2.2 FPMacServices (mac-services.md)

| Name used here | Owner | Needed behaviour |
|---|---|---|
| `FontRendering` (contracts §7), implemented by `FontRenderer` | WP-402 | (a) a `CTFont` for a `FaceRecord` at a point size and optional weight: URL descriptor, never registered, cascade `[LastResort]`, opsz pinned, `wght` set and clamped for variable faces; (b) a `CTFont` for a built file URL at a size, made the same way; (c) the characters a built file maps (`CTFontCopyCharacterSet` on (b) is acceptable). Called on the main actor, synchronously. mac-services.md WP-402 spelling: (a) `try renderer.font(for: FaceRenderRequest(face:pointSize:weight:scale:)).ctFont` (the `RenderedFont` also carries `syntheticBold` for the preview's stroke and kern); (b) `try renderer.builtFont(at: url, pointSize:).ctFont`; (c) `renderer.coverage(of: rendered) -> CodepointSet` or `CTFontCopyCharacterSet(rendered.ctFont)`. Both methods are synchronous, non-isolated and `throws` (`RenderError`). For a built font a throw is handled as described in WP-504 (fall back to the mix). For a material face (a file that vanished since the last scan) the run is drawn with the LastResort descriptor (`LastResort.shared.descriptor`, mac-services.md WP-402 §2) at the same size, so its characters look missing, and the error is logged once per face |
| `FontCataloging` | WP-401 | the visible `[FaceRecord]` (hidden faces dropped, deduped), scan progress, counts of hidden, duplicate and unreadable items |

#### S2.3 WP-501 seams (ui-shell.md)

WP-501 creates these so that 502, 503 and 504 can be implemented in parallel. **If a seam is missing on `main` when you start, add it exactly as written here.** Put stored properties in `AppModel`'s declaration and methods in `AppModel+EditingSeams.swift`. If two in-flight WPs add the same seam, keep one copy when you rebase.

| Seam | Declaration | Default / stub behaviour | Real behaviour from |
|---|---|---|---|
| Recipe | `var recipe: Recipe` | — | 501 |
| Visible catalog | `var catalogFaces: [FaceRecord]` (catalog order) | `[]` | 501/401 |
| Catalog status | `var catalogStatus: CatalogStatus`, where `struct CatalogStatus: Equatable, Sendable { var isScanning = false; var done = 0; var total = 0; var faceCount = 0; var unreadable: [Unreadable] = []; var hiddenCount = 0; var duplicateCount = 0; struct Unreadable: Equatable, Sendable { var path: String; var message: String } }` | idle, zeros | 501/401 |
| Building | `var isBuilding: Bool = false { didSet { if isBuilding { pickRequest = nil; trial = nil } } }` (a build closes the picker, `ui/app.py:267-270`) | `false` | 501/505 |
| Picker request | `var pickRequest: PickRequest?` (non-nil = the sidebar shows the picker) | `nil` | 503 |
| Open picker | `func openPicker(_ request: PickRequest)` | sets `pickRequest` unless `isBuilding` | 503 (full) |
| Trial | `var trial: PreviewTrial?` | `nil` | 503 writes, 504 reads |
| Built font | `var builtFont: BuiltFontPreview?` | `nil` | 505 writes, 504 reads |
| Preview preferences | `var previewPointSize: Int` (10…96, default 30), `var colourByFont: Bool` (default false), both persisted in `UserDefaults` | as stated | 501 persists, 504 edits |
| Renderer | `let renderer: any FontRendering` | — | 501 |
| Advanced | `func showAdvanced()` | no-op | 501/506 |
| Menu stubs | `func findFont()`, `func zoomPreviewIn()`, `func zoomPreviewOut()`, `func resetPreviewZoom()`, `func applySample(id: String)` in `AppModel+EditingSeams.swift` (ui-shell.md §S2 gives their stub behaviour; WP-501's menu calls them) | as ui-shell.md §S2 | 503 (`findFont`) and 504 (the rest) delete the stubs when they add the real versions |
| Placeholders | `struct RecipeColumn: View`, `struct FontPickerView: View`, `struct PreviewPane: View`, each `init(model: AppModel)`, placeholder body | `Text` placeholder | 502 / 503 / 504 replace the bodies |
| Sidebar switch | `struct SidebarView: View { … if model.pickRequest != nil { FontPickerView(model:) } else { RecipeColumn(model:) } }` | as stated | 501; 503 adds the transition and focus |
| Test construction | An `AppModel` initializer that takes fake services (at least a `FontRendering` and a `FontCataloging`) and a `UserDefaults` suite, never touches real Application Support/Caches folders, and starts no scan or helper process. Its exact form is ui-shell.md §S12: `AppModel(services: AppServices.testing(root: <temp dir>, defaults: <suite>, renderer: <fake>, catalog: <fake>))`, from `Tests/FPAppUITests/Support/ShellFakes.swift`. Tests in this spec call it and pass `UserDefaults(suiteName: "fp-test-<UUID>")`, removing the suite afterwards | — | 501 |

### S3. `EditingShared.swift` (normative, exact content)

Create this file with exactly this content if it isn't on `main` yet. Parallel WPs that create it identically merge cleanly. The `MixPalette` **values** are provisional: WP-507 replaces them with the contrast-verified table and increased-contrast variants of ui-shell.md §S9 (`systemOrange` and `systemGreen` measure about 2.3:1 on white, below the original's 3.0 rule) and keeps `colour(forMaterialAt:)` and `missingBackground` working. Tests in WP-502–504 must not assert the exact colour values, only that index 4 equals index 0 and that the colours are distinct. Only adapt FPCore type names that core.md spells differently. (Checked for this spec: it compiles in Swift 6 language mode against stub `FaceKey`/`Mix`/`ForgeSpec`/`Recipe` types; `colour(forMaterialAt: 4)` equals index 0 and a negative index doesn't trap; the dynamic colour resolves to `#7A2E2E` under `.darkAqua`.)

```swift
// Types shared by the editing surfaces. Spec: docs/specs/ui-editing.md §S3. Keep identical to the spec.
import AppKit
import FPCore

/// What the recipe column or the preview's missing-characters note asks of the font picker (ui/requests.py).
public struct PickRequest: Equatable, Sendable {
    /// A `Language` id: what the picker lists, and what an added font is for ("any" for Any language).
    public var languageID: String
    /// The material being replaced (Change…); nil adds a font.
    public var replaceKey: FaceKey?

    public init(languageID: String, replaceKey: FaceKey? = nil) {
        self.languageID = languageID
        self.replaceKey = replaceKey
    }
}

/// The picker's candidate, drawn by the preview instead of the recipe until the picker closes.
public struct PreviewTrial: Equatable {
    public var mix: Mix
    public var banner: String

    public init(mix: Mix, banner: String) {
        self.mix = mix
        self.banner = banner
    }
}

/// A font the build flow just produced. The preview draws it until the recipe no longer matches it.
public struct BuiltFontPreview: Equatable {
    public var url: URL
    /// "Family Style" as written into the font.
    public var displayName: String
    /// What it was built from.
    public var spec: ForgeSpec

    public init(url: URL, displayName: String, spec: ForgeSpec) {
        self.url = url
        self.displayName = displayName
        self.spec = spec
    }

    /// Stale once anything that reaches the build changed (the sample text does not).
    public func isStale(for recipe: Recipe) -> Bool { recipe.forgeSpec() != spec }
}

/// UI-M4: text colours and boundaries remain legible in every system appearance.
@MainActor public enum MixPalette {
    private static let colours = (0..<4).map { index in
        dynamic(name: "FPMix\(index)") { dark, contrast in
            hex(forMaterialAt: index, dark: dark, increasedContrast: contrast)
        }
    }
    public static func colour(forMaterialAt index: Int) -> NSColor { colours[((index % 4) + 4) % 4] }
    public static let missingBackground = dynamic(name: "FPMissingBackground", value: missingHex)
    public static let cardStroke = dynamic(name: "FPCardStroke", value: cardStrokeHex)
    nonisolated public static func hex(forMaterialAt index: Int, dark: Bool, increasedContrast: Bool) -> UInt32 {
        let table: [[UInt32]] = [
            [0x1a6bd8, 0xb85209, 0x267a3a, 0x7c3aed],
            [0x6aa3ff, 0xf5a25d, 0x5cc27a, 0xc79bff],
            [0x0a4ea8, 0x8a3800, 0x1c6630, 0x5b21b6],
            [0xa8c8ff, 0xffc58f, 0x8fe3a8, 0xdcc6ff],
        ]
        return table[column(dark: dark, contrast: increasedContrast)][((index % 4) + 4) % 4]
    }
    nonisolated public static func missingHex(dark: Bool, increasedContrast: Bool) -> UInt32 {
        [0xffb3b3, 0x7a2e2e, 0xff8a8a, 0xa32b2b][column(dark: dark, contrast: increasedContrast)]
    }
    nonisolated public static func cardStrokeHex(dark: Bool, increasedContrast: Bool) -> UInt32 {
        [0xc6c6c8, 0x3a3a3c, 0x6e6e73, 0x98989d][column(dark: dark, contrast: increasedContrast)]
    }
    nonisolated private static func column(dark: Bool, contrast: Bool) -> Int { (dark ? 1 : 0) + (contrast ? 2 : 0) }
    // Accessibility names are bestMatch results, not constructible NSAppearance instances.
    nonisolated static func appearanceTraits(for match: NSAppearance.Name?) -> (dark: Bool, increasedContrast: Bool) {
        (
            match == .darkAqua || match == .accessibilityHighContrastDarkAqua,
            match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
        )
    }
    private static func dynamic(name: String, value: @escaping @Sendable (Bool, Bool) -> UInt32) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            let traits = appearanceTraits(
                for: appearance.bestMatch(from: [
                    .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
                ]))
            let hex = value(traits.dark, traits.increasedContrast)
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }
}
```

### S4. Strings

Every user-visible string goes into `Localizable.xcstrings` (architecture §8). The English text is the key. Every string, interpolated or not, is made with `String(localized: …, bundle: .module, comment: "<string id>")`: without `bundle: .module` the lookup uses the app's main bundle, which does not hold FPAppUI's strings (ui-shell.md §S8; WP-507's lint rule L2 enforces it). Numbers use `IntegerFormatStyle` with an injectable `Locale` (default `.current`). Tests pass `Locale(identifier: "en_US")`, so `1101` reads "1,101". Each WP's text file (`RecipeText`, `PickerText`, `PreviewText`) holds its strings as `static` functions or constants, and tests assert against those. Menu items use title-style capitalisation (macOS). Labels and sentences use sentence case (the original's tone).

### S5. Test conventions (all three WPs)

- Swift Testing (`import Testing`) in `Tests/FPAppUITests`. Test names are lowerCamelCase. An audit regression test puts the finding ID first in both the display name and the function name: `@Test("UI-1: hidden faces are never listed") func ui1HiddenFacesAreNeverListed()`.
- **Everything is off-screen.** Views are created in an `NSWindow(…, defer: true)` that is never ordered front, or not attached to a window at all. Call `NSApplication.shared.setActivationPolicy(.prohibited)` once in the test support. Drawing is forced with `bitmapImageRepForCachingDisplay(in:)` + `cacheDisplay(in:to:)`. Tests never touch `NSPasteboard.general`; they use a pasteboard made with `NSPasteboard(name:)` and a UUID name, and release it with `releaseGlobally()`.
- **No name-based CoreText lookups.** Test fonts come from file URLs: files the test generates (504), or files from `CTFontManagerCopyAvailableFontURLs()` (503 performance). No registration beyond `kCTFontManagerScopeProcess`.
- **Test support types are per WP** and uniquely prefixed (`RecipeTestFaces`, `PickerTestFaces`, `PreviewFixtureFonts`), or `fileprivate`. Three WPs share one test module, so don't declare custom `Tag`s or common helper names.
- **FaceRecords in tests** are built by decoding JSON: contracts §3 fields, snake_case, with defaults for everything not given. Coverage ranges and `group_counts` are computed from the code points with `ScriptGroup.of`. Decoding keeps the builders working when core.md adds fields.
- **Fixture fonts (WP-504)** are generated at test time. `$FP_ENGINE_PYTHON` (exported by `make`) runs a fontTools `FontBuilder` script that is embedded as a string literal in `PreviewFixtureFonts.swift` and ported from `reference/fontplayground-py/tests/fixtures.py:31-95`. It writes into a temporary directory. Tests that need these fonts use `.enabled(if: ProcessInfo.processInfo.environment["FP_ENGINE_PYTHON"] != nil)`. Two deliberate differences from the reference builder, both needed for CoreText glyph-run assertions (checked for this spec with pyobjc CoreText on the reference builder's output):
  - every fixture font also maps U+0020 SPACE (real fonts always do). Without it CoreText sends the spaces to the `[LastResort]` cascade, and "LastResort appears only on missing characters" can't hold;
  - `setupNameTable` also gets `psName` (e.g. `"FixtureA-Regular"`). Without it CoreText reports a synthesized name such as `font00000000306be7ad`. Tests still identify a run's font by its **`kCTFontURLAttribute`**, never by name.
- **Fake renderers.** WP-504's fake `FontRendering` creates fonts from the fixture files by URL (`CTFontManagerCreateFontDescriptorsFromURL`, cascade `[LastResort]` from `/System/Library/Fonts/LastResort.otf` by URL). WP-502 and WP-503 view and table tests have no font files: their fake returns `CTFontCreateUIFontForLanguage(.system, size, nil)` for every face (the UI font, not a name lookup) and counts its calls.
- **Performance thresholds** assume Apple silicon (M1 or newer), not virtualized, in the debug build that `make mac-test` produces. Every threshold is multiplied by `Double(ProcessInfo.processInfo.environment["FP_PERF_FACTOR"] ?? "1") ?? 1` (proposed for `docs/testing.md`; see the backbone issues). Each performance test measures 5 runs after one warm-up run and asserts on the median, unless the AC says p95/max.
- **Signposts:** `OSSignposter(subsystem: "io.github.kciceblue.fontplayground", category: "Picker" | "Preview")`. Interval names: `PickerOpen`, `PickerRows`, `RowFonts` (one per batch), `PreviewRestyle`, `PreviewModeChange`. Use them for Instruments. Tests use their own clocks.

### S6. Drawing text in a face (rules for all three WPs)

1. A face's `CTFont` comes **only** from `FontRendering`, which works from the file URL (ADR-0011). Never use `CTFontCreateWithName`, `NSFont(name:size:)`, `Font.custom(_:size:)` or descriptor matching for a catalog face.
2. `CTFont` is not `Sendable`. Create and cache fonts on the main actor. The per-turn budgets below keep that cheap (0.15–0.5 ms per font measured).
3. Honest text (preview runs, picker sample lines) is drawn by CoreText with the LastResort cascade that `FontRendering` sets. A missing glyph therefore shows as a LastResort box, never as a glyph borrowed from another font.
4. Labels (the card's family and native names, the picker's names) are drawn in their own face **only when the face maps every non-ignorable scalar of the label** (`face.coverage`). Otherwise they use the system font. A symbol font's name stays readable, and no fallback glyph ever pretends to be the face.
5. **Swift 6 isolation of AppKit delegates.** `NSTableViewDelegate`, `NSTableViewDataSource`, `NSTextViewDelegate` and `NSSearchFieldDelegate` are main-actor protocols: a `@MainActor` coordinator conforms directly. `NSTextStorageDelegate` is **not** main-actor annotated in the SDK, so a `@MainActor` class that conforms to it fails to compile in Swift 6 mode ("conformance … crosses into main actor-isolated code"; checked for this spec). Declare its method `nonisolated` and wrap the body in `MainActor.assumeIsolated { … }` (the preview's text storage is only edited on the main thread). A Swift 6.2 isolated conformance (`extension PreviewStyler: @MainActor NSTextStorageDelegate`) is also acceptable.

---

## WP-502: Recipe column (font cards, main font, size/weight, add for language, replace/remove, colour by font)

**Goal:** The "Your font" column: an empty state with two steps, then one native card per material, top to bottom with the main font first, plus the next-step offers. Every action goes through `Recipe`.
**Depends on:** WP-501, WP-402, WP-304 · **Env:** macos · **Size:** L · **Closes findings:** UI-5

### Scope
- In: the empty state; font cards (colour dot, role, Change…, the ⋯ menu and context menu, names in their own face, Style, Size, Weight, the "Draws …" line with the line-spacing sentence, the licence line, the shaping lines); the next-step prompt; "Add a font for another language…" with its language menu; the "Advanced…" footer link; locking while a build runs; the colour-by-font legend (the card dots use `MixPalette`); VoiceOver labels for all of these.
- Out: the Colour by Font toggle and the preview colouring (WP-504); the picker itself (WP-503); Advanced (WP-506); menu-bar commands such as Start Over (WP-501). Drag-and-drop reordering is not in the original, so it is out (backlog). Move Up/Down covers reordering.

### Touched paths
- `Packages/FontPlaygroundMacKit/Sources/FPAppUI/Editing/Recipe/RecipeColumn.swift` (edit: replace the placeholder body)
- `…/Editing/Recipe/FontCardView.swift`, `RecipeColumnState.swift`, `RecipeText.swift`, `ShapingRule.swift` (new)
- `…/Editing/AppModel+Recipe.swift` (new)
- `…/Editing/EditingShared.swift` (new, only if missing; S3)
- (none in FPCore: WP-301 already ports `Languages.roleTitle`/`namedGroups` and `EnglishText.draws`/`joinLabels`/`roleTitle` with their tests. Don't add FPCore files here.)
- `Packages/FontPlaygroundMacKit/Tests/FPAppUITests/RecipeColumnStateTests.swift`, `RecipeColumnTextTests.swift`, `RecipeColumnViewTests.swift`, `RecipeTestFaces.swift` (new)

### Design

**Data flow.** `RecipeColumn` reads `model.recipe`, `model.catalogFaces` and `model.isBuilding`, and computes `RecipeColumnState.make(…)` in `body`. The computation is pure and cheap. User input becomes a `RecipeAction` that goes to `model.perform(_:)`. Nothing in the column stores recipe state (`ui/recipe.py:6-8`).

```swift
struct RecipeColumnState: Equatable {
    var isEmpty: Bool
    var cards: [FontCardState]
    var prompt: PromptState?          // exactly one material and missing sample scalars that point to a language
    var isLocked: Bool                // model.isBuilding

    static func make(recipe: Recipe, catalog: [FaceRecord], isBuilding: Bool) -> RecipeColumnState
}

struct FontCardState: Identifiable, Equatable {
    var id: FaceKey                   // SwiftUI identity: a card survives adjustments and style changes of other cards
    var index: Int, count: Int
    var face: FaceRecord
    var role: String                  // "MAIN FONT" for index 0, else EnglishText.roleTitle(Languages.roleTitle(tally))
    var draws: String                 // EnglishText.draws(Languages.namedGroups(tally)) + (isBase ? " Sets the line spacing." : "")
    var nameInOwnFace: Bool           // S6 rule 4 for face.family
    var nativeName: String?           // face.localNames.first; nil when empty
    var nativeInOwnFace: Bool
    var styles: [FaceRecord]          // RecipeText.familyStyles(face, catalog)
    var weight: Int?                  // material weight (nil = "As is")
    var sizePercent: Int              // RecipeText.scalePercent(material.scale)
    var showsAdjustments: Bool        // index > 0
    var unavailableLine: String?      // nil when available; otherwise RecipeText.missingFont
    var licenceLine: String?          // face.embedding == "restricted" ? RecipeText.licence : nil
    var shapingProblems: [ShapingProblem]   // complex groups it can't shape that the text or a rule asks of it (see Shaping lines)
    var appleOnlyNote: Bool           // face.aat.morx && face.otScripts.gsub.isEmpty && shapingProblems.isEmpty
    var canMakeMain: Bool, canMoveUp: Bool, canMoveDown: Bool   // index > 0, index > 0, index < count - 1
    var changeRequest: PickRequest    // latin for index 0, else tallyLanguage(tally), replaceKey = id
    var dotColourIndex: Int           // = index (MixPalette)
}

struct PromptState: Equatable { var text: String; var buttonTitle: String; var request: PickRequest }
struct ShapingProblem: Equatable { var group: ScriptGroup; var language: Language; var text: String; var buttonTitle: String }

enum RecipeAction: Equatable {
    case chooseMain                        // PickRequest(languageID: "latin")
    case pick(PickRequest)                 // prompt, add menu, shaping line button, Change…
    case chooseStyle(FaceKey, FaceRecord)  // recipe.replace(key, with: face, keepAdjustments: true)
    case setWeight(FaceKey, Int?)          // keeps the scale
    case setSizePercent(FaceKey, Int)      // clamps to 10…1000; 100 → scale nil; keeps the weight
    case makeMain(FaceKey), moveUp(FaceKey), moveDown(FaceKey), remove(FaceKey)
    case showAdvanced

    /// Only the Advanced link works while a build runs (recipe.py:542-548).
    var isAllowedWhileBuilding: Bool { self == .showAdvanced }
}
extension AppModel { @discardableResult func perform(_ action: RecipeAction) -> [WeightSwap] }   // returns [] at once when isBuilding && !action.isAllowedWhileBuilding
```

An action whose key is no longer in the recipe (the card went away between the click and the call) does nothing.

`perform` maps actions onto `Recipe` operations: `move(key, to: 0)` for Make Main, `move(key, to: index ∓ 1)` for Move Up/Down, `remove`, `replace`, `setAdjustments(for:weight:scale:)`. It calls `openPicker(_:)` for requests and `showAdvanced()` for the footer. `Recipe` already resets the adjustments of a font that becomes main (`ui/model.py:382-386`). The column doesn't duplicate that rule.

**Real weights (ENGINE-4, core.md WP-304 §3 "How it is surfaced").** For `.setWeight` whose resolved weight changes, `perform` applies `setAdjustments` and then `applyRealWeights(in: FaceCatalog(catalogFaces))` in the same recipe mutation, and returns the swaps (every other action returns `[]`). `RecipeColumn` keeps the returned swaps in `@State`, together with the `Recipe` value from before the action. It shows each swap as a one-line note under the card of `swap.to.key`: `EnglishText.weightSwap(swap)` (WP-507 swaps in `ModelText`) with an **Undo** button (`RecipeText.undo` = "Undo") that restores the previous `Recipe` value (through `edit { $0 = previous }` when ui-shell's `edit` exists). The notes disappear on the next recipe change. This mirrors WP-506's Default boldness notes (ui-shell.md).

**Pure helpers (`RecipeText`)**, ported from `ui/recipe.py:103-165`:

| Swift | Reference | Rule |
|---|---|---|
| `scalePercent(_ scale: Double?) -> Int` | `recipe.py:103-105` | nil → 100, else `Int((scale * 100).rounded())`, clamped to ±`Int32.max`. A non-finite value gives 100. A restored `1e20` is reported by validation, so showing it must not trap |
| `percentScale(_ percent: Int) -> Double?` | `recipe.py:108-110` | 100 → nil, else `Double(percent) / 100` |
| `weightChoices: [(Int?, String)]` | `recipe.py:53-56` | (nil, "As is"), (300, "Light (300)"), (400, "Regular (400)"), (500, "Medium (500)"), (600, "Semibold (600)"), (700, "Bold (700)"), (900, "Heavy (900)"). Build it from WP-501's `WeightChoice.standard` (ui-shell.md, `Shared/WeightChoice.swift`) when that exists, so there is one list; ui-shell.md AC-507-10 checks that the two agree |
| `weightMenuItems(selected: Int?)` | `recipe.py:124-131` | the choices, plus `(w, "\(w)")` appended when `w` is not in the list |
| `familyStyles(_ face:, _ catalog:) -> [FaceRecord]` | `recipe.py:134-144` | delegates to core.md's `Smart.familyStyles(of: face, in: FaceCatalog(catalog))` (WP-303, AC-303-17), which implements this rule: supported catalog faces with the same family, one per style name; the recipe's face wins its style; sorted by (weightClass, italic, style); just `[face]` when the family isn't in the catalog. Don't re-implement it |
| `tallyLanguage(_ tally:) -> String` | `recipe.py:147-157` | `Languages.languageOfTally(tally).rawValue` (core.md WP-301): the language id of the largest group worth naming (MIN_SHARE 1 %), "symbols" only if that is all, "any" otherwise. Don't re-implement it |
| `promptText(_ langs:, family:)` | `recipe.py:160-161` | "Your text has \(joinLabels(langs)) characters that \(family) can't draw." |
| `promptButtonTitle(_ lang:)` | `recipe.py:164-165` | "Choose a font for \(lang.shortLabel)…" |
| `addMenuLanguages: [Language]` | `recipe.py:506-512` | `Languages.all` without "any", in table order (the menu then adds a divider and "Any language…") |
| `cardAccessibilityLabel(role:family:style:)`, `dotAccessibilityLabel(index:)`, `moreActionsAccessibilityLabel(family:)`, `sizeAccessibilityLabel(family:)`, `weightAccessibilityLabel(family:)` | — | the exact strings of the Accessibility paragraph below |

**Prompt** (`recipe.py:611-619`): shown when `recipe.materials.count == 1` and `Languages.languagesForMissing(recipe.missingSampleCharacters())` is non-empty. It uses the first language. It is hidden with zero materials (the empty state explains) and with two or more (the preview's missing note takes over).

**Shaping lines (ADR-0008).** For card i whose face has a non-nil `shapesGroups`, `shapingProblems` lists every group G with `G.needsShaping` and G ∉ `face.shapesGroups`, in `ScriptGroup` order, for which (a) `recipe.analyze().problems` contains `.cannotShape(index: i, group: G)` (a user pin, core.md S7), or (b) some visible scalar of the sample text is in group G and in `face.unshaped` (the face maps it, but its shaping would be lost, so the plan sent it to another font or to nobody). The tally can't be used: with plannable coverage it never holds such characters (S2.1). Each problem gives:
- the text "\(family) can't shape \(language.shortLabel) in your font: its \(language.shortLabel) shaping is Apple-only.", where language = `G.language`;
- a button titled "Choose a font for \(language.shortLabel)…" that sends `.pick(PickRequest(languageID: language.id))`.

A morx-only face with no shaping problem gets a secondary note instead: "Apple-only ligatures and alternates in this font won't carry over." Both lines follow the tally live, like everything else on the card.

**Layout (SwiftUI, native controls only; nothing restyles AppKit controls, so UI-5 can't recur):**

- Column: `ScrollView { VStack(alignment: .leading, spacing: 10) }` with the title "Your font" (`.title3.weight(.semibold)`). The footer below the scroll view holds a `Button("Advanced…").buttonStyle(.link)` and the secondary hint "who draws what, line spacing".
- Empty state: the subtitle (secondary), then two `GroupBox`es. Step 1 has a filled circle badge "1" (accent), the title "Main font", its text, and `Button("Choose main font…").buttonStyle(.borderedProminent)`. Step 2 has a hollow badge "2", the title "Fonts for other languages" and its text, all in secondary style.
- Card: a `GroupBox`, top to bottom:
  1. Head `HStack`: dot (`Circle`, 9 pt, `MixPalette.colour(forMaterialAt: index)`, filled when `model.colourByFont`, stroked otherwise); role (`.caption.weight(.semibold)`, secondary); `Spacer`; `Button("Change…").buttonStyle(.link)` with help "Use another font in its place"; the ⋯ `Menu` (`Image(systemName: "ellipsis.circle")`, `.menuStyle(.button)`, `.buttonStyle(.borderless)`, `.menuIndicator(.hidden)`) with Make Main Font (only when `canMakeMain`), Move Up, Move Down, a `Divider`, and Remove. The card's `.contextMenu` has the same items.
  2. Names `HStack(alignment: .firstTextBaseline, spacing: 10)`: the family at 17 pt and the native name at 12 pt, secondary. Each uses `Font(ctFont)` from `renderer` when `…InOwnFace`, else `.system(size:)`. Both are `.lineLimit(1)` and `.truncationMode(.tail)`, and have `.help` with the full name.
  - An unavailable material (`notFound` or `fileGone`) stays in place with a visible triangle and "Missing font — replace or remove it." (`recipe.missingFont`); both name labels use the system font without asking the renderer. Change and Remove remain usable. This fulfils the missing-row promise in WP-501 and the no-silent-drops rule. `RecipeColumnStateTests.crit2Catalog7MissingCardsStayMarkedAndRepairable` covers both states and recovery.
  3. `LabeledContent("Style")` holding a `Picker(.menu)` over `styles` (item title = style, help = `"\(family) \(style)"`), with help "Another style of the same family".
  4. Only when `showsAdjustments`: "Size" is a `TextField(value:format: .number)` (width 52), then "%", then `Stepper(value:in: 10...1000, step: 5)`. The field commits on Return or when focus leaves; out-of-range values are clamped and non-numbers revert. Help: "Draw this font's characters larger or smaller (100 % keeps them as they are)". "Weight" is a `Picker(.menu)` over `weightMenuItems`, with help "Make this font bolder or lighter (“As is” keeps it unchanged)".
  5. `Text(draws)` (`.callout`, secondary, wraps).
  6. The licence line in `.orange`; the shaping lines (each a `Label` with `exclamationmark.triangle`, plus its link button); the Apple-only note (secondary).
- Prompt: a `GroupBox` tinted with the accent (`.backgroundStyle(.tint.opacity(0.12))`) that holds the prompt text and a `.borderedProminent` button.
- Add: `Menu { ForEach(Languages.all without "any") { Button(lang.label) }; Divider(); Button("Any language…") } label: { Label("Add a font for another language…", systemImage: "plus") }`, `.menuStyle(.button)`, bordered. Hidden while the recipe is empty.
- Locked: `.disabled(state.isLocked)` on every control except the Advanced link. Texts stay (`recipe.py:340-343,542-548`).

**Accessibility** (the views take every label from the `RecipeText` functions above). Each card is one `accessibilityElement(children: .contain)` with the label "\(role): \(family) \(style)". The dot has "Colour \(index + 1) in Colour by Font". The ⋯ menu has "More actions for \(family)". The Size field has "Size of \(family), percent" and the Weight picker "Weight of \(family)". The step badges are hidden from accessibility (their titles carry the meaning).

**Strings (S4)**, exact English. All of them are in `RecipeText`:
"Your font"; "Combine installed fonts into one font that every app can use."; "Main font"; "The font you like for letters and numbers. It also sets the line spacing."; "Choose main font…"; "Fonts for other languages"; "Chinese, Japanese, Korean… They fill in whatever the main font can't draw."; "MAIN FONT"; "Sets the line spacing."; "Its licence restricts embedding — fine for your own use; check before sharing the result."; "Change…"; "Make Main Font"; "Move Up"; "Move Down"; "Remove"; "Style"; "Size"; "Weight"; "Add a font for another language…"; "Any language…"; "Advanced…"; "who draws what, line spacing"; plus the prompt and shaping templates above.

### Acceptance criteria

Tests live in `Packages/FontPlaygroundMacKit/Tests/FPAppUITests/`. "State" means `RecipeColumnState.make` over a `Recipe` built with `RecipeTestFaces`. Action tests call `perform(_:)` on an `AppModel` built with the S2.3 test initializer and check `model.recipe` and `model.pickRequest`. The faces mirror `reference/fontplayground-py/tests/conftest.py:35-45`: A "Fixture A" covers "abc1,"; B "Fixture B" Bold, weight 700, covers "ab漢，"; C "Fixture C" covers "a→Ω" with embedding "restricted"; V "Fixture V" is variable and covers "ab". Two more for ADR-0008: G "Geeza Pro" covers U+0627–U+0632 (12 Arabic letters) with `aat.morx = true`, `ot_scripts.gsub = []`, `shapes_groups = []`; M "Morx Latin" covers "abcdefgh" with `aat.morx = true`, `ot_scripts.gsub = []`.

- **AC-502-1** `scalePercent`, `percentScale` and `weightChoices` behave as in `test_scale_and_weight_helpers` (`tests/test_recipe.py:48-52`): 1.2 → 120, 0.95 → 95, nil → 100; 100 → nil, 120 → 1.2; the 7 choice texts and weights are exact. (`RecipeColumnTextTests.scaleAndWeightHelpers`)
- **AC-502-2** `tallyLanguage` returns "chinese_s", "greek", "symbols", "korean", "any", "any" for the six tallies of `test_recipe.py:55-60`. (`RecipeColumnTextTests.tallyLanguagePrefersLargestNamedGroup`)
- **AC-502-3** `familyStyles` lists Light, Regular, Bold for a family whose Black face is unsupported, and returns `[face]` for a family missing from the catalog (`test_recipe.py:63-72`). (`RecipeColumnTextTests.familyStylesLightestFirst`)
- **AC-502-4** For an empty recipe, the state is empty, with no cards, no prompt and no add button. `RecipeText` holds the six empty-state strings exactly as listed. `.chooseMain` makes the model's `pickRequest` equal `PickRequest(languageID: "latin")`. (`RecipeColumnStateTests.emptyStateExplainsTwoSteps`)
- **AC-502-5** Adding A leaves the empty state and shows the add button. Starting over (`recipe = Recipe()` with the same sample text) brings the empty state back. (`RecipeColumnStateTests.emptyStateGoesAndComesBack`)
- **AC-502-6** With sample "ab 漢字 あ" and only A: prompt text "Your text has Chinese and Japanese characters that Fixture A can't draw.", button "Choose a font for Chinese…", request `languageID "chinese_s"`. With sample "abc" there is no prompt. With "ab あ" the button is "Choose a font for Japanese…". Adding B hides the prompt, and removing B brings it back (`test_recipe.py:104-126`). (`RecipeColumnStateTests.promptFollowsSampleAndFontCount`)
- **AC-502-7** After A, B, C, card ids are `[A, B, C]`. `setWeight(B, 700)` and `setSizePercent(B, 120)` keep the ids and show "Bold (700)" and 120. Moving C to 0 gives `[C, A, B]`. Removing A gives `[C, B]`. (`RecipeColumnStateTests.cardsFollowRecipeOrder`)
- **AC-502-8** For this name-rendering test only, extend A and B’s coverage to include every scalar of their family labels, and B’s coverage to include "汉字体" (the shared sparse fixtures otherwise cannot satisfy S6 rule 4). B with local name "汉字体": the card has `nativeName == "汉字体"`, and A's is nil. Both names draw in their own face. A face whose coverage lacks a letter of its family name gets `nameInOwnFace == false` (S6 rule 4). (`RecipeColumnStateTests.namesInOwnFaceWhenCovered`)
- **AC-502-9** Card 0 has `showsAdjustments == false` and card 1 has true. A new card shows size 100 and weight nil ("As is"). The size clamps: 5 → 10, 2000 → 1000. (`RecipeColumnStateTests.firstCardHasNoSizeOrWeight`)
- **AC-502-10** Right after each edit, with no timers or waiting: A then B gives roles "MAIN FONT" / "FOR CHINESE". Their draws lines are "Draws letters, numbers and punctuation. Sets the line spacing." and "Draws Chinese characters and CJK punctuation.". Adding V then C gives "ADDS NOTHING" with "Draws nothing — the fonts above already cover everything it has." and "FOR GREEK" (`test_recipe.py:193-213`). (`RecipeColumnStateTests.rolesAndDrawsAreAlwaysCurrent`)
- **AC-502-11** With `setBase(B)`, only B's draws line ends with " Sets the line spacing.", and the card ids are unchanged. Resetting the base moves the sentence back to A (`test_recipe.py:216-231`). (`RecipeColumnStateTests.lineSpacingSentenceFollowsBase`)
- **AC-502-12** C's card has `licenceLine` equal to the exact licence text, and A's has nil. (`RecipeColumnStateTests.licenceLineOnlyForRestricted`)
- **AC-502-13** "Fake" Regular (400) and Bold (700) are in the catalog, and "Other" Medium is not in Fake's list. Fake Regular gets weight 600 and scale 1.1. `.chooseStyle(key, bold)` replaces it: keys become `[A, bold]`, the adjustments (600, 1.1) are kept, and the new card lists styles ["Regular", "Bold"] with "Bold" selected (`test_recipe.py:246-265`). (`RecipeColumnStateTests.styleChoiceKeepsAdjustments`)
- **AC-502-14** On card B: `setSizePercent(120)` → (nil, 1.2); `setWeight(700)` → (700, 1.2); `setSizePercent(100)` → (700, nil); `setWeight(nil)` → (nil, nil) (`test_recipe.py:268-281`). (`RecipeColumnStateTests.sizeAndWeightSetTheAdjustment`)
- **AC-502-15** A stored weight of 650 shows in the weight menu as the item "650", with 8 items in all. (`RecipeColumnTextTests.offListWeightShownAsNumber`)
- **AC-502-16** With three cards: the first has `canMakeMain == false`, `canMoveUp == false`, `canMoveDown == true`; the middle has all true; the last has `canMoveDown == false`. Make Main on the last gives [C, A, B]. Move Down on index 1 gives [C, B, A]. Move Up on index 2 gives [C, A, B]. Remove on index 0 gives [A, B] (`test_recipe.py:293-316`). (`RecipeColumnStateTests.menuActionsFollowPosition`)
- **AC-502-17** With A, B and V: the three cards' `changeRequest`s are (latin, A), (chinese_s, B) and (any, V) (`test_recipe.py:319-328`). (`RecipeColumnStateTests.changeAsksInTheCardsLanguage`)
- **AC-502-18** `RecipeText.addMenuLanguages` lists `Languages.all` minus "any" in table order, and their labels are used unchanged (e.g. "Armenian & Georgian" keeps its single "&"). `RecipeText.anyLanguage` is "Any language…". `perform(.pick(PickRequest(languageID: "japanese")))` and then `perform(.pick(PickRequest(languageID: "any")))` leave `model.pickRequest` equal to "japanese" and then "any" (`test_recipe.py:336-349`). (`RecipeColumnStateTests.addMenuOffersEveryLanguageThenAny`)
- **AC-502-19** `RecipeAction.showAdvanced.isAllowedWhileBuilding` is true, and it is false for one value of every other case. With `model.isBuilding = true`: `perform(.remove(A))`, `.moveDown(A)`, `.setWeight(B, 700)`, `.setSizePercent(B, 120)`, `.chooseStyle(…)`, `.makeMain(B)`, `.chooseMain` and `.pick(…)` leave `model.recipe` and `model.pickRequest` unchanged. The state has `isLocked == true`, and its cards' `role` and `draws` texts equal those of the unlocked state (`test_recipe.py:363-379`). (`RecipeColumnStateTests.lockedWhileBuilding`)
- **AC-502-20** With A then G, where G ("Geeza Pro") covers 12 Arabic characters that are all in its `unshaped`, has `shapes_groups = []`, and the sample text contains one of them, card 1 has exactly one shaping problem (its tally has 0 Arabic characters). The same happens with the sample text free of Arabic but `setPin(.arabic, to: G.key)` (the `.cannotShape` path). Its text is "Geeza Pro can't shape Arabic in your font: its Arabic shaping is Apple-only.", its button title is "Choose a font for Arabic…" and its request is `PickRequest(languageID: "arabic")`. G's `appleOnlyNote` is false (the problem line wins). With M alone, M has no problem and `appleOnlyNote == true`. A (no morx) has neither. G with `shapes_groups = ["arabic"]` has no problem. (`RecipeColumnStateTests.shapingLinesFollowADR0008`)
- **AC-502-21** Card dots use `MixPalette.colour(forMaterialAt: index)`: index 4 has the same colour as index 0. `RecipeText.dotAccessibilityLabel(index: 0)` is "Colour 1 in Colour by Font". (`RecipeColumnStateTests.dotsUseTheMixPalette`)
- **AC-502-22** Accessibility strings: `cardAccessibilityLabel(role: "MAIN FONT", family: "Fixture A", style: "Regular")` is "MAIN FONT: Fixture A Regular"; `moreActionsAccessibilityLabel(family: "Fixture B")` is "More actions for Fixture B"; the Size and Weight labels are "Size of Fixture B, percent" and "Weight of Fixture B". (`RecipeColumnTextTests.accessibilityLabels`) Off-screen render smoke test: `NSHostingView(rootView: RecipeColumn(model:))` with A and B, in a never-shown `NSWindow` of 320 × 700 pt, lays out and draws through `cacheDisplay(in:to:)` without a crash. The bitmap is not uniformly one colour, and the fake renderer (S5) was asked for a font for both faces. That the view applies the labels is checked in AC-502-M2. (`RecipeColumnViewTests.rendersOffScreen`)
- **AC-502-23** `grep -rnE 'NSComboBox|: *ButtonStyle *\{|: *MenuStyle *\{|: *PickerStyle *\{' Packages/FontPlaygroundMacKit/Sources/FPAppUI/Editing/Recipe` prints nothing and exits 1. Only stock control styles are used, so UI-5 can't recur.
- **AC-502-24** `make lint`, `make mac-test` and `make app` pass.
- **AC-502-25** (ENGINE-4) Catalog "PingFang SC" Regular (400), Medium (500) and Semibold (600) with the same coverage; recipe [A, PingFang SC Regular]. `perform(.setWeight(regularKey, 600))` returns one `WeightSwap` to Semibold, and `recipe.keys == [A, semiboldKey]` with weight 600 kept. `.setWeight(semiboldKey, 600)` again returns `[]`. Restoring the saved previous `Recipe` gives back Regular. (`RecipeColumnStateTests.engine4WeightChoiceUsesARealHeavierFace`)
- **AC-502-M1** (manual, macos) Run a debug build with Helvetica Neue as main, PingFang SC added for Chinese, and one restricted-embedding font. Attach light and dark screenshots of the column. They must show: native popup buttons and a stepper that look like System Settings controls (no square frames, UI-5); names in their own faces; PingFang's native name "苹方-简"; the Size and Weight row on cards 2 and 3 only; the licence line on the restricted card.
- **AC-502-M2** (manual, macos) With VoiceOver on (⌘F5), move through one card. Attach the VoiceOver caption panel transcript showing the card label, "Change…", "More actions for …", Style, Size and Weight in order.

### Verification
```bash
make lint
make mac-test
make app
```

### Notes for the implementer
- The tallies are current after every mutation (ADR-0006). Don't port the "…" pending state or the "plan pending" half of `test_change_asks_for_a_replacement…`.
- Keep `RecipeColumnState.make` free of AppKit so the state tests don't need a window. Only the view resolves fonts from `model.renderer`.
- Use the `Stepper` step of 5 for comfort; typed values accept any integer from 10 to 1000. `QSpinBox` stepped by 1 (`recipe.py:278-283`). Record this in the PR as a deliberate deviation.
- `ui/recipe.py:113-115` (`mnemonic_safe`) is Qt-only: SwiftUI shows "&" as is. The Qt theme tests (`test_apply_theme_rerenders_and_retints_the_dots`, `test_panel_built_in_dark`) are replaced by AC-502-21 and AC-502-M1, because colours are dynamic system colours.
- `test_name_line_gets_the_room_its_text_needs` (Qt layout) maps to `.lineLimit(1)` + `.truncationMode(.tail)` + `.help`. It is checked visually in AC-502-M1.
- `reference/fontplayground-py/tests/test_widgets.py` covers Qt widgets. `ElidedLabel` becomes native truncation plus `.help`. `elide_middle` and `Disclosure` belong to the WP-505/506 surfaces.

---

## WP-503: Font picker

**Goal:** A fast, honest, keyboard-first picker. Every family is drawn in its own face. Only fonts that draw (and can shape) the language are listed. ↑/↓ tries the current font in the live preview.
**Depends on:** WP-501, WP-401, WP-402, WP-304 · **Env:** macos · **Size:** L · **Closes findings:** UI-1, UI-14, CATALOG-2, CATALOG-11

### Scope
- In: presentation in the sidebar; title; search; language filter; the filter note; the AAT toggle; sections; family rows drawn in their own face (name, native name, "in your font" tag, sample line); the Style choice; Back, Cancel and Use; the keyboard; double-click; the debounced trial (`model.trial`) and its banner text; empty, no-match and scanning states; row updates during a scan; the hidden-face and suspicious-face guards; the CATALOG-11 platform-preferred font lookup and its use; closing when a build starts; `openPicker`, `usePickedFace`, `cancelPicker` and `findFont`; VoiceOver labels; performance and signposts.
- Out: drawing the trial in the preview (WP-504; this WP only sets `model.trial`); ranking suggestions (WP-304; this WP passes the preferred PostScript names); the catalog store and hidden-face dropping (WP-401); downloadable fonts and "Get more fonts…" (WP-404); the ⌘F menu item itself (WP-501 calls `findFont()`).

### Touched paths
- `Packages/FontPlaygroundMacKit/Sources/FPAppUI/Editing/Picker/FontPickerView.swift` (edit: replace the placeholder body)
- `…/Editing/Picker/PickerModel.swift`, `PickerRows.swift`, `PickerText.swift`, `FontListView.swift`, `FontRowCellView.swift`, `RowFontCache.swift`, `SearchFieldView.swift` (new)
- `…/Editing/SidebarView.swift` (edit: transition and focus)
- `…/Editing/AppModel+Picker.swift` (new)
- `…/Editing/AppModel+EditingSeams.swift` (WP-501, ui-shell.md §S2; edit: delete the `openPicker(_:)` and `findFont()` stubs, which `AppModel+Picker` replaces with the same signatures; otherwise Swift reports an invalid redeclaration)
- the file that declares `AppModel` (WP-501; edit: add only the three stored properties listed under "AppModel+Picker" below)
- the app's production wiring of `AppModel` (WP-501; edit: one line that sets `platformFontLookup = PlatformFontPreferences.lookUp`)
- `…/Editing/EditingShared.swift` (new, only if missing; S3)
- `Packages/FontPlaygroundMacKit/Sources/FPMacServices/PlatformFontPreferences.swift` (new)
- `Packages/FontPlaygroundMacKit/Tests/FPAppUITests/PickerRowsTests.swift`, `PickerModelTests.swift`, `PickerKeyboardTests.swift`, `PickerFlowTests.swift`, `PickerTableTests.swift`, `PickerPerformanceTests.swift`, `PickerTestFaces.swift` (new)
- `Packages/FontPlaygroundMacKit/Tests/FPMacServicesTests/PlatformFontPreferencesTests.swift` (new)

### Design

**Presentation: in the sidebar, in place of the recipe column.** The candidate has to be tried in a preview that stays fully visible and live while the user moves through the list. That rules out the alternatives:
- A **sheet** is modal and slides over the window content, covering the preview.
- A **popover** is transient: it closes on any click outside, including the click a user makes into the preview to change the sample. It also can't hold a 64 pt-row list comfortably.
- A **floating panel** adds window management (key-window focus, positioning, ⌘W semantics) for no gain.

The original replaced the left column (`ui/app.py:214-235`), and a sidebar that pushes into a sub-list is a familiar Mac pattern. `SidebarView` switches on `model.pickRequest` with `.transition(.move(edge: .trailing).combined(with: .opacity))` (0.2 s; no animation when Reduce Motion is on). The search field gets keyboard focus on open. Closing returns focus to the control that opened the picker, if it still exists, or to the preview.

**Layout (top → bottom):**
1. A `Button { cancel } label: { Label("Back", systemImage: "chevron.backward") }.buttonStyle(.link)` and the title (`.title3.weight(.semibold)`, wraps). *WP-701 finding C:* the title and the filter note must not use `fixedSize(horizontal: false, vertical: true)`. AppKit measures them at zero width when it computes the window's minimum; a long title ("Choose a font for Thai & SE Asian") then raised the minimum to 778–798 pt and grew the window under the Dock. `PolishOffscreenTests.pickerKeepsTheMinimumWindowSize` guards this.
2. `SearchFieldView` (an `NSSearchField` wrapper) with the placeholder "Search \(n) fonts — English or native name" ("1 font" when n = 1). n = families listed for the language before the search.
3. "Show fonts for" + `Picker(.menu)` over `Languages.all` (label = `language.label`) at its full width, with the filter note "Only fonts that draw it well" (secondary, wraps; hidden for "any") on the line below. *WP-701 finding B:* side by side in one `HStack`, the sidebar's menu shrank to "L…" / "中…".
4. A checkbox, shown only when `unshapableCount > 0`: "Show fonts that can't shape \(short) (\(n))".
5. `FontListView` (an `NSTableView` wrapper, fills the height).
6. The status line (secondary): the status text, plus a determinate `ProgressView` (width 120) while scanning. When `hiddenCount + duplicateCount > 0`, its help reads "\(h) hidden system fonts and \(d) duplicates aren't listed." Unreadable files are listed in the help, one "path: message" per line (`picker.py:469-483`).
7. The "Style" `Picker(.menu)` on its own row (shown only when the current family has more than one usable style), then the buttons: `Spacer`, `Button("Cancel")` (`.cancelAction`), and `Button("Use \(name)")` (`.defaultAction`, `.borderedProminent`). The name is cut to 23 characters + "…" when the family has more than 24 characters (`picker.py:676`). Without a current row the button is "Use" and disabled.

**List control: view-based `NSTableView` (primary).** It is wrapped in `NSViewRepresentable` (`FontListView`) with a coordinator as data source and delegate. The choice is deliberate:
- Rows are recycled (`makeView(withIdentifier:owner:)`), and only visible rows get views.
- `rows(in:)` on the clip view's bounds gives the visible range, which prefetch needs. SwiftUI `List` exposes neither the visible range nor recycling control.
- `tableView(_:isGroupRow:)` and `shouldSelectRow` handle headers and greyed rows.
- Keyboard commands come through AppKit (`doCommand(by:)`), which is IME-safe (UI-17).
- Per-row accessibility is explicit.
- The prototype met the budgets (see Context).

Fallback rule: a SwiftUI `List` may replace the table **only** if it passes every AC of this WP unchanged, including AC-503-26…28. If you do this, record it in the PR under "Spec deviations".

Table configuration:
- `style = .inset`, `headerView = nil`, one column, `selectionHighlightStyle = .regular`, `floatsGroupRows = false`, `allowsTypeSelect = false`.
- Row height 64 pt; group rows 28 pt; `usesAutomaticRowHeights = false`.
- The scroll view has `autohidesScrollers = true`. Leave `scrollerStyle` at the system preference (UI-14: overlay scrollers are native; no custom right inset).
- `PickerRowView: NSTableRowView` only overrides `isEmphasized` (`get { window?.isKeyWindow ?? false } set { }`: AppKit's writes are ignored), so the current row shows the accent while the search field has focus (as in Xcode's Open Quickly). It does **not** override any drawing method.
- `doubleAction` calls `coordinator.handleDoubleClick(row: tableView.clickedRow)`, which selects and uses that row when it is selectable and does nothing otherwise. Clicking a row selects it; the preview tries it after the debounce.

**Row cell (`FontRowCellView: NSTableCellView`)** draws in `draw(_:)` with CoreText. There are no `NSTextField`s, so each row is one layer.
- Name line (top 26 pt): the family (14 pt, own face per S6 rule 4), then after an 8 pt gap the native name (11 pt, own face per rule 4, secondary colour), both elided at the tail with `CTLineCreateTruncatedLine` and "…". The tag "in your font" (11 pt system, `systemGreen`) is right-aligned and reserves its width first.
- Sample line (the rest): `language.pickerSample` at 18 pt in the face's `CTFont` (honest, S6 rule 3), elided at the tail.
- Colours use `kCTForegroundColorFromContextAttributeName` with the context fill set in `draw(_:)`: `labelColor` / `secondaryLabelColor`, or `alternateSelectedControlTextColor` when `backgroundStyle == .emphasized`. A greyed row uses `tertiaryLabelColor` and replaces the tag with its reason, "Can't shape \(short): its shaping is Apple-only" (11 pt, secondary).
- While a font is not ready (see below), that line is drawn in the system font at the same size in `secondaryLabelColor`, and redrawn when the font arrives.
- For tests, the cell records `private(set) var drewInOwnFace: Bool` in every `draw(_:)`: true when the sample line was drawn with the face's own `CTFont`.
- Group row cell: the header text (`.headline`-sized system font, secondary), baseline 6 pt above the bottom.

**Fonts for rows (`RowFontCache`, main actor).**

```swift
@MainActor final class RowFontCache {
    init(renderer: any FontRendering, capacity: Int = 512, budgetPerTurn: Duration = .milliseconds(8))
    /// Cached font, or one created now while this run-loop turn has budget left; else nil and queued.
    func font(for face: FaceRecord, size: CGFloat) -> CTFont?
    /// Queue fonts for rows about to scroll in (lowest priority, same budget).
    func prefetch(_ faces: [FaceRecord], sizes: [CGFloat])
    /// Called once per drained batch with the keys whose fonts became available.
    var onFontsReady: (Set<FaceKey>) -> Void
    func removeAll()     // after a rescan: a key may now mean another file
}
```

- Keys are `(FaceKey, size)`. Eviction is least-recently-used. A creation failure is cached as a failure: the row keeps the system font and the failure is logged once per key.
- The budget is measured with `ContinuousClock` from the first creation in the current turn. It resets when the queue drain task runs (`Task { @MainActor in … }`, one batch per turn, until the queue is empty). Each batch is logged as a `RowFonts` signpost interval and ends with `onFontsReady` → `reloadData(forRowIndexes:columnIndexes:)` for the visible rows with those keys.
- Prefetch runs on `NSView.boundsDidChangeNotification` of the clip view (and after `reloadData`). It covers the rows in the visible rect grown by one viewport height up and down.
- Nothing ever loads more than one turn's budget. This replaces the original rule "nothing is ever loaded inside paint()" (`picker.py:8-10`); URL descriptors are cheap enough to allow a bounded amount.

**`PickerModel` (`@MainActor @Observable`)** owns the picker state and is testable without views:

```swift
@MainActor @Observable final class PickerModel {
    struct Context: Equatable { var request: PickRequest; var main: FaceRecord?; var recipeKeys: Set<FaceKey>
                                var suggestions: [FaceRecord]; var preferredFamilies: [String: String] } // language id → family
    init(locale: Locale = .current, candidateDelay: Duration = .milliseconds(120), refreshInterval: Duration = .milliseconds(300),
         clock: any Clock<Duration> = ContinuousClock())   // tests pass a manual clock (AC-503-13, -14, -16)
    private(set) var isOpen: Bool
    private(set) var context: Context
    var languageID: String            // didSet → rebuild
    var query: String                 // didSet → rebuild (no debounce: a rebuild is cheap, see AC-503-26)
    var showsUnshapable: Bool         // didSet → rebuild
    private(set) var rows: [PickerRow]
    private(set) var currentRowID: PickerRow.ID?
    var chosenStyle: FaceRecord?      // Style menu; reset when the current row changes
    var title: String { get }
    var searchPlaceholder: String { get }
    var statusText: String { get }
    var useTitle: String { get }
    var isUseEnabled: Bool { get }
    var unshapableCount: Int { get }
    @ObservationIgnored var onCandidate: (FaceRecord?) -> Void = { _ in }   // debounced; never called while closed

    func open(_ context: Context, catalog: [FaceRecord], status: CatalogStatus)
    func catalogChanged(_ catalog: [FaceRecord], status: CatalogStatus)  // throttled rebuild while scanning; immediate at scan end
    func select(_ id: PickerRow.ID)
    func move(by delta: Int)          // selectable family rows only (headers and greyed rows are skipped); clamps at the ends
    func moveToStart(), moveToEnd()
    func page(by direction: Int, visibleRows: Int)
    func use() -> FaceRecord?         // chosenStyle ?? current row face; closes the model
    func cancel()                     // closes the model
}

enum PickerRow: Identifiable, Equatable {
    case header(Header)
    case family(FamilyRow)
    var id: PickerRowID { get }
    var isSelectable: Bool { get }    // family rows with unavailableReason == nil
}
/// "The same row" across rebuilds (picker.py:116-118): a family in a section, or one suggested face.
struct PickerRowID: Hashable { var section: PickerSection; var text: String; var faceKey: FaceKey? }
struct Header: Equatable { var section: PickerSection; var title: String; var accessibilityLabel: String }
    // id = PickerRowID(section: section, text: title, faceKey: nil)
struct FamilyRow: Equatable { var section: PickerSection; var family: String; var face: FaceRecord
                              var styles: [FaceRecord]; var nativeName: String; var inRecipe: Bool
                              var unavailableReason: String? }
    // id = PickerRowID(section: section, text: family, faceKey: section == .suggested ? face.key : nil)
enum PickerSection: Hashable { case suggested, all, unshapable }

enum PickerRows {
    struct Result: Equatable { var rows: [PickerRow]; var listedFamilyCount: Int; var unshapableCount: Int }
    /// Pure: the catalog (catalog order), the language, the trimmed query, the context, the toggle.
    static func build(catalog: [FaceRecord], language: Language, query: String, context: PickerModel.Context,
                      showsUnshapable: Bool, locale: Locale) -> Result
    static func isHidden(_ face: FaceRecord) -> Bool
}
```

**Row building (`PickerRows.build`, pure)** ports `picker.py:559-597`:
1. `eligible(face)` requires `face.supported && !face.suspiciousCoverage && !isHidden(face)`, where `isHidden(face) = face.hidden || face.family.hasPrefix(".") || face.postscriptName?.hasPrefix(".") == true || face.family == "LastResort" || face.family == "System Font"`. This is UI-1 and CATALOG-2 defence in depth. The rule is the verifier's (`UI-1`: `family.startswith('.') or family in {'System Font', 'LastResort'}`, i.e. Qt's `isPrivateFamily` plus `System Font`), extended with the `.`-prefixed PostScript name that also catches `System Font` (`.SFNS-…`).
2. Group eligible faces by family, in catalog order. `good(family)` = faces with `language.coversWell(face)` that can shape the language (S2.1 shaping rule). `unshaped(family)` = faces that cover the language well but can't shape it.
3. **Suggested**: walk `context.suggestions` in order and keep up to 3 faces that are eligible, cover the language well, can shape it, match the query, and aren't seen yet. Each kept face gives a row with `section = .suggested` and `face = suggestion`. The section header is "Suggested for your text".
4. **All**: families with a non-empty `good` set that match the query, sorted by `family.compare(other, options: [.caseInsensitive, .numeric])`, ties by `<`. Each row's face is `Smart.defaultFace(good, main: context.main)`, and its styles are `good` sorted by (weightClass, italic, style). Header: "All \(name) fonts · \(count)", where name is "Latin" for latin and `shortLabel` otherwise; "All fonts · \(count)" for any (`picker.py:99-104`).
5. **Can't shape** (only when `showsUnshapable`): families where `good` is empty and `unshaped` is not, matching the query, sorted the same way, with header "Can't shape \(short) · \(count)". Rows have `unavailableReason` set and are not selectable.
6. Matching: `haystack(family)` = the family plus every `localNames` entry of its eligible faces. Both sides are folded with `.caseInsensitive, .widthInsensitive` (locale nil). The query is trimmed; an empty query matches everything (`picker.py:457-459,559-565`).
7. `nativeName` = the row face's first local name, else the first local name of any face in the family, else "" (`picker.py:567-571`). `inRecipe` = any catalog face of that family is in `recipeKeys`.
8. The listed count (for the placeholder) is the number of families with a non-empty `good`, before the query. `unshapableCount` counts families that fail only on shaping, before the query.
9. The folded haystacks depend only on the catalog. `PickerModel` computes them once per `open`/`catalogChanged` and passes them in (an extra `haystacks: [String: String]` parameter, or a `PickerRows.Index` value built from the catalog: implementer's choice). They are never recomputed per query.

**Current row** (port of `_pick_row`, `picker.py:617-636`). There is a wish identity W. On open, W is the replaced family's row in All when `replaceKey` is set; otherwise W is nil. After every rebuild:
- choose the row with identity W;
- else a family row with the same family text, preferring the All section;
- else (on open only, with W nil and no Suggested section) the row of `context.preferredFamilies[languageID]` if listed (CATALOG-11);
- else the first selectable row.

The fallback becomes the new W, **except** while a scan is running (the wished row may still arrive). User moves set W.

**Style menu** (new; the original had none). The button row's "Style" `Picker(.menu)` lists the current family row's `styles` (item title = style) and is shown only when `styles.count > 1`. Its selection is `chosenStyle ?? row.face`. Choosing a style sets `chosenStyle`, which restarts the candidate debounce. `use()` returns `chosenStyle ?? row.face`. Any current-row change resets `chosenStyle` to nil. Suggested rows have `styles == [face]`, so the menu is hidden there.

**Candidate and trial.** Every current-row change (including the first after `open`, and a change of `chosenStyle`) restarts a `Task` that sleeps `candidateDelay` on `clock` and then calls `onCandidate(chosenStyle ?? currentFace)` if the model is still open. When the rows become empty, the candidate is nil. `AppModel+Picker` connects `onCandidate` like `ui/app.py:240-251`:
- `pickRequest == nil` (the picker was closed by a build or by Start Over while the debounce ran) → call `picker.cancel()` and ignore the candidate;
- nil face → `trial = nil`;
- otherwise `trial = PreviewTrial(mix: recipe.mix(trying: face, replacing: request.replaceKey, for: language), banner: PickerText.trialBanner(...))`. The language is nil when the recipe is empty or when replacing; otherwise it is the picker's current `languageID`, and nil for "any".

`PickerText.trialBanner(family:, languageID:, replacedFamily:, first:)` ports `ui/app.py:75-85`. It returns "Trying \(family) as your main font", "Trying \(family) instead of \(replaced)", "Trying \(family)" or "Trying \(family) for \(short)", each followed by " — ↑ ↓ try the next font, Return uses it.".

**AppModel+Picker** (ports `ui/app.py:214-264`). Swift extensions can't add stored properties, so this WP adds exactly these to `AppModel`'s declaration:

```swift
let picker = PickerModel()                                            // onCandidate wired in AppModel+Picker on first open
var platformPreferredNames: [String: String] = [:]                    // language id → PostScript name (CATALOG-11)
@ObservationIgnored var platformFontLookup: (@Sendable ([String: String]) async -> [String: String])? = nil
```

`platformFontLookup` is nil in the test initializer, so tests never call CoreText's fallback lookup. They set `platformPreferredNames` directly. The production wiring (WP-501's) sets it to `PlatformFontPreferences.lookUp`. On the first `openPicker` with a non-nil lookup and empty `platformPreferredNames`, `AppModel+Picker` starts one `Task` that awaits the lookup (probes built as described under CATALOG-11 below) and stores the result. The picker never waits for it: an open before it finishes simply has no preference.

- `openPicker(_ request:)`:
  1. Ignore it while `isBuilding`.
  2. `language = Languages.language(rawID: request.languageID) ?? Languages.language(.any)`.
  3. `recipe.setSampleText(Languages.withLanguageLine(recipe.sampleText, language))` (it returns false when nothing changes).
  4. `preferred` = the values of `platformPreferredNames` that are the PostScript name of a face in `catalogFaces`. When `request.replaceKey == nil && !recipe.materials.isEmpty`, `suggestions = recipe.suggestions(for: language.id, in: FaceCatalog(catalogFaces), limit: 3, preferences: PlatformPreferences([language.id: preferred.map { .postscriptName($0) }]).appending(.macOS))`; otherwise none.
  5. `preferredFamilies` = for each (language id, name) in `platformPreferredNames` whose name belongs to a catalog face, that face's family.
  6. Set `pickRequest` (with `languageID` replaced by `language.id`, so an unknown id becomes "any"), then `picker.open(Context(request:, main: <the main material's face, nil when the recipe is empty>, recipeKeys: Set(recipe.keys), suggestions:, preferredFamilies:), catalog: catalogFaces, status: catalogStatus)`.
- `FontPickerView` calls `picker.catalogChanged(model.catalogFaces, status: model.catalogStatus)` from `.onChange` of either value while the picker is open.
- `usePickedFace(_ face:)`:
  - with `replaceKey`: `recipe.replace(key, with: face, keepAdjustments: false)`;
  - with an empty recipe: `recipe.add(face, for: nil)`;
  - otherwise `recipe.add(face, for: languageID == "any" ? nil : LanguageID(rawValue: languageID))` (core.md's `add(_:for:)` takes a `LanguageID?`; `.any` would pin nothing either).
  When `recipe.defaultWeight != nil`, the same mutation then calls `applyRealWeights(in: FaceCatalog(catalogFaces))` (core.md WP-304 §3). Then close.
- `cancelPicker()`: `picker.cancel(); pickRequest = nil; trial = nil`.
- `findFont()`: if the picker is open, focus the search field and select its text; otherwise `openPicker(PickRequest(languageID: recipe.isEmpty ? "latin" : "any"))`.
- When `isBuilding` becomes true, the picker closes (`ui/app.py:267-270`): the WP-501 seam's `didSet` clears `pickRequest` and `trial` (S2.3). The candidate rule above stops a pending debounce, and `FontPickerView.onDisappear` calls `picker.cancel()`.

**Keyboard.**
- `SearchFieldView.Coordinator` is `init(model: PickerModel, visibleRows: @escaping @MainActor () -> Int)`. The view passes a closure that reads the table's visible height; tests pass a constant. The coordinator is the `NSSearchField`'s delegate and implements `control(_:textView:doCommandBy:)`. It returns `true` for:
  - `moveUp:`, `moveDown:` → `move(by: ∓1)`;
  - `scrollPageUp:`, `scrollPageDown:`, `pageUp:`, `pageDown:` → `page`;
  - `moveToBeginningOfDocument:`, `moveToEndOfDocument:` (⌘↑/⌘↓), `scrollToBeginningOfDocument:`, `scrollToEndOfDocument:` (Home/End) → start/end;
  - `insertNewline:` → use;
  - `cancelOperation:` (Esc and ⌘.) → cancel.
  Every other selector returns `false`, so text editing still works.
- AppKit delivers these commands only when no input method is composing, so IME candidate windows keep their arrows and Return (UI-17).
- `PickerTableView.keyDown(with:)` sends the same commands. The arrow and page keys go to the model, not to the table's own handling, so headers and greyed rows are skipped consistently. Return and Enter use the row. Esc and ⌘. cancel. Printable characters with no ⌘ or ⌃ move focus to the search field and are re-sent there with `insertText`.
- `page` uses `visibleRows = max(1, Int(visibleHeight / 64))`.

**Status text** (`picker.py:713-727`):
- while scanning: "Looking for fonts…", or "Looking for fonts… \(done) / \(total)" once a total is known;
- with no rows and a query: "No fonts match “\(query)”.";
- with no rows, no query, and a language other than any: "None of your fonts draw \(label) well.";
- otherwise the catalog text: "\(n) fonts" ("1 font"), with " · \(k) files couldn't be read" ("1 file") appended when k > 0. Here n = the number of faces in the catalog passed to `open`/`catalogChanged` for which `!PickerRows.isHidden(face) && !face.suspiciousCoverage` (unsupported faces count, as in the original's `len(self._faces)`), and k = `status.unreadable.count`. Numbers use the injected locale ("1,101").
- The status help (`PickerText.statusHelp(unreadable:hidden:duplicates:)`): one "\(path): \(message)" line per unreadable file, then, when `hiddenCount + duplicateCount > 0`, the line "\(h) hidden system fonts and \(d) duplicates aren't listed." (each count pluralised: "1 hidden system font", "1 duplicate"). Empty when there is nothing to say.

**Titles** (`picker.py:50-53,515-521`):
- "Replace \(family)" when replacing;
- "Choose your main font" when the recipe is empty;
- "Choose a font" for any;
- otherwise "Choose a font for \(short)".

**Scanning while open** (`picker.py:452-483`): while `status.isScanning`, `catalogChanged` stores the new catalog and, unless a refresh is already pending, starts a trailing refresh `Task` that sleeps `refreshInterval` and then rebuilds once with the latest catalog (the original's single-shot `_refresh_timer`). When a call brings `isScanning == false`, the pending refresh is cancelled and the rows rebuild at once. `cancel()`/`use()` cancel a pending refresh. `RowFontCache.removeAll()` runs when a scan starts (the first call with `isScanning == true` after one with false).

**CATALOG-11: `PlatformFontPreferences` (FPMacServices).**

```swift
public enum PlatformFontPreferences {
    /// Language id → BCP 47 tag, for the languages that have a platform default.
    public static let languageTags: [String: String] = [
        "chinese_s": "zh-Hans", "chinese_t": "zh-Hant", "japanese": "ja", "korean": "ko", "greek": "el",
        "cyrillic": "ru", "armenian_georgian": "hy", "hebrew": "he", "arabic": "ar", "indic": "hi",
        "southeast_asian": "th"]
    /// PostScript name CoreText itself falls back to for each language's probe string. Runs off the main actor.
    public static func lookUp(probes: [String: String]) async -> [String: String]
}
```

- **Probe** (built by `AppModel+Picker`, keyed by language id, for each id in `languageTags`): the first scalar of `Language(id:)!.textSample` whose `ScriptGroup` is in `language.groups`, as a one-scalar `String`. Ids without such a scalar are left out.
- **Lookup** (inside `lookUp`, for each probe whose id has a tag): base font `CTFontCreateUIFontForLanguage(.user, 13, nil)` (the user's document font, Helvetica on a stock Mac; a UI-font type, not a name lookup). Then `CTFontCreateForStringWithLanguage(base, probe as CFString, CFRange(location: 0, length: probe.utf16.count), tag as CFString)` and `CTFontCopyPostScriptName`. A result whose PostScript name starts with "." is dropped.
  - **Don't use `.system` as the base.** Checked for this spec on macOS 27: with the `.system` UI font, every language resolves to a private UI face (`.PingFangUITextSC-Regular`, `.HiraKakuInterface-W4`, `.AppleSDGothicNeoI-Regular`, `.SFArabic-Regular`…), which the catalog hides, so nothing would ever be preferred.
  - With `.user` (Helvetica) the results match the audit's CATALOG-11 evidence: zh-Hans `PingFangSC-Regular`, zh-Hant `PingFangTC-Regular`, ja `HiraginoSans-W3`, ko `AppleSDGothicNeo-Regular`, ar `GeezaPro`, hi `KohinoorDevanagari-Regular`, th `Thonburi`. For el and ru the base itself is returned (Helvetica covers them), which is harmless. `GeezaPro` is AAT-only (ADR-0008). The picker never lists it for Arabic, so the preference simply finds no row there.
- **Timing:** once per launch (see AppModel+Picker). `lookUp` is `nonisolated` and runs off the main actor; `CTFont` values never leave it (they aren't `Sendable`). The result is `[languageID: postscriptName]`.
- **Filtering:** only names that belong to a visible catalog face are used. They become `preferredPostScriptNames` (for WP-304) and `preferredFamilies` (for the initial row).
- **Safety:** it is not name matching. It is still limited to the listed languages, never runs in tests except behind `FP_APPLE_FONTS=1`, and fails soft to `[:]`.

**Accessibility.** The search field is "Search fonts", the language picker "Show fonts for", and the table "Fonts". A family row's label is "\(family), \(native), in your font", leaving out the empty parts. Its help is "Sample: \(sample)". A greyed row's label ends with ", unavailable: \(reason)". A header's label is its title with "·" replaced by ",", for example "All Chinese fonts, 37". The Use button's label is its title.

**Signposts** (S5): `PickerOpen` (from `openPicker` until the first table draw after `reloadData`), `PickerRows` (each build), `RowFonts` (each cache batch).

### Acceptance criteria

`PickerTestFaces` builds the reference picker catalog (`tests/test_picker.py:20-32`) as FaceRecords:
- S "Picker Simplified": 2,600 Han + the markers + "Aa1";
- H "Picker Plain Han": 2,600 Han, no markers;
- L/LB "Picker Latin" Regular/Bold (LB weight 700): 100 Latin;
- Z "Picker Zeta": 100 Latin, local name "测试黑体";
- X "Picker Bitmap": unsupported.
Model tests call `open(...)` with that catalog directly.

- **AC-503-1** The language picker lists `Languages.all` labels and ids in table order. (`PickerModelTests.languagePickerListsEveryLanguage`)
- **AC-503-2** For chinese_s the All section lists ["Picker Simplified"], with placeholder "Search 1 font — English or native name". For any it lists [Latin, Plain Han, Simplified, Zeta] with "Search 4 fonts — …". For latin it lists [Latin, Zeta]. For korean there are no rows and the status is "None of your fonts draw Korean well.". X is never listed (`test_picker.py:70-85`). (`PickerRowsTests.languageFilterListsFamiliesThatDrawItWell`)
- **AC-503-3** With any selected: the query "ZETA" matches [Zeta], "测试" matches [Zeta] (native name "测试黑体"), "plain" matches [Plain Han], and "ＺＥＴＡ" (full width) matches [Zeta]. "nothing like it" gives no rows, no current face, the status "No fonts match “nothing like it”." and a disabled Use. Clearing the query restores the 4 family rows and the status "6 fonts" (X counts: it is a face of the catalog, just not listed) (`test_picker.py:88-102`). (`PickerRowsTests.searchMatchesEnglishAndNativeNames`)
- **AC-503-4** The row texts are exactly ["All Chinese fonts · 1", "Picker Simplified"] (chinese_s), ["All Latin fonts · 2", "Picker Latin", "Picker Zeta"] (latin), and a first row "All fonts · 4" (any). With "han", any gives ["All fonts · 1", "Picker Plain Han"]. Headers are not selectable (`test_picker.py:105-117`). (`PickerRowsTests.sectionsAndCounts`)
- **AC-503-5** With the suggestion [Z] for latin, the rows are ["Suggested for your text", "Picker Zeta", "All Latin fonts · 2", "Picker Latin", "Picker Zeta"] and the current row is index 1. With the query "latin" the Suggested section disappears. The suggestion [S] is dropped for latin (it doesn't cover it well) (`test_picker.py:120-129`). (`PickerRowsTests.suggestedSectionOnlyWithPassingSuggestions`)
- **AC-503-6** When `recipeKeys` holds LB, Picker Latin's row has `inRecipe` and Zeta's doesn't. The tag text is "in your font". (`PickerRowsTests.inYourFontTag`)
- **AC-503-7** The titles are "Choose your main font" (empty recipe), "Choose a font for Chinese", "Choose a font" (any) and "Replace Picker Zeta". When replacing Z, Z's All row is current, the language is latin and the query is empty (`test_picker.py:139-158`). (`PickerModelTests.titlesAndOpenState`)
- **AC-503-8** On the rows of AC-503-5, `moveDown:` goes from index 1 to 3 (skipping the header), then to 4, and stays at 4. `moveUp:` ×3 ends at 1. `scrollPageDown:` goes to 4 and `scrollPageUp:` to 1. `moveToEndOfDocument:` and `moveToBeginningOfDocument:` go to 4 and 1. Each command is sent through `SearchFieldView.Coordinator.control(_:textView:doCommandBy:)`, which returns true. `insertText:` is not handled (returns false) (`test_picker.py:162-187`). (`PickerKeyboardTests.commandsMoveSkippingHeaders`)
- **AC-503-9** Return (`insertNewline:`) uses the family's default face: L when there is no main, LB when the main is a weight-700 face (`test_picker.py:190-200`, `smart.default_face`). (`PickerKeyboardTests.returnUsesTheFamilysDefaultFace`)
- **AC-503-10** In the off-screen `PickerTableView` (latin, rows ["All Latin fonts · 2", "Picker Latin", "Picker Zeta"]): Return (`keyDown` with a synthesized `NSEvent.keyEvent`, key code 36) uses the current row; the double-click handler, called as the table's `doubleAction` does it with the clicked row (`FontListView.Coordinator.handleDoubleClick(row: 2)`; `clickedRow` itself is read-only), uses row 2 (Zeta); a double click on a header does nothing; a printable key moves first responder to the search field and appends the character there (`test_picker.py:203-213`). (`PickerTableTests.returnDoubleClickAndTyping`)
- **AC-503-11** `cancelOperation:` from the search field or the table, the Back button and Cancel all close the model and clear `model.trial` (`test_picker.py:216-227`). (`PickerModelTests.escapeBackAndCancel`)
- **AC-503-12** The Use button reads "Use Picker Latin", and "Use Picker Zeta" after the query "zeta". A 30-character family shows the first 23 characters + "…". With no rows the title is "Use" and the button is disabled (`test_picker.py:230-239`). (`PickerModelTests.useButtonNamesTheFamily`)
- **AC-503-13** With `candidateDelay = .milliseconds(50)` and a manual clock: `open` for any schedules one candidate 50 ms out. Nothing arrives at 49 ms, and one candidate (L, the first row's default face) arrives at 50 ms. 3 `move(by: 1)` calls 30 ms apart each restart the wait, so nothing arrives and two waits are cancelled; exactly one candidate (Z) arrives 50 ms after the last one. A query with no match produces a nil candidate (`test_picker.py:242-255`). (`PickerModelTests.candidateIsDebounced`)
- **AC-503-14** With a manual clock: `cancel()` before the candidate task starts, and `cancel()` 10 ms after `open`, both cancel the pending wait (none is left on the clock), and no candidate arrives when the clock then advances 1 s (`test_picker.py:258-267`). (`PickerModelTests.noCandidateAfterClose`)
- **AC-503-15** Scan texts: "Looking for fonts…"; "Looking for fonts… 340 / 1,101" (en_US); after the scan with one unreadable file, "6 fonts · 1 file couldn't be read" with the help "/x/bad.ttf: TTLibError: bad". Then "1 font · 3 files couldn't be read" with three help lines, and "0 fonts" with an empty help (`test_picker.py:271-294`). With `hiddenCount = 3` and `duplicateCount = 1`, the help's last line is "3 hidden system fonts and 1 duplicate aren't listed." (`PickerModelTests.scanLifecycleTexts`)
- **AC-503-16** While scanning with `refreshInterval = 300 ms` and a manual clock: adding Z does not rebuild at 299 ms and has rebuilt to ["All Latin fonts · 1", "Picker Zeta"] at 300 ms. Adding L and ending the scan rebuilds at once (no wait) to ["All Latin fonts · 2", "Picker Latin", "Picker Zeta"], Z stays current, and the status is "2 fonts" (`test_picker.py:297-311`). (`PickerModelTests.rowsFollowARunningScanThrottled`)
- **AC-503-17** **UI-1.** The catalog also holds:
  - ".Apple SD Gothic NeoI" (`hidden = true`, covers Latin and Hangul);
  - "System Font" with PostScript ".SFNS-Regular" and `hidden = false` (a record from an older scanner);
  - ".LastResort" (`hidden = false`, `suspiciousCoverage = true`, covers everything).
  For every language, none of them appears in any row. The first All row starts with a letter. No preselected row or Use title names them. None of them counts in the placeholder. (`PickerRowsTests.ui1HiddenFacesAreNeverListed`)
- **AC-503-18** **CATALOG-2.** Passing ".LastResort" (suspicious) and ".Hiragino Sans GB Interface" (hidden) as suggestions for chinese_s gives no Suggested section. The initial current row is Picker Simplified. (`PickerRowsTests.catalog2SuspiciousAndHiddenFacesAreNeverSuggested`)
- **AC-503-19** **CATALOG-11.** Two Chinese families, "Lantinghei SC" and "PingFang SC" (PostScript "PingFangSC-Regular"), have identical coverage (2,600 Han + the chinese_s markers) and glyph counts. The model's `platformPreferredNames` is set to `["chinese_s": "PingFangSC-Regular"]` and `platformFontLookup` stays nil (no CoreText call):
  (a) with a recipe holding "Latin Sans" (AC-503-23) and the sample "Hello 你好", opening for chinese_s gives a Suggested section whose first row is PingFang SC. This relies on WP-304's tie-breaker, a dependency of this WP. Control: the catalog lists "Lantinghei SC" first, and calling `Recipe.suggestions(for:in:limit:preferences:)` with `.none` puts Lantinghei SC first. The app always appends `.macOS`, whose existing PingFang family preference also breaks this tie when `platformPreferredNames` is empty; clearing only the lookup result therefore is not a preference-free control;
  (b) with nothing missing (no Suggested section), the initial current row is PingFang SC even though "Lantinghei SC" sorts first.
  (`PickerFlowTests.catalog11PlatformFontBreaksTiesAndIsTheInitialRow`)
- **AC-503-20** `PlatformFontPreferences.lookUp(probes: ["chinese_s": "你", "japanese": "こ"])` returns `"PingFangSC-Regular"` for chinese_s (exact name; the audit Mac and macOS 27 agree) and a name starting with "HiraginoSans" for japanese. No returned name starts with ".", and ids without a tag are absent (`["latin": "a"]` gives `[:]`). It runs only with `FP_APPLE_FONTS=1` (`.enabled(if:)`), and the test performs no name-based lookup. (`FPMacServicesTests/PlatformFontPreferencesTests.catalog11ChineseDefaultIsPingFang`)
- **AC-503-21** **ADR-0008.** Two test faces cover U+0621–U+064A (42 Arabic letters, above the 40 that "draws Arabic well" needs) and "Aa1": "Geeza Pro" with `shapes_groups = []` and "Noto Naskh Arabic" with `shapes_groups = ["arabic"]`. For arabic, Geeza Pro is not listed. `unshapableCount` is 1 and the checkbox label is "Show fonts that can't shape Arabic (1)". With the checkbox on, it appears under "Can't shape Arabic · 1" with the reason "Can't shape Arabic: its shaping is Apple-only". It is not selectable, and `move(by:)` skips it. Noto Naskh Arabic is listed normally. For latin (with 100 Latin letters added to both faces) Geeza Pro is listed normally. (`PickerRowsTests.unshapableFontsHiddenOrGreyed`)
- **AC-503-22** **UI-14.** In the off-screen table:
  - `style == .inset`, `selectionHighlightStyle == .regular` and `autohidesScrollers == true`;
  - `scrollerStyle == NSScroller.preferredScrollerStyle`;
  - the row view class is `PickerRowView`, which overrides none of `drawSelection(in:)`, `drawBackground(in:)` and `drawSeparator(in:)` (checked with `class_getInstanceMethod` against `NSTableRowView`'s implementation);
  - `FontListView` sets no content insets on the scroll view (`contentInsets == NSEdgeInsetsZero`).
  (`PickerTableTests.ui14NativeScrollersAndSelection`)
- **AC-503-23** Flows (port `tests/test_app.py:24-35,118-160`). An `AppModel` from the S2.3 test initializer holds the catalog `catalogFaces` = three FaceRecords: "Latin Sans" (U+0020–U+007E, U+00A0–U+017F), "Han Sans" (U+0020–U+007E, U+4E00…+2,600, "们这说国门来你好世界，。！、", U+3041–U+3096, U+30A1–U+30FA) and "Hangul Sans" (U+0020–U+007E, U+AC00…+2,100). The sample text is "Hello 你好 あ". Each scenario starts from a fresh model. "Choose X" = set `picker.query` to X, wait (≤ 1 s) until the current row's family is X, then send `insertNewline:` through the search coordinator.
  1. `perform(.chooseMain)` opens latin; choosing "Latin Sans" closes the picker and gives materials ["Latin Sans"] with no rules.
  2. Continuing from 1: the prompt request (`RecipeColumnState.prompt.request`) opens chinese_s; choosing "Han Sans" gives ["Latin Sans", "Han Sans"] with the rule han → "Han Sans".
  3. Fresh model with ["Latin Sans"]: `openPicker(PickRequest(languageID: "korean"))` appends the Korean sample line (the sample now contains "안녕"). The query "Hangul" leads, within 1 s, to a `trial` whose banner starts with "Trying Hangul Sans for Korean" and whose mix has 2 fonts, while the recipe still has 1 material. `cancelOperation:` then clears `trial` and `pickRequest`, and the recipe still has 1 material.
  4. Fresh model with ["Latin Sans", "Hangul Sans" added for korean]: `perform(.pick(card 1's changeRequest))` opens with `replaceKey` = Hangul Sans; setting `picker.languageID = "chinese_s"` and choosing "Han Sans" gives ["Latin Sans", "Han Sans"], and the hangul rule now points to "Han Sans".
  (`PickerFlowTests.chooseTryCancelAndReplace`)
- **AC-503-24** Setting `isBuilding = true` while the picker is open closes it (`pickRequest == nil`, `trial == nil`). Setting it within 20 ms after a row change (while the debounce runs) leaves `trial == nil` 200 ms later. `openPicker` is ignored while building (`test_app.py:182-196`). (`PickerFlowTests.buildingClosesAndBlocksThePicker`)
- **AC-503-25** Row fonts go through `RowFontCache`:
  - with a fake renderer that sleeps 3 ms per font and a budget of 8 ms, requesting 20 fonts in one turn creates ≤ 3 synchronously and queues the rest;
  - later turns create all of them and call `onFontsReady`;
  - a second request returns the same object (`===`);
  - capacity 4 evicts the least recently used;
  - a failing face is not retried.
  (`PickerModelTests.rowFontsRespectTheBudgetAndCache`)
- **AC-503-26** Performance, rows: `PickerRows.build` over 1,200 synthetic FaceRecords in 420 families (the audit catalog's size), for "any" and for chinese_s with a 2-character query, has a median ≤ 25 ms × `FP_PERF_FACTOR` (debug build). (`PickerPerformanceTests.rowsBuildWithin25ms`)
- **AC-503-27** Performance, open: 420 families (synthetic records whose fake renderer maps each face round-robin onto the `file:` URLs from `CTFontManagerCopyAvailableFontURLs()` whose file exists, via `CTFontManagerCreateFontDescriptorsFromURL`; never by name). The time from `openPicker` to the first `cacheDisplay` of the 360 × 640 pt list in a never-shown window has a median ≤ 150 ms × factor. The prototype measured 41 ms (debug, M5 Pro). (`PickerPerformanceTests.openWithin150ms`)
- **AC-503-28** Performance, scrolling: in the same harness, scroll through the whole list in half-viewport steps, each step `scroll(to:)` + `reflectScrolledClipView` + `cacheDisplay`, and steps one 16 ms frame apart. The test spends that frame yielding to the main actor (queued font batches run), not sleeping: a coarse-timer runner stretches a sleep and lets the core idle, which about doubles the next step's time (docs/testing.md §3). Step time must be p95 ≤ 16.7 ms and max ≤ 33 ms × factor, and every family row that is visible at a step has `FontRowCellView.drewInOwnFace == true` by the second step after it first became visible (faces whose fake font creation failed are excluded). The prototype measured p95 13.7 ms and max 16.6 ms (debug). (`PickerPerformanceTests.scrollWithoutDroppedFrames`)
- **AC-503-29** Accessibility: in the off-screen table (latin, `recipeKeys` = {Z}), the cell returned by `view(atColumn: 0, row:, makeIfNecessary: true)` for Z's row has `accessibilityLabel() == "Picker Zeta, 测试黑体, in your font"` and `accessibilityHelp() == "Sample: Aa Bb Cc 0123"`. The header row's cell label is "All Latin fonts, 2". `PickerText.searchAccessibilityLabel` is "Search fonts" (its use on the `NSSearchField` is checked in AC-503-M4). (`PickerTableTests.voiceOverLabels`)
- **AC-503-30** `PickerText.trialBanner` returns the four forms of `test_app.py:101-106` with "Return uses it." at the end. (`PickerModelTests.trialBannerSaysWhatIsTried`)
- **AC-503-31** `make lint`, `make mac-test` and `make app` pass.
- **AC-503-32** Style menu: for latin with no main, the current row "Picker Latin" has `styles == [L, LB]` (by weight). Setting `chosenStyle = LB` produces one candidate LB after the debounce, and `use()` returns LB. `move(by: 1)` to Zeta resets `chosenStyle` to nil, and Zeta's `styles.count == 1` (menu hidden). (`PickerModelTests.styleMenuChoosesAnotherStyle`)
- **AC-503-M1** (manual, macos) On a stock Mac, run a debug build and set the sample to include Chinese. Open "Choose a font for Chinese". Attach a screenshot. It must show: PingFang SC among the rows, and first in "Suggested for your text" when it ties; no family starting with "."; no ".LastResort"; each row drawn in its own face with its native name (e.g. "苹方-简"); the "All Chinese fonts · n" header as a native group row.
- **AC-503-M2** (manual, macos) IME: switch to Pinyin, focus the picker search, type "nihao" and press ↓ in the candidate window. The candidate selection moves and the picker's current row doesn't. Press Return to commit "你好". The search then runs on the committed text. Record the steps and the result in the PR.
- **AC-503-M3** (manual, macos) Scrolling: with ≥ 300 families, flick through "All fonts" with a trackpad. Scrolling is smooth, and rows show in their own face at once or within a frame or two. Optional: attach an Instruments "os_signpost" trace showing no `RowFonts` interval > 8 ms.
- **AC-503-M4** (manual, macos) Start VoiceOver and move through the picker: search field, language picker, a header, two rows, Use. Attach the caption transcript. It must match the labels of AC-503-29.

### Verification
```bash
make lint
make mac-test
make app
FP_APPLE_FONTS=1 make mac-test   # also runs the opt-in CATALOG-11 CoreText lookup (AC-503-20)
```

### Notes for the implementer
- **Never** resolve a face by name for drawing. `FontRendering` only (S6). Hidden faces never reach the list, so there is also no reason to draw one.
- Don't start the debounce or the throttle with `Timer`. Use cancellable `Task`s on the main actor that sleep on the model's `clock` (`ContinuousClock` in the app), and cancel them in `cancel()`/`use()`. A closed model must emit nothing (AC-503-14).
- Keep `PickerRows.build` pure and allocation-light. It runs on every keystroke in the search field. Precompute the folded haystacks once per catalog (`picker.py:457-459`), not per query.
- `NSTableView.reloadData()` loses the selection. Re-select the current row after every rebuild and call `scrollRowToVisible`.
- Don't use SwiftUI `.onKeyPress` for the arrows. It is not IME-aware in the same way as `doCommand(by:)`.
- The original's `test_the_delegate_never_loads_a_file_while_painting` is replaced by AC-503-25. `test_apply_theme_dark` is dropped: colours are dynamic system colours, checked visually in AC-503-M1.
- Section titles moved to sentence case on purpose (Context table). The recipe's role titles stay upper case (FPCore strings).
- `CTFontCreateForStringWithLanguage` has been available since macOS 10.9 (SDK header `CTFont.h`), so it is within the macOS 14 deployment target.

---

## WP-504: Preview pane (editable text, runs, missing characters, built-font mode, zoom)

**Goal:** An editable preview that draws the user's text exactly as CoreText will draw the result: one font per `source_of` run, no fallback, missing characters marked and listed, the built font after a build, with native editing (IME, RTL, undo, plain paste) and native zoom.
**Depends on:** WP-501, WP-302, WP-402 · **Env:** macos · **Size:** L · **Closes findings:** UI-M6, NATIVE-M1

### Scope
- In: the toolbar (title, hint, Colour by Font toggle, size slider with value, Sample Text menu); the trial banner (text from `model.trial`); the editable TextKit 2 text view; per-run fonts from the shown mix, trial or built font; colour by font; missing-character marking; the missing-characters note with its "find a font" button; built-font mode with its badge and staleness; the empty-recipe placeholder mode; plain-text paste and drop; RTL paragraphs; IME; undo; zoom (slider, ⌘+/⌘−/⌘0 actions, pinch, ⌘-scroll); `PreviewController` for menu commands; fixed line height from the base material; synthetic-bold approximation; VoiceOver labels; performance.
- Out: producing the built font and setting `model.builtFont` (WP-505); the View menu items (WP-501, which calls this WP's `AppModel` methods); persisting the preferences (WP-501 stores `previewPointSize`/`colourByFont`); the picker (WP-503 sets `model.trial`).

### Touched paths
- `Packages/FontPlaygroundMacKit/Sources/FPAppUI/Editing/Preview/PreviewPane.swift` (edit: replace the placeholder body)
- `…/Editing/Preview/PreviewTextEditor.swift`, `PreviewTextView.swift`, `PreviewStyler.swift`, `PreviewRuns.swift`, `PreviewConfiguration.swift`, `PreviewText.swift`, `PreviewController.swift` (new)
- `…/Editing/AppModel+Preview.swift` (new; plus one stored property `let previewController = PreviewController()` in `AppModel`)
- `…/Editing/AppModel+EditingSeams.swift` (WP-501, ui-shell.md §S2; edit: delete the `zoomPreviewIn()`, `zoomPreviewOut()`, `resetPreviewZoom()` and `applySample(id:)` stubs, which `AppModel+Preview` replaces with the same signatures)
- `…/Editing/EditingShared.swift` (new, only if missing; S3)
- `…/Resources/Localizable.xcstrings` (preview strings)
- `Packages/FontPlaygroundMacKit/Tests/FPAppUITests/PreviewRunsTests.swift`, `PreviewConfigurationTests.swift`, `PreviewTextViewTests.swift`, `PreviewRenderingTests.swift`, `PreviewPaneTests.swift`, `PreviewPerformanceTests.swift`, `PreviewFixtureFonts.swift` (new)

### Design

**What is drawn** (first match wins; `ui/preview.py:9-11,297-304`):

```swift
enum PreviewMode: Equatable {
    case empty                                   // no materials: system font, faint, nothing missing, fallback allowed
    case mix(Mix)                                // the recipe
    case trial(PreviewTrial)                     // the picker's candidate (wins over built)
    case built(BuiltFontPreview, coverage: CharacterSet)   // one file; missing = not in its character set
}
struct PreviewConfiguration: Equatable {
    var mode: PreviewMode
    var pointSize: Int                           // 10…96
    var colourByFont: Bool
    static func make(recipe: Recipe, trial: PreviewTrial?, built: BuiltFontPreview?, builtCoverage: CharacterSet?,
                     pointSize: Int, colourByFont: Bool) -> PreviewConfiguration
    /// Index of the font drawing `scalar` (0 for the built font); nil = missing. `.empty` returns 0.
    func source(of scalar: Unicode.Scalar) -> Int?
    /// Visible scalars (TextUtil.visibleScalars) with no source; [] for .empty.
    func missingScalars(in text: String) -> [Unicode.Scalar]
}
```

`make` works like this:
- trial → `.trial`;
- else a built font that is present and `!built.isStale(for: recipe)`, with coverage available → `.built`;
- else an empty recipe → `.empty`;
- else `.mix(recipe.mix())`.

Built coverage comes from `CTFontCopyCharacterSet` on the built `CTFont` (`renderer`'s font for the built URL), cached per URL in `PreviewController.builtCoverage(for:renderer:)`. If the built font can't be created (the file is gone), that returns nil, the pane falls back to `.mix`, and it logs once per URL. `PreviewConfiguration` stays a plain value. `PreviewStyler` caches `source(of:)` per scalar for its current configuration and clears the cache in `apply(_:)` (`preview.py:115-125`).

**Runs** (`PreviewRuns`, pure; port of `preview.py:89-113,128-133`):

```swift
enum PreviewRuns {
    /// Per scalar of one paragraph (no line break inside): the source index, nil where missing.
    /// Ignorable scalars take the run before them; at the paragraph start they look ahead to the next visible
    /// scalar (0 when that one is missing or none follows). They are never missing. After a missing scalar the run
    /// before is 0.
    static func sources(_ paragraph: Substring.UnicodeScalarView, source: (Unicode.Scalar) -> Int?) -> [Int?]
    /// Consecutive equal sources merged into UTF-16 ranges relative to the paragraph start.
    static func runs(_ paragraph: Substring, source: (Unicode.Scalar) -> Int?) -> [(range: NSRange, source: Int?)]
}
```

Ranges are counted in **UTF-16 units**, so a scalar above U+FFFF counts 2 (`preview.py:39-41`). Paragraphs are split by `NSString.paragraphRange(for:)`. The line-break characters belong to the paragraph and take the run before them (they are ignorable).

**Attributes per run** (`PreviewStyler`). The styler sets a complete dictionary with `setAttributes(_:range:)`, which removes anything foreign:

| Mode / source | `.font` | `.foregroundColor` | `.backgroundColor` | extra |
|---|---|---|---|---|
| `.empty` | `NSFont.systemFont(ofSize: size)` | `.tertiaryLabelColor` | — | — |
| mix/trial, source i | font i (below) | `colourByFont ? MixPalette.colour(forMaterialAt: i) : .textColor` | — | synthetic bold of i |
| mix/trial, missing | font 0 | `.textColor` | `MixPalette.missingBackground` | — |
| built, 0 | the built font at size | `.textColor` | — | — |
| built, missing | the built font | `.textColor` | `MixPalette.missingBackground` | — |

Every run also gets `.paragraphStyle`: `baseWritingDirection = .natural`, `alignment = .natural`. In every mode except `.empty`, it also gets `minimumLineHeight = maximumLineHeight = ascent + descent + leading` of the **base** material's font (`mix.baseIndex`; the built font in `.built`). This matches the result, which takes its vertical metrics from the base font.

Font i = `renderer` font for `mix.fonts[i].face` at `CGFloat(pointSize) * mix.fonts[i].scale`. A variable face with a `wght` axis also gets `weight = mix.fonts[i].weight` (the renderer clamps it; nil = the axis default). The pane caches fonts per (FaceKey, size, weight) for the current configuration.

**Synthetic bold approximation** for static faces (engine rule: `engine/prepare.py:165-171`, `engine/synth_bold.py:8-13`). When there is no `wght` axis and `Δ = weight − face.weightClass ≥ 50`, set `d = min(Δ, 500)`. Then `.strokeWidth = -(Double(d) * 0.02)` (percent of the point size; negative = fill and stroke, which thickens stems by `d/1000 × 0.2 × size`, like the engine's stroke). `.strokeColor` = the run's foreground colour, and `.kern = d/1000 × 0.2 × runPointSize` (the engine adds the same amount to every advance). When Δ ≤ −50 nothing changes: the engine can't make a face lighter.

Typing attributes are always the attributes of source 0 (or the built or system font), so the caret and empty lines have the base size (`preview.py:303`).

**Text view** (`PreviewTextView: NSTextView`, created with `NSTextView(usingTextLayoutManager: true)` and wrapped by `PreviewTextEditor: NSViewRepresentable` inside an `NSScrollView`):
- `isRichText = true`, so programmatic per-run attributes are kept. The user cannot apply attributes: `usesFontPanel = false`, `usesRuler = false`, `usesInspectorBar = false`, `importsGraphics = false`, `allowsImageEditing = false`, `allowsDocumentBackgroundColorChange = false`.
- The sample must stay exactly as typed, so these are all `false`: `isAutomaticQuoteSubstitutionEnabled`, `isAutomaticDashSubstitutionEnabled`, `isAutomaticTextReplacementEnabled`, `isAutomaticSpellingCorrectionEnabled`, `isContinuousSpellCheckingEnabled`, `isGrammarCheckingEnabled`, `isAutomaticLinkDetectionEnabled`, `isAutomaticDataDetectionEnabled`, `isAutomaticTextCompletionEnabled`, `smartInsertDeleteEnabled`.
- `allowsUndo = true`. The editor's delegate returns a dedicated `UndoManager` from `undoManager(for:)`.
- `textContainerInset = NSSize(width: 14, height: 14)`. The background is `.textBackgroundColor`, inside a rounded bezel.
- **Plain paste and drop:** `override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }` and `override var acceptableDragTypes: [NSPasteboard.PasteboardType] { [.string] }`. Fonts come from the mix, never from the clipboard (`preview.py:207-221`).
- **Zoom:**
  - `override func magnify(with event: NSEvent)`: at `.began`, remember `startSize`; accumulate `event.magnification`; then `size = clamp(Int((Double(startSize) * (1 + accumulated)).rounded()), 10, 96)` → `onZoom(size)`.
  - `override func scrollWheel(with event: NSEvent)`: when `event.modifierFlags.contains(.command)`, accumulate `scrollingDeltaY`. With precise deltas, every 8 points is one step; otherwise one line is one step. A step is ±1 pt, clamped; positive `scrollingDeltaY` makes the text bigger. The event is not passed to `super`. Without ⌘ it calls `super`. A synthesized event (`CGEvent(scrollWheelEvent2Source:units: .pixel,…)` with `.maskCommand` → `NSEvent(cgEvent:)`) reports `hasPreciseScrollingDeltas == true` and `scrollingDeltaY == 16` for `wheel1: 16`; checked for this spec.
  - Both go through `PreviewZoom` (pure):

    ```swift
    enum PreviewZoom {
        static let range = 10...96
        static let steps = [10, 12, 14, 18, 24, 30, 36, 48, 64, 72, 96]
        static let defaultSize = 30
        static func size(from start: Int, magnification: Double) -> Int      // clamp(round(start × (1 + m)))
        /// Whole steps in `delta` (8 pt per step when precise, else 1 per line); keeps the remainder in `carry`.
        static func scrollSteps(delta: Double, precise: Bool, carry: inout Double) -> Int
        static func next(after size: Int) -> Int                             // first step > size, else 96
        static func previous(before size: Int) -> Int                        // last step < size, else 10
    }
    ```
  - `PreviewTextView.onZoom: (Int) -> Void` receives the new size; the coordinator sets `model.previewPointSize`.
- **Never** access `layoutManager` on this view: that silently switches it to TextKit 1. Use `textLayoutManager` / `textContentStorage` only.
- Accessibility label "Preview text", help "Type to try your own text. Each character is drawn by the font that will draw it in your font."

**Restyling** (`@MainActor final class PreviewStyler: NSObject, NSTextStorageDelegate`, holding the current `PreviewConfiguration` and its fonts; the delegate method is `nonisolated` + `MainActor.assumeIsolated`, see S6 rule 5):
- In `textStorage(_:didProcessEditing:range:changeInLength:)`: when the mask contains `.editedCharacters`, restyle `paragraphRange(for: editedRange)`. When it contains only `.editedAttributes` and the styler isn't restyling, restyle that paragraph range too (this reverts foreign attributes). An `isRestyling` flag prevents re-entry. Changing attributes there is allowed (NSTextStorageDelegate contract). Marked (IME) text keeps working: the experiment in Context confirmed it.
- `apply(_ configuration:)`: when the configuration differs, rebuild the fonts, then restyle the whole text inside `beginEditing()`/`endEditing()` (signpost `PreviewModeChange`), and set the typing attributes.
- Styling changes never register undo and never produce a text edit.
- When the editor factory explicitly enables `recordHistory: true` for tests, the styler appends every range it restyles to `private(set) var restyledRanges: [NSRange]` (cleared by `resetRestyleLog()`). Recording defaults to off; the production editor retains no diagnostic history.

**Text ↔ recipe.** `recipe.sampleText` is the model (persisted in `RecipeDocument`).
- User edits reach `textDidChange(_:)` in the coordinator, which sets `model.recipe.sampleText = textView.string`. An `isApplyingModelText` flag suppresses the echo. While `textView.hasMarkedText()` the coordinator does **not** update the recipe: romaji or pinyin being composed is not the user's text yet, like Qt's preedit (`UI-17`). The commit's `textDidChange` then carries the committed text. With the test factory’s explicit `recordHistory: true`, the coordinator appends every text it writes to the recipe to `private(set) var recipeUpdates: [String]`; production never retains these full-text snapshots.
- In `updateNSView`, when `model.recipe.sampleText != textView.string` (the picker added a language line, Start Over, a document load), replace the whole text through `textStorage.replaceCharacters` (not undoable), then `undoManager.removeAllActions()`. This is not a user edit (`preview.py:186-194`).
- Sample presets are one undoable edit (`preview.py:196-205`): `breakUndoCoalescing()`, `shouldChangeText(in: fullRange, replacementString: text)`, `replaceCharacters`, `didChangeText()`, `breakUndoCoalescing()`. The coordinator then updates the recipe like any edit. It also observes its dedicated undo manager’s completed undo/redo notifications and synchronizes text through the same guarded path: TextKit can restore text without `textDidChange` in an off-screen editor. ⌘Z brings the user's text back in one step. Nothing happens when the text already equals the preset. An off-screen test explicitly closes the typing undo group and opens the menu action’s group to model the separate AppKit event.

**`PreviewController` and the editor factory.**

```swift
@MainActor final class PreviewController {
    weak var textView: PreviewTextView?          // set by PreviewTextEditor.makeNSView, cleared in dismantleNSView
    /// One undoable edit when a text view is attached; otherwise returns false and the caller sets recipe.sampleText.
    func replaceAllUndoably(with text: String) -> Bool
    func focus()                                 // makes the text view first responder when it has a window
    func builtCoverage(for url: URL, renderer: any FontRendering) -> CharacterSet?   // cached per URL
}
extension PreviewTextEditor {
    /// Builds the scroll view, the TextKit 2 text view, the styler and the coordinator exactly as makeNSView does.
    /// Tests use it to get a working editor without SwiftUI.
    @MainActor static func makeEditor(model: AppModel, recordHistory: Bool = false) -> (scrollView: NSScrollView, textView: PreviewTextView, coordinator: Coordinator)
}
```

The coordinator keeps the styler's configuration current: it computes `PreviewConfiguration.make(…)` from the model in `updateNSView` (and, for the factory, whenever the model changes: tests call `coordinator.refresh()` after changing the model).

**Pane layout (SwiftUI `PreviewPane`):**
1. Toolbar `HStack` (at narrow widths, wrap the heading, toggle/menu and size controls into separate rows so the 140-point slider remains usable):
   - "Preview" (`.headline`) and the hint "Click and type to try your own text" (secondary, `lineLimit(1)`, `.layoutPriority(-1)`, so it truncates first);
   - `Spacer`;
   - `Toggle("Colour by Font", isOn: $model.colourByFont).toggleStyle(.button)` (`@Bindable var model`), help "Draw each font's characters in that font's colour";
   - "Size" + a continuous `Slider(value:in: 10...96)` (width 140, no tick marks) over a `Binding<Double>` that rounds into `model.previewPointSize`, accessibility label `PreviewText.sizeAccessibilityLabel` ("Preview size"), value `PreviewText.sizeAccessibilityValue(n)` ("\(n) points");
   - the value text "\(n) pt" (monospaced digits, fixed width for "96 pt");
   - A sample menu listing `Samples.presets` labels, whose visible title is the matching preset's label when `recipe.sampleText` exactly matches its text, otherwise "Custom Text". Derive the title from the recipe so typing, Undo/Redo and document loads keep it current. Its accessibility label is "Sample Text" and its value is the visible title. Help: "Replace the text with a sample (⌘Z brings yours back)".
2. The trial banner, when `model.trial != nil`: a rounded, accent-tinted strip with `model.trial.banner` (`preview_pane.py:192-200`).
3. In `.built` mode, a trailing row above the editor with the badge (*WP-701 finding A:* overlaid on the editor, wrapped text at half-screen width ran under it), then the text editor, which takes the remaining height. On top of the editor:
   - a non-interactive placeholder `Text("Type something to see it in your font")` (tertiary) while the text is empty.
   The badge is `Label("Built font", systemImage: "checkmark.seal")` in a capsule, with help "Showing \(displayName), the font that was just built. Change your font to go back to the preview of the mix." and accessibility label "Showing the built font".
4. The missing note, when `missingScalars` is non-empty (`preview_pane.py:256-263`): a rounded strip (`MissingNoteStrip`) tinted `.yellow.opacity(0.15)` with `PreviewText.missingText(scalars)` (wraps) and a bordered button at its full title width (*WP-701 finding G:* squeezed, it read "Add a font for Chines…" at half-screen width; `PolishOffscreenTests.missingNoteButtonKeepsItsTitle`). The button title is "Add a font for \(first.shortLabel)…" when `Languages.languagesForMissing(scalars)` is non-empty, else "Find a font…". It calls `model.openPicker(PickRequest(languageID: first?.id ?? "any"))`. The pane shows exactly what this pure function returns, so tests don't need SwiftUI:

   ```swift
   struct MissingNote: Equatable { var text: String; var buttonTitle: String; var request: PickRequest }
   extension PreviewText {
       /// nil when nothing is missing (always nil in .empty mode).
       static func missingNote(_ configuration: PreviewConfiguration, text: String) -> MissingNote?
   }
   ```

   Likewise the banner text is `model.trial?.banner`, and the badge shows iff `configuration.mode` is `.built`.

`PreviewText.missingText` (`preview_pane.py:60-67`, MAX_LISTED = 12):
- "“한” isn't in any of your fonts, so it would show as a box.";
- "“안”, “녕”, “하” aren't in any of your fonts, so they would show as boxes.";
- after 12: "…, “타” and 2 more aren't in any of your fonts, so they would show as boxes.".

`PreviewText.sizeText(n)` = "\(n) pt". `PreviewText` also holds every other string of this WP as constants: "Preview", "Click and type to try your own text", "Colour by Font", "Size", "Sample Text", "Custom Text", "Type something to see it in your font", "Built font", "Find a font…", the helps quoted above, `sizeAccessibilityLabel` = "Preview size", `sizeAccessibilityValue(n)` = "\(n) points", `builtBadgeAccessibilityLabel` = "Showing the built font", `editorAccessibilityLabel` = "Preview text", and `addFontButtonTitle(_ language:)` = "Add a font for \(language.shortLabel)…".

**Commands** (`AppModel+Preview`, called by WP-501's View menu and by the toolbar):
- `zoomPreviewIn()`: `previewPointSize = PreviewZoom.next(after: previewPointSize)`;
- `zoomPreviewOut()`: `PreviewZoom.previous(before:)`;
- `resetPreviewZoom()`: 30;
- `applySample(id:)`: the text of `Samples.presets` with that id (unknown ids do nothing), via `previewController.replaceAllUndoably(with:)`; when that returns false, `recipe.sampleText = text`;
- `focusPreview()`: `previewController.focus()`.
Pinch and ⌘-scroll set `previewPointSize` directly. WP-501 persists it (debounced).

**Signposts:** `PreviewRestyle` around every edit-triggered restyle, and `PreviewModeChange` around `apply`.

### Acceptance criteria

`PreviewFixtureFonts` generates with `$FP_ENGINE_PYTHON` (S5). Every font also maps U+0020 and has a `psName` (S5):
- A "Fixture A" covers "abc1,";
- B "Fixture B" Bold, weight 700, CFF, covers "ab漢，";
- C "Fixture C" UPM 2048 covers "a→Ω";
- V "Fixture V" variable wght 100–900 (default 400) covers "ab";
- R "Fixture Arabic": "ab", U+0627, U+0628, U+062F, U+063A and the presentation forms U+FE8D…U+FED0, each mapped to its own glyph. Its only layout table is a GSUB whose ScriptList has just `latn`, added with `fontTools.feaLib.builder.addOpenTypeFeaturesFromString(font, "languagesystem latn dflt;\nfeature liga { sub uni0061 uni0062 by uni0062; } liga;\n")`. This is the shape of the audit's forged Georgia + Baghdad font (NATIVE-M1: "GSUB scripts ['latn']"). No GPOS, no `morx`;
- R0 "Fixture Arabic Plain": the same cmap as R and **no GSUB at all**.

Checked for this spec with the reference builder and pyobjc CoreText on macOS 27: CoreText draws "بغداد" in R **unjoined** (glyphs = the nominal glyphs, visually reversed). In R0 it **joins** it, using the presentation-form glyphs (U+FE91, U+FED0, U+FEAA …) through its legacy fallback. That is why AC-504-15 compares the preview with CoreText itself rather than asserting "never joined".

The `FontRendering` in the test support creates fonts from those URLs with the LastResort cascade (S5). Tests may use the production URL renderer with generated temporary fixture files. The same attributed string the text storage holds is inspected with `CTLineCreateWithAttributedString` → `CTLineGetGlyphRuns` → `kCTFontAttributeName` → `kCTFontURLAttribute` (fonts are identified by file URL; LastResort by its URL).

- **AC-504-1** The editor is TextKit 2 (`textLayoutManager != nil`), both at creation and after all the other preview tests' operations. It is rich text for attributes only, and every automatic substitution listed in the Design is off. The placeholder text is "Type something to see it in your font". The default size is 30, colour by font is off, and the mode is `.empty` (`test_preview.py:48-56`). (`PreviewTextViewTests.editorIsTextKit2WithSubstitutionsOff`)
- **AC-504-2** With the mix (A, B) and the text "ab漢c": the run fonts are A, A, B, A; the sources are [0, 0, 1, 0]; nothing is missing; there are 3 merged runs [(0,2,A), (2,1,B), (3,1,A)]; the typing attributes' font is A (`test_preview.py:59-68`). (`PreviewRenderingTests.eachCharacterIsDrawnInTheFontThatDrawsIt`)
- **AC-504-3** The rule `{latin: 1}` makes "ab" come from B (`test_preview.py:71-75`). (`PreviewRunsTests.aRuleDecidesWhoDrawsASharedCharacter`)
- **AC-504-4** Size and scale: with B at 0.8, run fonts are 30 and 24 pt. After size 20, they are 20 and 16, and the typing font is 20 (`test_preview.py:78-86`). (`PreviewRenderingTests.sizeAndScaleReachTheRuns`)
- **AC-504-5** The mixes are built directly with FPCore's `Mix`/`MixFont` initialisers (the main font of a `Recipe` has no weight of its own). For V with weight 700, the run font's `CTFontCopyVariation` has `wght` 700 (key: the axis identifier `0x77676874`). For static A (weight class 400) with weight 700, the runs carry `.strokeWidth` −6.0 and `.kern` 0.06 × 30 = 1.8. With weight 430 (Δ < 50) there is no stroke. With 1000, Δ is capped at 500 (stroke −10). (`PreviewRenderingTests.variableWeightAndSyntheticBoldApproximation`)
- **AC-504-6** With the mix (A) and the text "a 漢‍b": 漢 has the missing background and is drawn in font A (a LastResort box in the CTLine). The space and the ZWJ have no background and source 0. The missing scalars are ["漢"]. In " 漢 " only 漢 is marked (`test_preview.py:97-107`). (`PreviewRenderingTests.missingIsMarkedButSpacesAndJoinersNeverAre`)
- **AC-504-7** In " 漢 a" with (A, B at 0.5), the sources are [1, 1, 1, 0]: the leading space looks ahead, and the space after 漢 is 15 pt (`test_preview.py:110-114`). (`PreviewRunsTests.spaceTakesTheRunBefore`)
- **AC-504-8** In "𠀀ab漢" with (A, B), the runs are [(0,2,missing), (2,2,A), (4,1,B)] in UTF-16 units, and the missing scalars are ["𠀀"] (`test_preview.py:117-125`). (`PreviewRunsTests.astralScalarsDoNotShiftLaterRuns`)
- **AC-504-9** "a\n漢\nb" with the mix (A) is 3 paragraphs, and only 漢 is marked. After `resetRestyleLog()`, replacing "b" with "c" (`insertText("c", replacementRange: NSRange(location: 4, length: 1))`) makes `restyledRanges == [NSRange(location: 4, length: 1)]` (`test_preview.py:128-134`). (`PreviewTextViewTests.eachParagraphIsRestyledOnItsOwn`)
- **AC-504-10** Colour by font in "a漢한" with (A, B): the foregrounds are `MixPalette.colour(0)` and `MixPalette.colour(1)`. 한 is missing, has the text colour and the missing background. Turning colour by font off gives `.textColor` everywhere. Built mode never colours (`test_preview.py:138-147`). (`PreviewRenderingTests.colourByFont`)
- **AC-504-11** A trial overrides the mix: with (A) and "a漢" the trial (A, B) gives 漢 → B and nothing missing. A recipe change during the trial doesn't show. Clearing the trial shows the new recipe (`test_preview.py:162-176`). (`PreviewConfigurationTests.trialOverridesTheMixUntilCleared`)
- **AC-504-12** Recipe (A, B) with `builtFont = BuiltFontPreview(url: <A's file>, displayName: "Fixture A Regular", spec: recipe.forgeSpec())`, A's file standing in for a build: all runs use the built font (their `kCTFontURLAttribute` is the built URL), 漢 is missing, the badge is visible, and a trial still wins. Changing the recipe (`setAdjustment` on B) makes `isStale` true, and the pane returns to the mix with the badge hidden. Editing the sample text only does **not** make it stale (`test_preview.py:179-193`, `ui/model.py:771-774`). (`PreviewConfigurationTests.builtFontUntilTheRecipeChanges`)
- **AC-504-13** **CATALOG-4 guard.** A copy of fixture A is registered with `kCTFontManagerScopeProcess` from a second file. Built mode on the first file still draws runs whose `kCTFontURLAttribute` is the first file. Unregister in a `defer`. (`PreviewRenderingTests.builtFontDrawsTheFileNotASameNamedRegisteredFont`)
- **AC-504-14** **NATIVE-M1 (a).** For the mix (A) and "ab 漢 →", the run fonts of `CTLineGetGlyphRuns` over the stored attributed string are A for "ab ", LastResort for 漢, A for " " and LastResort for → (string ranges {0,3}, {3,1}, {4,1}, {5,1}; checked for this spec). For the mix (A, B) the fonts are only {A, B, LastResort}, with LastResort only on →. No other font file ever appears (no fallback). (`PreviewRenderingTests.nativeM1RunsAreCoreTextWithoutFallback`)
- **AC-504-15** **NATIVE-M1 (b): the preview draws exactly what CoreText (TextEdit) draws.** In built mode, the text "بغداد" gives CTLine glyph IDs (all runs, in order) equal to those of a reference `CTLine` made from the same string with only `kCTFontAttributeName` = a fresh URL-created `CTFont` of the same file at the same size. Checked for both R and R0. In addition, for R the glyphs equal the nominal glyphs from `CTFontGetGlyphsForCharacters` in reverse order (unjoined, as TextEdit shows the audit's forged font), and none is a presentation-form glyph. For R0 at least one presentation-form glyph appears, and the preview shows it too. (`PreviewRenderingTests.nativeM1BuiltFontMatchesCoreTextShaping`)
- **AC-504-16** **RTL.** In "abc\nمرحبا", the runs of paragraph 2 have `CTRunGetStatus(run).contains(.rightToLeft)`, and the stored paragraph style has `baseWritingDirection == .natural` and `alignment == .natural`. (`PreviewRenderingTests.rtlParagraphsUseNaturalDirection`)
- **AC-504-17** **IME.** With the mix (A, B) and the text "ab" (caret at the end), call `setMarkedText("h", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))`, then the same with "ha". The marked range is `{2, 2}`, and the marked scalars have a `.font` attribute. The recipe's sample text is still "ab" (no update while text is marked). Committing with `insertText("漢", replacementRange: markedRange())` leaves `hasMarkedText() == false`, the committed 漢 has B's font, and `coordinator.recipeUpdates == ["ab漢"]` (one update, for the commit). (`PreviewTextViewTests.markedTextKeepsWorkingWhileRestyled`)
- **AC-504-18** **Plain paste.** A private pasteboard holds `.rtf` (red, bold 40 pt) and `.string` "bold big". `readSelection(from:)` inserts "bold big", with the recipe font and no red foreground, bold trait or 40 pt size. `readablePasteboardTypes == [.string]` (`test_preview.py:227-247`). (`PreviewTextViewTests.pasteIsPlainText`)
- **AC-504-19** **Edits vs model text.**
  - Setting `recipe.sampleText` from the model (then `coordinator.refresh()`) replaces the text view's string and adds nothing to `recipeUpdates`. Doing it twice with the same text does nothing. Colour and size changes add nothing to `recipeUpdates` and leave `undoManager.canUndo` unchanged.
  - From "ab", typing "c" then "1" at the end (`insertText` with `NSRange(location: NSNotFound, length: 0)`) gives `recipeUpdates == ["abc", "abc1"]`, and each typed character has a `.font` attribute right after its `insertText`.
  - `applySample(id: "korean")` replaces the text as one step: one `undo()` restores the user's text, and the recipe follows.
  (`test_preview.py:197-224`, `test_preview_pane.py:132-143`.) (`PreviewTextViewTests.editsSamplesAndUndo`)
- **AC-504-20** Missing note (`PreviewText.missingNote` over `PreviewConfiguration.make(…)`):
  - hidden for "abc 1,\n​" with (A);
  - shown for "abc 한", with the button "Add a font for Korean…" requesting "korean";
  - "a 가나다라마바사아자차카타파하 가" gives the 12-listed text with " and 2 more";
  - "a한" gives the singular sentence;
  - "a漢字한" gives "Add a font for Chinese…";
  - "aሀ" gives "Find a font…" → "any";
  - an empty recipe never shows it.
  (`test_preview_pane.py:71-128`.) (`PreviewPaneTests.missingNote`)
- **AC-504-21** `PreviewText.missingText` matches `test_preview_pane.py:96-101` exactly. (`PreviewPaneTests.missingTextWording`)
- **AC-504-22** Banner: with the recipe (A) and "a漢", setting `model.trial` to a trial of (A, B) with banner "Trying Fixture B for Chinese — ↑ ↓ try the next font, Return uses it." makes the configuration `.trial` and `missingNote` nil. Clearing it brings back `.mix` and the note for 漢 (`test_preview_pane.py:168-181`). (`PreviewPaneTests.bannerOnlyDuringATrial`)
- **AC-504-23** **UI-M6.**
  - `PreviewZoom.size(from: 30, magnification: 0.5) == 45`, `(from: 30, −0.9) == 10` (clamped) and `(from: 90, 0.5) == 96`.
  - A ⌘-scroll event built with `CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 16, wheel2: 0, wheel3: 0)` with `flags = .maskCommand` → `NSEvent(cgEvent:)` → `scrollWheel(with:)` raises `model.previewPointSize` from 30 to 32 (2 steps of 1 pt) and leaves the clip view's `bounds.origin` unchanged. The same event without ⌘ leaves the size alone.
  - `zoomPreviewIn()` from 30 gives 36, `zoomPreviewOut()` from 30 gives 24, `resetPreviewZoom()` gives 30, in from 96 stays 96, and out from 10 stays 10.
  (`PreviewTextViewTests.uiM6PinchScrollAndKeysZoom`)
- **AC-504-24** **Line height from the base.** In the mix (A, B) with base 0, every `NSTextLineFragment` of a paragraph containing 漢 has a height within 0.5 pt of A's `ascent + descent + leading` at the size. Rebased on B, it equals B's. (`PreviewRenderingTests.lineHeightComesFromTheBaseFont`)
- **AC-504-25** The empty recipe draws "abc 漢\n𠀀" in the system font with `.tertiaryLabelColor`, nothing missing, no background, and size 30 → 12 when changed (`test_preview.py:251-264`). (`PreviewRenderingTests.emptyRecipeDrawsAFaintPlaceholderFont`)
- **AC-504-26** **Performance, restyle.** Restyling one edited paragraph of 2,000 UTF-16 units that alternate A, B and missing has a median ≤ 25 ms × factor. Setting "ab漢" × 1,000 and turning colour by font on takes ≤ 250 ms × factor in total and yields 2,000 runs (`test_preview.py:267-276`). The measured `-O` restyle was 1.7 ms (M5 Pro). (`PreviewPerformanceTests.restyleWithinBudget`)
- **AC-504-27** **Performance, typing.** In an off-screen editor of 700 × 500 pt, time 300 keystrokes (`insertText` at varied positions + `textViewportLayoutController.layoutViewport()`):
  - with 2,000 units in 50 lines: p95 ≤ 16 ms × factor (measured 0.69 ms `-O`);
  - with one 2,000-unit paragraph: p95 ≤ 60 ms × factor (measured 22 ms `-O`, mostly TextKit layout).
  A full mode change (colour by font on) with layout of 2,200 units takes ≤ 50 ms × factor (measured 6 ms). (`PreviewPerformanceTests.typingStaysInteractive`)
- **AC-504-28** Accessibility: the editor from `PreviewTextEditor.makeEditor` has `accessibilityLabel() == "Preview text"`. `PreviewText.sizeAccessibilityLabel == "Preview size"`, `sizeAccessibilityValue(30) == "30 points"` and `builtBadgeAccessibilityLabel == "Showing the built font"`. That the SwiftUI controls apply them is AC-504-M6. (`PreviewPaneTests.voiceOverLabels`)
- **AC-504-29** `make lint`, `make mac-test` and `make app` pass.
- **AC-504-30** The sample menu title follows every chosen preset, shows "Custom Text" after editing or clearing the text, and follows model text replacement and Undo/Redo. (`PreviewPaneTests.sampleSelectionFollowsPresetAndModelText`, `PreviewTextViewTests.editsSamplesAndUndo`.)
- **AC-504-M1** (manual, macos) Set up Helvetica Neue + PingFang SC, Colour by Font on, and a sample with Latin, Chinese and one Korean character. Attach light and dark screenshots. They must show: each font in its own colour; 한 as a LastResort box with the missing ground; the note "“한” isn't in any of your fonts, so it would show as a box." with "Add a font for Korean…".
- **AC-504-M2** (manual, macos) IME: type "nihao" with Pinyin into the preview and commit "你好". Then type with Kotoeri (Japanese). The composing text shows an underline, the committed characters take the CJK material's font, and ⌘Z undoes the commit. Record the steps in the PR.
- **AC-504-M3** (manual, macos) Zoom: pinch on a trackpad (the size follows smoothly between 10 and 96), ⌘-scroll, and View ▸ Bigger/Smaller/Actual Size (⌘+/⌘−/⌘0). The slider and "n pt" follow each one, and the size persists after relaunch. Record the steps in the PR.
- **AC-504-M4** (manual, macos) RTL: add a font for Arabic from the picker. The picker lists only fonts that can shape Arabic (ADR-0008), so the result will join. Type an Arabic line, then a Latin line. The Arabic paragraph is right-aligned and joined, and the Latin paragraph is left-aligned. Attach a screenshot.
- **AC-504-M5** (manual, macos; only once WP-505 is merged) After Install, the "Built font" badge shows and the text is drawn from the built file. Changing a Size hides the badge and returns to the mix. Attach before and after screenshots. If WP-505 isn't merged, write "deferred to WP-505" in the PR. AC-504-12 covers the logic.
- **AC-504-M6** (manual, macos) With VoiceOver on (⌘F5), move through the preview toolbar and the editor. Attach the caption transcript. It must read "Colour by Font" as a toggle button, "Preview size, 30 points" (adjustable), "Sample Text" as a menu button with the current preset label or "Custom Text" as its value, and "Preview text" for the editor, and in built mode "Showing the built font".
- **AC-504-M7** (manual, macos) Choose sample presets, edit the text, and Undo/Redo; the menu's visible title follows the current preset or shows "Custom Text". At wide and narrow widths, the size slider has no tick marks, changes the preview in whole points between 10 and 96, and keeps its value text visible. Record the steps and screenshots in the PR.

### Implementation clarifications

- The toolbar wraps at narrow widths rather than forcing its controls beyond the preview column. The sample title and size controls retain their intrinsic widths; if the colour toggle and sample title cannot share a row, they occupy separate rows.
- Diagnostic range/text histories are test opt-ins, disabled by default to avoid retaining every typed sample in production.
- The off-screen editor synchronizes the model after completed undo/redo notifications as well as `textDidChange`; a regression verifies both directions.
- Preview rendering tests use the production URL renderer on generated temporary fonts, exercising its LastResort cascade and variable axes directly.

### Verification
```bash
make lint
make mac-test
make app
```

### Notes for the implementer
- The honest rendering chain is: `FontRendering` URL font → run attribute → TextKit 2 → CoreText. Don't add a fallback anywhere. No `NSFont(name:)`, and no `substituteFontForFont`-style repair of missing glyphs. A missing glyph must look missing.
- Accessing `textView.layoutManager` (even in a debug print) switches the view to TextKit 1. AC-504-1 checks `textLayoutManager` at the end of the suite on purpose.
- Restyle only the edited paragraph on keystrokes. A full restyle is only for configuration changes. Group scalars into runs, and call `setAttributes` once per run, not per scalar. Per-scalar calls were 25× slower in the prototype.
- Missing characters are **Unicode scalars** (Python code points), not Swift `Character`s. "é" as e + U+0301 is two scalars, and each has its own source (`ui/textutil.py:21-23`).
- Don't read the built font's coverage from `FaceRecord`s or the helper. `CTFontCopyCharacterSet` on the built `CTFont` is what CoreText will use.
- The synthetic-bold approximation is visual only. The report (WP-505) tells the user about synthetic bold; the preview doesn't need to say it.
- `ui/preview.py:315-322` (Qt font-change events) has no equivalent: dynamic system colours and SwiftUI updates cover appearance changes. A `viewDidChangeEffectiveAppearance` re-apply is only needed if `MixPalette.missingBackground` doesn't update by itself. Check that in AC-504-M1.
- Test support must never touch the general pasteboard or show a window (S5).
