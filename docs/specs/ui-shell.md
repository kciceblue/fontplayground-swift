# UI shell: app, window, menus, Settings, build and install, Advanced, accessibility

> Scope: WP-501, WP-505, WP-506, WP-507 · Env: macos · Architecture refs: docs/architecture.md §1 (goals), §2 (components, dependency rule), §3 (process model), §4 steps 4–7, §5 (face identity), §7 (baseline), §8 (cross-cutting rules); docs/specs/contracts.md §3–§8 · ADRs: 0003, 0005, 0006, 0007, 0008, 0009, 0010, 0011, 0012

## Context

### What the original app did

The original app is one Qt window (`reference/fontplayground-py/fontplayground/ui/app.py:88-402`). Its parts:

- **Layout.** The recipe column or the font picker sits on the left, in a `QStackedWidget` fixed at 420 pt (`app.py:34-35`, `app.py:121-125`). The preview pane is on the right. The action bar runs along the bottom, 84 pt high (`ui/action_bar.py:28`).
- **Commands.** Everything that is not on a button hides in a `⋯` menu (`app.py:171-199`): Rescan fonts, Add folder…, Start over, Advanced…, Theme (System/Light/Dark), Open settings folder.
- **Start-up and state.** The window scans fonts at start-up and restores `forge_last.json` once the scan finishes (`app.py:315-337`). It saves the recipe 300 ms after every change (`app.py:143-146`, `app.py:371-378`). It asks before quitting during a build (`app.py:380-402`). It opens at a fixed 1280×820 with a 1000×640 minimum (`app.py:405-415`).
- **Building.** `ui/build.py` (`BuildController`) decides what the bar's buttons do: build when there is no fresh result, then install or save a copy, remember what it installed, offer "Update installed font" when the result goes stale, and put failures in plain words (`build.py:30-52`, `build.py:122-353`). `ui/model.py` owns the combine lifecycle, the temporary results (`model.py:32-33`, `model.py:66-76`) and the stage wording (`model.py:50-63`).
- **Advanced.** `ui/advanced.py` is a non-modal dialog showing who draws which script, line spacing, default boldness and size, and the last build's report.
- **Theme.** `ui/theme.py` pushes a custom palette and follows the system colour scheme.

### What the audit found

The audit (`docs/research/macos-audit.md`) found these problems in this area:

| Finding | What is wrong on macOS | Closed by |
|---|---|---|
| UI-2 | No menu bar; no About, Settings, Edit, View, Window or Help; no ⌘W, ⌘, or ⌘F | WP-501 |
| UI-3 | The unbundled app is called "python" and has no icon | WP-501 (the app bundle) |
| UI-4 | The default window is taller than the usable screen and not centred; its frame is not remembered | WP-501 |
| UI-11 | "Open settings folder" and "Show file" open folders instead of revealing the item | WP-501 (settings folder), WP-505 (files) |
| UI-15 | No inspector-style Advanced, no drag and drop, quit-on-close undecided | WP-501 (quit-on-close, folder drops, inspector toggle), WP-506 (inspector content) |
| CRIT-8 | A 1000-pt minimum width and a fixed 420-pt column block half-screen tiling on a 1352-pt display | WP-501 |
| UI-9 | File dialogs are app-modal and untitled; `.ttf` is not guaranteed | WP-505 |
| UI-10 | Message boxes lose their titles, use Yes/No, and are app-modal | WP-505 (conflicts), WP-501 (quit, Start Over) |
| UI-M3 | A leading "." in the font name is accepted | WP-505 (UI side; FPCore raises `familyNameStartsWithDot`) |
| UI-M7 | The save-only flow gives no native way to install the result | WP-505 |
| UI-M8 | No Dock attention when a background build finishes | WP-505 |
| INSTALL-13 | Windows wording; "Show file" opens the folder | WP-505 |
| UI-13 | VoiceOver names are missing on icon-only and custom-drawn controls | WP-507 |
| UI-M4 | Custom colours ignore Increase Contrast; colour-by-font colours are too faint | WP-507 |
| UI-6 | No shortcuts; PC key names in hints | WP-507 (audit), WP-501 (shortcuts) |

### What goes away (Windows-only or Qt-only)

| Original | macOS replacement |
|---|---|
| `⋯` menu (`app.py:171-199`) | The menu bar (§S6). No `⋯` button in the preview toolbar |
| Theme menu System/Light/Dark and custom palette (`theme.py`) | Native controls and system colours. An Appearance override in Settings sets `NSApp.appearance`. Only the colour-by-font colours and the missing-character ground stay custom (`MixPalette`, §S9) |
| "Save…" as the primary button when installing is unsupported (`action_bar.py:282-283`) | Not ported: install is always available on macOS (ADR-0009) |
| `settings.json` and `forge_last.json` in `%LOCALAPPDATA%` | FPCore `AppSettings` stored in `UserDefaults` (§S4), and `last.fontrecipe` (contracts §8). Both are imported once from the Qt app (FPCore `LegacyImport`) |
| `RESULT_DIR` in the system temporary folder (`model.py:32`) | `…/Caches/io.github.kciceblue.fontplayground/builds/` (WP-505) |
| In-process `QThread` build that cancels at stage boundaries | The `fpengine forge` helper. Cancel means cancelling the consuming `Task` (ADR-0003) |
| `QMessageBox.question` with Yes/No | Sheet alerts with verb buttons |
| `PointingHandCursor` on buttons | The arrow cursor everywhere (UI-M5) |
| Registry, `WM_FONTCHANGE`, "Windows already has…" | `FontInstalling` (WP-403) and macOS wording |

### How this spec fits with the others

This spec is the frame that the other UI and service specs plug into:

| Spec | What it owns |
|---|---|
| `ui-editing.md` | WP-502 recipe column, WP-503 picker, WP-504 preview. Its §S2.3 lists the WP-501 seams it needs, and its §S3 fixes `Editing/EditingShared.swift`. This spec adopts both exactly (§S2) |
| `core.md` | FPCore: `Recipe`, `RecipeDocument`, `AppSettings`, `AtomicFile`, `LegacyImport`, `FaceCatalog`, `EnglishText`, `Naming` |
| `helper.md` | `EngineRunning`, `EngineClient`, `EngineError`, the H7 sweep |
| `mac-services.md` | `FontCataloging`/`CatalogStore`, `FontRendering`, `FontInstalling`/`FontInstaller`, and the English of `ConflictReason`/`InstallError` (§S8) |
| `foundation-release.md` | WP-001 Make targets and the app target this spec extends (`App/project.yml`, `Info.plist`, `Launcher`), the build paths (§S2), `AppLog` (§S7), WP-601 bundling and `--self-test`, WP-602 docs and licence texts |

Where this spec names another spec's API, it states the capability it needs. **The owning spec's exact names win.** Adapt the call site and record the change under "Spec deviations".

---

## Shared definitions

This section is normative for WP-501, WP-505, WP-506 and WP-507, and for the WP-501 seams that `ui-editing.md` relies on.

### S1. Files and ownership

All FPAppUI paths are under `Packages/FontPlaygroundMacKit/Sources/FPAppUI/`. Tests are under `Packages/FontPlaygroundMacKit/Tests/FPAppUITests/`. WP-501 creates every file listed as "created by 501". A "stub" file holds the fixed signatures of §S2 with placeholder bodies, and the owning WP later replaces the body. This way the five wave-10 PRs (`docs/plan.md` §4) touch different files, except for the stored properties that `ui-editing.md` WP-503/504 add to `AppModel`'s declaration.

| File | Created by | Owned afterwards by |
|---|---|---|
| `App/FPAppDelegate.swift`, `App/MainWindowController.swift`, `App/MainWindowGeometry.swift`, `App/QuitCoordinator.swift` | 501 | 501 |
| `Model/AppModel.swift` (the declaration) | 501 | 501; WP-503/504 add their stored properties (ui-editing.md) |
| `Model/AppServices.swift`, `Model/AppServices+Live.swift`, `Model/AppPaths.swift`, `Model/SettingsStore.swift`, `Model/SystemActions.swift`, `Model/FilePanels.swift`, `Model/AppNotice.swift`, `Model/AlertContent.swift`, `Model/CommandState.swift`, `Model/MenuCommand.swift`, `Model/CacheSweeper.swift`, `Model/AppModel+Actions.swift` (menu, folder and notice routes), `Model/Launch.swift` (restore, legacy import, autosave, reconcile), `Model/UnavailableEngine.swift` | 501 | 501 |
| `Diagnostics/AppLog.swift` (exactly foundation-release.md §S7, so WP-601 reuses it) | 501 | 501 |
| `Shared/EngineErrorText.swift` (`reason(_:)`, D3) | 501 | 501; WP-505 adds the build texts (WP-505 D8) |
| `Shared/ModelText.swift` (catalog-backed text for FPCore values, §S8) | 507 | 507 |
| WP-001's placeholders `Sources/FPAppUI/RootView.swift` and `Tests/FPAppUITests/PlaceholderTests.swift` | WP-001 | deleted by 501 (replaced by `MainWindowView` and the WP-501 tests) |
| `Model/BuildController.swift` (stub) | 501 | 505 |
| `Model/AdvancedModel.swift` | 506 | 506 |
| `Commands/AppCommands.swift` | 501 | 501 |
| `Views/MainWindowView.swift`, `Views/NoticeStack.swift`, `Views/ReportSheet.swift`, `Views/Settings/SettingsView.swift` | 501 | 501 |
| `Views/ActionBarView.swift` (stub) | 501 | 505 |
| `Views/AdvancedInspectorView.swift` (stub) | 501 | 506 |
| `Editing/EditingShared.swift` (exact content of ui-editing.md §S3) | 501 (or the first of 502–504 to land) | shared; 507 changes `MixPalette` (§S9) |
| `Editing/AppModel+EditingSeams.swift` (seam methods, §S2) | 501 | 501; WP-503/504 move their methods out (§S2) |
| `Editing/SidebarView.swift` | 501 | 503 |
| `Editing/Recipe/RecipeColumn.swift` (stub), `Editing/Picker/FontPickerView.swift` (stub), `Editing/Preview/PreviewPane.swift` (stub) | 501 | 502, 503, 504 |
| `Shared/ShellText.swift`, `Shared/Symbols.swift`, `Shared/ReportText.swift`, `Shared/AboutCredits.swift`, `Shared/WeightChoice.swift` | 501 | 501 (507 audits) |
| `Shared/BuildText.swift`, `Shared/AdvancedText.swift` | 505, 506 | same |
| `Resources/Localizable.xcstrings` | 501 | every UI WP adds its keys |
| `Tests/FPAppUITests/Support/ShellFakes.swift`, `Support/ShellFaces.swift`, `Support/ShellTempDirectory.swift` | 501 | 501; others may use them |
| App target: `App/project.yml`, `App/Info.plist`, `App/Sources/FontPlaygroundApp.swift` (all created by WP-001, edited here), `App/Resources/**` | WP-001 / 501 | 501; WP-601 and WP-602 extend them. `App/Sources/Launcher.swift` (WP-001's `@main`) is **not** touched by this spec |

A stub file carries the comment `// Stub: WP-NNN fills this in (docs/specs/ui-shell.md §S2).` That is the WP reference AGENTS.md requires for placeholders.

### S2. Seams (fixed)

**The editing seams.** These are exactly the declarations in ui-editing.md §S2.3.

- Stored in `AppModel`'s declaration:
  - `recipe: Recipe`
  - `catalogFaces: [FaceRecord]`
  - `catalogStatus: CatalogStatus`, with ui-editing's exact struct: `isScanning`, `done`, `total`, `faceCount`, `unreadable: [Unreadable(path, message)]`, `hiddenCount`, `duplicateCount`
  - `isBuilding: Bool = false`, with `didSet { if isBuilding { pickRequest = nil; trial = nil } }`
  - `pickRequest: PickRequest?`
  - `trial: PreviewTrial?`
  - `builtFont: BuiltFontPreview?`
  - `previewPointSize: Int` (10…96, default 30)
  - `colourByFont: Bool`
  - `let renderer: any FontRendering`
- The placeholder views `RecipeColumn`, `FontPickerView` and `PreviewPane` each take `init(model: AppModel)`. `SidebarView` shows `FontPickerView` when `model.pickRequest != nil`, else `RecipeColumn`.
- `Editing/EditingShared.swift` defines `PickRequest(languageID:replaceKey:)`, `PreviewTrial`, `BuiltFontPreview` and `MixPalette`.

**Seam methods.** They live in `Editing/AppModel+EditingSeams.swift`, and the menu (§S6) calls them. A method whose real version comes from another WP is removed from this file by that WP when it adds its own version. Otherwise Swift reports an invalid redeclaration.

| Method | Stub behaviour (501) | Real version, and the file it moves to |
|---|---|---|
| `openPicker(_ request: PickRequest)` | Sets `pickRequest` unless `isBuilding` | WP-503, `Editing/AppModel+Picker.swift` |
| `findFont()` | `openPicker(PickRequest(languageID: recipe.materials.isEmpty ? "latin" : "any"))` | WP-503, `Editing/AppModel+Picker.swift` |
| `zoomPreviewIn()` / `zoomPreviewOut()` / `resetPreviewZoom()` | Next or previous value on the ladder 10, 12, 14, 18, 24, 30, 36, 48, 64, 72, 96; or 30 | WP-504, `Editing/AppModel+Preview.swift` |
| `applySample(id:)` | `recipe.setSampleText(text)` with the text of the `Samples.presets` entry whose `id` matches (unknown ids do nothing; not undoable; allowed while building, like every sample-text edit) | WP-504, `Editing/AppModel+Preview.swift` |
| `showAdvanced()` | Sets `inspectorPresented = true` and persists it | stays (501) |

**Build seam.** `Model/BuildController.swift` is a stub that WP-505 fills in (full design under WP-505):

```swift
@MainActor @Observable public final class BuildController {
    weak var app: AppModel?                                // set at the end of AppModel.init
    public internal(set) var lastReport: ForgeReport?      // read by WP-506
    public internal(set) var lastErrorDetail: String?      // read by WP-506
    public var commands: BuildCommands { get }             // stub: .unavailable
    public func install()
    public func saveCopy()
    public func cancel()
    public func uninstall()
    public func showInFinder()
    public func openInFontBook()
    public func showReport()
    public func reset()                                    // Start Over
    public func cancelAndWait() async                      // quit; returns once the build Task has ended (≤ 3 s)
    public func discardResultFiles()                       // termination
    public init()                                          // the stub keeps no services; WP-505 reads them through `app`
}
public struct BuildCommands: Equatable, Sendable {
    public var canSaveCopy, canInstall, canShowInFinder, canOpenInFontBook, canUninstall: Bool
    public var installTitle: String                        // "Install" or "Update Installed Font"
    public static let unavailable: BuildCommands           // all false; installTitle "Install"
}
```

The stub's methods do nothing, and `cancelAndWait()` returns at once. WP-505 keeps `app.isBuilding` in step with its busy state, and it sets and clears `app.builtFont`. Those two seams are how the rest of the UI learns about builds.

### S3. Services, paths and AppModel

**Service protocols consumed.** `docs/specs/contracts.md` §7 fixes the protocol names. The owning specs fix the signatures, quoted here so the call sites can be written without guessing. If the owning spec changes a name before this WP lands, its spelling wins; record the adaptation under "Spec deviations".

| Protocol (owner) | Signatures FPAppUI calls | Used by |
|---|---|---|
| `EngineRunning` (helper.md WP-204 §1) | `hello() async throws -> EngineHello` (`protocolVersion`, `fpengineVersion`, `python`, `fonttools`, …). `forge(_ request: ForgeRequest) -> AsyncThrowingStream<ForgeEvent, any Error>` with `ForgeEvent.progress(EngineProgress)` (`stage: EngineStage`, `fraction`, `materialIndex: Int?`) and `ForgeEvent.finished(ForgeReport)`. Failures are thrown as `EngineError` (`.helperNotFound`, `.launchFailed`, `.incompatibleHelper`, `.helperFailed(HelperFailure)` with `code: HelperErrorCode`, `message`, `detail`, `materialIndex`; `.protocolViolation`, `.interrupted`, `.crashed`, `.timedOut`). **Cancelling the consuming `Task` ends the stream normally, without an error and without `.finished`** (helper.md WP-204 step 7) | 501 (hello), 505 (forge) |
| `FontCataloging` (mac-services.md WP-401 §2) | `snapshots() async -> AsyncStream<CatalogSnapshot>` (current snapshot first, then every publish); `refresh(_ mode: RefreshMode) async throws -> CatalogSnapshot` (`.incremental`, `.full`); `currentSnapshot() async -> CatalogSnapshot`; `setExtraFolders(_ folders: [URL]) async` (**only stores** them and starts no refresh; the caller then calls `refresh(.incremental)`, so one user action costs one refresh, mac-services.md AC-401-21); `noteInstalled(_ fileURL: URL) async throws -> CatalogSnapshot`; `noteRemoved(_ fileURL: URL) async -> CatalogSnapshot`; `startObservingSystemChanges() async`; `stopObservingSystemChanges() async`; `cancelRefresh() async`. Errors: `CatalogError.engineUnavailable(String)` | 501, 505 (note…) |
| `FontRendering` (mac-services.md WP-402) | held as `renderer` (seam); used by 502–504 | 502–504 |
| `FontInstalling` (mac-services.md WP-403 §1) | `conflict(for: InstallQuery) async throws -> InstallConflict` (`.noConflict`, `.replaceOurs(InstalledFont)`, `.ask(ConflictReason)`, `.block(ConflictReason)`); `install(_ source: URL, expecting: InstallQuery, confirmed: InstallConflict?) async throws -> InstalledFont`; `uninstall(_ font: InstalledFont) async throws -> UninstallOutcome` (`.movedToTrash(URL?)`, `.notInstalled`); errors are `InstallError`, which conforms to `LocalizedError` with `errorDescription == englishText` | 505 |

**Mapping a `CatalogSnapshot` to the seams** (mac-services.md WP-401 §2): `catalogFaces = snapshot.faces`; `catalogStatus.isScanning` = `snapshot.activity` is `.refreshing`; `done`/`total` = its progress (`filesDone`/`filesTotal`, 0/0 when idle); `faceCount = counts.faces`; `unreadable` = the snapshot's `.unreadable(path:code:message:)` issues as `(path, message)`; `hiddenCount = counts.hiddenFaces`; `duplicateCount = counts.duplicateFaces`. In addition, `AppModel.folderIssues: [String: String]` (folder path → text) holds the `.noAccess`, `.folderMissing` and `.folderUnreadable` issues with their mac-services.md §S8 English (`issue.englishText` in v1), so Settings can show them (D7; no silent drops). A snapshot is a **completed refresh** when `isComplete && activity == .idle`.

**FPCore API consumed.** core.md is authoritative for these names.

| Need | core.md | Used by |
|---|---|---|
| `Recipe`: `materials` (`face`, `weight`, `scale`, `availability`), `main: FaceRecord?`, `keys`, `index(of:)`, `names` (`family`, `style`), `sampleText`, `pins`, `baseKey`, `defaultWeight`, `defaultScale`, `suggestedFileName`, `scriptRules()`, `forgeSpec()`, `forgeRequest(outputPath:)`, `analyze() -> RecipeAnalysis` (`validity`, `glyphWarning`, `canForge`), `reset()` (keeps the sample text), `setFamily(_:byUser:)`, `setStyle(_:byUser:)`, `setSampleText(_:)`, `setPin(_:to:)`, `setBase(_:)`, `setDefaults(weight:scale:)`, `reconcile(with:) -> ReconcileReport` (`nowMissing`, `relocated`, `recovered`), `applyRealWeights(in:) -> [WeightSwap]`. "Empty recipe" in this spec means `recipe.materials.isEmpty` | WP-303, WP-304 | all |
| `RecipeProblem` (including `familyNameStartsWithDot`, `familyNameHasControlCharacter`, `styleNameHasControlCharacter`), `GlyphWarning`, and `EnglishText.problem(_:in:)` / `glyphWarning(_:)` for the English wording | WP-303 | 505 |
| `FaceCatalog(_:)` built from `catalogFaces` | WP-301 | 501, 506 |
| `RecipeDocument.decode(_:) throws` (throws `RecipeDocumentError` only), `init(recipe:)`, `encoded() throws -> Data`, `makeRecipe(catalog:) -> (recipe: Recipe, report: LoadReport)`; `LoadReport.outcomes`, `.unresolved`; `EnglishText.unresolvedSummary(_:)`, `EnglishText.replacementOffer(missing:replacement:)` | WP-305 | 501 |
| `AppSettings` (value; `Appearance`), `normalized(using:) -> (settings:, issues: [SettingsIssue])`, `FolderCheck.check(_:using:) -> Result<Accepted, Failure>`, `FileSystemProbe`, `LocalFileSystem` | WP-301, WP-305 | 501 |
| `LegacyImport.legacyFolder(home:)`, `.recipeFileName`, `.settingsFileName`, `.recipe(fromForgeLast:catalog:probe:) -> (recipe:, report: LegacyRecipeReport)` (`readable`, `load: LoadReport`, `lastSaveDirectory`), `.settings(from:probe:) -> (settings:, report: LegacySettingsReport)` (`readable`, `droppedFolders`) | WP-305 | 501 |
| `AtomicFile.write(_:to:)` (through `AppServices.writeFile`) | WP-305 | 501, 505 |
| `Naming.fileName(family:style:)` (strips leading dots), `Naming.cleanName(_:)`, `Naming.postscriptName(family:style:)` | WP-303/304 | 505 |
| `RuleResolver.smartSupplier(_:counts:order:)`, `RuleResolver.counts(for:)`, `ScriptGroup.allCases` (in GROUPS order), `needsShaping`, `FaceRecord.canShape(_:)`, `EnglishText.groupLabel(_:)`, `EnglishText.weightSwap(_:)` | WP-301/303/304 | 506 |
| `Languages.all`, `EnglishText.languageLabel(_:)`, `Samples.presets: [(id:, text:)]`, `EnglishText.samplePresetLabel(_:)` | WP-301 | 501 (menus) |
| `ForgeSpec`, `ForgeRequest`, `ForgeReport` (`fullName`, `postscriptName`, `familyName`, `styleName`, `materials`, `licenceNotes`, `warnings`, `durationSeconds: Double?`) | contracts §4, core.md WP-303 §8 | 505, 506 |

**AppPaths.** Every file the app writes goes through this type. Tests use `rooted(at:)`.

```swift
public struct AppPaths: Equatable, Sendable {
    public var applicationSupport: URL          // ~/Library/Application Support/io.github.kciceblue.fontplayground
    public var caches: URL                      // ~/Library/Caches/io.github.kciceblue.fontplayground
    public var userFonts: URL                   // ~/Library/Fonts (passed to FontInstalling)
    public var documents: URL                   // ~/Documents (first default for Save a Copy…)
    public var legacyFolder: URL                // LegacyImport.legacyFolder(home:) = ~/Library/Application Support/FontPlayground
    public var builds: URL { caches.appending(path: "builds") }
    public var helperTemp: URL { caches.appending(path: "tmp") }            // the helper's TMPDIR (architecture §3)
    public var lastRecipe: URL { applicationSupport.appending(path: "last.fontrecipe") }
    public var installedManifest: URL { applicationSupport.appending(path: "installed.json") }
    public static func live(fileManager: FileManager = .default) -> AppPaths
    public static func rooted(at root: URL) -> AppPaths   // every URL under root, for tests
}
```

**System adapters.** These are the only way FPAppUI touches `NSApp`, `NSWorkspace`, panels and the Dock. Tests use fakes.

```swift
public enum SystemEvent: Sendable { case didBecomeActive, displayOptionsChanged }
/// Opaque handle for a ProcessInfo activity. The live implementation keeps a [UUID: NSObjectProtocol] table.
public struct ActivityToken: Hashable, Sendable { public let id: UUID; public init(id: UUID = UUID()) { self.id = id } }

@MainActor public protocol SystemActions: AnyObject {
    var isAppActive: Bool { get }                       // NSApp.isActive
    var increaseContrast: Bool { get }                  // NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    var isFontBookAvailable: Bool { get }               // urlForApplication(withBundleIdentifier: "com.apple.FontBook") != nil
    /// NSApplication.didBecomeActiveNotification (NotificationCenter.default) → .didBecomeActive;
    /// NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, which is posted on
    /// NSWorkspace.shared.notificationCenter (not NotificationCenter.default) → .displayOptionsChanged.
    var events: AsyncStream<SystemEvent> { get }
    func applyAppearance(_ appearance: AppSettings.Appearance)   // NSApp.appearance = nil / .aqua / .darkAqua
    func reveal(_ urls: [URL])                          // NSWorkspace.shared.activateFileViewerSelecting(_:)
    func openFontBook()                                 // NSWorkspace.shared.openApplication(at:configuration:)
    func openInFontBook(_ file: URL)                    // NSWorkspace.shared.open([file], withApplicationAt:configuration:)
    func openURL(_ url: URL)                            // NSWorkspace.shared.open(_:)
    func requestAttention()                             // NSApp.requestUserAttention(.informationalRequest), only when !isAppActive
    func setDockBadge(_ text: String?)                  // NSApp.dockTile.badgeLabel
    func beginActivity(reason: String) -> ActivityToken // ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason:)
    func endActivity(_ token: ActivityToken)
    func showAboutPanel(credits: String)                // NSApp.orderFrontStandardAboutPanel(options: [.credits: …])
    func copyToPasteboard(_ text: String)
}

public struct SavePanelRequest: Equatable, Sendable {
    public var suggestedFileName: String                // Recipe.suggestedFileName
    public var directory: URL
    public var message: String?                         // NSSavePanel.message (licence lines, WP-505)
    public var allowedExtension: String = "ttf"
}
public struct FolderPanelRequest: Equatable, Sendable { public var prompt: String; public var message: String }
@MainActor public protocol FilePanels: AnyObject {
    /// NSSavePanel as a sheet on the main window (beginSheetModal(for:)). nil when cancelled.
    func chooseSaveLocation(_ request: SavePanelRequest) async -> URL?
    /// NSOpenPanel (directories only, multiple selection) as a sheet on NSApp.keyWindow (Settings or the main window).
    func chooseFolders(_ request: FolderPanelRequest) async -> [URL]
}
```

The live `FilePanels` configures the panels as follows.

- Save panel: `allowedContentTypes = [UTType(filenameExtension: request.allowedExtension)!]`, `nameFieldStringValue`, `directoryURL`, `canCreateDirectories = true`, `isExtensionHidden = false`. For `ttf`, the type is `public.truetype-ttf-font`, and the native panel then appends and enforces `.ttf` (UI-9 verifier).
- Folder panel: `canChooseDirectories = true`, `canChooseFiles = false`, `allowsMultipleSelection = true`, `treatsFilePackagesAsDirectories = false`, `prompt`, `message`.
- Both wrap the completion handler in `withCheckedContinuation`. With no window, both fall back to `runModal()`.

**AppServices and AppModel.**

```swift
@MainActor public struct AppServices {
    public var engine: any EngineRunning
    public var catalog: any FontCataloging
    public var renderer: any FontRendering
    public var installer: any FontInstalling
    public var system: any SystemActions
    public var panels: any FilePanels
    public var fileProbe: any FileSystemProbe       // FPCore protocol; live = LocalFileSystem()
    public var paths: AppPaths
    public var defaults: UserDefaults
    public var now: @Sendable () -> Date
    /// Every app-written file goes through this (AGENTS.md rule 8). Live: `try AtomicFile.write(data, to: url.path)`.
    /// Tests wrap it to count writes or inject an error.
    public var writeFile: @Sendable (_ data: Data, _ url: URL) throws -> Void
    /// helper.md H7 sweep. Live: `{ EngineClient.sweepLeftovers(temporaryDirectory: $0, outputDirectories: $1, now: $2) }`.
    public var sweepHelperLeftovers: @Sendable (_ temporaryDirectory: URL, _ outputDirectories: [URL], _ now: Date) -> Int
    public var helpURL: URL?                        // bundled UserGuide.html (WP-602), else Info.plist FPHelpURL, else nil
    public var acknowledgements: String?            // contents of Acknowledgements.txt in the app bundle, if present
    public var donateURL: URL?                      // Info.plist FPDonateURL when non-empty, else nil (WP-501 D8)
    public static func live(bundle: Bundle = .main) -> AppServices     // AppServices+Live.swift
}

public enum LaunchPhase: Equatable, Sendable { case starting, loadingFonts, ready }
public enum EngineStatus: Equatable, Sendable { case unknown, available(EngineHello), unavailable(String) }

@MainActor @Observable public final class AppModel {
    public let services: AppServices
    public let settings: SettingsStore
    public let build: BuildController
    public let renderer: any FontRendering                  // seam

    public var recipe: Recipe { didSet { recipeDidChange(from: oldValue) } }   // seam; autosave + analysis
    public private(set) var analysis: RecipeAnalysis        // recipe.analyze(), recomputed synchronously on change (ADR-0006)
    public internal(set) var catalogFaces: [FaceRecord]     // seam
    public internal(set) var catalogStatus: CatalogStatus   // seam
    public var isBuilding: Bool { didSet { if isBuilding { pickRequest = nil; trial = nil } else { runDeferredReconcile() } } }  // seam (+ D4 step 7)
    public var pickRequest: PickRequest?                    // seam
    public var trial: PreviewTrial?                         // seam
    public var builtFont: BuiltFontPreview?                 // seam
    public var previewPointSize: Int { didSet { schedulePreferenceSave() } }   // seam, 10…96
    public var colourByFont: Bool { didSet { schedulePreferenceSave() } }      // seam

    public private(set) var launchPhase: LaunchPhase
    public private(set) var engineStatus: EngineStatus
    public private(set) var increaseContrast: Bool
    public private(set) var folderIssues: [String: String]   // §S3 mapping; shown in Settings
    public var notices: [AppNotice]
    public var alert: AlertContent?
    public var sheet: SheetContent?
    public var inspectorPresented: Bool { didSet { settings.inspectorPresented = inspectorPresented } }
    public var sidebarVisibility: NavigationSplitViewVisibility   // starts .automatic; not persisted

    public init(services: AppServices)                      // no scan, no helper, no file IO beyond UserDefaults
    public func start() async
    public func prepareForTermination()
    public func flushAutosave()                             // writes last.fontrecipe now if a write is pending
    public func flushPreferences()                          // writes pending previewPointSize / colourByFont now
    @discardableResult public func edit(_ change: (inout Recipe) -> Void) -> Bool   // false while isBuilding
    public var commandState: CommandState { get }
    // menu and button routes: §S6 and WP-501 D6
}
```

`SettingsStore` (`Model/SettingsStore.swift`):

```swift
@MainActor @Observable public final class SettingsStore {
    public init(defaults: UserDefaults, probe: any FileSystemProbe)   // reads every key once (§S4), then normalizes
    public private(set) var value: AppSettings                         // FPCore value, already normalized
    public private(set) var loadIssues: [SettingsIssue]                // what normalized(using:) changed at load
    public var inspectorPresented: Bool { didSet { /* write through */ } }
    public var showAllScriptGroups: Bool { didSet { /* write through */ } }
    public var donationOffered: Bool { didSet { /* write through */ } }
    public func update(_ change: (inout AppSettings) -> Void)          // applies, writes every changed key at once
}
```

**Mutation rule.** While `isBuilding`, nothing that reaches the build may change. The original locks the recipe during a build (`app.py:267-272`, `advanced.py:215-223`). How each part obeys this:

- `edit(_:)` refuses changes while building.
- WP-502's `perform(_:)` applies the same guard (ui-editing.md).
- Sample-text edits are always allowed, because they don't change the build: they write `recipe.setSampleText(_:)` directly (WP-504, `applySample(id:)`).
- The only other direct writers of `recipe` are restore, reconcile (deferred while building) and Start Over (after `build.reset()` has ended the build), all inside `AppModel`. Everything else — Name/Style fields, notice replacements, Advanced intents and their Undo — goes through `edit`.

**How `recipe.didSet` works.** It does three things:

- When `launchPhase == .ready`, it schedules an autosave (WP-501 D4).
- It recomputes `analysis`.
- If the new recipe no longer matches `builtFont` (`builtFont.isStale(for:)`), it leaves `builtFont` in place. WP-504 checks staleness itself.

### S4. Settings (UserDefaults, domain = bundle id)

`SettingsStore` (`@MainActor @Observable`) holds FPCore's `AppSettings` value (core.md WP-305 §3) plus three FPAppUI-only values. How it loads and saves:

- It takes a `UserDefaults` in its initialiser. Tests pass `UserDefaults(suiteName: "fp-test-<uuid>")` and remove the suite afterwards.
- It reads every key once with `defaults.object(forKey:)` and builds `AppSettings`. A value of the wrong type reads as the default; for example `"yes"` for a Bool, or `true` for an Int. Pitfall: `UserDefaults` stores Bools as `NSNumber`, so `integer(forKey:)` and `bool(forKey:)` can't tell them apart. An Int key accepts an `NSNumber` only when `CFGetTypeID(n) != CFBooleanGetTypeID()`; a Bool key accepts only a CFBoolean.
- It then applies `normalized(using: probe)` and keeps the `SettingsIssue`s in `loadIssues`. `AppModel.init` posts one `settingsIssues` notice naming every `.droppedFolder` path (CRIT-2). `.previewSizeReset` and `.lastSaveDirectoryDropped` post nothing; they are logged with `AppLog.app.notice` (the Save panel then falls back to `~/Documents`).
- It writes through on every change, and it writes back the normalized values once at load, so a dropped folder is not reported again at the next launch.

This ports `app.py:61-72` and its test `test_preference_helpers_fall_back_to_defaults`.

| Key | Type | Default | Maps to | Written by |
|---|---|---|---|---|
| `settingsVersion` | Int | 1 | — | 501 |
| `appearance` | String | `"system"` | `AppSettings.appearance` (`system`, `light`, `dark`) | 501 |
| `extraFontFolders` | [String] | `[]` | `AppSettings.extraFolders` | 501 |
| `previewPointSize` | Int | 30 | `AppSettings.previewPointSize` (10…96) and the seam | 501 (from the seam, debounced 0.3 s) |
| `colourByFont` | Bool | false | `AppSettings.colourByFont` and the seam | 501 (from the seam, debounced 0.3 s) |
| `lastSaveDirectory` | String | none | `AppSettings.lastSaveDirectory` | 505 |
| `legacyImportDone` | Bool | false | `AppSettings.legacyImportDone` | 501 |
| `inspectorPresented` | Bool | false | FPAppUI only | 501 |
| `showAllScriptGroups` | Bool | false | FPAppUI only | 506 |
| `donationOffered` | Bool | false | FPAppUI only: the one-time donation offer has been shown | 501 D8 |
| `NSWindow Frame FPMainWindow` | AppKit frame string | none | window frame | AppKit autosave |

### S5. Layout constants

| Constant | Value | Why |
|---|---|---|
| Main window minimum content size | 640 × 480 pt | Half of a 1352-pt screen is 676 pt (CRIT-8). The audit data point is a MacBook Pro 14-inch at default scaling: 1352×878 pt, visible 1352×764 pt. 640 leaves 36 pt for tiling margins |
| Preferred window frame | 1280 × 848 pt (1280 × 820 content + 28 pt title bar, as the original) | `app.py:412`, UI-4 |
| First-launch frame | `MainWindowGeometry` (WP-501 D2) | UI-4 verifier |
| Recipe column (sidebar) width | min 260, ideal 280, max 420 pt | 420 was the fixed width (`app.py:35`). The column now collapses with ⌃⌘S |
| Detail column (preview and action bar) minimum width | 360 pt | 260 + 360 + 20 (dividers) ≤ 640 |
| Advanced inspector width | min 260, ideal 300, max 420 pt | WP-506 |
| Preview point size | 10…96, default 30. Zoom ladder 10, 12, 14, 18, 24, 30, 36, 48, 64, 72, 96 | `preview_pane.py:22`, `preview.py:28`, ui-editing.md WP-504 |
| Settings window content | 480 pt wide, height to fit | — |

### S6. Menu bar (normative)

`AppCommands` (a `Commands` value attached to the app's `Settings` scene) builds the menu bar. Titles are `ShellText` strings. "Auto" means SwiftUI or AppKit provides the item; it must still be present. Shortcuts use ⌘ command, ⌥ option, ⇧ shift, ⌃ control.

| # | Menu | Item | Shortcut | Placement | Action | Enabled when | Behaviour owner |
|---|---|---|---|---|---|---|---|
| 1 | Font Playground | About Font Playground | — | `CommandGroup(replacing: .appInfo)` | `showAbout()` | always | 501 |
| 1a | Font Playground | Donate… | — | same group | `openDonation()` | `services.donateURL != nil` | 501 D8 |
| 2 | Font Playground | Settings… | ⌘, | auto (Settings scene) | — | always | 501 |
| — | Font Playground | Services, Hide Font Playground ⌘H, Hide Others ⌥⌘H, Show All, Quit Font Playground ⌘Q | | auto | | | system |
| 3 | File | Start Over | ⌘N | `replacing: .newItem` | `startOver()` | the recipe is not empty, or `isBuilding` | 501 |
| 4 | File | Add Font Folder… | ⌘O | same group | `addFontFolder()` | always | 501 |
| 5 | File | Rescan Fonts | ⌘R | same group | `rescanFonts()` | not `catalogStatus.isScanning`, and the engine is not `.unavailable` | 501 |
| 6 | File | Save a Copy… | ⇧⌘S | `CommandGroup(before: .saveItem)` | `build.saveCopy()` | `build.commands.canSaveCopy` | 505 |
| 7 | File | Install *or* Update Installed Font | — | same group | `build.install()` | `build.commands.canInstall`; title = `build.commands.installTitle` | 505 |
| 8 | File | Show in Finder | ⇧⌘R | same group | `build.showInFinder()` | `build.commands.canShowInFinder` | 505 |
| 9 | File | Open in Font Book | — | same group | `build.openInFontBook()` | `build.commands.canOpenInFontBook` | 505 |
| 10 | File | Uninstall Font | — | same group | `build.uninstall()` | `build.commands.canUninstall` | 505 |
| — | File | Close ⌘W, Close All ⌥⌘W | | auto (the `.saveItem` group: never replace it) | | | system |
| 11 | Edit | Find Font… | ⌘F | `CommandGroup(after: .pasteboard)` | `findFont()` | not `isBuilding`, and `catalogFaces` is not empty | 503 (stub 501) |
| — | Edit | Undo ⌘Z, Redo ⇧⌘Z, Cut, Copy, Paste, Delete, Select All, AutoFill, Start Dictation…, Emoji & Symbols | | auto (responder chain; recipe undo is backlog B-4) | | | system |
| 12 | View | Colour by Font | — (checkmark) | `CommandGroup(before: .toolbar)` | toggles `colourByFont` | always | 501 (504 draws) |
| 13 | View | Bigger | ⌘+ | same group | `zoomPreviewIn()` | `previewPointSize < 96` | 504 (stub 501) |
| 14 | View | Smaller | ⌘− | same group | `zoomPreviewOut()` | `previewPointSize > 10` | 504 (stub 501) |
| 15 | View | Actual Size | ⌘0 | same group | `resetPreviewZoom()` | `previewPointSize ≠ 30` | 504 (stub 501) |
| 16 | View | Sample Text ▸ one item per `Samples.presets` entry, in order, titled `EnglishText.samplePresetLabel(id)` | — | same group | `applySample(id:)` | always | 504 (stub 501) |
| 17 | View | Show Sidebar / Hide Sidebar | ⌃⌘S | `SidebarCommands()` | — | always | 501 |
| — | View | Enter Full Screen ⌃⌘F | | auto (full-screen-capable window) | | | system |
| 18 | Font | Choose Main Font… (empty recipe) / Change Main Font… | — | `CommandMenu` "Font" | `openPicker(PickRequest(languageID: "latin", replaceKey: recipe.main?.key))` | not `isBuilding`, and `catalogFaces` is not empty | 501 route, 503 |
| 19 | Font | Add Font For ▸ every `Languages.all` entry except "any", in list order, titled `EnglishText.languageLabel(id)`; a divider; Any Language… | — | same menu | `openPicker(PickRequest(languageID: id))` | not `isBuilding`, and the recipe has a main font | 501 route, 503 |
| 20 | Font | Show Advanced / Hide Advanced | ⌥⌘I | same menu | `toggleAdvanced()` | always | 501 (506 content) |
| — | Window | Minimize ⌘M, Zoom, tiling items (macOS 15+), Bring All to Front, Font Playground | | auto | | | system |
| 21 | Help | Font Playground Help | ⌘? | `CommandGroup(replacing: .help)` | `openHelp()` | `services.helpURL != nil` | 501 |

Rules:

- **No clashes.** No two items share a key equivalent with the same modifiers. Rows 3–21 never use ⌘H, ⌘Q, ⌘M, ⌘W, ⌘, or ⌘Z.
- **No Install shortcut.** Install has no shortcut and is not the window's default button, so Return in the Name field never starts a build.
- **Menus are data.** `MenuCommand` is an enum with one case per numbered row except row 2 (the Settings scene provides it). Rows 16 and 19 take the sample or language id as an associated value (`.sample(id: String)`, `.addFontFor(languageID: String)`, and `.addFontForAnyLanguage` for "Any Language…"), and a hand-written `static var allCases: [MenuCommand]` lists every case in menu order, with every sample and language expanded. Each case carries:

  ```swift
  public enum MenuName: String, Sendable { case app, file, edit, view, font, help }
  public enum MenuPlacement: Equatable, Sendable {
      case appInfo, newItem, beforeSaveItem, afterPasteboard, beforeToolbar, sidebar, fontMenu, sampleSubmenu,
           addFontForSubmenu, help
  }
  extension MenuCommand {
      public var menu: MenuName { get }
      public var defaultTitle: String { get }          // the first title of the Item column (ShellText)
      public var shortcut: KeyboardShortcut? { get }   // SwiftUI KeyboardShortcut (Hashable); nil = none
      public var placement: MenuPlacement { get }
  }
  ```

  `AppCommands.menuOrder: [MenuCommand]` is the static list the `Commands` body iterates (it equals `MenuCommand.allCases` for the current `Samples.presets` and `Languages.all`). `CommandState` is a pure `Equatable` value computed from `AppModel`: `func isEnabled(_ command: MenuCommand) -> Bool`, `func title(_ command: MenuCommand) -> String`, `var isColourByFontOn: Bool`, plus the named flags the tests use (`canStartOver`, `canRescan`, `canFindFont`, `canChooseMainFont`, `canAddFontFor`, `canZoomIn`, `canZoomOut`, `canResetZoom`, `canOpenHelp`). `AppCommands` renders from both, so tests can check the tables without building menus.
- **Enabled states update.** Reading an `@Observable` model inside a `Commands` body works on macOS 14: SwiftUI refreshes enabled states when a menu opens. This was verified with a headless SwiftUI app (see "Notes for the implementer" under WP-501).

### S7. Alerts, sheets and notices

```swift
public struct AlertButton: Identifiable {
    public let id = UUID()
    public var title: String
    public var role: ButtonRole?             // .cancel for Cancel / Keep Building
    public var isDefault: Bool               // gets .keyboardShortcut(.defaultAction)
    public var action: @MainActor () -> Void
}
public struct AlertContent: Identifiable {
    public let id = UUID()
    public var title: String                 // NSAlert messageText (bold)
    public var message: String?              // informativeText
    public var buttons: [AlertButton]        // verb buttons, default first (UI-10)
}
public enum SheetContent: Identifiable, Equatable { case report(String) }   // id derived from the case
```

`MainWindowView` presents `model.alert` with SwiftUI `.alert(_:isPresented:presenting:actions:message:)`. On macOS this attaches the alert to the window as a sheet (UI-10). Any button sets `model.alert = nil` first and then runs its action. `model.sheet` is presented with `.sheet(item:)`, and `.report` shows `ReportSheet`.

```swift
public struct AppNotice: Identifiable, Equatable {
    public enum Kind: Equatable { case unresolvedFonts, fontsUnavailable, damagedRecipe, engineUnavailable,
                                       settingsIssues, restorationIssues, fileDropped, imported, importFailed, autosaveFailed }
    /// A CRIT-3 suggestion (core.md WP-305 §5): replace the unresolved material `missing` with catalog face `replacement`.
    public struct Replacement: Equatable { public var missing: FaceKey; public var missingName: String
                                           public var replacement: FaceKey; public var replacementName: String }
    public let id: UUID
    public var kind: Kind
    public var text: String
    public var revealURL: URL?               // shows a "Show in Finder" button when set
    public var replacements: [Replacement] = []
}
```

Notices appear in `NoticeStack` at the top of the detail column. Each one has:

- its text;
- one **Use %@** button per replacement ("Use %@", `shell.notice.use`, filled with `replacementName`). It calls `model.applyReplacement(_:)`, which runs `edit { $0.replace(r.missing, with: face) }` with the catalog face for `r.replacement`, then removes that replacement from the notice (and the notice when none is left). It does nothing while building, like every `edit`;
- an optional **Show in Finder** button ("Show in Finder", `shell.notice.showInFinder`);
- a **Dismiss** button: an `IconButton` with the symbol `xmark` and the label "Dismiss" (`shell.notice.dismiss`).

A new notice of the same `kind` replaces the old one. Notices never expire on their own. Texts:

| Kind | String id | English |
|---|---|---|
| unresolvedFonts | — | `EnglishText.unresolvedSummary(report)` (FPCore) + ".", then, for each `.notFound(replacements:)` outcome with at least one replacement, a space and the suggestion below, using the **first** replacement. Each such pair is also a `Replacement` |
| (suggestion) | `shell.notice.suggestion` | %1$@ isn't on this Mac. Use %2$@ instead? (the English of `EnglishText.replacementOffer(missing:replacement:)`; %1$@ = the unresolved display name, %2$@ = the replacement display name) |
| fontsUnavailable (one) | `shell.notice.unavailableOne` | “%@” is no longer available. It stays in your font, marked as missing, until you replace or remove it. |
| fontsUnavailable (several) | `shell.notice.unavailableMany` | %1$lld fonts are no longer available: %2$@. They stay in your font, marked as missing, until you replace or remove them. |
| damagedRecipe | `shell.notice.damaged` | Your last recipe couldn't be read, so Font Playground started with an empty one. The file was kept as “%@”. |
| engineUnavailable | `shell.notice.engine` | Font Playground can't start its font engine, so it can't list or build fonts: %@ |
| settingsIssues | `shell.notice.badFolders` | Some saved font folders were ignored because they aren't valid on this Mac: %@. |
| restorationIssues | `shell.notice.restorationIssues` | Some saved entries couldn't be used: %@. (count duplicate/invalid font entries, ignored font rules and legacy settings; identify an invalid saved line-spacing font and ignored legacy output path) |
| fileDropped | `shell.notice.fileDropped` | To use a font file, add the folder it's in with File › Add Font Folder…, or install it with Font Book. |
| imported | `shell.notice.imported` | Imported your last recipe and settings from the earlier version of Font Playground. |
| importFailed | `shell.notice.importFailed` | Font Playground found settings from an earlier version but couldn't read them. |
| autosaveFailed | `shell.notice.autosaveFailed` | Font Playground couldn't save your recipe: %@ |

A list inside a notice joins names with ", " and puts each name in “ ”. Names are display names (`"family style"`).

### S8. Strings, the String Catalog and source lint

- **One catalog.** There is one String Catalog, `Resources/Localizable.xcstrings`, and **the English text is the key** (ui-editing.md §S4). From v1.1 it also holds `zh-Hans`, and a word that needs two translations gets a context key (localisation.md §L2, WP-508).
  - Every FPAppUI string is produced with `String(localized: "…", bundle: .module, comment: "<string id>")`. Interpolation keys follow the catalog's format specifiers (`%@`, `%lld`).
  - The `bundle: .module` argument is required. Without it, the lookup uses the app's main bundle, which does not contain FPAppUI's compiled strings.
  - Verified on the audit Mac: SwiftPM compiles an `.xcstrings` resource into `en.lproj/*.strings` inside FPAppUI's resource bundle, and `swift test` reads it.
- **String ids and text types.** The dotted identifiers in this spec (for example `build.status.idle`) are string ids. The implementation passes the id as the `comment:`, so translators and tests can find it. It exposes the string as a static member of the area's text type: `ShellText`, `BuildText`, `AdvancedText`, and ui-editing's `RecipeText`, `PickerText`, `PreviewText`. Tests assert against those members.
- **Strings from FPCore and FPMacServices.** FPCore and FPMacServices return typed values (`RecipeProblem`, `GlyphWarning`, `LoadReport`, `ScriptGroup`, language and sample ids, `ConflictReason`, `InstallError`, …) and give their English through `EnglishText` / `englishText`. core.md (§ "No user-facing localized strings in FPCore") and mac-services.md §S8 require FPAppUI to render them through the String Catalog. The rule in this spec:
  - WP-501, WP-505 and WP-506 may call `EnglishText.*` and `.englishText` / `localizedDescription` directly (v1 English), except where this spec already gives a catalog string (for example `ConflictText`, WP-505 D4).
  - **WP-507** adds `Shared/ModelText.swift`: one catalog-backed function per `EnglishText` function that FPAppUI uses, plus `catalogIssue(_:)` for the folder issues of §S3 (`problem(_:in:)`, `glyphWarning(_:)`, `unresolvedSummary(_:)`, `replacementOffer(missing:replacement:)`, `groupLabel(_:)`, `languageLabel(_:)`, `languageShortLabel(_:)`, `samplePresetLabel(_:)`, `weightSwap(_:)`, and any others ui-editing's WPs call). Its English is identical to FPCore's, which a test checks case by case. WP-507 then replaces every FPAppUI call to `EnglishText` with `ModelText`, and lint rule L9 keeps it that way.
  - **Engine data** is shown as it comes and is never localised in v1: `ForgeReport.warnings`, `licenceNotes[].text`, `MaterialReport.warnings`, `HelperFailure.message`/`detail`, `FaceRecord.unsupportedReason`, and `InstallError`'s `localizedDescription` fragments (mac-services.md §S8 says WP-505 shows them after "Couldn't install the font: ").
- **Source lint** (`SourceLintTests.swift`). It reads every `.swift` file under `Sources/FPAppUI`, locating them from `#filePath`, strips `//` comments, and fails on:

| Rule | Forbidden | Allowed only in | Introduced by |
|---|---|---|---|
| L5 | `NSCursor`, `.pointerStyle(` (UI-M5) | nowhere | 501 |
| L6 | hex colour literals (`#[0-9A-Fa-f]{6}\b`, `0x[0-9A-Fa-f]{6}\b`), `Color(red:`, `NSColor(red:`, `NSColor(srgbRed:`, `NSColor(calibratedRed:` | `Editing/EditingShared.swift` | 501 |
| L7 | name-based font lookup: `NSFont(name:`, `Font.custom(`, `CTFontCreateWithName`, `CTFontDescriptorCreateWithNameAndSize`, `CTFontDescriptorCreateMatchingFontDescriptor`, `NSFontDescriptor(name:`. These can start system font downloads (AGENTS.md rule 4, ui-editing.md §S6) | nowhere | 501 |
| L1 | a string literal as the first argument of `Text(`, `Button(`, `Label(`, `Toggle(`, `Picker(`, `TextField(`, `Section(`, `Menu(`, `Stepper(`, `LabeledContent(`, `Link(`, `CommandMenu(`, or of `.help(`, `.accessibilityLabel(`, `.accessibilityHint(`, `.accessibilityValue(`, `.alert(`, `.confirmationDialog(`. Regex: `\b(Text|Button|…)\(\s*"` and `\.(help|accessibilityLabel|…)\(\s*"`. `Text(verbatim:` is allowed | nowhere | 507 |
| L2 | `String(localized:` without `bundle: .module` in the same call; `NSLocalizedString(` | nowhere | 507 |
| L4 | `Image(systemName:` with no `.accessibilityLabel(` or `.accessibilityHidden(true)` within the next 3 lines, unless it is the image of a `Label(` | `Shared/Symbols.swift` | 507 |
| L8 | `IconButton(` whose `label:` is `""` | nowhere | 507 |
| L9 | `EnglishText.` and `.englishText` (FPCore / FPMacServices English; §S8) | nowhere in `Sources/FPAppUI` (`ModelText` builds its own catalog strings; tests are not linted and may call both) | 507 |

  L1, L2, L4, L8 and L9 come in with WP-507, after WP-502–506 have landed, so the wave-10 WPs can follow ui-editing.md as written, and WP-507 converts what remains. WP-501's own code already follows L1, L2, L4 and L8. Every rule has a built-in positive snippet (it must match) and a negative snippet (it must not match), so a broken regex can't pass silently.
- **Lint mechanics.** `SourceLintTests` finds the sources with `URL(fileURLWithPath: #filePath)`: three `deletingLastPathComponent()` calls reach `Packages/FontPlaygroundMacKit`, and the sources are under `Sources/FPAppUI`. It removes `//` comments (outside string literals) and `/* … */` blocks before matching. "Within the next 3 lines" (L4) counts physical lines after the match. The rules are a `[LintRule]` table (`id`, `pattern: Regex`, `allowedFiles: Set<String>`, `positive: String`, `negative: String`), with balanced initializer scanning for the L4 `Label` exception and L8 nested `IconButton` arguments; regular expressions alone cannot reliably delimit these calls.

### S9. Colour-by-font and missing-character colours (applied by WP-507)

WP-501 creates `MixPalette` with ui-editing.md §S3's exact content (system blue, orange, green and purple). On white, `systemOrange` and `systemGreen` measure 2.31 and 2.22 (measured on the audit Mac). That is below the original's own rule of ≥ 3.0 for mix colours (`tests/test_theme.py:23-28`) and below WCAG's 4.5 for text. WP-507 (UI-M4) therefore replaces `MixPalette`'s colours with this table and keeps its API:

- `colour(forMaterialAt:)` and `missingBackground` become dynamic `NSColor(name:dynamicProvider:)` values. `colour(forMaterialAt:)` returns one of four cached colours, so index 4 still equals index 0.
- The provider picks the column from the appearance alone. Use `bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])`. The chosen name determines dark and increased-contrast flags. No global flag is read inside the provider.
- Pure table functions are added for tests: `static func hex(forMaterialAt:dark:increasedContrast:) -> UInt32`, `static func missingHex(dark:increasedContrast:) -> UInt32`, and `static func cardStrokeHex(dark:increasedContrast:) -> UInt32`, plus `static let cardStroke: NSColor` for any custom stroke.

Tests check the pure functions and all four `bestMatch` result-to-palette mappings, then resolve dynamic colours under Aqua and Dark Aqua. AppKit documents the accessibility appearance names as matching results; constructing them with `NSAppearance(named:)` is unsupported (Xcode 27 `NSAppearance.h`, accessibility-name declarations, and [Apple's documentation](https://developer.apple.com/documentation/appkit/nsappearance/name-swift.struct/accessibilityhighcontrastdarkaqua)). On the implementation Mac those requests collapse to ordinary Aqua/Dark Aqua. Read sRGB channel components inside `performAsCurrentDrawingAppearance`. Live Increase Contrast switching remains AC-507-M3, with no system preference changes in automated tests.


| Token | Light | Dark | Light, increased | Dark, increased | Rule (WCAG ratio) |
|---|---|---|---|---|---|
| mix 0 | #1a6bd8 | #6aa3ff | #0a4ea8 | #a8c8ff | text on the text background: ≥ 4.5 standard, ≥ 7.0 increased |
| mix 1 | #b85209 | #f5a25d | #8a3800 | #ffc58f | same |
| mix 2 | #267a3a | #5cc27a | #1c6630 | #8fe3a8 | same |
| mix 3 | #7c3aed | #c79bff | #5b21b6 | #dcc6ff | same |
| missing | #ffb3b3 | #7a2e2e | #ff8a8a | #a32b2b | label (#000000 light, #ffffff dark) on the fill ≥ 7.0; fill against the text background ≥ 1.6 standard, ≥ 2.2 increased |
| cardStroke | #c6c6c8 | #3a3a3c | #6e6e73 | #98989d | against the text background ≥ 1.4 standard, ≥ 3.0 increased |

- **Text background.** #ffffff (light) and #1e1e1e (dark): `NSColor.textBackgroundColor` / `controlBackgroundColor` as measured on macOS 27 with the SDK-27 look (CRIT-1).
- **Measured ratios**, in the order light / dark / light increased / dark increased:

| Token | Ratios |
|---|---|
| mix 0–3, light | 5.07, 4.94, 5.35, 5.70 |
| mix 0–3, dark | 6.59, 8.10, 7.50, 7.59 |
| mix 0–3, light increased | 7.87, 7.94, 7.02, 8.98 |
| mix 0–3, dark increased | 9.82, 10.82, 10.89, 10.77 |
| missing, text on fill | 12.35, 9.30, 9.25, 7.15 |
| missing, fill against background | 1.70, 1.79, 2.27, 2.33 |
| cardStroke | 1.71, 1.47, 5.07, 5.81 |

- **Origin of the values.** The light and dark mix colours are the original's (`theme.py:110`, `theme.py:124`); mix 1 and mix 2 were darkened to reach 4.5. The missing fills are the original's `missing` token (`theme.py:109`, `theme.py:123`) and ui-editing's dynamic colour.
- **Colour index.** Colours repeat every four materials.

### S10. Build report text (`Shared/ReportText.swift`)

`ReportText.render(_ report: ForgeReport, groupLabel: (String) -> String = ReportText.defaultGroupLabel) -> String` is the macOS port of `ForgeReport.as_text` (`reference/fontplayground-py/fontplayground/engine/spec.py:120-129`, as extended by engine-metadata.md WP-110 "as_text"). WP-505's report sheet and WP-506's inspector both show it. `defaultGroupLabel` maps a group id through `ScriptGroup(rawValue:)` and `EnglishText.groupLabel`, and returns an unknown id as it is.

- Lines are joined with `"\n"`; there is no trailing newline.
- Sections that would be empty are left out, together with the blank line before them. The "Built in" line is left out when `durationSeconds` is nil. The "Font:" line drops " (PostScript name …)" when `postscriptName` is empty.
- Numbers are plain integers, with no grouping separators, as in the original. The duration uses `String(format: "%.1f", …)`.
- The original's first line (`Output: <temporary path>`) is replaced by the font's names: the temporary path means nothing to the user.

```
Font: {fullName} (PostScript name {postscriptName})
Characters: {totalCodepoints}   Glyphs: {totalGlyphs}
Built in {durationSeconds, one decimal} s

{material.name}: {codepoints} characters  [{group labels joined by ", ", or "-"}]
    warning: {each material warning}

Licence:
  - {note.text} ({names of materials[note.materialIndexes], joined by ", "; left out with its parentheses when empty})

Warnings:
  - {each warnings[] line}
```

Every material line is followed by its own warning lines. `ReportText.failure(message:detail:) -> String` returns `message`. When `detail` is not empty, it adds a blank line and `detail`.

### S11. Symbols (`Shared/Symbols.swift`)

```swift
/// An icon-only button. The label is required: VoiceOver reads it, and the tooltip shows it (UI-13).
public struct IconButton: View { public init(symbol: String, label: String, action: @escaping () -> Void) }
/// A decorative icon, hidden from accessibility (for example the tone icon next to status text).
public struct DecorativeSymbol: View { public init(_ symbol: String) }
```

`IconButton` applies `.accessibilityLabel(Text(label))` and `.help(Text(label))`, uses `.buttonStyle(.borderless)`, and never changes the cursor.

### S12. Test support

- **`Support/ShellFakes.swift`** holds one fake per service:
  - `ShellFakeEngine` (`EngineRunning`, a `final class … : @unchecked Sendable` guarded by a lock): `helloResult: Result<EngineHello, EngineError>` and a `helloCalls` counter. `forge(_:)` records the `ForgeRequest` and returns a stream whose continuation the test drives: `emitProgress(_ stage: EngineStage, _ fraction: Double, materialIndex: Int?)`, `finish(report:)` (writes a few bytes to `request.outputPath` first, as the helper does, then yields `.finished`), `fail(_ error: EngineError)`, and `endWithoutResult()`. The stream's `onTermination` records `.cancelled` and finishes normally, as the real client does. `scan` is never used by FPAppUI and returns an empty finished stream.
  - `ShellFakeCatalog` (`FontCataloging`, an actor): the test pushes snapshots with `publish(_:)`. `setExtraFolders(_:)` records its argument and returns at once (it only stores, like `CatalogStore`). `refresh(_:)` records its mode and suspends until the test calls `finishRefresh(with: snapshot)` or `failRefresh(_ error:)`. It records `noteInstalled`/`noteRemoved` URLs and `startObservingSystemChanges`/`stopObservingSystemChanges` calls. A helper `ShellSnapshot.make(faces:isComplete:scanning:)` builds `CatalogSnapshot` values.
  - `ShellFakeRenderer`: returns `CTFontCreateUIFontForLanguage(.system, size, nil)`, never a name lookup.
  - `ShellFakeInstaller` (`FontInstalling`, an actor): scripted `conflict` results (a queue; the last one repeats), `install` results or errors, `uninstall` outcomes or errors; records every call with its arguments, including `confirmed`.
  - `ShellFakeSystemActions`: records every call; the test sets `isAppActive`, `increaseContrast` and `isFontBookAvailable`, and yields `events`.
  - `ShellFakeFilePanels`: scripted answers; records requests.
  - `ShellFakeFileProbe`: an in-memory file system (an FPCore `FileSystemProbe`).
  - `ShellFileWriter`: the `writeFile` closure for tests. It counts writes per URL, throws a scripted error when one is set, and otherwise calls the real `AtomicFile.write` into the temporary root.
  - `ShellTestError: LocalizedError` with a given `errorDescription`, for "access denied" and "the disk is full".
- **The shared test initialiser.** The same file provides `AppServices.testing(root: URL, defaults: UserDefaults, renderer: (any FontRendering)? = nil, catalog: (any FontCataloging)? = nil) -> AppServices`, which fills everything else with fakes: `paths = .rooted(at: root)`, `now = { Date() }`, `writeFile` = a `ShellFileWriter`, `sweepHelperLeftovers` = a recorder that returns 0, `helpURL = nil`, `acknowledgements = nil`, `donateURL = nil` (so no test sees the donation offer unless it sets one). Tests replace any field before creating the model (`var s = AppServices.testing(…); s.engine = myEngine`). `AppModel(services: .testing(…))` is the test initialiser that ui-editing.md §S2.3 asks for.
- **`Support/ShellFaces.swift`** builds `FaceRecord` values by decoding JSON (contracts §3 fields, with defaults), as ui-editing.md §S5 does. Where a test needs a file to exist, it creates an empty file under the temporary root.
- **`Support/ShellTempDirectory.swift`** creates a unique folder under `FileManager.default.temporaryDirectory` and removes it at the end. `AppPaths.rooted(at:)` points every path there.
- **Test rules.** Tests use `@testable import FPAppUI` (so they can set `internal(set)` properties such as `build.lastReport`). Every UI test is `@MainActor`. No test uses `UserDefaults.standard`, touches the real Application Support, Caches or `~/Library/Fonts`, or orders a window front (docs/testing.md §5).
- **Finding tests.** A regression test for an audit finding puts the ID first in its display name and its function name, for example `@Test("UI-4: the first frame fits the visible screen") func ui4InitialFrameFitsTheVisibleScreen()`.

---

## WP-501: App shell: XcodeGen target, `AppModel`, window, menu bar, Settings, About/Acknowledgements

**Goal:** A bundled, native macOS app. Its single main window (recipe column | preview | action bar) tiles on a MacBook screen. It has the full menu bar, Settings, About, the launch sequence, and the seams the other UI WPs fill.
**Depends on:** WP-001, WP-305, WP-401, WP-402, WP-403 · **Env:** macos · **Size:** L · **Closes findings:** UI-2, UI-3, UI-4, UI-11, UI-15, CRIT-8, TOOLING-M3

### Scope
- **In:**
  - the XcodeGen app target and its Info.plist;
  - `FPAppDelegate`, the main window controller, window geometry and frame restoration;
  - `AppModel` composition and DI, with all seams of §S2;
  - `SettingsStore`;
  - the launch sequence: sweep, restore, one-time legacy import, catalog refresh, hello;
  - autosave and reconcile;
  - the main window layout and the stubs of §S1;
  - the menu bar (§S6) and its routes;
  - the Settings scene;
  - the About panel with acknowledgements, and Help;
  - notices, alerts, quit and close handling;
  - folder drag and drop;
  - `ShellText` (including `shortPath(_:home:)`), `Symbols`, `ReportText`, `WeightChoice`, `EngineErrorText.reason(_:)`, `AppLog`, `UnavailableEngine`;
  - source lint rules L5–L7.
- **Out:**
  - recipe cards, the picker, preview drawing (WP-502–504, ui-editing.md);
  - build, install, save and the action bar (WP-505);
  - Advanced content (WP-506);
  - the accessibility and localisation audit, and the `MixPalette` colours (WP-507);
  - the icon art, helper embedding, signing and `--self-test` (WP-601);
  - licence texts and the user guide (WP-602);
  - opening single font files and `.fontrecipe` documents (backlog B-5).

### Touched paths
- `App/project.yml` (edit; WP-001 created it, foundation-release.md WP-001 item 6)
- `App/Info.plist` (edit), `App/Sources/FontPlaygroundApp.swift` (edit: replace WP-001's body; it stays un-annotated, `Launcher` remains the only `@main`)
- `App/Resources/Assets.xcassets/` (new: `AccentColor`, an empty `AppIcon` set; WP-601 replaces the icon), `App/Resources/InfoPlist.xcstrings` (new), `App/Resources/Acknowledgements.txt` (new; WP-602 completes it)
- `Packages/FontPlaygroundMacKit/Package.swift` (edit)
- `Packages/FontPlaygroundMacKit/Sources/FPMacServices/Rendering/FontRendering.swift` (add the public `RenderedFont` initializer needed by injected renderers; rendering behavior is unchanged)
- every FPAppUI file that §S1 lists as "created by 501" (new); `Sources/FPAppUI/RootView.swift` (delete)
- `Packages/FontPlaygroundMacKit/Tests/FPAppUITests/` (new): `Support/Shell*.swift`, `AppBundleTests.swift`, `SettingsStoreTests.swift`, `EditingSeamsTests.swift`, `LaunchTests.swift`, `RestoreTests.swift`, `ReconcileFlowTests.swift`, `StartOverTests.swift`, `FontFoldersTests.swift`, `MenuCommandTests.swift`, `CommandStateTests.swift`, `MainWindowGeometryTests.swift`, `QuitCoordinatorTests.swift`, `SettingsActionsTests.swift`, `AboutCreditsTests.swift`, `ReportTextTests.swift`, `SourceLintTests.swift`, `DropTests.swift`, `NoticeTests.swift`; `PlaceholderTests.swift` (delete)

### Integration clarifications

- `RenderedFont` exposes an initializer for its existing fields: a renderer in `FPAppUITests` must construct that public value across module boundaries (§S12). This adds no rendering behavior.
- Architecture §8 requires surfacing every omission on restore. D4 therefore posts a `restorationIssues` notice for duplicate/malformed material entries, ignored rules, an out-of-range saved base selection, ignored legacy setting keys and an ignored legacy output path. Successful relocation is not an omission. `RestoreTests.ignoredRecipeEntriesAreCountedAndReported` and `.ignoredLegacyEntriesAreCountedAndReported` cover these reports in addition to unresolved faces.
- FPCore uses the `LanguageID` enum. The shell keeps the specified string-valued picker and menu seams and converts with `rawValue` / `init(rawValue:)` at that boundary.
- Menu, folder and notice routes live in `Model/AppModel+Actions.swift`, keeping `AppModel.swift` focused on stored state and its private setters.

### Design

**D1. App target and bundle (UI-3).** WP-001 already created the app target (foundation-release.md WP-001 item 6): `App/project.yml` with the target and scheme `FontPlayground`, `App/Version.xcconfig` (the version numbers), `App/Info.plist` with the minimum keys, `App/Sources/Launcher.swift` (the **only** `@main`, which handles `--self-test` before `NSApplication` exists and then calls `FontPlaygroundApp.main()`), and a placeholder `App/Sources/FontPlaygroundApp.swift`. `make app` builds `build/DerivedData/Build/Products/Debug/Font Playground.app` (foundation-release.md §S2). WP-501 **extends** these files and never replaces WP-001's settings.

`App/project.yml` edits (everything else stays as WP-001 wrote it; the version stays in `Version.xcconfig`):

```yaml
targets:
  FontPlayground:
    sources:
      - path: Sources
      - path: Resources          # new: Assets.xcassets, InfoPlist.xcstrings, Acknowledgements.txt
    settings:
      base:
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon   # new (WP-601 keeps it)
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor   # new
```

`App/Info.plist` keys. WP-001's keys stay; WP-501 adds the rows marked "new". Where the table says so, values come from build settings.

| Key | Value | |
|---|---|---|
| `CFBundleName`, `CFBundleDisplayName` | `Font Playground` | WP-001 |
| `CFBundleIdentifier` | `$(PRODUCT_BUNDLE_IDENTIFIER)` (= `io.github.kciceblue.fontplayground`) | WP-001 |
| `CFBundleExecutable` | `$(EXECUTABLE_NAME)` (= `Font Playground`, the path `make self-test` uses) | WP-001 |
| `CFBundleShortVersionString`, `CFBundleVersion` | `$(MARKETING_VERSION)`, `$(CURRENT_PROJECT_VERSION)` | WP-001 |
| `CFBundlePackageType`, `CFBundleInfoDictionaryVersion`, `NSHighResolutionCapable` | `APPL`, `6.0`, `true` | WP-001 |
| `LSMinimumSystemVersion` | `$(MACOSX_DEPLOYMENT_TARGET)` (= 14.0) | WP-001 |
| `CFBundleDevelopmentRegion` | `en` | WP-001 |
| `LSApplicationCategoryType` | `public.app-category.graphics-design` | new |
| `CFBundleIconName` | `AppIcon` | new |
| `CFBundleAllowMixedLocalizations` | `true` (CRIT-10's cheap step) | new |
| `NSHumanReadableCopyright` | the copyright line of `LICENSE`, verbatim | new |
| `NSDocumentsFolderUsageDescription`, `NSDesktopFolderUsageDescription`, `NSDownloadsFolderUsageDescription`, `NSRemovableVolumesUsageDescription`, `NSNetworkVolumesUsageDescription` | `Font Playground reads fonts in folders you add and saves fonts where you choose.` (TOOLING-M3) | new |
| `FPHelpURL` | empty string (the maintainer or WP-602 sets the README URL) | new |
| absent | `NSRequiresAquaSystemAppearance`, `UIDesignRequiresCompatibility`, `LSUIElement` (foundation-release.md WP-601 item 4) | |

There are no entitlements (ADR-0010). `InfoPlist.xcstrings` holds `CFBundleDisplayName`, `CFBundleName` and the five usage descriptions, each with an `en` value equal to Info.plist's. `App/Sources/FontPlaygroundApp.swift` becomes (still **not** `@main`):

```swift
import FPAppUI
import SwiftUI

/// Not `@main`: `Launcher` is the entry point (foundation-release.md WP-001 item 6).
struct FontPlaygroundApp: App {
    @NSApplicationDelegateAdaptor(FPAppDelegate.self) private var delegate
    var body: some Scene {
        Settings { SettingsView(model: delegate.model) }
            .commands { AppCommands(model: delegate.model) }
    }
}
```

`FPAppDelegate.model` is `public let model: AppModel`. Scene-less main window: the app declares only the `Settings` scene, so SwiftUI opens no window at launch, and `FPAppDelegate` creates the main window (D2). Verified for this review with a headless SwiftUI app (macOS 27 SDK, deployment target 14.0, activation policy `.prohibited`): with only a `Settings` scene, `NSApp.windows` is empty after launch, and `NSApplicationDelegateAdaptor` forwards `applicationShouldTerminateAfterLastWindowClosed`, `applicationShouldTerminate` and `applicationShouldHandleReopen` to `FPAppDelegate`.

`Package.swift` edits:

- add `defaultLocalization: "en"`;
- give `FPAppUI` `resources: [.process("Resources")]` and dependencies on `FPMacServices`, `FPEngineClient` and `FPCore`;
- keep the test target `FPAppUITests` (WP-001) depending on `FPAppUI`.

**D2. Main window: an AppKit window hosting SwiftUI (UI-4, CRIT-8, UI-15).** Do not use a SwiftUI `Window` or `WindowGroup` for the main window, for two reasons:

- A single `Window` scene quits the app when the window closes (SwiftUI documentation, checked in the SDK's `.swiftdoc`).
- SwiftUI on macOS 14 cannot veto a close, but the original asks before closing during a build (`app.py:380-388`).

`MainWindowController` (`@MainActor`, an `NSObject` and `NSWindowDelegate`) therefore creates:

- **The hosting controller:** `NSHostingController(rootView: MainWindowView(model:))` with `sizingOptions = [.minSize]` and `sceneBridgingOptions = [.toolbars, .title]` (macOS 14). With these options, SwiftUI toolbar items (the sidebar toggle, the Advanced toggle) appear in the window toolbar.
- **The window:** `NSWindow(contentViewController:)` with:
  - style `.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView`;
  - title "Font Playground" (`shell.window.title`);
  - `contentMinSize = 640×480`;
  - `collectionBehavior.insert(.fullScreenPrimary)`, `tabbingMode = .disallowed`;
  - `isRestorable = false`, `isReleasedWhenClosed = false`, `delegate = self`.
- **The frame:**
  - If `window.setFrameUsingName("FPMainWindow")` fails, set `window.setFrame(MainWindowGeometry.initialFrame(visibleFrame: screen.visibleFrame, chromeHeight: window.frame.height - window.contentLayoutRect.height), display: false)`, where `screen` is `NSScreen.main`. With no screen, use 1280×848 at the origin.
  - Then call `window.setFrameAutosaveName("FPMainWindow")`.
  - AppKit pulls a restored frame that is off-screen back onto the screen when the window is ordered front (UI-4 verifier: `constrainFrameRect(_:to:)`).
- **Closing:** `windowShouldClose(_:)` returns `quit.windowShouldClose()`.

`MainWindowGeometry` is pure:

```swift
public enum MainWindowGeometry {
    public static let minContentSize = CGSize(width: 640, height: 480)
    public static let preferredFrameSize = CGSize(width: 1280, height: 848)
    /// UI-4 verifier: size = min(preferred, 90 % of the visible frame), at least the minimum frame;
    /// centred in the visible frame, rounded down to whole points; if larger than the visible frame,
    /// x = visible.minX and the top edge is kept at visible.maxY (the title bar stays reachable).
    public static func initialFrame(visibleFrame v: CGRect, chromeHeight: CGFloat) -> CGRect
}
```

Algorithm:

1. `w = max(640, min(1280, floor(0.9·v.width)))`
2. `h = max(480 + chromeHeight, min(848, floor(0.9·v.height)))`
3. `x = v.minX + floor((v.width − w) / 2)`, `y = v.minY + floor((v.height − h) / 2)`
4. If `w > v.width`, then `x = v.minX`. If `h > v.height`, then `y = v.maxY − h`.

`FPAppDelegate` is declared `@MainActor public final class FPAppDelegate: NSObject, NSApplicationDelegate`. It must be `@MainActor`, or `AppModel.init` doesn't compile under Swift 6.

| Callback | Behaviour |
|---|---|
| `init()` / `init(services:)` | `public override convenience init() { self.init(services: .live()) }` is what `@NSApplicationDelegateAdaptor` calls. `public init(services: AppServices)` creates `model = AppModel(services:)` and `quit = QuitCoordinator(...)` (live closures below), and creates no window. Tests use `init(services:)` |
| `applicationDidFinishLaunching` | Creates `MainWindowController` and calls `makeKeyAndOrderFront`. WP-503 adds one line here, `model.platformFontLookup = PlatformFontPreferences.lookUp` (ui-editing.md WP-503 touched paths); WP-501 writes no such line. Then runs `Task { await model.start() }` |
| `applicationShouldHandleReopen(_:hasVisibleWindows:)` | If no window is visible, shows the main window again. Returns true |
| `applicationShouldTerminateAfterLastWindowClosed` | `true`: quit-on-close. The UI-15 verifier says this is right for a single-window utility |
| `applicationShouldTerminate` | `quit.shouldTerminate()` |
| `applicationWillTerminate` | `model.prepareForTermination()` |
| `applicationDidBecomeActive` | `model.appDidBecomeActive()`, which clears the Dock badge set by WP-505 |

`--self-test` never reaches `FPAppDelegate`: WP-001's `Launcher` handles it before `NSApplication` exists (foundation-release.md §S6).

The live `QuitCoordinator` closures: `isBuilding = { model.isBuilding }`, `stopBuilding = { await model.build.cancelAndWait() }`, `flush = { model.flushAutosave(); model.flushPreferences() }`, `present = { model.alert = $0 }`, `reply = { NSApp.reply(toApplicationShouldTerminate: $0) }`, `closeWindow = { window.close(); NSApp.terminate(nil) }`. The explicit `terminate` matters when the Settings window is still open: closing the main window alone would not quit then, but the user chose "Quit".

`QuitCoordinator` is pure logic with injected closures:

```swift
@MainActor final class QuitCoordinator {
    init(isBuilding: @escaping () -> Bool, stopBuilding: @escaping () async -> Void,
         flush: @escaping () -> Void, present: @escaping (AlertContent) -> Void,
         reply: @escaping (Bool) -> Void, closeWindow: @escaping () -> Void)
    func shouldTerminate() -> NSApplication.TerminateReply
    func windowShouldClose() -> Bool
}
```

- `shouldTerminate()`:
  - If nothing is building, it calls `flush()` and returns `.terminateLater`. Then it runs `await stopCatalog()` (`model.stopCatalog()`: `await catalog.cancelRefresh()`, which returns once the refresh and its helper have stopped, then `stopObservingSystemChanges()`), then `reply(true)`. So a scan helper never outlives the app; an unstructured task in `applicationWillTerminate` could be dropped before it ran. While this is pending, `shouldTerminate()` returns `.terminateCancel`.
  - Otherwise it presents the quit alert and returns `.terminateLater`. **Quit** runs `await stopBuilding()`, then `flush()`, then `await stopCatalog()`, then `reply(true)`. **Keep Building** runs `reply(false)`.
- `windowShouldClose()`:
  - If nothing is building, it returns true.
  - Otherwise it presents the same alert and returns false. **Quit** runs `await stopBuilding()`, sets an internal `allowClose` flag (so the next `windowShouldClose()` returns true), then calls `closeWindow()`. The app then terminates, and `shouldTerminate()` finds nothing building. **Keep Building** does nothing.
  - While the quit alert is already shown, a second `shouldTerminate()` returns `.terminateCancel` and a second `windowShouldClose()` returns false; neither presents another alert.
- The quit alert (UI-10):
  - title "Your font is still being built. Quit anyway?" (`shell.quit.title`, `app.py:40`);
  - buttons "Quit" (`shell.quit.quit`, default) and "Keep Building" (`shell.quit.keepBuilding`, cancel role).

**D3. Composition and DI (ADR-0006).** `AppModel.init(services:)`:

1. Creates `settings = SettingsStore(defaults: services.defaults, probe: services.fileProbe)`. If `settings.loadIssues` has `.droppedFolder` entries, posts one `settingsIssues` notice listing those paths (CRIT-2; §S4).
2. Calls `services.system.applyAppearance(settings.value.appearance)`. This happens before any window exists, so nothing flashes in the wrong appearance. The original also pushed its palette before creating widgets (`app.py:111-113`).
3. Sets `previewPointSize`, `colourByFont` and `inspectorPresented` from the settings, `increaseContrast` from `services.system`, `renderer = services.renderer`, and `recipe = Recipe()`, `analysis = recipe.analyze()`, `launchPhase = .starting`, `engineStatus = .unknown`. Creates `build` and sets `build.app = self`.
4. Does no file IO beyond `UserDefaults`, starts no scan, and starts no helper.

`AppServices.live(bundle:)` builds `AppPaths.live()`, `UserDefaults.standard`, the live `SystemActions`, `FilePanels` and `LocalFileSystem()`, and the services, using the constructors from their specs:

- **Engine** (helper.md WP-204 §1–2): `EngineClient(configuration: EngineConfiguration(launch: try EngineLaunch.resolve(bundleURL: bundle.bundleURL), temporaryDirectory: paths.helperTemp))`, with `logHandler` writing to `AppLog.engine`. `resolve` prefers the embedded runtime and falls back to `FP_ENGINE_PYTHON`. If it throws, the engine is `UnavailableEngine(error: error)` (`Model/UnavailableEngine.swift`, an `EngineRunning` that keeps the thrown error): its `hello()` throws that error, and `scan`/`forge` return streams that finish by throwing it. The app still starts; `start()` reports it (D4 step 4).
- **Catalog** (mac-services.md WP-401): `CatalogStore(engine: engine, configuration: c)` where `var c = CatalogConfiguration.standard(); c.cacheDirectory = paths.caches`.
- **Renderer**: WP-402's `FontRenderer` production initialiser, as mac-services.md defines it.
- **Installer** (mac-services.md WP-403 §8): `FontInstaller(fontsFolder: paths.userFonts, manifestURL: paths.installedManifest)`.
- `writeFile` is `{ try AtomicFile.write($0, to: $1.path) }`; `sweepHelperLeftovers` calls `EngineClient.sweepLeftovers`.
- `helpURL` is `bundle.url(forResource: "UserGuide", withExtension: "html")`, else `URL(string:)` of a non-empty `FPHelpURL`, else nil.
- `acknowledgements` is the UTF-8 contents of `bundle.url(forResource: "Acknowledgements", withExtension: "txt")`, or nil.
- `donateURL` is `URL(string:)` of a non-empty `FPDonateURL`, else nil. `bundle.object(forInfoDictionaryKey:)` returns the running language's value: Info.plist and the `en` entry of `App/Resources/InfoPlist.xcstrings` give `https://buymeacoffee.com/kciceblue`, and its `zh-Hans` entry gives Afdian (爱发电), `https://afdian.com/a/kciceblue`. The language only changes at launch (localisation.md D5), so one URL per run is enough.

`EngineErrorText.reason(_ error: any Error) -> String` (`Shared/EngineErrorText.swift`) gives the short reason used by the `engineUnavailable` notice and by WP-505:

| Error | Reason (`ShellText`) |
|---|---|
| `EngineError.helperNotFound` | "its files are missing from the app" (`shell.engine.missing`) |
| `EngineError.launchFailed` | "it couldn't be started" (`shell.engine.launchFailed`) |
| `EngineError.incompatibleHelper(reported:supported:)` | "it's a different version (protocol %1$lld, expected %2$lld)" (`shell.engine.incompatible`) |
| `EngineError.timedOut` | "it didn't answer in time" (`shell.engine.timedOut`) |
| `EngineError.crashed`, `.interrupted`, `.protocolViolation` | "it stopped unexpectedly" (`shell.engine.stopped`) |
| `EngineError.helperFailed(f)` | `f.message` (engine data) |
| `CatalogError.engineUnavailable(s)` | `s` |
| anything else | its `localizedDescription` |

**D4. Launch sequence, restore, autosave, reconcile (`Model/Launch.swift`).** `start()` returns without waiting for the font scan. It runs these steps in order:

1. **Sweep.** Create `paths.helperTemp` and `paths.builds` if missing. Then:
   - `services.sweepHelperLeftovers(paths.helperTemp, [paths.builds], services.now())`: the helper's own leftovers (helper.md H7: dead-pid or > 24 h `fpengine-*` folders and `.fpengine-*.partial.ttf` files).
   - `CacheSweeper.sweepBuilds(paths.builds, olderThan: 600, now: services.now())`: deletes the files **directly** in `builds/` whose name matches `^forged-.*\.ttf$` and whose modification date is more than 10 minutes before `now`. Nothing else is touched (WP-505 D2). A younger file may belong to a second running instance; if that instance later finds its result gone, it simply rebuilds (WP-505 D1 "fresh").
   - Errors are logged with `AppLog.app` and never stop the launch.
2. **Read what to restore.**
   - **(a)** If `lastRecipe` exists, read it and decode it with `RecipeDocument.decode(_:)`. On a read error or any `RecipeDocumentError` (including `.newerVersion`), move the file to `last-damaged-<yyyyMMdd-HHmmss>.fontrecipe` in the same folder (local time, `DateFormatter` with `en_US_POSIX`; add `-2`, `-3`… if the name exists) and post a `damagedRecipe` notice whose `revealURL` is the kept file. The original silently reset instead (`app.py:326-330`). The pending restore is then "nothing".
   - **(b)** Otherwise, if `!settings.value.legacyImportDone` and a folder exists at `paths.legacyFolder`:
     - Read `settings.json` from it, if present, and import it right away with `LegacyImport.settings(from:probe:)`. Apply the result with `settings.update` (appearance, extra folders, preview size, colour by font), call `system.applyAppearance`, and copy `previewPointSize` and `colourByFont` into the model. Post a `settingsIssues` notice naming `report.droppedFolders`, if any.
     - Read `forge_last.json`, if present, and keep its bytes as the pending legacy recipe.
     - Set `legacyImportDone = true` right away, whatever happens (core.md WP-305 §4).
     - If `settings.json` exists but could not be read, or its report says `readable == false`, post `importFailed`.
   - **(c)** Otherwise there is nothing to restore.
3. **Loading fonts.** Set `launchPhase = .loadingFonts`.
4. **Engine check.** Start `hello()` in a child `Task`. Success gives `engineStatus = .available(hello)`. Failure gives `.unavailable(EngineErrorText.reason(error))` and an `engineUnavailable` notice.
5. **Catalog.** Start the observation `Task`: `for await snapshot in await services.catalog.snapshots() { apply(snapshot) }`, where `apply` sets `catalogFaces` and `catalogStatus` (§S3 mapping) and, once `launchPhase == .ready`, reconciles every new completed refresh (step 7). Then start the launch `Task`:
   ```swift
   let folders = settings.value.extraFolders.map { URL(fileURLWithPath: $0) }
   let first: CatalogSnapshot?
   await services.catalog.setExtraFolders(folders)                       // stores only (mac-services.md WP-401 §2)
   do { first = try await services.catalog.refresh(.incremental) }       // the first incremental refresh
   catch { first = nil; /* engineUnavailable notice with EngineErrorText.reason(error) */ }
   let snapshot: CatalogSnapshot
   if let first { snapshot = first } else { snapshot = await services.catalog.currentSnapshot() }   // may hold cached faces
   await firstRefreshFinished(snapshot, refreshFailed: first == nil)
   await services.catalog.startObservingSystemChanges()                 // CATALOG-6: installs by Font Book etc.
   ```
   `start()` returns after starting both tasks and the hello task; it never awaits them.
6. **Restore, in `firstRefreshFinished(_ snapshot:refreshFailed:)`:**
   - Apply the snapshot to the seams, and remember its `generation` as handled.
   - Build `FaceCatalog(catalogFaces)`.
   - For a document: `(recipe, report) = document.makeRecipe(catalog:)`. For a legacy recipe: `(recipe, legacy) = LegacyImport.recipe(fromForgeLast:catalog:probe:)` and `report = legacy.load`; when `legacy.lastSaveDirectory` is set, store it with `settings.update`; when `legacy.readable` is false, post `importFailed` and keep the empty recipe.
   - If `report.unresolved` is not empty **and** `refreshFailed` is false, post an `unresolvedFonts` notice (§S7 text and replacements; CRIT-2, CRIT-3). When the refresh failed, the `engineUnavailable` notice already explains, and the placeholders are recovered by a later reconcile. Unresolved materials stay in the recipe as placeholders (core.md WP-305), so nothing is dropped.
   - After a successful legacy import, post `imported`.
   - Set `launchPhase = .ready`. A restore also counts as a change, so the recipe is autosaved in the new format.
7. **Reconcile.** Every completed-refresh snapshot whose `generation` is newer than the last handled one (a rescan, a folder change, `noteInstalled`/`noteRemoved`, or a system change seen by WP-401's observer) runs `let r = recipe.reconcile(with: FaceCatalog(catalogFaces))` through a direct write to `recipe` (core.md WP-303 §6). When `r.nowMissing` or `r.recovered` is non-empty, the `fontsUnavailable` notice is rebuilt from **every** material that is unavailable now, not only this refresh's change. It is posted when something went missing, or updated when it is still shown. It is removed when nothing is missing any more (`unavailableNoticeListsEveryFontMissingNow`). `relocated` needs no notice (CATALOG-7). While `isBuilding`, the reconcile is deferred: `isBuilding`'s `didSet` runs it once when `isBuilding` becomes false.

**Autosave.** From `launchPhase == .ready` on, every change to `recipe` schedules a write 0.5 s later, and a new change restarts that delay (the pending `Task` is cancelled and replaced). The original used 300 ms (`app.py:143-146`). `flushAutosave()` cancels the pending task and writes at once if a write was pending. The write is `services.writeFile(try RecipeDocument(recipe: recipe).encoded(), paths.lastRecipe)` (AtomicFile, AGENTS.md rule 8). Before `.ready` nothing is written, so a quit during the scan leaves the stored file untouched (`app.py:394-395`). A failed write posts one `autosaveFailed` notice per session, filled with the error's `localizedDescription`. The preview preferences are saved separately (§S4, 0.3 s, `flushPreferences()`).

`prepareForTermination()` does three things:
- cancels the observation, launch and hello tasks. A scan helper that is still running gets SIGTERM from the client's stream termination, and in any case stops within about 1 s through its orphan watchdog (helper.md H6);
- calls `flushAutosave()` and `flushPreferences()`;
- calls `build.discardResultFiles()`.

**D5. Main window layout.** `MainWindowView`:

```
NavigationSplitView(columnVisibility: $model.sidebarVisibility)
 ├─ sidebar: SidebarView(model:)                 (width min 260 / ideal 280 / max 420)
 └─ detail: VStack(spacing: 0) { NoticeStack(model:); PreviewPane(model:) }   (minWidth 360)
        .safeAreaInset(edge: .bottom) { ActionBarView(model:) }
        .inspector(isPresented: $model.inspectorPresented) { AdvancedInspectorView(model:) }   (260/300/420)
        .toolbar { IconButton(symbol: "sidebar.trailing", label: Show/Hide Advanced) { model.toggleAdvanced() } }
 .dropDestination(for: URL.self) { urls, _ in model.handleDrop(urls) }
 .alert(…model.alert…)  .sheet(item: $model.sheet)
```

The placeholder bodies of the stubs are `Color.clear` at the minimum sizes above, which is enough to check the layout.

**How the sizes work together.**
- The window minimum (640) equals the sidebar minimum (260) plus the detail minimum (360) plus 20 pt of dividers. WP-507 measures a 640 × 463 native floor with the initial 280-pt sidebar and complete licence/missing-character notes; 640 × 480 is the tested minimum content size. The action-bar safe-area inset declares its 360-pt minimum itself, so a zero-width minimum-size probe cannot wrap its paragraphs into an excessively tall window.
- ⌃⌘S collapses the sidebar. `MainWindowController` supplies the actual content width to `AppModel`; opening Advanced below the 940-pt combined sidebar/detail/inspector width collapses the sidebar. `AppModel.presentAdvanced()` then hands the presentation to `MainWindowController`, which runs it on the next main-queue turn and holds the window frame while it happens, widening only to the 660-pt minimum if the window is narrower (*WP-701 finding H*). Presenting in the same update as the collapse left the inspector collapsed until an unrelated update. Uncollapsing also restores the inspector's stale 580-pt width, and when the preview can't give that up, AppKit widened a half-screen window to 1257 pt. Toggling again before the presentation runs cancels it. Wider windows retain the sidebar. Attach `.inspector` to the detail content, not around `NavigationSplitView`: wrapping the entire split causes the hosting minimum to count the inspector width twice on macOS 27. The detail wrapper explicitly reports a 360-pt minimum while closed and 660 pt while open, preventing the collapsed inspector from reserving its ideal width. The root wrapper reports a 640/660-pt minimum, so initial sidebar measurements cannot enlarge a restored window with Advanced already open. With the sidebar collapsed and the inspector at its 300-pt ideal width, the measured native minimum is 660 pt, fitting a 676-pt half-screen window. Hiding the inspector allows a 640-pt-wide window again.
- While the picker is open, `SidebarView` shows it (ui-editing.md). The picker shows the scan progress ("Looking for fonts…", WP-503).

**D6. Routes behind the menu (§S6) and buttons.**

| Route | Behaviour |
|---|---|
| `startOver()` | If `recipe.materials.isEmpty` and nothing is building, does nothing. Otherwise presents an alert (see "The Start Over alert" below). On confirm: `build.reset()`, `pickRequest = nil`, `trial = nil`, `recipe.reset()` (keeps the sample text; `model.py:452-477`) |
| `addFontFolder()` | `panels.chooseFolders(FolderPanelRequest(prompt: "Add Folder", message: "Choose folders that contain fonts. The fonts don't need to be installed."))` (`shell.folders.prompt`, `shell.folders.message`), then `addFontFolders(_:)` |
| `addFontFolders(_:)` | Runs each URL's path through `FolderCheck.check(_:using: services.fileProbe)`. Accepted paths (`Accepted.path`, standardised) are appended in order, skipping ones already stored. Rejected paths are named in one `settingsIssues` notice (no silent drops). If anything was added: `settings.update`, then `Task { await catalog.setExtraFolders(all folders as URLs); try await catalog.refresh(.incremental) }` (§S3); an error posts `engineUnavailable` |
| `removeFontFolder(_ path: String)` | Removes the folder, `settings.update`, then `setExtraFolders` as above. Materials from that folder become unavailable through the reconcile of the resulting snapshot, with a `fontsUnavailable` notice |
| `rescanFonts()` | `Task { try await catalog.refresh(.full) }`; an error posts `engineUnavailable`. The original's Rescan ignored the cache (`app.py:201-202`). The reconcile runs from the snapshot stream (D4 step 7) |
| `toggleAdvanced()` / `showAdvanced()` | Flips, or sets, `inspectorPresented` |
| `setAppearance(_ a: AppSettings.Appearance)` | `settings.update { $0.appearance = a }`, then `system.applyAppearance(a)` (the Settings picker's binding calls it) |
| `showAbout()` | `system.showAboutPanel(credits: AboutCredits.make(acknowledgements:engine:))` |
| `openHelp()` | `system.openURL(helpURL)` |
| `openDonation()` | `system.openURL(donateURL)`; does nothing when it is nil (D8) |
| `showSettingsFolderInFinder()` | Creates `paths.applicationSupport` if missing, then `system.reveal([paths.applicationSupport])`. Finder shows the folder selected in its parent (UI-11) |
| `getMoreFonts()` | `system.openFontBook()` (ADR-0007; in-app downloads are WP-404 and B-7) |
| `handleDrop(_ urls: [URL]) -> Bool` | Only `file:` URLs count. `services.fileProbe.kind(of: url.path) == .directory` → collected and passed to one `addFontFolders(_:)` call. A `.file` whose extension is ttf, otf, ttc, otc or dfont (any case) → one `fileDropped` notice per drop, however many such files. Everything else is ignored (it isn't something the app could use). Returns true when a folder or a font file was handled (UI-15). While building, folders are still added (they don't change the recipe) |
| `appDidBecomeActive()` | `system.setDockBadge(nil)` |
| system event `.displayOptionsChanged` | `increaseContrast = system.increaseContrast` (an observation `Task` over `system.events`, started in `start()`) |
| system event `.didBecomeActive` | `appDidBecomeActive()` (the delegate's `applicationDidBecomeActive` calls it too; calling it twice is harmless) |
| `applyReplacement(_ r: AppNotice.Replacement)` | §S7 |

**The Start Over alert.**
- Title: "Start over?" (`shell.startOver.title`).
- Message: "This clears your fonts and names. Your sample text stays, and fonts you saved or installed are not affected." (`shell.startOver.message`). While a build runs, " The build in progress will stop." is added (`shell.startOver.stopsBuild`).
- Buttons: "Start Over" (default) and "Cancel".
- The original started over without asking. The confirmation is new because there is no undo yet (backlog B-4).

`CommandState` computes the "Enabled when" column of §S6 from `recipe`, `isBuilding`, `pickRequest`, `catalogFaces`, `catalogStatus`, `engineStatus`, `previewPointSize`, `services.helpURL` and `services.donateURL`. Rows 6–10 come from `build.commands`.

**D7. Settings scene.** This covers UI-11 and the parity items "Appearance" and "Show Settings Folder in Finder". `SettingsView` is one `Form` (`.formStyle(.grouped)`), 480 pt wide:

| Row | Control | Strings |
|---|---|---|
| Appearance | A segmented `Picker` whose binding reads `settings.value.appearance` and writes through `model.setAppearance(_:)`, which applies to the whole app, including the Settings window and panels (`NSApp.appearance`) | "Appearance" (`shell.settings.appearance`). Options: "System", "Light", "Dark" (`shell.appearance.system`, `.light`, `.dark`) |
| Extra font folders | A `List(selection:)` of `settings.value.extraFolders`. Each row shows the folder name (last path component), and the path abbreviated with `~` (`ShellText.shortPath(_ path: String, home: String) -> String`: a path that starts with `home + "/"` becomes `"~/"` + the rest; any other path stays as it is; the live `home` is `NSHomeDirectory()`; port of `action_bar.py:77-83`) in secondary text. Below the list: `IconButton("plus", "Add Font Folder")` calls `addFontFolder()`, and `IconButton("minus", "Remove Selected Folder")` calls `removeFontFolder(selected)` (disabled without a selection). The Delete key (`.onDeleteCommand`) does the same. A folder with an entry in `model.folderIssues` shows that text in red (`.foregroundStyle(.red)` plus a `DecorativeSymbol("exclamationmark.triangle.fill")`) instead of the path, for example "Font Playground has no access to “Fonts”." | "Extra font folders" (`shell.settings.folders`). Footer: "Fonts in these folders show up in Font Playground without being installed." (`shell.settings.foldersFooter`) |
| (button) | Calls `showSettingsFolderInFinder()` | "Show Settings Folder in Finder" (`shell.settings.showFolder`) |
| (button) | Calls `getMoreFonts()`. Disabled when `!system.isFontBookAvailable` | "Get More Fonts…" (`shell.settings.getMore`). Footer: "Font Book can download more fonts that come with macOS." (`shell.settings.getMoreFooter`) |

**D8. About, acknowledgements, Help, Donate.** `AboutCredits.make(acknowledgements: String?, engine: EngineHello?) -> String` joins these parts with blank lines:

1. The licence note (ADR-0012): "Font Playground doesn't include or sell any fonts. Fonts you forge keep their sources' licences; Font Playground tells you what it knows about them, but it is up to you to respect them." (`shell.about.licence`)
2. When `engine` is known (`engineStatus == .available(hello)`): "Font engine: fpengine %1$@, fontTools %2$@, Python %3$@" (`shell.about.engine`), filled with `fpengineVersion`, `fonttools` and `python`.
3. When there is acknowledgements text: "Acknowledgements" (`shell.about.acknowledgements`), followed by that text.

The live `showAboutPanel` turns the credits into an `NSAttributedString` with `NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)` and `NSColor.labelColor`, and calls `NSApp.orderFrontStandardAboutPanel(options: [.credits: …])`. The name, version and copyright come from Info.plist. The standard panel scrolls long credits.

`App/Resources/Acknowledgements.txt` starts with this app's MIT notice and lists the bundled components by name and licence:
- CPython: PSF License;
- fontTools: MIT;
- skia-pathops: BSD-3-Clause;
- unicodedata2: Apache-2.0.

This committed file is only the curated introduction. At build time WP-601's licence phase appends every licence text to the bundled copy, and WP-602 completes the introduction (foundation-release.md §S5; TOOLING-11).

**Donate** (decisions.md D33). Donations go through a web page, `services.donateURL`, never In-App Purchase: StoreKit needs a Mac App Store build, which ADR-0010 rules out. The page follows the interface language: Buy Me a Coffee in English, Afdian in Simplified Chinese (see `AppServices.live(bundle:)` above). Two ways in:

- **Font Playground › Donate…** (§S6 row 1a) calls `openDonation()`. It is disabled when `donateURL` is nil.
- **The one-time offer.** `firstRefreshFinished` calls `offerDonationOnce()` right after `setLaunchPhase(.ready)`, so the offer comes once the window is usable. It does nothing when `donateURL` is nil, when `settings.donationOffered` is true, or when `alert` is already set (it never replaces another alert; the next launch tries again). Otherwise it sets `donationOffered = true` first, then presents `alert`:
  - title "Support Font Playground" (`shell.donate.title`);
  - message "Font Playground is free. If you find it useful, you can buy me a coffee to support its development. You won't see this message again, but Font Playground › Donate… is always there." (`shell.donate.message`);
  - buttons "Buy Me a Coffee" (`shell.donate.confirm`, default; calls `openDonation()`) and "No Thanks" (`shell.donate.decline`, cancel).

  The flag is keyed on the user, not the version, so people updating from 1.0 see the offer once too. `DonationTests` covers the offer, the deferral, the flag's Bool-only read and the menu route.

**D9. Windows-only features removed.** The macOS app has none of these:
- the Theme menu (Settings has Appearance instead);
- the `⋯` button;
- "Open settings folder" (replaced by Show Settings Folder in Finder);
- the "Save…" fallback;
- the Segoe UI font override (`app.py:409-410`).

### Acceptance criteria

**Bundle and settings**
- **AC-501-1** `make app` succeeds (macOS 14+, Xcode 26+, xcodegen) and produces `build/DerivedData/Build/Products/Debug/Font Playground.app` (foundation-release.md §S2). `plutil -extract CFBundleName raw` and `plutil -extract LSApplicationCategoryType raw` on its `Contents/Info.plist` print `Font Playground` and `public.app-category.graphics-design`. (UI-3)
- **AC-501-2** `AppBundleTests.ui3InfoPlistNamesTheApp` finds the repository root five `deletingLastPathComponent()` calls up from `#filePath`, reads the committed `App/Info.plist` with `PropertyListSerialization` and `App/project.yml` as text, and asserts:
  - every Info.plist key and value of the D1 table (the build-setting placeholders literally, for example `$(PRODUCT_BUNDLE_IDENTIFIER)`), and that the "absent" keys are absent;
  - `project.yml` contains the lines `PRODUCT_NAME: "Font Playground"`, `PRODUCT_BUNDLE_IDENTIFIER: io.github.kciceblue.fontplayground`, `MACOSX_DEPLOYMENT_TARGET: "14.0"`, `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` and `- path: Resources` (whitespace-insensitive line match), and no `CODE_SIGN_ENTITLEMENTS`;
  - no `*.entitlements` file exists under `App/`;
  - `App/Sources/FontPlaygroundApp.swift` contains `NSApplicationDelegateAdaptor(FPAppDelegate.self)` and does not contain `@main`;
  - `App/Resources/InfoPlist.xcstrings` has an `en` value for `CFBundleName`, `CFBundleDisplayName` and the five usage descriptions, equal to Info.plist's. (UI-3, TOOLING-M3)
- **AC-501-3** `SettingsStoreTests.invalidValuesFallBackToDefaults` (port of `test_preference_helpers_fall_back_to_defaults`):
  - An empty suite reads the §S4 defaults.
  - `appearance = "sepia"` reads `.system`; `previewPointSize = 400` or `true` reads 30; `colourByFont = "yes"` or `1` (an Int) reads false.
  - `"dark"`, 40 and `true` read back as stored.
  - A stored folder `"D:/Fonts"` is dropped, the suite no longer holds it after `init`, and `AppModel.init` posts exactly one `settingsIssues` notice whose text contains `“D:/Fonts”`. A stored `lastSaveDirectory` that does not exist becomes nil and posts nothing. (CRIT-2)
- **AC-501-4** `SettingsStoreTests.appearanceAppliesAtInitAndOnChange`:
  - With `"dark"` stored, `AppModel.init` makes exactly one `applyAppearance(.dark)` call, during `init`.
  - `setAppearance(.light)` calls `applyAppearance(.light)` and stores `"light"`.
  - `previewPointSize = 44` and `colourByFont = true` on the model are in the suite after `flushPreferences()`, and a new `AppModel` on the same suite starts with them. This ports `test_theme_choice_retints_every_part_and_persists` and `test_preview_preferences_persist`.

**Seams**
- **AC-501-5** `EditingSeamsTests.seamsHaveTheirDefaults`:
  - `AppModel(services: .testing(…))` starts with `recipe.materials.isEmpty`, `catalogFaces == []`, `catalogStatus == CatalogStatus()`, `isBuilding == false`, `pickRequest`, `trial` and `builtFont` all nil, `previewPointSize == 30`, `colourByFont == false`, and `renderer` being the injected fake (`===`).
  - `openPicker(PickRequest(languageID: "korean"))` sets `pickRequest`. Setting `isBuilding = true` clears `pickRequest` and `trial`. `openPicker` while building leaves `pickRequest` nil.
  - `zoomPreviewIn()` from 30 gives 36, `zoomPreviewOut()` from 30 gives 24, `resetPreviewZoom()` gives 30; in from 96 stays 96 and out from 10 stays 10. `applySample(id: "unknown")` changes nothing.
  - `Editing/EditingShared.swift` compiles, and `MixPalette.colour(forMaterialAt: 4) == MixPalette.colour(forMaterialAt: 0)`.

**Launch, restore and reconcile**
- **AC-501-6** `LaunchTests.startReturnsBeforeTheScanFinishes`: with a `ShellFakeCatalog` whose `refresh` is still suspended, `await model.start()` returns with `launchPhase == .loadingFonts`. `hello()` was called once, `setExtraFolders([])` was called once before `refresh(.incremental)`, which was requested once (and `.full` never), `startObservingSystemChanges` has not been called yet, and `last.fontrecipe` has not been written.
- **AC-501-7** `LaunchTests.sweepRemovesOnlyOldResults`: with `now` fixed, after `start()`:
  - `builds/forged-a.ttf` dated 11 minutes before `now` is deleted; `builds/forged-b.ttf` dated 5 minutes before is kept; `builds/keep.ttf` dated 11 minutes before and a file outside `builds/` are kept;
  - `sweepHelperLeftovers` was called once with `(paths.helperTemp, [paths.builds], now)`;
  - both folders exist.
- **AC-501-8** `RestoreTests.recipeIsRestoredAfterTheFirstRefresh` (port of `test_the_recipe_is_restored_after_the_scan`):
  - Setup: a stored `last.fontrecipe` has 2 materials, a pin `han` on the second, and the sample "mine 你好".
  - After `finishRefresh(with:)` with a snapshot holding both faces, the recipe has both materials in order, the pin and the sample, `launchPhase == .ready`, no notice is posted, and `startObservingSystemChanges` was called once.
- **AC-501-9** `RestoreTests.crit2UnresolvedFontsStayAndAreReported`:
  - Setup: a stored recipe names "Microsoft YaHei" (PostScript `MicrosoftYaHei`) and "Georgia". The catalog has Georgia (at another path, same PostScript name) and PingFang SC.
  - Georgia resolves.
  - "Microsoft YaHei" stays as a placeholder with `availability == .notFound`.
  - One `unresolvedFonts` notice has the text "1 font could not be found: Microsoft YaHei Regular. Microsoft YaHei Regular isn't on this Mac. Use PingFang SC Regular instead?" and one `Replacement`.
  - `applyReplacement(thatReplacement)` puts PingFang SC Regular in the placeholder's position, and the notice is gone. (CRIT-2, CRIT-3; this uses the FPCore tables.)
  - `refreshFailedSuppressesTheUnresolvedNotice`: the same setup with `failRefresh(CatalogError.engineUnavailable("x"))` still restores both materials (as placeholders where unresolved), posts `engineUnavailable`, and posts no `unresolvedFonts` notice.
- **AC-501-10** `RestoreTests.quitBeforeRestoreKeepsTheStoredRecipe` (port of `test_closing_during_a_scan_keeps_the_stored_recipe`): `prepareForTermination()` during `.loadingFonts` leaves `last.fontrecipe` byte-for-byte unchanged, and the `ShellFileWriter` recorded no write.
- **AC-501-11** `RestoreTests.damagedRecipeIsKeptAndReported` (port of `test_malformed_settings_do_not_break_startup`):
  - Setup: `last.fontrecipe` contains `{"materials": "nope"`, and the suite holds values of the wrong type.
  - After the first refresh, the app has an empty recipe and `launchPhase == .ready`.
  - `last.fontrecipe` is gone and exactly one file matches `last-damaged-\d{8}-\d{6}\.fontrecipe` with the original bytes; a `damagedRecipe` notice's `revealURL` points at it.
- **AC-501-12** `RestoreTests.autosaveIsDebouncedAndAtomic`:
  - After `.ready`, three `edit` calls in a row followed by `flushAutosave()` produce exactly one write of `last.fontrecipe` (`ShellFileWriter` count), and a later `flushAutosave()` with nothing pending writes nothing.
  - The file decodes (`RecipeDocument.decode`) to a document equal to `RecipeDocument(recipe: model.recipe)`, and no `.*.tmp` file remains in the folder.
  - A sample-text change also schedules a write.
  - With `ShellFileWriter.error` set, two failed writes post exactly one `autosaveFailed` notice.
- **AC-501-13** `RestoreTests.legacyImportRunsOnce`:
  - Setup: no `last.fontrecipe`. The legacy folder under the temporary root holds core.md AC-305-12's `forge_last.json` and `settings.json` `{"theme": "dark", "extra_dirs": ["D:/Fonts"]}`. The catalog has Georgia and Songti SC.
  - The first launch applies `.dark`, posts `settingsIssues` naming "D:/Fonts", sets `legacyImportDone` before the first refresh ends, imports the recipe after it (Georgia, and a SimSun placeholder with a "Use Songti SC Regular" replacement), and posts `imported`.
  - A second `AppModel` on the same suite and root, with `last.fontrecipe` removed, imports nothing and posts neither notice.
  - `unreadableLegacySettingsReportImportFailed`: `settings.json` containing `nope` posts `importFailed` and still sets `legacyImportDone`.
- **AC-501-14** `ReconcileFlowTests.rescanKeepsTheRecipe` (port of `test_rescan_keeps_the_recipe`): `rescanFonts()` records `refresh(.full)`. After it completes with the same faces (a new generation), the recipe is unchanged and no notice is posted.
- **AC-501-15** `ReconcileFlowTests.catalog7MovedAssetKeepsTheMaterial`: a published completed snapshot in which a material's face has a new path but the same PostScript name relocates the material. There is no notice.
- **AC-501-16** `ReconcileFlowTests.vanishedFontIsKeptAndReported`: after a completed snapshot without a material's face, the material is still in the recipe with `availability == .fileGone`, and a `fontsUnavailable` notice names it. `whileBuildingReconcileWaits`: with `isBuilding = true`, the same snapshot changes nothing; setting `isBuilding = false` runs the reconcile once. A snapshot with `isComplete == false` never reconciles. (CATALOG-7, no silent drops)

**Commands and menus**
- **AC-501-17** `StartOverTests.startOverAsksThenClears` (port of `test_start_over_clears_the_recipe`):
  - With one material and `pickRequest` set, `startOver()` presents an alert titled "Start over?" with the buttons ["Start Over", "Cancel"].
  - Cancel changes nothing.
  - "Start Over" empties the materials, keeps the sample text, clears `pickRequest` and `trial`, and calls `build.reset()`.
  - With an empty recipe and nothing building, `commandState.canStartOver == false`.
- **AC-501-18** `MenuCommandTests.ui2MenuBarHasEveryCommand`: `MenuCommand.allCases` matches §S6 rows 1, 1a and 3–21 exactly, in order, with rows 16 and 19 expanded from `Samples.presets` and `Languages.all` (the test builds that part of the expected list from the same FPCore tables): menu, default title, shortcut (`KeyboardShortcut` equality: key and modifiers) and placement. `AppCommands.menuOrder == MenuCommand.allCases`. `shortcutsAreUniqueAndAvoidSystemKeys`: no shortcut is shared, none is ⌘H, ⌘Q, ⌘M, ⌘W, ⌘, or ⌘Z, and Install (row 7) has none. (UI-2, UI-6)
- **AC-501-19** `CommandStateTests` is a table test that covers every "Enabled when" rule of §S6 over these states:
  - an empty idle recipe; a recipe with a main font;
  - `isBuilding`; `pickRequest` set; `catalogStatus.isScanning`;
  - the engine `.unavailable`;
  - `previewPointSize` of 10, 30 and 96;
  - `helpURL` nil.

  Each state lists the expected `isEnabled` for every row, and rows 6–10 follow a scripted `build.commands`. The titles switch between "Choose Main Font…" and "Change Main Font…", between "Show Advanced" and "Hide Advanced", and row 7 shows `build.commands.installTitle`.

**Window and quitting**
- **AC-501-20** `MainWindowGeometryTests.ui4InitialFrameFitsTheVisibleScreen` (chrome 52) checks:

  | Visible frame | Result |
  |---|---|
  | `(0,85,1352,764)` | `(68,123,1216,687)` |
  | `(0,0,2560,1415)` | `(640,283,1280,848)` |
  | `(0,0,1024,700)` | `(51,35,921,630)` |
  | `(−1440,0,1440,875)` | `(−1360,44,1280,787)` |
  | `(0,0,600,400)` | `(0,−132,640,532)` |

  For every result, the top edge is at most `visible.maxY`. (UI-4)
- **AC-501-21** `MainWindowGeometryTests.crit8MinimumWidthAllowsHalfScreenTiling`: `minContentSize.width ≤ 660`, and sidebar minimum + detail minimum + 20 ≤ `minContentSize.width`. (CRIT-8)
- **AC-501-22** `QuitCoordinatorTests.ui10QuitWhileBuildingAsksWithVerbButtons`: (UI-10)
  - While building, `shouldTerminate()` returns `.terminateLater` and presents "Your font is still being built. Quit anyway?" with the buttons ["Quit", "Keep Building"].
  - "Keep Building" calls only `reply(false)`.
  - "Quit" calls `stopBuilding`, then `flush`, then `stopCatalog`, then `reply(true)`, in that order.
  - When nothing is building, it calls `flush`, returns `.terminateLater`, then calls `stopCatalog` and `reply(true)`.
  - While the alert is shown, a second `shouldTerminate()` returns `.terminateCancel` and presents nothing.
- **AC-501-23** `QuitCoordinatorTests.ui15ClosingTheWindowQuitsAndAsksWhileBuilding`: (UI-15)
  - `FPAppDelegate(services: .testing(…)).applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)` is `true`. This creates no window and uses no live service.
  - While building, `windowShouldClose()` returns false and presents the quit alert. "Quit" stops the build and calls `closeWindow`. After that, `windowShouldClose()` returns true.

**Settings, folders, About and lint**
- **AC-501-24** `SettingsActionsTests.ui11ShowSettingsFolderRevealsIt`: with the Application Support folder missing, `showSettingsFolderInFinder()` creates it and calls `reveal([applicationSupport])`. `getMoreFonts()` calls `openFontBook()`. (UI-11)
- **AC-501-25** `FontFoldersTests.addRemoveAndValidateFolders`:
  - `addFontFolders([a, a/., b, missing])`, where `missing` does not exist in the fake file system, stores `[a, b]`, calls `setExtraFolders([a, b])` once followed by `refresh(.incremental)` once, and posts one `settingsIssues` notice naming `missing`.
  - Adding `[a]` again changes nothing and calls nothing.
  - `removeFontFolder(a)` stores `[b]` and calls `setExtraFolders([b])`, then `refresh(.incremental)`.
- **AC-501-26** `DropTests.ui15DroppingFoldersAddsThem` (the fake file system knows `folder` as a directory and the files as files): `handleDrop([folder, font.ttf, Other.OTF, note.txt])` adds the folder, posts exactly one `fileDropped` notice, and returns true. `handleDrop([note.txt])` returns false and posts nothing. `handleDrop([URL(string: "https://example.com/a.ttf")!])` returns false. (UI-15)
- **AC-501-27** `AboutCreditsTests.creditsCarryTheLicenceNoteAndAcknowledgements`: the credits contain the licence note. They contain the engine line only when `hello` succeeded. They contain the acknowledgements text when it is given.
- **AC-501-28** `ReportTextTests.rendersEverySection`:
  - A report with `fullName` "Test Mix Regular", `postscriptName` "TestMix-Regular", 7 code points, 8 glyphs, `durationSeconds` 2.34, materials `("Fixture A Regular", 5, ["latin"], [])` and `("Fixture B Bold", 2, ["han", "cjk_symbols"], ["Made bolder synthetically (+300)"])`, one licence note `(apple-sla, [1], <the ADR-0012 text>)` and warnings `["w1", "w2"]` renders exactly:
    ```
    Font: Test Mix Regular (PostScript name TestMix-Regular)
    Characters: 7   Glyphs: 8
    Built in 2.3 s

    Fixture A Regular: 5 characters  [Latin]
    Fixture B Bold: 2 characters  [Han, CJK symbols & fullwidth]
        warning: Made bolder synthetically (+300)

    Licence:
      - Bundled with macOS: licensed for use on this Mac only; do not distribute the forged font. (Fixture B Bold)

    Warnings:
      - w1
      - w2
    ```
  - The same report with no warnings, no licence notes and `durationSeconds == nil` ends after the last material line and has no "Built in" line.
  - `ReportText.failure(message: "m", detail: "")` returns `"m"`; with detail `"Traceback…"` it returns `"m\n\nTraceback…"`.
- **AC-501-29** `SourceLintTests` passes rules L5–L7 over FPAppUI. Each rule's positive snippet is detected, and its negative snippet is not.
- **AC-501-30** `make lint` and `make test` pass on macOS, including `make mac-test`. The linux targets still pass.
- **AC-501-31** `NoticeTests.noticesReplaceByKindAndHaveExactTexts`: every §S7 text renders exactly with sample arguments (for example `fontsUnavailable` for two names gives "2 fonts are no longer available: “A Regular”, “B Bold”. They stay in your font, marked as missing, until you replace or remove them."). A second notice of the same kind replaces the first (one notice left, the new text). Dismiss removes it. A notice with `revealURL` offers Show in Finder, which calls `reveal([url])`.
- **AC-501-32** `LaunchTests.engineUnavailableIsReportedNotFatal`: with `services.engine = UnavailableEngine(error: EngineError.helperNotFound(searched: []))` and a catalog whose refresh fails with `CatalogError.engineUnavailable("x")`, `start()` returns, `engineStatus == .unavailable("its files are missing from the app")`, one `engineUnavailable` notice reads "Font Playground can't start its font engine, so it can't list or build fonts: its files are missing from the app" or "…: x" (the later one replaces the earlier), `launchPhase` reaches `.ready`, and Rescan Fonts is disabled. `EngineErrorTextTests.reasonsCoverEveryCase` checks every row of the D3 table.
- **AC-501-33** `LaunchTests.systemEventsAreFollowed`: after `start()`, yielding `.displayOptionsChanged` with `ShellFakeSystemActions.increaseContrast = true` sets `model.increaseContrast`, and yielding `.didBecomeActive` records `setDockBadge(nil)`.
- **AC-501-34** `FontFoldersTests.folderIssuesAreShownNotDropped`: publishing a completed snapshot with `.noAccess(folder: "/x/Fonts")` sets `model.folderIssues["/x/Fonts"]` to that issue's `englishText`; the folder stays in the settings.

**Manual checks**
- **AC-501-M1** (manual, macos) First launch. (UI-4)
  1. Build with `make app`.
  2. Clear any saved frame with `defaults delete io.github.kciceblue.fontplayground "NSWindow Frame FPMainWindow"`. Ignore "not found".
  3. On a display at most 1512 pt wide, start the app with `open --env FP_ENGINE_PYTHON="$PWD/engine/.venv/bin/python" "<the .app make app produced>"`.
  4. Take a screenshot. The window must be centred, and the bottom of the detail column must be fully above the Dock.
  5. Move and resize the window, quit with ⌘Q, and relaunch. A second screenshot must show the same frame.
- **AC-501-M2** (manual, macos) Tiling. (CRIT-8)
  1. On macOS 15+, choose Window › Move & Resize › Left. On macOS 14, hold the green button and choose Tile Window to Left of Screen.
  2. Put Finder on the right half.
  3. Take a screenshot. Both windows must be side by side, with the recipe column and the preview visible and nothing clipped.
  4. Press ⌃⌘S. The recipe column hides, and the preview fills the window.
- **AC-501-M3** (manual, macos) Menu bar. (UI-2, UI-3)
  1. Take a screenshot of each open menu: Font Playground, File, Edit, View, Font, Window, Help.
  2. The menus must match §S6. The app menu reads "About Font Playground", "Settings… ⌘," and "Quit Font Playground ⌘Q". "Enter Full Screen" is in the View menu.
  3. The Dock tooltip and the ⌘Tab switcher show "Font Playground", never "python".
- **AC-501-M4** (manual, macos) Settings. (UI-11)
  1. Press ⌘, to open Settings.
  2. Switch Appearance to Dark, then Light, then System. Each time, the main window and the Settings window change immediately. Take a screenshot of each.
  3. Add a folder with +. The panel appears as a sheet on the Settings window, and its button reads "Add Folder". Remove the folder with −.
  4. Click "Show Settings Folder in Finder". Finder opens with the `io.github.kciceblue.fontplayground` folder selected. Take a screenshot.
- **AC-501-M5** (manual, macos) About. Choose Font Playground › About Font Playground. The panel shows the name, version and copyright, plus scrollable credits that contain the licence note and "Acknowledgements". Take a screenshot.
- **AC-501-M6** (manual, macos) Quit-on-close and folder drops.
  1. With nothing building, close the window with ⌘W. The app quits, and `pgrep -fl fpengine` prints nothing.
  2. Relaunch, and drag a folder of fonts from Finder onto the window. It appears under Settings › Extra font folders.

### Verification
```bash
make lint
make mac-test
make app
plutil -extract CFBundleName raw "build/DerivedData/Build/Products/Debug/Font Playground.app/Contents/Info.plist"   # → Font Playground
make test
```

### Notes for the implementer
- **Verified on the audit Mac** (Xcode 27 SDK, deployment target 14.0, Swift 6 mode):
  - The D1 app struct with `.commands` on the `Settings` scene builds a complete menu bar.
  - `CommandGroup(before: .saveItem)` puts items above Close and Close All. Those two belong to the `.saveItem` group, so never use `replacing: .saveItem`.
  - `CommandMenu("Font")` lands between View and Window.
  - `SidebarCommands()` adds "Show Sidebar ⌃⌘S".
  - An `@Observable` property read in a `Commands` body shows its new enabled state the next time the menu opens.
  - The D2/D5 skeleton (`NSHostingController` + `NavigationSplitView` + `.inspector` + a generic `.alert` + `dropDestination`) typechecks under `-swift-version 6` for macOS 14.
  - Re-checked for this review with a headless app (activation policy `.prohibited`, no window): SwiftUI's default Edit menu has no Find item, so ⌘F (row 11) doesn't clash; the resulting menus were About/Settings…/Services/Hide/Quit, File (Start Over ⌘N, Save a Copy… ⇧⌘S, Close ⌘W, Close All ⌥⌘W), Edit (standard items, then Find Font… ⌘F, AutoFill, Dictation, Emoji & Symbols), View (Bigger ⌘+, Show Sidebar ⌃⌘S), Font, Window, Help (⌘?). "Enter Full Screen" appears in View only once a full-screen-capable window exists.
  - `NSHostingController.sceneBridgingOptions`, `.inspector`, `.selectionDisabled()`, `dropDestination(for: URL.self)`, `onDeleteCommand`, `NSApp.orderFrontStandardAboutPanel(options: [.credits: …])`, `NSApp.requestUserAttention(.informationalRequest)` and `ProcessInfo.beginActivity(options: .userInitiated, reason:)` all typecheck against `arm64-apple-macos14.0` in Swift 6 mode.
- **Don't test VoiceOver through the view tree.** SwiftUI's accessibility tree is not filled in for an offscreen `NSHostingView` (verified: only the root `AXGroup` appears). WP-507 tests the label providers and does a manual VoiceOver pass.
- **macOS 15-only APIs.** `pointerStyle` and `defaultWindowPlacement` need macOS 15+. Neither is needed here.
- **Keep `AppModel.swift` small.** Everything wave 10 adds goes in its own files (§S1). The only exceptions are the stored properties that ui-editing.md lets WP-503/504 add to the declaration.
- **Test hygiene.** Don't register fonts, look fonts up by name, or show windows in tests. `FPAppDelegate` is only created in AC-501-23, and `init(services:)` creates no window.

---

## WP-505: Build & install flow (name, Save a Copy…, Install/Update, progress/cancel, report, conflicts, Finder)

**Goal:** The action bar and `BuildController`. The user names the font; the app builds it through the helper with progress and cancel, installs or updates it in `~/Library/Fonts`, saves a copy through a sheet, explains conflicts and failures in plain macOS words, and hands the built font to the preview.
**Depends on:** WP-501, WP-204, WP-304, WP-403 · **Env:** macos · **Size:** L · **Closes findings:** UI-9, UI-10, UI-M3, UI-M7, UI-M8, INSTALL-13 (Show in Finder part), INSTALL-6

### Scope
- **In:**
  - the full `BuildController`, replacing the §S2 stub, and keeping the `isBuilding` and `builtFont` seams in step;
  - the output lifecycle in `builds/`;
  - stage and error wording;
  - the Name and Style fields and their extra validation;
  - `ActionBarState` and `ActionBarView`;
  - the Save a Copy… sheet;
  - Install and Update, with conflict alerts;
  - Uninstall, Show in Finder, Open in Font Book;
  - the report sheet and the Notes link;
  - licence notes;
  - Dock attention and the process activity;
  - `BuildText`.
- **Out:**
  - conflict detection and the copy into `~/Library/Fonts` (WP-403, `FontInstalling`);
  - drawing the built font (WP-504 reads `builtFont`);
  - the family-name dot rule, which FPCore owns (`RecipeProblem.familyNameStartsWithDot`);
  - Advanced (WP-506).

### Touched paths
- `Packages/FontPlaygroundMacKit/Sources/FPAppUI/Model/BuildController.swift` (replace the stub)
- `…/FPAppUI/Model/BuildState.swift`, `ActionBarState.swift`, `StageText.swift`, `NameValidation.swift`, `ConflictText.swift`, `LicenceNotes.swift`, `BuildOutputs.swift` (new)
- `…/FPAppUI/Shared/EngineErrorText.swift` (edit: add the D8 build texts; `reason(_:)` is WP-501's)
- `…/FPAppUI/Views/ActionBarView.swift` (replace the stub)
- `…/FPAppUI/Shared/BuildText.swift` (new), `…/FPAppUI/Resources/Localizable.xcstrings` (edit)
- `…/Tests/FPAppUITests/BuildControllerTests.swift`, `ActionBarStateTests.swift`, `StageTextTests.swift`, `NameValidationTests.swift`, `ConflictTextTests.swift`, `SaveCopyTests.swift`, `BuildOutputsTests.swift`, `BackgroundAttentionTests.swift`, `LicenceNotesTests.swift`, `FileNameAgreementTests.swift` (new), `Support/ShellFakes.swift` (edit, if a helper is missing)
- `Packages/FontPlaygroundMacKit/Sources/FPMacServices/Install/InstallFileName.swift` (edit, only if `InstallFileName` is not `public`: make it public for AC-505-31)

### Design

**D1. State (port of `build.py:45-52` and `build.py:99-114`).**

```swift
public enum BuildIntent: Equatable, Sendable { case install, save(URL) }
public enum BuildState: Equatable {
    case idle                                               // nothing done yet, or undone (reset, uninstall)
    case building(intent: BuildIntent?, stage: String, fraction: Double, stopping: Bool)
    case installing                                         // new: the installer runs off the main actor
    case saving
    case built                                              // a build with no intent finished (internal build(), tests)
    case installed
    case saved
    case failed(message: String)                            // one line; lastErrorDetail holds the rest
    case cancelled
}
public struct BuildResult: Equatable {                      // at most one at a time
    public let id: UUID
    public let url: URL                                     // builds/forged-<uuid>.ttf
    public let report: ForgeReport
    public let spec: ForgeSpec                              // what it was built from
}
public struct InstalledRecord: Equatable {
    public var font: InstalledFont                          // WP-403's record (fileURL, fullName, postscriptName, …)
    public var resultID: UUID                               // the BuildResult it was installed from
}
```

`BuildController` stores `state`, `result: BuildResult?`, `installed: InstalledRecord?`, `pendingRemoval: InstalledFont?` (an older font of ours that an Update under a new name could not remove yet), `savedURL: URL?`, `notice: String?`, `lastReport`, `lastErrorDetail`, `nameFocusRequest: Int` (incremented by "Change Name"), the running build `Task`, and a `runID: UUID` that identifies the current build (a build that ends after `reset()` carries an old `runID` and is ignored, `build.py:224-229`, `build.py:309-315`).

Derived values:

- `isFresh = result != nil && FileManager.default.fileExists(atPath: result!.url.path) && result!.spec == app.recipe.forgeSpec()`. This is value equality (core.md WP-303 §7), so an edit that is undone makes the result fresh again; a result file swept away by another instance is simply rebuilt (`build.py:235-237`).
- `isStale = result != nil && !isFresh`.
- `isUpdate = installed != nil && (result == nil || !isFresh || installed!.resultID != result!.id || pendingRemoval != nil)` (`build.py:129-134`).
- `isBusy` is true in `.building`, `.installing` and `.saving`. On every change, `app.isBuilding = isBusy`. The seam's `didSet` then closes the picker (`app.py:267-270`), and `AppModel.edit` refuses changes while it is set.
- `shownFile` is `savedURL` when `state == .saved`, else `installed?.font.fileURL`, else `savedURL` (`build.py:136-140`).
- `snapshot: BuildControllerSnapshot` (D7) for the action bar.
- The preview seam:
  - When a result arrives, set `app.builtFont = BuiltFontPreview(url: result.url, displayName: report.fullName, spec: result.spec)`.
  - Set it to nil on `reset()` and `discardResultFiles()`.
  - WP-504 checks `isStale(for:)` itself (ADR-0011, `app.py:274-284`).
- While a build runs, the controller holds `system.beginActivity(reason: "Building a font")` and ends it when the build stops, however it stops. A background build therefore keeps running at full speed.

**Consuming the forge stream.** The build `Task` is created on the main actor:

```swift
let runID = UUID(); self.runID = runID
task = Task { @MainActor in
    var report: ForgeReport?
    do {
        for try await event in services.engine.forge(request) {
            switch event {
            case .progress(let p): progressed(p, runID: runID)
            case .finished(let r): report = r
            }
        }
        if let report { finished(report, runID: runID) }
        else if Task.isCancelled || stopping { cancelled(runID: runID) }      // the client ends the stream normally on cancel
        else { failed(EngineError.protocolViolation("helper exited without a result", stderrTail: ""), runID: runID) }
    } catch is CancellationError { cancelled(runID: runID) }
      catch { if Task.isCancelled || stopping { cancelled(runID: runID) } else { failed(error, runID: runID) } }
}
```

Every handler first returns if `runID != self.runID` (the run belongs to the state before a reset).

**Transitions** (all on the main actor):

| From | Event | To | Effects |
|---|---|---|---|
| not busy | `install()`, guard passes, fresh result | conflict check (D4), then `installing` | D4 |
| not busy | `install()`, guard passes, no fresh result | conflict check (D4), then `building(.install, "Starting…", 0, false)` | D2, then D4 on the result |
| not busy | `saveCopy()`, guard passes, the panel returns URL `u` | `saving` (fresh result) or `building(.save(u), …)` | D5 |
| not busy | `build()` (internal; tests and a later "Build" command) | `building(nil, …)` | D2 |
| `building` | `.progress` | `building` | Updates the stage (D3) and fraction. Ignored while `stopping` |
| `building` | `cancel()` | `building(stopping: true)` with the stage "Stopping…" | Cancels the `Task` (ADR-0003) |
| `building` | stream ended with `.finished(report)` | `built`, or `installing` / `saving` for the intent | Deletes the previous result file, stores the new result, sets `lastReport = report`, `lastErrorDetail = nil` and `builtFont` |
| `building` | stream ended after a cancel (above) | `cancelled` | Deletes the output file if it exists. Clears the intent |
| `building` | stream threw any other error | `failed(message)` | Deletes the output file if it exists and sets `lastErrorDetail` (D8). `lastReport` is unchanged |
| `installing` | the installer returns / throws | `installed` / `failed(…)` or an alert | D4 steps 6–8. After a failure the result stays |
| `saving` | the write succeeds / throws | `saved` / `failed("Couldn't save the font: %@")` | D5 |
| `installed` | `uninstall()` | `idle` with a notice | D9 |
| any | `reset()` (Start Over) | `idle` | Cancels a running build and changes `runID`, so its end is ignored. Deletes the result file and sets `builtFont = nil`. Forgets `installed`, `pendingRemoval`, `savedURL`, `notice`, `lastReport` and `lastErrorDetail` (`build.py:224-229`). Already installed or saved files are **not** touched |

Entering `building`, `installing` or `saving` clears `notice` and the previous failure (`build.py:246-252`).

**D2. Forge request and outputs (`BuildOutputs`).**

- **Output path.** `paths.builds/forged-<UUID().uuidString.lowercased()>.ttf` (contracts §8). `builds/` is created when needed.
- **Request.** `app.recipe.forgeRequest(outputPath:)`. It carries each material's `expect`, so a changed file fails with `stale_material` (contracts §4).
- **Running.** The `services.engine.forge(request)` stream is consumed inside the build `Task` (D1). Cancelling that `Task` is the whole cancel protocol (ADR-0003). `cancel()`, `cancelAndWait()` and `reset()` cancel it from a global dispatch queue, never on the main actor: the engine stream holds the cancelling thread until the helper has exited (helper.md WP-204 step 9), up to about 3 s for a helper that ignores SIGTERM. A superseded run keeps draining its stream until that cancel lands, rather than dropping the stream with the helper still running (review 2026-10-05 M1).
- **Lifecycle.** At most one result file exists.
  - The previous result file is deleted when a new result arrives, on `reset()`, and in `discardResultFiles()` (called at quit).
  - A failed or cancelled build deletes its own output file if it exists.
  - A stale result is kept until one of those events, because an undo can make it fresh again.
  - `BuildOutputs.delete(_ url: URL, builds: URL)` deletes only a file directly inside `builds/` whose name matches `^forged-.*\.ttf$`; for any other URL it does nothing and logs.
- `cancelAndWait()`: cancels the build `Task` if one runs (off the main actor, as above), then awaits `task.value`, but at most 2.8 s (a racing `Task.sleep`, leaving headroom inside the 3 s quit deadline), then deletes the output file. The helper itself exits within about 1 s of SIGTERM (helper.md AC-201-16).

**D3. Stage text (port of `model.py:50-63`; stage values from contracts §5).** `StageText.text(for stage: EngineStage, materialIndex: Int?, materials: [Material]) -> String?` maps each stage to a `BuildText` string; `nil` means "keep the previous text":

| Stage | Text |
|---|---|
| (build started) | "Starting…" (`build.stage.starting`) |
| `validate` | "Checking your fonts…" (`build.stage.validate`) |
| `plan` | "Deciding which font supplies each character…" (`build.stage.plan`) |
| `prepare` with `materialIndex` i in range | "Preparing %@…" (`build.stage.prepare`), with `materials[i].face.displayName` |
| `prepare` without an index, or out of range | "Preparing the fonts…" (`build.stage.prepareAny`) |
| `merge` | "Combining the fonts…" (`build.stage.merge`) |
| `finish` | "Finishing the font…" (`build.stage.finish`) |
| `verify` | "Checking the result…" (`build.stage.verify`) |
| `done` | "Done." (`build.stage.done`) |
| `scan`, or any other | `nil` (the previous text stays) |
| stopping | "Stopping…" (`build.stage.stopping`) |

The status line is "Building your font — %@" (`build.status.building`). The stage text's first letter is lowercased only when its second letter is lowercase (`action_bar.py:91-93`): "Preparing PingFang SC…" becomes "preparing PingFang SC…", and "UI…" stays as it is. `StageText.lowerFirst(_:)` does this on `Character`s.

**D4. Install and Update (port of `action_bar.py:291-303` and `build.py:142-285`; ADR-0009; mac-services.md WP-403).** `install()`:

1. **Guard.** Do nothing unless all hold: not busy, `app.analysis.canForge`, `NameValidation.problem(family:style:)` is nil, and `app.engineStatus` is not `.unavailable` (`build.py:232-233`).
2. **Retry of a pending removal.** If `pendingRemoval != nil`, `isFresh`, and `installed?.resultID == result?.id`, skip to step 7 (remove the old font only; no second install; `test_updating_under_a_new_name_reports_an_old_font_it_could_not_remove`). If the recipe changed or another result was built while a removal was pending, retry that removal before starting a new update. On failure keep it recorded and stop; on success continue with the current recipe. This prevents another renamed update from overwriting the one pending-removal record and silently abandoning an older installed font (`BuildControllerTests.anotherUpdateNeverForgetsAPendingRemoval`).
3. **Conflict check.** `let query = InstallQuery(family: Naming.cleanName(family), style: Naming.cleanName(style), postscriptName: Naming.postscriptName(family: family, style: style))`, where `family`/`style` are `app.recipe.names`. The PostScript name is the one the engine will write (core.md WP-304, engine-metadata.md WP-109), so the check runs **before** building and never makes the user wait for a build that can't be installed. Call `try await installer.conflict(for: query)` (the installer is an actor, so the main thread stays free).
   - `.replaceOurs(f)` where `f.fileURL == installed?.font.fileURL` (this session's own install under the same name) counts as confirmed without asking. This replaces the original's early return at `build.py:153`, which INSTALL-M1 showed to be unsafe: the installer still checks that the file is ours.
   - If the lookup throws, show `failed("Couldn't install the font: %@")` with its `localizedDescription` and stop.
4. **Alert.** `ConflictText.alert(for: conflict, onChangeName:, onConfirm:)` builds the alert (UI-10, INSTALL-13, INSTALL-5). The titles are mac-services.md §S8's English, now as `BuildText` catalog strings:

| `InstallConflict` | Alert title | Message | Buttons |
|---|---|---|---|
| `.block(.systemHas(name))` | "macOS already has a font called “%@” — choose another name." (`build.conflict.system`) | — | "Change Name" (default) |
| `.block(.installedForEveryone(name))` | "A font called “%@” is already installed for everyone on this Mac — choose another name." (`build.conflict.local`) | — | "Change Name" |
| `.block(.youHave(name))` | "You already have a font called “%@” installed — choose another name." (`build.conflict.user`) | — | "Change Name" |
| `.block(.internalNameInUse(ps))` | "Another installed font already uses the internal name “%@” — choose another name." (`build.conflict.postscript`) | — | "Change Name" |
| `.block(.internalNameUsedByYourFont(ps, fullName))` | "Your font “%1$@” already uses the internal name “%2$@” — choose another name." (`build.conflict.ownPostscript`; %1 = fullName, %2 = ps) | — | "Change Name" |
| `.block(.hiddenName)` | "Names that start with “.” are hidden by macOS — choose another name." (`build.conflict.hidden`) | — | "Change Name" |
| `.ask(.appleOffersDownload(name))` | "macOS can download a font called “%@”. Install yours under this name anyway?" (`build.conflict.downloadable`) | "If that font is downloaded later, apps may confuse it with yours." (`build.conflict.downloadableInfo`) | "Install Anyway" (default), "Cancel" |
| `.ask(other reason)` | the reason's title from the `.block` rows | — | "Install Anyway" (default), "Cancel" |
| `.replaceOurs(font)` (not this session's) | "Replace the “%@” you installed earlier?" (`build.conflict.replace`, filled with `font.fullName`) | "The new font takes its place." (`build.conflict.replaceInfo`) | "Replace" (default), "Cancel" |
| `.noConflict` | — | — | — |

   - "Change Name" increments `nameFocusRequest`; `ActionBarView` observes it with `.onChange` and moves `@FocusState` to the Name field. No build and no install starts.
   - "Install Anyway" / "Replace" continue with `confirmed = conflict`. "Cancel" does nothing.
   - A test asserts that each title equals the matching `ConflictReason.englishText` / §S8 text for sample arguments.
5. **Build if needed.** If `isFresh`, go to `installing`. Otherwise build with the intent `.install`, remember `confirmed`, and continue here when the result arrives (`build.py:328-340`).
6. **Install.** In `installing`, call `try await installer.install(result.url, expecting: InstallQuery(family: report.familyName, style: report.styleName, postscriptName: report.postscriptName, fullName: report.fullName), confirmed: confirmed)`. WP-403 validates the file with CoreText, stages it, renames it into place (it picks the file name), and removes our previous copy of the **same** name when `confirmed` is `.replaceOurs`.
   - Success: `let previous = installed`; `installed = InstalledRecord(font: new, resultID: result.id)`; notify `catalog.noteInstalled(new.fileURL)` (INSTALL-6; WP-401). An incremental catalog failure is surfaced as a nonfatal notice, "The font is installed, but Font Playground couldn't refresh its font list: %@" (`build.installedCatalogWarning`); installation still succeeds. If `previous` exists and `previous.font.fullName` differs (case-insensitively) from `new.fullName`, set `pendingRemoval = previous.font` and go to step 7. Otherwise state `installed`.
   - `InstallError.conflict(c)`: the situation changed since step 3 (INSTALL TOCTOU guard). Present step 4's alert for `c`; its confirm button retries step 6 with `confirmed = c`, and "Change Name" / "Cancel" leave the result as it is. While the alert is shown, the state returns to what it was before `install()` (for example `installed` or `idle`).
   - `InstallError.previousCopyNotRemoved(installed: new, previous: old, message:)`: the new font **is** installed. Record it as in "Success", set `pendingRemoval = old`, and fail with the text of step 7.
   - Any other error: `failed("Couldn't install the font: %@")` (`build.error.install`) with `error.localizedDescription` (for `InstallError` that is its `englishText`, mac-services.md §S8). The result stays fresh, so a retry does not rebuild (`test_install_errors_fail_with_a_plain_message`).
7. **Remove the older font after an Update under a new name** (`build.py:274-279`). `try await installer.uninstall(pendingRemoval!)`:
   - `.movedToTrash` or `.notInstalled`: `Task { await catalog.noteRemoved(old.fileURL) }`, `pendingRemoval = nil`, state `installed`.
   - Throws: state `failed("Installed “%1$@”, but couldn't remove “%2$@”: %3$@")` (`build.error.replace`, filled with the new full name, the old full name and `localizedDescription`). `pendingRemoval` stays, so the primary button reads "Update Installed Font" and the next `install()` retries only this step (step 2).

**D5. Save a Copy… (UI-9; `action_bar.py:305-308`, `build.py:192-200`, `build.py:287-297`).**

1. **Guard.** The same as D4 step 1.
2. **Panel.** Present `SaveCopy.request(for: app.recipe, settings: settings.value, paths: paths, probe: fileProbe, licenceLines: …) -> SavePanelRequest` (a pure function in `Model/BuildOutputs.swift`) with `panels.chooseSaveLocation(_:)`, which shows a sheet on the main window:
   - `suggestedFileName`: `recipe.suggestedFileName` (`Naming.fileName`, which strips leading dots, UI-M3);
   - `directory`: `settings.value.lastSaveDirectory` if `fileProbe.kind(of:)` says it is a directory, else `paths.documents`;
   - `message`: the licence lines (D10) joined by newlines, or nil.

   If the result is `nil` (cancelled), do nothing.
3. **Extension safety net.** If the chosen URL's extension is not `ttf` (any case), append `.ttf`. The native panel already enforces it, and the UI-9 verifier found the extra check harmless.
4. **Remember and build.** Store the chosen parent folder with `settings.update { $0.lastSaveDirectory = u.deletingLastPathComponent().path }`. If `isFresh`, go to `saving`. Otherwise build with the intent `.save(u)`, then go to `saving`.
5. **Save.** In `saving`, read the result file (`Data(contentsOf:)`) and call `services.writeFile(data, u)` (AtomicFile: it renames over an existing file; the panel has already asked "Replace?").
   - Success: `savedURL = u`, state `saved`.
   - Failure (reading or writing): `failed("Couldn't save the font: %@")` (`build.error.save`) with the error's `localizedDescription`.

**D6. Name and Style (UI-M3; `action_bar.py:121-122`, `action_bar.py:315-323`).**

- **Fields.** Two `TextField`s bound to `ActionBarView.familyBinding(_ model: AppModel) -> Binding<String>` and `styleBinding(_:)`: `get` reads `model.recipe.names.family` (`.style`), `set` calls `model.edit { $0.setFamily(text, byUser: true) }` (`setStyle`). They are disabled while busy. The Name field has `@FocusState` and takes focus when `build.nameFocusRequest` changes.
- **Labels and placeholders.** Labels: "Name" (`build.field.name`) and "Style" (`build.field.style`). Placeholders: "Name your font" (`build.field.namePlaceholder`) and "Regular" (`build.field.stylePlaceholder`).
- **Validation.** FPCore already raises `familyNameEmpty`, `styleNameEmpty`, `familyNameStartsWithDot`, `familyNameHasControlCharacter` and `styleNameHasControlCharacter` (core.md WP-303 §5). `NameValidation.problem(family:style:) -> String?` adds only the checks FPCore doesn't make. It checks `Naming.cleanName` of each name (the same trimming FPCore uses), and the first rule that matches wins:

| Rule | Text |
|---|---|
| style starts with "." | "A style name can't start with a dot." (`build.style.leadingDot`; macOS hides such names too, UI-M3) |
| family longer than 63 characters (`String.count`, grapheme clusters) | "Use a font name of at most 63 characters." (`build.name.tooLong`) |
| style longer than 63 characters | "Use a style name of at most 63 characters." (`build.style.tooLong`) |

  The 63-character limit is an app rule, not an engine rule: it keeps names usable in font menus and matches the PostScript-name budget (contracts §6). The problem shown is `NameValidation.problem` if there is one. Otherwise it is `EnglishText.problem(analysis.validity!, in: recipe)` when `analysis.validity` is not nil (WP-507 swaps in `ModelText`).

**D7. The action bar (port of `action_bar.py:213-288`).** `ActionBarState.make(problem: String?, engineMissing: Bool, glyphWarning: String?, build: BuildControllerSnapshot, licenceLines: [String], fontBookAvailable: Bool, home: String) -> ActionBarState` is pure. `BuildController.snapshot` supplies `build`; `ActionBarView` passes `engineMissing = (app.engineStatus is .unavailable)`, `licenceLines` from D10, `fontBookAvailable = system.isFontBookAvailable` and `home = NSHomeDirectory()`.

```swift
public struct BuildControllerSnapshot: Equatable {
    public var state: BuildState
    public var isFresh: Bool, isUpdate: Bool
    public var installedFullName: String?     // installed?.font.fullName
    public var savedPath: String?             // savedURL?.path
    public var hasShownFile: Bool             // shownFile != nil
    public var notice: String?
    public var notesCount: Int                // Set(lastReport.warnings + lastReport.licenceNotes.map(\.text)).count, 0 without a report
}
public struct ActionBarState: Equatable {
    public enum Tone: Equatable { case plain, muted, ok, warn, danger }
    public enum LinkKind: Equatable { case showInFinder, openInFontBook, uninstall, notes(Int), details }
    public var status: String; public var tone: Tone
    public var detailLines: [String]
    public var links: [LinkKind]
    public var progress: Double?              // nil hides the bar
    public var showsCancel: Bool; public var cancelEnabled: Bool
    public var showsSaveCopy: Bool; public var saveCopyEnabled: Bool
    public var primaryTitle: String; public var primaryEnabled: Bool; public var primaryIsDone: Bool
    public var namesEditable: Bool
}
```

The status follows this priority order (all texts come from `BuildText`):

| Condition | Status | Tone | Detail lines | Links |
|---|---|---|---|---|
| `building` | "Building your font — {stage}" | plain | — | — (progress = fraction; Cancel shown, enabled unless stopping) |
| `installing` | "Installing your font…" (`build.status.installing`) | plain | — | — |
| `saving` | "Saving your font…" (`build.status.saving`) | plain | — | — |
| `engineMissing` | "Font Playground can't find its font engine. Reinstall the app." (`build.error.engineMissing`) | danger | — | — |
| problem ≠ nil | the problem | danger | — | — |
| notice is "That file is no longer there." | that notice (D9; must remain visible after a successful install or save) | muted | — | — |
| `installed` | "Installed as “%@”." (`build.status.installed`, filled with `installedFullName`) | ok | "Choose it in any app's font list — apps that were already open may need to be reopened." (`build.detail.installed`), plus the licence lines | Show in Finder, Uninstall, Notes(n) if n > 0 |
| `saved` and `isFresh` | "Saved to %@" (`build.status.saved`; `ShellText.shortPath(savedPath, home:)`, middle truncation in the view, the full path in `.help`) | ok | licence lines | Show in Finder, Open in Font Book (when available), Notes(n) if n > 0 |
| `failed` | its message | danger | — | Details |
| `cancelled` | "Cancelled." (`build.status.cancelled`) | muted | — | — |
| notice ≠ nil | the notice | muted | — | — |
| glyph warning ≠ nil | `EnglishText.glyphWarning(…)` | warn | licence lines | — |
| otherwise | "Installs in your Fonts folder — only for you, no password needed." (`build.status.idle`) | muted | licence lines | — |

- **Notes count.** `n = notesCount`. The link is left out when `n == 0` (`test_no_notes_link_without_warnings`).
- **Show in Finder** is listed only when `hasShownFile`. **Open in Font Book** only when `fontBookAvailable`.
- **Link titles.** "Notes (%lld)", "Show in Finder", "Open in Font Book", "Uninstall", "Details" (`build.link.*`).

The primary button (port of `action_bar.py:277-288`):

| Condition | Title | Enabled | Done look |
|---|---|---|---|
| building with intent install / save / none | "Installing…" / "Saving…" / "Building…" (`build.button.installing` / `.saving` / `.building`) | no | no |
| installing / saving | "Installing…" / "Saving…" | no | no |
| `engineMissing` | "Install" | no | no |
| `installedFullName != nil` and `isUpdate` | "Update Installed Font" (`build.button.update`) | when there is no problem | no |
| `installedFullName != nil` and not `isUpdate` | "Installed" (`build.button.installed`) | no | yes (a decorative checkmark symbol) |
| otherwise | "Install" (`build.button.install`) | when there is no problem | no |

Other parts of the bar:

- **Save a Copy… button** (`build.button.saveCopy`). Shown when not busy. Enabled when there is no problem and the engine is not missing.
- **Name fields.** `namesEditable = !busy`.
- **Tone icons** (`DecorativeSymbol`): ok `checkmark.circle.fill`, warn `exclamationmark.triangle.fill`, danger `xmark.octagon.fill`. The text uses the label colour, so the meaning never rests on colour alone.

`BuildCommands` for the menu is derived from the same values:

- `canSaveCopy` and `canInstall` follow the two buttons;
- `installTitle` is "Update Installed Font" when `isUpdate`, else "Install";
- `canShowInFinder = shownFile != nil`;
- `canOpenInFontBook = state == .saved && isFresh && fontBookAvailable`;
- `canUninstall = installed != nil && !isBusy`.

**`ActionBarView` layout.** It uses `ViewThatFits(in: .horizontal)` with three variants, so nothing is clipped at the 360-pt detail minimum (CRIT-8):

- **Wide** (≥ about 700 pt): `[Name field 200…260][Style field 90…120] [status column] [Cancel][Save a Copy…][Primary ≥ 140]`.
- **Two rows:** the fields first, then the status column and the buttons.
- **Compact:** like two rows, with "Save a Copy…" hidden. It stays in the File menu (⇧⌘S). The primary button shrinks to its title, and the status wraps (up to three lines; a saved path stays on one line, truncated in the middle, with the full path as help), so nothing is cut at half-screen width (*WP-701 finding A*).

**Parts of the bar.**
- **Status column.** The status line (icon and text, one line, tail truncation, the full text in `.help`). Below it, either the `ProgressView(value:)` while busy, or the detail lines and links (`.buttonStyle(.link)`).
- **Primary button.** `.borderedProminent` and `.controlSize(.large)`. `ActionBarView.primaryShortcut` is `nil`, so the button has no shortcut (§S6).
- **Cancel button.** Uses `ActionBarView.cancelShortcut = .cancelAction`, so Esc and ⌘. both trigger it.
- **Bar.** Padding is 12 pt vertical and 16 pt horizontal. The bar sits on `.bar` material with a top divider.

**D8. Engine errors (`EngineErrorText.buildFailure(_ error: any Error, materials: [Material]) -> (message: String, detail: String)`).** These are the errors the forge stream throws (helper.md WP-204; contracts §5):

| Error | `message` | `detail` |
|---|---|---|
| `EngineError.helperFailed(f)` with `f.code == .staleMaterial` | "“%@” changed since Font Playground last read it. Choose File › Rescan Fonts, then try again." (`build.error.staleMaterial`), with `materials[f.materialIndex].face.displayName`. When the index is nil or out of range: "A font changed since Font Playground last read it. Choose File › Rescan Fonts, then try again." (`build.error.staleMaterialUnknown`) | `f.detail ?? ""` |
| `EngineError.helperFailed(f)`, any other code | "Couldn't build the font: %@" (`build.error.build`), filled with the first line of `f.message` (engine wording) | `f.message` + blank line + `f.detail` |
| `.crashed`, `.interrupted`, `.protocolViolation` | "Couldn't build the font: %@" filled with "the font engine stopped unexpectedly." (`build.error.engineStopped`) | the error's `stderrTail` |
| `.timedOut` | "Couldn't build the font: %@" filled with "the font engine took too long." (`build.error.timedOut`) | the error's `stderrTail` |
| `.helperNotFound`, `.launchFailed`, `.incompatibleHelper`, anything else | "Couldn't build the font: %@" filled with `EngineErrorText.reason(error)` + "." | `String(describing: error)` |

`lastErrorDetail = ReportText.failure(message: message, detail: detail)`. The detail is only shown through Details. If the engine is `.unavailable`, Install and Save a Copy… are disabled (D7).

**D9. Uninstall, Finder, Font Book, report.**

- **`uninstall()`** (`build.py:209-222`). Does nothing when `installed` is nil or the controller is busy. If `pendingRemoval` exists, first retry removal of that older font through D4 step 7, without a separate success attention request. If it fails, stop and preserve both `installed` and `pendingRemoval` with the visible failure; never forget the older installed font. After it succeeds (or if none was pending), `try await installer.uninstall(installed.font)`. WP-403 moves the file to the Trash (INSTALL-9). `BuildControllerTests.uninstallResolvesThePendingOldFontBeforeTheCurrentFont` covers the failure and successful retry order.
  - `.movedToTrash`: the notice becomes "Removed from your fonts — it's in the Trash." (`build.status.removed`).
  - `.notInstalled`: the notice becomes "That font was no longer installed." (`build.status.notInstalled`).
  - A thrown error (for example `InstallError.notOurs`): `failed("Couldn't remove the font: %@")` (`build.error.remove`) with its `localizedDescription`; `installed` stays.

  After either outcome: `Task { await catalog.noteRemoved(font.fileURL) }`, forget `installed` and `pendingRemoval`, clear the failure, set the state to `idle`. The result stays, so a later Install installs at once without rebuilding.
- **`showInFinder()`.** If `shownFile` exists on disk, calls `system.reveal([shownFile])`, which reveals and selects the file itself (INSTALL-13, UI-11). Otherwise the notice becomes "That file is no longer there." (`build.status.fileGone`), which takes priority over the previous installed/saved success status. A successful reveal clears that notice.
- **`openInFontBook()`.** When `state == .saved`, `isFresh` and `system.isFontBookAvailable`, calls `system.openInFontBook(savedURL)`. Font Book shows its own Install button (UI-M7).
- **`showReport()`** (the Notes and Details links). Sets `app.sheet = .report(text)`, where `text` is `lastErrorDetail` when the state is `.failed`, else `ReportText.render(lastReport)`, else nothing happens. `ReportSheet` (WP-501) shows:
  - the title "Build Report" (`shell.report.title`);
  - the text in a monospaced, selectable scroll view, at least 520×360;
  - the buttons "Copy" (`shell.report.copy`, which calls `system.copyToPasteboard`) and "Done" (`shell.report.done`; default, Esc).

**D10. Licence notes (ADR-0012).** `LicenceNotes.lines(for materials: [FaceRecord]) -> [String]` returns one line per licence class present that is not open, in this order:

- `apple-sla`: "Bundled with macOS: licensed for use on this Mac only; do not distribute the forged font." (`build.licence.appleSLA`; the ADR's own text)
- `microsoft-product`: "Supplied with a Microsoft product: licensed for use with that product only; do not distribute the forged font." (`build.licence.microsoft`)
- `unknown`: "Licence unknown: check the source font's licence before you share the forged font." (`build.licence.unknown`)

These are exactly engine-metadata.md WP-110's `LICENCE_NOTES` texts, in its fixed order (checked for this review), so the lines before and after a build read the same.

Where the lines come from:
- **While the result is not fresh** (no build yet, or the recipe changed), they come from the available materials' `FaceRecord.licence.licenceClass` (placeholders are skipped).
- **While the result is fresh**, `result.report.licenceNotes.map(\.text)` replace them (engine data, shown as it comes).

The lines appear in three places: the action bar's detail lines, the Save panel's `message`, and the report.

**D11. Background completion (UI-M8).** When an install, save or build that the user started ends (success or failure) and `system.isAppActive == false`:

- call `system.requestAttention()`, which bounces the Dock icon once. It uses `NSApp.requestUserAttention(.informationalRequest)`; the header says to call it only when the app is not active.
- call `system.setDockBadge("1")`. `AppModel.appDidBecomeActive()` clears the badge.

When the app is active, do neither. This app does not use `UNUserNotificationCenter`: it would need an authorisation prompt, and the finding asks only for a bounce and a badge.

### Acceptance criteria

All tests are in `Tests/FPAppUITests/` and use `ShellFakeEngine`, `ShellFakeInstaller`, `ShellFakeSystemActions`, `ShellFakeFilePanels` and `ShellFileWriter`. The model has two materials, "Fixture A Regular" and "Fixture B Bold" (built with `ShellFaces`, licence class `open` unless an AC says otherwise), the family "Test Mix" and the style "Regular", as in `tests/test_build.py:24-31`. The fake engine's report has `fullName` "Test Mix Regular", `familyName` "Test Mix", `styleName` "Regular", `postscriptName` = `Naming.postscriptName(family: "Test Mix", style: "Regular")` and one warning. The fake installer returns `InstalledFont(fileURL: <root>/Fonts/Test Mix-Regular.ttf, …)` and creates that file.

**Action bar states and names**
- **AC-505-1** `ActionBarStateTests.idleOffersInstallAndACopy` (port of `test_idle_offers_install_and_a_copy`):
  - The status is "Installs in your Fonts folder — only for you, no password needed.", tone muted, with no detail lines and no links.
  - The primary button reads "Install" and is enabled. "Save a Copy…" is shown and enabled.
  - There is no progress bar and no Cancel.
- **AC-505-2** `ActionBarStateTests.anInvalidRecipeShowsTheProblem` (port of `test_an_invalid_recipe_shows_the_problem_and_disables_install`): with no materials, the status is "Add at least one font." (FPCore), tone danger, and Install and Save are disabled. After adding a material, the idle state returns. `engineMissingDisablesBuilding`: with `engineMissing: true`, the status is "Font Playground can't find its font engine. Reinstall the app.", tone danger, and Install and Save are disabled.
- **AC-505-3** `ActionBarStateTests.glyphWarningUsesTheWarnTone` (port of `test_a_glyph_budget_warning_uses_the_warn_tone`, which patched the budget): `ActionBarState.make(problem: nil, engineMissing: false, glyphWarning: EnglishText.glyphWarning(.nearLimit), build: <idle snapshot>, …)` has that status, tone warn, and Install enabled.
- **AC-505-4** `NameValidationTests.uiM3NamesThatMacOSWouldHideAreRejected`: (UI-M3)
  - Family ".MyFont" gives FPCore's `familyNameStartsWithDot` text ("Family name can't start with “.”: macOS hides fonts whose names start with a dot.").
  - Style ".Bold" gives "A style name can't start with a dot.".
  - A family of 64 "a"s gives "Use a font name of at most 63 characters."; 63 "a"s give nothing.
  - Family "A\u{0007}" gives FPCore's "Family name contains a control character." (NameValidation itself returns nil for it).
  - Each of these disables Install and Save through `ActionBarState`, and `install()` records no `conflict` call.
  - `uiM3SuggestedFileNameNeverStartsWithADot`: a recipe named ".Apple SD Gothic NeoI Forged" / "Regular" gives a Save panel `suggestedFileName` of "Apple SD Gothic NeoI Forged-Regular.ttf" (the guard is bypassed for this check by calling `SaveCopy.request(for:)`, the pure function that builds the `SavePanelRequest`).
- **AC-505-5** `BuildControllerTests.namesAreTwoWay` (port of `test_names_are_two_way`): setting `ActionBarView.familyBinding(model).wrappedValue = "Mine"` gives `recipe.names.family == "Mine"` with `familyEdited == true`. A family set through `app.edit { $0.setFamily("Other", byUser: true) }` is what the binding reads. While building, setting the binding changes nothing.

**Building and cancelling**
- **AC-505-6** `BuildControllerTests.buildingShowsProgressAndLocksTheNames` (port of `test_building_shows_progress_and_locks_the_names`):
  - After `install()` with no result, the state is `building(.install…)`, and `app.isBuilding == true`.
  - The primary button reads "Installing…" and is disabled. The status is "Building your font — starting…". After `emitProgress(.prepare, 0.4, materialIndex: 1)` it is "Building your font — preparing Fixture B Bold…" and the progress is 0.4. Cancel is shown and enabled, and "Save a Copy…" is hidden.
  - The names are not editable, `app.edit` returns false, and `app.pickRequest` is nil.
  - `savingShowsSaving` (port of `test_saving_shows_saving`): a Save a Copy… that has to build shows "Saving…" on the primary button.
  - `StageTextTests.everyStage` checks every row of the D3 table, including `prepare` with index 1 giving "Preparing Fixture B Bold…", index 7 giving "Preparing the fonts…", `.scan` giving nil, and the lowercasing rule ("Preparing X…" → "preparing X…"; "UI…" unchanged).
- **AC-505-7** `BuildControllerTests.cancelStopsTheBuild` (port of `test_cancel_stops_the_build`):
  - `cancel()` sets the stage to "Stopping…" and disables Cancel; a later progress event does not change the stage.
  - When the fake stream ends without a result (its `onTermination` saw the cancel), the state is `cancelled` and the status reads "Cancelled.".
  - The output file the fake created is gone, `app.isBuilding == false`, no `install` was recorded, and the primary button reads "Install".
- **AC-505-26** `BuildControllerTests.installIsIgnoredWhileBusyOrInvalid` (port of `test_install_is_ignored_while_busy_or_invalid`): a second `install()` during a build records no second `ForgeRequest` and no `conflict` call; `install()` and `saveCopy()` with an empty recipe, or with `engineStatus == .unavailable`, record nothing and show no panel.

**Install and update**
- **AC-505-8** `BuildControllerTests.installBuildsThenInstallsUnderTheFontName` (port of `test_install_without_a_result_builds_then_installs_under_the_font_name`):
  - `conflict(for:)` is called once, **before** any `ForgeRequest`, with `InstallQuery(family: "Test Mix", style: "Regular", postscriptName: Naming.postscriptName(family: "Test Mix", style: "Regular"))`.
  - Exactly one `ForgeRequest`: `outputPath` is directly inside `builds/` and matches `forged-[0-9a-f-]{36}\.ttf`, and the request equals `recipe.forgeRequest(outputPath:)`.
  - Exactly one `install` call, with the result URL, the report's family, style, PostScript name and full name, and `confirmed == nil`.
  - Afterwards the state is `installed`:
    - The status reads "Installed as “Test Mix Regular”.", and the first detail line is "Choose it in any app's font list — apps that were already open may need to be reopened.".
    - The links are [Show in Finder, Uninstall, Notes (1)]. The primary button reads "Installed" and is disabled, with the done look.
    - `app.builtFont?.url == result.url`, and `noteInstalled(<root>/Fonts/Test Mix-Regular.ttf)` was recorded. (INSTALL-6)
- **AC-505-9** `BuildControllerTests.aFreshResultInstallsAtOnce` (port of `test_install_with_a_fresh_result_installs_at_once`): after `build()` finishes (state `built`), `install()` installs without a second `ForgeRequest`. `aNewResultTheControllerDidNotInstallIsAnUpdate` (port): after an install, `build()` finishes in `built`, and the primary button reads "Update Installed Font".
- **AC-505-10** `BuildControllerTests.aChangeOffersAnUpdate` (port of `test_a_later_change_offers_an_update_and_installing_again_asks_nothing` and `test_installed_then_a_change_offers_an_update`):
  - After an install, a recipe edit makes the primary button read "Update Installed Font" and be enabled, the state stays `installed`, and `app.builtFont!.isStale(for: app.recipe)` is true.
  - `install()` with the fake's `conflict` returning `.replaceOurs(<the font installed in this session>)` presents no alert, rebuilds (2 `ForgeRequest`s in total), and calls `install(…, confirmed: .replaceOurs(thatFont))`. No `uninstall` is recorded. The primary button reads "Installed" again.
- **AC-505-11** `BuildControllerTests.updatingUnderANewNameRemovesTheOldFont` (port of both `test_updating_under_a_new_name_…` tests):
  - With the style changed to "Bold", `install()` installs "Test Mix Bold", then records `uninstall(<the Regular font>)` and `noteRemoved(<its URL>)`; the state is `installed` with "Test Mix Bold".
  - `oldFontThatCannotBeRemovedStaysOnRecord`: if that uninstall throws `ShellTestError("access denied")`, the state is `failed("Installed “Test Mix Bold”, but couldn't remove “Test Mix Regular”: access denied")`, the installed font is "Test Mix Bold", and the primary button reads "Update Installed Font". With the error cleared, `install()` records a second `uninstall` of the Regular font, no second `install` of Bold, and no third `ForgeRequest`; the state is `installed`.
  - `previousCopyNotRemovedIsReported`: an `install` that throws `InstallError.previousCopyNotRemoved(installed: new, previous: old, message: "busy")` leaves `new` recorded as installed and fails with "Installed “<new>”, but couldn't remove “<old>”: busy".
- **AC-505-12** `BuildControllerTests.installErrorsFailPlainly` (port of `test_install_errors_fail_with_a_plain_message`): an `install` that throws `InstallError.fileSystem(operation: "copy", message: "the font folder is locked")` gives "Couldn't install the font: the font folder is locked", tone danger, and nothing recorded as installed. With the error cleared, `install()` installs without a second `ForgeRequest`.
- **AC-505-13** `BuildControllerTests.aFailedBuildSaysWhy` (port of `test_a_failed_build_says_why` and `test_notes_and_details_ask_for_the_report`):
  - `fail(.helperFailed(HelperFailure(code: .mergeFailed, stage: .merge, materialIndex: nil, message: "the fonts disagree", detail: "Traceback…")))` gives the status "Couldn't build the font: the fonts disagree", tone danger, the links [Details], and no output file.
  - `showReport()` sets `app.sheet = .report(text)` where `text` starts with "Couldn't build the font: the fonts disagree" and contains "Traceback…".
  - `.staleMaterial` with index 0 gives "“Fixture A Regular” changed since Font Playground last read it. Choose File › Rescan Fonts, then try again."; with index nil it gives "A font changed since Font Playground last read it. Choose File › Rescan Fonts, then try again.".
  - `.crashed(exitCode: 1, signal: nil, stderrTail: "boom")`, and `endWithoutResult()` without a cancel, both give "Couldn't build the font: the font engine stopped unexpectedly."; `.timedOut` gives "Couldn't build the font: the font engine took too long.".
  - After a successful build, `showReport()` shows `ReportText.render(lastReport)`.
- **AC-505-14** `ConflictTextTests.install13ConflictTextsUseMacOSWording` checks each row of the D4 table (title, message and button titles) for sample arguments, and that each `.block`/`.ask` title equals the matching `ConflictReason(...).englishText` from FPMacServices. `ui10ConflictPromptsUseVerbButtons` (INSTALL-13, UI-10):
  - `.block(.systemHas(name: "Helvetica"))` for the family "Helvetica" presents "macOS already has a font called “Helvetica” — choose another name." with the single button "Change Name". No `ForgeRequest` or `install` is recorded, and "Change Name" increments `nameFocusRequest`.
  - `.replaceOurs(f)` for a font installed in an earlier session presents "Replace the “Test Mix Regular” you installed earlier?" with ["Replace", "Cancel"]. Cancel records nothing more; Replace builds and calls `install(…, confirmed: .replaceOurs(f))`.
  - `.ask(.appleOffersDownload(name: "Test Mix"))` presents ["Install Anyway", "Cancel"]; Install Anyway passes `confirmed: .ask(.appleOffersDownload(name: "Test Mix"))`.
  - `raceDetectedByTheInstallerAsksAgain`: an `install` that throws `InstallError.conflict(.block(.youHave(name: "Test Mix")))` presents that block alert; nothing is recorded as installed.
  - No alert title or button in any row is "Yes", "No" or "OK".
- **AC-505-15** `BuildControllerTests.uninstallMovesToTheTrashAndSaysSo` (port of `test_uninstall_removes_the_font_and_leaves_a_notice` and `test_uninstall_link_removes_the_font`):
  - With the fake returning `.movedToTrash(nil)`: the status reads "Removed from your fonts — it's in the Trash." (tone muted), with no links; the primary button reads "Install" and is enabled; `noteRemoved` was recorded.
  - `install()` then installs at once (no second `ForgeRequest`). An uninstall returning `.notInstalled` gives "That font was no longer installed.". A third `uninstall()` with nothing installed records nothing (2 `uninstall` calls in total).
  - An uninstall that throws `InstallError.notOurs(name: "Test Mix Regular")` gives "Couldn't remove the font: Font Playground didn't install “Test Mix Regular”, so it won't remove it", and the font stays recorded.
- **AC-505-16** `BuildControllerTests.install13ShowInFinderRevealsTheFile` (port of `test_show_file_opens_the_folder`, corrected): (INSTALL-13, UI-11)
  - After an install, `showInFinder()` calls `reveal([installedFileURL])`: the file itself, not its folder.
  - After a save, it reveals the saved file.
  - With the file deleted, the notice reads "That file is no longer there." and nothing is revealed.
- **AC-505-27** `BuildControllerTests.resetForgetsEverything` (port of `test_reset_forgets_everything`): after install, uninstall and install, `reset()` gives state `idle`, `installed`, `pendingRemoval`, `savedURL`, `notice`, `lastReport` and `lastErrorDetail` all nil, `app.builtFont == nil`, the result file gone, and the installed file in `<root>/Fonts` untouched.

**Save a Copy**
- **AC-505-17** `SaveCopyTests.ui9SaveACopyUsesASheetWithTTF` (port of `test_save_a_copy_asks_for_a_path` and `test_save_copy_builds_writes_the_file_and_remembers_it`): (UI-9)
  - The panel request has `suggestedFileName` "Test Mix-Regular.ttf", `allowedExtension` "ttf", and `directory == paths.documents` on first use; the next request has the folder used last.
  - A cancelled panel (`nil`) records no `ForgeRequest`.
  - Choosing `<root>/copies/Mine.ttf` builds, then writes the file through `writeFile`: the bytes equal the result file's, and no `.*.tmp` file remains in `copies/`.
  - The state is `saved`, the status reads "Saved to " followed by `ShellText.shortPath` of the path, and, with `isFontBookAvailable == true`, the links are [Show in Finder, Open in Font Book, Notes (1)].
  - Choosing `<root>/copies/Mine` saves `<root>/copies/Mine.ttf`; `Mine.TTF` is kept as it is.
- **AC-505-18** `SaveCopyTests.aChangeAfterSavingNoLongerSaysSaved` (port of `test_a_change_after_saving_no_longer_says_saved`): after a save, a style change returns the status to the idle text with no links.
- **AC-505-19** `SaveCopyTests.saveErrorsFailPlainly` (port of `test_save_errors_fail_with_a_plain_message`): with `ShellFileWriter.error = ShellTestError("the disk is full")`, the status is "Couldn't save the font: the disk is full".
- **AC-505-20** `SaveCopyTests.uiM7OpenInFontBookAfterSaving`: `openInFontBook()` calls `openInFontBook(savedURL)`. With `isFontBookAvailable == false`, the link is absent, `build.commands.canOpenInFontBook` is false, and `openInFontBook()` records nothing. (UI-M7)
- **AC-505-28** `ActionBarStateTests.shortPathUsesATildeForTheHomeFolder` (port of `test_short_path_uses_a_tilde_for_the_home_folder`): `ShellText.shortPath("/Users/example/Documents/X.ttf", home: "/Users/example") == "~/Documents/X.ttf"`; `"/Volumes/Fonts/X.ttf"` and `"/Users/example2/X.ttf"` stay as they are.
- **AC-505-29** `ActionBarStateTests.noNotesLinkWithoutWarnings` (port of `test_no_notes_link_without_warnings`): a report with no warnings and no licence notes gives no Notes link after an install.

**Licence notes, outputs and background**
- **AC-505-21** `LicenceNotesTests.adr12LinesPerNonOpenClass`:
  - A recipe with one `apple-sla` material and one `open` material shows exactly the Apple line, both in the idle detail lines and in the Save panel's `message`.
  - A recipe with `unknown` and `apple-sla` materials lists the Apple line first, then the unknown line.
  - An open-only recipe shows neither.
  - After a build whose report has `licenceNotes == [("microsoft-product", [0], "M")]`, the lines are `["M"]` while the result is fresh, and the recipe's lines again after an edit.
- **AC-505-22** `BuildOutputsTests.atMostOneResultFileAndOnlyInBuilds`:
  - After two builds, `builds/` holds one `forged-*.ttf`, the second one.
  - A failed build and a cancelled build leave no new file.
  - `reset()` and `discardResultFiles()` remove the result and set `app.builtFont` to nil.
  - A file named `keep.ttf` in `builds/`, and any file outside `builds/`, survive all of these. `BuildOutputs.delete(<root>/other/forged-x.ttf, builds:)` deletes nothing.
- **AC-505-23** `BackgroundAttentionTests.uiM8BackgroundBuildBouncesTheDock`: (UI-M8)
  - An install that ends while `isAppActive == false` records `requestAttention()` once and `setDockBadge("1")`. The same install while the app is active records neither. A failed build in the background also bounces once.
  - `appDidBecomeActive()` records `setDockBadge(nil)`.
  - A build records `beginActivity` when it starts and `endActivity` with the same token when it ends, including on cancel and on failure.
- **AC-505-24** `BuildControllerTests.startOverDuringABuildStaysIdle` (port of `test_start_over_during_a_build_stays_idle_when_the_cancel_lands`): `reset()` during a build gives `idle`. When the cancelled stream ends afterwards (even with `finish(report:)`), the state is still `idle`, no result is stored, and no `forged-*.ttf` remains.
- **AC-505-30** `BuildControllerTests.cancelAndWaitStopsTheBuildForQuit`: during a build, `await cancelAndWait()` returns after the fake stream ends (and within 3 s if it never ends); the output file is gone and `app.isBuilding == false`.
- **AC-505-31** `FileNameAgreementTests.installerAndSaveUseTheSameStem`: for every `file_stem` case of `spec/fixtures/naming/family-names.json` whose family does not start with ".", plus (".Hidden", "Regular"), ("  ", "") and ("A/B", "C:D"), `InstallFileName.stem(family:style:) + ".ttf" == Naming.fileName(family:style:)` (mac-services.md WP-403 §7, core.md WP-304 §5). `InstallFileName` must be `public` in FPMacServices (WP-505 makes it public if WP-403 left it internal).
- **AC-505-25** `make lint` and `make mac-test` pass. `SourceLintTests` (L5–L7) passes over the new files.

**Manual checks**
- **AC-505-M1** (manual, macos) A real build.
  1. Run the app that `make app` built, using `open --env FP_ENGINE_PYTHON=…`.
  2. Choose Helvetica Neue as the main font, add PingFang SC for Chinese, and press Install.
  3. The progress bar moves through the D3 texts. The status then reads "Installed as “Helvetica Neue PingFang SC Regular”." (or the recipe's name), and the preview shows its "Built font" badge (WP-504).
  4. In TextEdit, Format › Font › Show Fonts lists the family.
  5. Take a screenshot of the action bar.
  6. Press Uninstall. Finder shows the file in the Trash.
- **AC-505-M2** (manual, macos) The save sheet.
  1. Press ⇧⌘S. The save panel appears as a sheet attached to the main window. Take a screenshot. It suggests the name "…-Regular.ttf" and shows the apple-sla licence line as its message.
  2. Type "Mine" without an extension and save. The file is saved as `Mine.ttf`.
  3. "Show in Finder" selects the file, and "Open in Font Book" opens Font Book's preview of it.
- **AC-505-M3** (manual, macos) A conflict.
  1. Type the name "Helvetica" and press Install.
  2. A sheet, not a free-floating alert, says "macOS already has a font called “Helvetica” — choose another name." and has the button "Change Name".
  3. Pressing the button focuses the Name field. Take a screenshot.
- **AC-505-M4** (manual, macos) Background completion.
  1. Start a CJK build and switch to Finder.
  2. When the build ends, the Dock icon bounces once and shows the badge "1".
  3. Switch back to Font Playground. The badge is cleared.
- **AC-505-M5** (manual, macos) Quitting during a build.
  1. During a build, press ⌘Q. A sheet asks "Your font is still being built. Quit anyway?" with "Quit" and "Keep Building".
  2. "Keep Building" lets the build continue. The red close button shows the same sheet.
  3. "Quit" exits within 3 s. Afterwards, `pgrep -fl "fpengine forge"` prints nothing, and `builds/` holds no `forged-*.ttf`.
- **AC-505-M6** (manual, macos) The narrow layout.
  1. Shrink the window to the 640-pt minimum with the sidebar shown. The action bar uses two rows, and no control or text is clipped. Take a screenshot.
  2. At full width, it uses a single row.

### Verification
```bash
make lint
make mac-test
make app
make test
```

### Notes for the implementer
- **Port the tests.** Port `reference/fontplayground-py/tests/test_build.py` and `test_action_bar.py` one to one; the porting map is below. The original's catalog-based `conflict()` logic (`build.py:142-179`) belongs to WP-403's installer. Don't re-implement it here: map the installer's answer to text.
- **Tests not ported.** `test_without_install_support_the_primary_saves` and `test_apply_theme_restyles_the_bar` are dropped. Install is always supported on macOS (ADR-0009), and colours are native.
- **Keep the main thread free.** `FontInstaller` and `CatalogStore` are actors with async APIs, so `await` them from the main actor; they never block it. Never block the main thread on file IO longer than a `stat`, except `Data(contentsOf:)` + `writeFile` of one font for Save a Copy… (a few MB).
- **Delete narrowly.** Delete only `forged-*.ttf` files directly inside `builds/`. This WP never deletes anything else. Uninstall goes through the installer, which moves only our own files to the Trash.
- **Keep the `.ttf` safety net.** `NSSavePanel` with `allowedContentTypes` already enforces `.ttf` (UI-9 verifier; `UTType(filenameExtension: "ttf")` is `public.truetype-ttf-font`). Keep the extra check anyway.
- **One forge at a time.** A forge needs 0.7–0.95 GB (ENGINE-9), so never start a second one while one runs. The state machine guarantees this.
- **Cancel is not an error.** The client ends the stream normally when the consuming `Task` is cancelled (helper.md WP-204 step 7). Decide "cancelled" from your own `stopping` flag or `Task.isCancelled`, never from a thrown `CancellationError` alone.
- **Don't re-check conflicts in the UI.** `ConflictChecker` (WP-403) decides; this WP only maps `InstallConflict` to alerts and passes the confirmed value back, which the installer compares (`confirmed == c`) to rule out stale confirmations.

| Reference test | Swift test (AC) |
|---|---|
| test_build.py: test_install_without_a_result_builds_then_installs_under_the_font_name | BuildControllerTests.installBuildsThenInstallsUnderTheFontName (AC-505-8) |
| test_install_with_a_fresh_result_installs_at_once | aFreshResultInstallsAtOnce (AC-505-9) |
| test_install_is_ignored_while_busy_or_invalid | installIsIgnoredWhileBusyOrInvalid (AC-505-26) |
| test_a_later_change_offers_an_update_and_installing_again_asks_nothing | aChangeOffersAnUpdate (AC-505-10) |
| test_a_new_result_the_controller_did_not_install_is_an_update | aNewResultTheControllerDidNotInstallIsAnUpdate (AC-505-9) |
| test_updating_under_a_new_name_removes_the_font_installed_before, test_updating_under_a_new_name_reports_an_old_font_it_could_not_remove | updatingUnderANewNameRemovesTheOldFont, oldFontThatCannotBeRemovedStaysOnRecord (AC-505-11) |
| test_install_errors_fail_with_a_plain_message | installErrorsFailPlainly (AC-505-12) |
| test_save_copy_builds_writes_the_file_and_remembers_it | SaveCopyTests.ui9SaveACopyUsesASheetWithTTF (AC-505-17) |
| test_save_errors_fail_with_a_plain_message | SaveCopyTests.saveErrorsFailPlainly (AC-505-19) |
| test_a_failed_build_says_why | aFailedBuildSaysWhy (AC-505-13) |
| test_cancel_stops_the_build | cancelStopsTheBuild (AC-505-7) |
| test_uninstall_removes_the_font_and_leaves_a_notice | uninstallMovesToTheTrashAndSaysSo (AC-505-15) |
| test_no_conflict_for_a_new_name, test_a_windows_font_with_the_same_family_blocks, test_a_font_the_user_installed_elsewhere_blocks, test_a_forged_font_installed_earlier_asks_to_replace, test_a_forged_font_of_another_style_is_no_conflict, test_a_catalog_face_whose_file_is_gone_is_no_conflict, test_a_native_family_name_counts_too, test_the_registered_font_decides_when_the_catalog_does_not_know_it | WP-403 `ConflictChecker` tests (detection); ConflictTextTests (wording, AC-505-14) |
| test_reset_forgets_everything | resetForgetsEverything (AC-505-27) |
| test_start_over_during_a_build_stays_idle_when_the_cancel_lands | startOverDuringABuildStaysIdle (AC-505-24) |
| test_action_bar.py: test_idle_offers_install_and_a_copy | ActionBarStateTests.idleOffersInstallAndACopy (AC-505-1) |
| test_an_invalid_recipe_shows_the_problem_and_disables_install | anInvalidRecipeShowsTheProblem (AC-505-2) |
| test_a_glyph_budget_warning_uses_the_warn_tone | glyphWarningUsesTheWarnTone (AC-505-3) |
| test_names_are_two_way | BuildControllerTests.namesAreTwoWay (AC-505-5) |
| test_building_shows_progress_and_locks_the_names | buildingShowsProgressAndLocksTheNames (AC-505-6) |
| test_saving_shows_saving | savingShowsSaving (AC-505-6) |
| test_installed_then_a_change_offers_an_update | aChangeOffersAnUpdate (AC-505-10) |
| test_uninstall_link_removes_the_font | uninstallMovesToTheTrashAndSaysSo (AC-505-15) |
| test_show_file_opens_the_folder | install13ShowInFinderRevealsTheFile (AC-505-16; corrected: the file is revealed) |
| test_notes_and_details_ask_for_the_report | aFailedBuildSaysWhy (AC-505-13) |
| test_no_notes_link_without_warnings | noNotesLinkWithoutWarnings (AC-505-29) |
| test_a_name_windows_already_has_is_refused | ui10ConflictPromptsUseVerbButtons (AC-505-14; macOS wording) |
| test_replacing_a_forged_font_asks_first | ui10ConflictPromptsUseVerbButtons (AC-505-14) |
| test_save_a_copy_asks_for_a_path | SaveCopyTests.ui9SaveACopyUsesASheetWithTTF (AC-505-17) |
| test_a_change_after_saving_no_longer_says_saved | aChangeAfterSavingNoLongerSaysSaved (AC-505-18) |
| test_short_path_uses_a_tilde_for_the_home_folder | shortPathUsesATildeForTheHomeFolder (AC-505-28) |
| test_without_install_support_the_primary_saves, test_apply_theme_restyles_the_bar | not ported (install is always supported on macOS, ADR-0009; native colours) |

---

## WP-506: Advanced inspector (scripts table, line spacing, defaults, last report)

**Goal:** The Advanced inspector in the main window. It shows which font draws each script (editable), which font sets the line spacing, the default boldness and size, and the last build's report.
**Depends on:** WP-501, WP-304 · **Env:** macos · **Size:** M · **Closes findings:** UI-15

### Scope
- **In:**
  - `AdvancedModel`, a pure port of the logic in `ui/advanced.py`;
  - `AdvancedInspectorView`, replacing the stub;
  - `AdvancedText`;
  - locking the controls during builds;
  - refusing pins that a font can't shape (ADR-0008).
- **Out:**
  - the inspector toggle, its menu item and its persistence (WP-501);
  - `ReportText` (WP-501);
  - producing reports (WP-505). Until WP-505 is merged, the report reads "No build yet.".

### Touched paths
- `…/FPAppUI/Model/AdvancedModel.swift` (new)
- `…/FPAppUI/Views/AdvancedInspectorView.swift` (replace the stub)
- `…/FPAppUI/Shared/AdvancedText.swift` (new), `…/FPAppUI/Resources/Localizable.xcstrings` (edit)
- `…/Tests/FPAppUITests/AdvancedModelTests.swift`, `AdvancedInspectorToggleTests.swift` (new)

### Design

**D1. Presentation (UI-15).**

- **Where it lives.** The inspector is the trailing column of the detail area (`.inspector(isPresented: $model.inspectorPresented)`, macOS 14), 260/300/420 pt wide.
- **How it opens and closes.** Font › Show/Hide Advanced (⌥⌘I) toggles it, and so does the toolbar button (both WP-501). WP-502's "Advanced…" footer link calls `showAdvanced()`. Esc does not close it; ⌥⌘I does.
- **Persistence.** Its visibility is saved (`inspectorPresented`).
- **Stable native layout.** The main split view and inspector disable implicit SwiftUI animations. On macOS 27 the animated column transition can enter an AppKit layout cycle and freeze the window. The native inspector and its controls remain unchanged.
- **What it replaces.** There is only ever one instance. The original's non-modal dialog and its Close button (`advanced.py:167-171`) are gone.

**D2. `AdvancedModel` (pure).**

```swift
public struct AdvancedModel {
    public init(recipe: Recipe, showAll: Bool, isLocked: Bool, lastReport: ForgeReport?, lastErrorDetail: String?,
                locale: Locale = .current)          // number formatting; tests pass en_US
    public struct Choice: Equatable { public var title: String; public var key: FaceKey?; public var isDisabled: Bool }
    public struct ScriptRow: Equatable, Identifiable {
        public var id: ScriptGroup
        public var label: String                 // English group label (FPCore)
        public var isCovered: Bool
        public var choices: [Choice]             // [Auto → name] + materials; empty when not covered
        public var selectedIndex: Int            // 0 = Auto
        public var countsText: String            // "Fixture A 5 · Fixture B 2" ("PingFang SC 30,000"), or "—"
        public var drawnByText: String           // current choice title, or "nobody"
    }
    public var rows: [ScriptRow]
    public var lineSpacingChoices: [String]      // ["Main font", material display names…]
    public var lineSpacingIndex: Int
    public var weightChoices: [WeightChoice]     // WeightChoice.standard, plus the current value if it is not standard
    public var weightIndex: Int
    public var sizePercent: Int                  // 10…1000
    public var reportText: String
    public var controlsEnabled: Bool             // !isLocked
    public var lineSpacingEnabled: Bool          // !isLocked && !recipe.materials.isEmpty
    public static func shortNames(_ faces: [FaceRecord]) -> [FaceKey: String]
    // Intents return the change to apply with AppModel.edit, or nil when refused
    public func pin(_ group: ScriptGroup, choiceIndex: Int) -> ((inout Recipe) -> Void)?
    public func lineSpacing(index: Int) -> (inout Recipe) -> Void
    public func defaults(weightIndex: Int?, sizePercent: Int?) -> (inout Recipe) -> Void   // nil keeps that value
}
```

Rules (port of `advanced.py:261-327`):

- **Counts.** `counts[key][group]` comes from `RuleResolver.counts(for:)`. That is the same count the automatic rules use, so an unavailable material or a suspicious face counts 0.
- **Covered groups.** A group is covered when some material's count for it is above 0. Rows follow `ScriptGroup.allCases` order. With `showAll`, all 15 groups are listed, and an uncovered group shows "nobody" (`advanced.nobody`) and "—" (`advanced.noCount`) (`advanced.py:33-34`, `advanced.py:276-279`).
- **Choice 0** is "Auto → %@" (`advanced.auto`), filled with the display name of `RuleResolver.smartSupplier(group, counts:, order: recipe.keys)`. For a covered group this is never nil (the best material always qualifies); if it is, use "?" as the original did. The materials' display names follow, in recipe order.
- **Selection.** `selectedIndex` is the pinned material's position + 1, or 0 when nothing is pinned (`advanced.py:280-286`).
- **countsText** lists the materials whose count is above 0, sorted by count (highest first), then by recipe order. The material that `recipe.scriptRules()[group]` picks comes first. Each entry is `"\(shortName) \(count)"` with the count formatted by `count.formatted(.number.locale(locale))` (grouping separators, as the original's `{:,}`), and entries are joined by " · " (`advanced.py:292-297`).
- **Short names.** `shortNames` gives the family when it is unique among the materials, else "family style" (`advanced.py:67-71`).
- **Shaping guard (ADR-0008).** For a group with `needsShaping`, a material whose face returns `canShape(group) == false` gets `isDisabled = true` and the title "%1$@ — can't shape %2$@" (`advanced.cantShape`, with the name and the group label). `pin` returns nil for a disabled choice, so the recipe does not change. The view also marks the item `.selectionDisabled()`.
- **pin.** Index 0 gives `setPin(group, to: nil)`. Index i gives `setPin(group, to: materials[i−1].key)`.
- **lineSpacing** (`advanced.py:235-254`, `advanced.py:317-319`). Index 0 gives `setBase(nil)`. Index i gives `setBase(materials[i−1].key)`. The choice follows the font, not its position.
- **Default boldness.** `WeightChoice.standard` (`Shared/WeightChoice.swift`, WP-501: `public struct WeightChoice: Equatable { public var weight: Int?; public var title: String }`) is As is (nil), Light (300), Regular (400), Medium (500), Semibold (600), Bold (700), Heavy (900) (`recipe.py:53-56`), with `ShellText` titles. ui-editing.md WP-502 has the same list as `RecipeText.weightChoices`; the English keys are identical, so the catalog holds one entry each, and WP-507 checks that both lists agree. A stored weight outside the list is appended as its number, for example "650" (`recipe.py:124-131`).
- **Default size.** 10…1000 % (`recipe.py:52`). `sizePercent = Int((recipe.defaultScale * 100).rounded())`. `defaults` sets `setDefaults(weight: choice.weight, scale: Double(percent) / 100)`, keeping the other value when its argument is nil.
- **Real weights after Default boldness** (core.md WP-304 §3 "How it is surfaced"). When a `defaults` change sets a different weight, `AdvancedInspectorView` applies it and then, in the same `app.edit`, `applyRealWeights(in: FaceCatalog(app.catalogFaces))`. Each returned `WeightSwap` becomes a note under the Defaults section: `EnglishText.weightSwap(swap)` (WP-507: `ModelText`) with an **Undo** button (`advanced.undo`) that restores the `Recipe` value from before the change through `app.edit { $0 = previous }`. The notes disappear on the next recipe change. `AdvancedModel.weightSwapNotes(_ swaps: [WeightSwap]) -> [String]` is pure.
- **reportText.** `ReportText.render(lastReport)`, else `lastErrorDetail`, else "No build yet." (`advanced.noBuild`) (`advanced.py:299-310`).

**D3. The view.** `AdvancedInspectorView` builds an `AdvancedModel` from `app.recipe`, `app.settings.showAllScriptGroups`, `app.isBuilding`, `app.build.lastReport` and `app.build.lastErrorDetail`. It applies every intent through `app.edit`. It is a `Form` (`.formStyle(.grouped)`) with these sections:

| Section | Content | Strings (`AdvancedText`) |
|---|---|---|
| "Who draws what" (`advanced.who`) | One row per script: a menu-style `Picker` labelled with the script label, listing its choices, with `countsText` below in secondary text. Uncovered rows show "nobody" and "—" as plain text. After the rows, a `Toggle` bound to `showAllScriptGroups` | Picker `.help`: "Which font draws this script. Auto picks the highest font in your list that draws it well." (`advanced.drawnByHelp`). Toggle: "Show all %lld scripts" (`advanced.showAll`, 15). Toggle help: "Also list the scripts none of your fonts draws" (`advanced.showAllHelp`) |
| "Line spacing" (`advanced.lineSpacingSection`) | A `Picker` labelled "Line spacing from" (`advanced.lineSpacing`). Choices: "Main font" (`advanced.mainFont`), then the materials | Help: "Which font's line spacing your font uses (the main font's unless you choose)" (`advanced.lineSpacingHelp`) |
| "Defaults" (`advanced.defaults`) | A `Picker` "Default boldness" (`advanced.defaultBoldness`). A `Stepper` with a number field, "Default size" (`advanced.defaultSize`), showing "%lld %" (`advanced.percent`). Footer: "For fonts without their own setting." (`advanced.defaultsNote`) | Helps: "Boldness of every font that has no Weight of its own" (`advanced.defaultBoldnessHelp`), "Size of every font that has no Size of its own" (`advanced.defaultSizeHelp`) |
| "Last build" (`advanced.lastBuild`) | `Text(verbatim: reportText)`, monospaced, `.textSelection(.enabled)`, in a scroll view up to 240 pt high | — |

The Default size number field hides its own visual label because the enclosing row already supplies one; it keeps the TextField accessibility label. This avoids a duplicated label wrapping inside the 52-pt number field.

`AdvancedIntents` (`Model/AdvancedModel.swift`, `@MainActor enum`) holds the three impure steps the view calls, so tests can drive them without a view: `pin(_ model: AppModel, group:choiceIndex:)`, `lineSpacing(_:index:)` and `applyDefaults(_:weightIndex:sizePercent:) -> [WeightSwap]` (applies `setDefaults` and, when the weight changed, `applyRealWeights` in one `edit`; returns the swaps, which the view keeps in `@State` with the previous `Recipe` for Undo).

**D4. Locking.** While a build runs, the pickers and the stepper are disabled, but the toggle and the report stay usable (`advanced.py:215-223`). With no materials, the line-spacing picker is disabled (`advanced.py:256-259`).

### Acceptance criteria
- **AC-506-1** `AdvancedModelTests.shortNamesUseTheFamilyUnlessShared` (port of `test_short_names_use_the_family_unless_two_fonts_share_it`).
- **AC-506-2** `AdvancedModelTests.rowsListOnlyCoveredScriptsUntilShowAll` (port of `test_table_lists_only_covered_scripts_until_show_all`):
  - Setup (built with `ShellFaces`, like `tests/test_advanced.py`'s fonts): Fixture A covers Latin 5. Fixture B covers Latin 2, Han 1 and CJK symbols 1.
  - The rows are latin, han, cjk_symbols, labelled "Latin", "Han", "CJK symbols & fullwidth".
  - Latin: countsText is "Fixture A 5 · Fixture B 2", and the choices are ["Auto → Fixture A Regular", "Fixture A Regular", "Fixture B Bold"].
  - Han: drawnByText is "Auto → Fixture B Bold".
  - With `showAll`, there are 15 rows, and arabic has "nobody", "—" and no choices.
- **AC-506-3** `AdvancedModelTests.choosingAFontPinsAndAutoUnpins` (port):
  - Choosing index 2 for latin pins Fixture B. The rebuilt model selects index 2, and its countsText is "Fixture B 2 · Fixture A 5".
  - Choosing index 0 removes the pin.
- **AC-506-4** `AdvancedModelTests.rowsFollowTheRecipe` (port of `test_table_follows_the_model`): after removing B, only latin is listed. After `reset()`, nothing is listed.
- **AC-506-5** `AdvancedModelTests.lineSpacingSetsTheBase` (port):
  - The choices are ["Main font", "Fixture A Regular", "Fixture B Bold"].
  - Index 2 sets the base to B. After B moves to the top, the selection still names "Fixture B Bold".
  - Index 0 clears the base.
  - With no materials, `lineSpacingEnabled` is false.
- **AC-506-6** `AdvancedModelTests.defaultsSetTheRecipe` (port of `test_defaults_set_the_model`):
  - There are 7 weight choices, starting with "As is" and "Light (300)".
  - Choice 5 gives (700, 1.0). Size 90 then gives (700, 0.9). Choice 0 then gives (nil, 0.9).
  - A recipe default of (650, 1.25) shows "650" and 125.
- **AC-506-7** `AdvancedModelTests.lastBuildReport` (port): it reads "No build yet." with neither a report nor an error; `ReportText.render(report)` with a report; the error detail when there was only a failure.
- **AC-506-8** `AdvancedModelTests.lockedDisablesWhatChangesTheFont` (port of `test_set_locked_disables_what_changes_the_font`): with `isLocked`, both `controlsEnabled` and `lineSpacingEnabled` are false, and the report text is still there.
- **AC-506-9** `AdvancedModelTests.adr8FontsThatCannotShapeAreNotOffered`:
  - A material whose face can't shape Arabic appears as "Geeza Pro Regular — can't shape Arabic", with `isDisabled`.
  - `pin(.arabic, choiceIndex:)` for it returns nil, and the recipe's pin is unchanged.
  - A material that can shape Arabic can be pinned.
- **AC-506-10** `AdvancedInspectorToggleTests.ui15AdvancedIsAnInspector` (port of `test_advanced_opens_one_dialog`): (UI-15)
  - `toggleAdvanced()` and `showAdvanced()` set `inspectorPresented`.
  - A new `AppModel` on the same suite starts with the saved value.
  - `showAllScriptGroups` is saved too.
- **AC-506-11** `make lint` and `make mac-test` pass.
- **AC-506-12** `AdvancedModelTests.countsUseGroupingSeparators`: with `locale: Locale(identifier: "en_US")`, a material counting 30000 Han characters shows "PingFang SC 30,000" in countsText.
- **AC-506-13** `AdvancedInspectorToggleTests.defaultBoldnessPrefersRealWeights` (core.md WP-304 §3): the main font "Main Regular" covers Latin only and is the only face of its family; "Fam Regular" (400) and "Fam Bold" (700) both cover the sample's Han characters, and "Fam Regular" is the second material. `AdvancedIntents.applyDefaults(model, weightIndex: 5, sizePercent: nil)` replaces "Fam Regular" with "Fam Bold" in one `edit`, produces one note "Using Fam Bold instead of making Fam Regular bolder.", and its Undo restores the recipe exactly (`==` the value before the change). While `isBuilding`, the intent changes nothing.
- **AC-506-14** `AdvancedInspectorLayoutTests.ui15InspectorLayoutFinishesAfterBuild`: an offscreen production window controller opens and closes Advanced twice, before a build and after a fake build/install with a long report. The test pumps the AppKit run loop and Core Animation display cycle; an independent watchdog fails the process if synchronous layout never returns. Files, preferences and installation services stay temporary; frame autosaving is disabled.
- **AC-506-15** `AdvancedInspectorLayoutTests.ui15InspectorLayoutFinishesAfterBuild`: starting with the sidebar shown, open Advanced in 1216 × 680-pt and 676 × 680-pt offscreen production windows, then again at 676 pt with the sidebar already hidden, with an empty recipe and a fake installed build with a long report. The sidebar stays visible at normal width and automatically collapses at half-screen width. The content frame and all native split-view bounds fit the requested size after real display cycles, and the inspector pane is visible at 260–420 pt (*WP-701 finding H*). `AdvancedInspectorToggleTests.wp701FindingHPresentsAfterTheSidebarCollapse` checks the deferred presentation and its cancellation. Closing Advanced permits a 640-pt-wide window again. A saved open inspector also fits both widths when the native window is first created. Manual acceptance remains separate.
- **AC-506-M1** (manual, macos) The inspector with a real recipe.
  1. Build a Helvetica Neue + PingFang SC recipe and show the inspector at its ideal width.
  2. Take a screenshot. It must show rows for Latin, Han, Kana, CJK symbols and so on, the counts under each picker, and the report after a build.
  3. Start a build. The pickers dim, and the report can still be selected and copied with ⌘C.
- **AC-506-M2** (manual, macos) The inspector in a half-screen window.
  1. Tile the window to half of a 1352-pt screen and show the inspector.
  2. Take a screenshot. Nothing is clipped; the sidebar may collapse.
  3. Press ⌥⌘I. The inspector hides.

### Verification
```bash
make lint
make mac-test
make app
```

### Notes for the implementer
- **No dependency on WP-505.** The inspector only reads `build.lastReport` and `build.lastErrorDetail`, so it doesn't need WP-505 to be merged. Tests set those two properties directly.
- **The shaping guard lives in the model.** `selectionDisabled` is available on macOS 14, but a menu-style `Picker` may still let the item be chosen. The refusal in `pin` is what counts; after it, the picker snaps back to the recipe's value.
- **No Close button.** An inspector closes with its toggle.

| Reference test (test_advanced.py) | Swift test |
|---|---|
| test_short_names_use_the_family_unless_two_fonts_share_it | shortNamesUseTheFamilyUnlessShared |
| test_dialog_is_titled_advanced_and_not_modal | ui15AdvancedIsAnInspector |
| test_table_lists_only_covered_scripts_until_show_all | rowsListOnlyCoveredScriptsUntilShowAll |
| test_choosing_a_font_pins_the_script_and_auto_unpins | choosingAFontPinsAndAutoUnpins |
| test_table_follows_the_model | rowsFollowTheRecipe |
| test_line_spacing_combo_sets_the_base | lineSpacingSetsTheBase |
| test_defaults_set_the_model | defaultsSetTheRecipe |
| test_last_build_report | lastBuildReport |
| test_set_locked_disables_what_changes_the_font | lockedDisablesWhatChangesTheFont |
| test_apply_theme | not ported (native colours) |

---

## WP-507: Accessibility, String Catalog, Increase Contrast, keyboard audit

**Goal:** Every control has a VoiceOver name, every FPAppUI string is in the String Catalog, custom colours meet contrast rules and respond to Increase Contrast, and the whole app works from the keyboard, with Mac key names and no pointing-hand cursors.
**Depends on:** WP-502, WP-503, WP-504, WP-505, WP-506 · **Env:** macos · **Size:** M · **Closes findings:** UI-13, UI-M4, UI-6, UI-M5, UI-17

### Scope
- **In:**
  - an audit of every FPAppUI view, with fixes. This WP may edit files owned by WP-501–506, including `Editing/EditingShared.swift`'s `MixPalette` (§S9);
  - accessibility labels, values, traits and grouping;
  - catalog completeness and `bundle: .module`;
  - lint rules L1, L2, L4, L8 and L9;
  - `Shared/ModelText.swift`: catalog-backed text for FPCore values, replacing FPAppUI's `EnglishText` calls (§S8);
  - Mac key wording;
  - the contrast table and Increase Contrast;
  - keyboard reachability and shortcuts;
  - the manual QA pass.
- **Out:**
  - translations (backlog B-8);
  - new features;
  - engine data (report warnings, licence note texts, helper messages), which is shown as it comes in v1 (§S8);
  - changing FPCore's or FPMacServices' English (their specs own it).

### Touched paths
- `Packages/FontPlaygroundMacKit/Sources/FPAppUI/**` (edit: accessibility modifiers, strings, `MixPalette`)
- `Packages/FontPlaygroundMacKit/Sources/FPAppUI/Resources/Localizable.xcstrings` (edit), `App/Resources/InfoPlist.xcstrings` (edit)
- `Packages/FontPlaygroundMacKit/Sources/FPAppUI/Shared/ModelText.swift` (new)
- `docs/specs/ui-editing.md` §S3 (edit: the new `MixPalette` content, AGENTS.md "update the spec text")
- `…/Tests/FPAppUITests/LocalizationCatalogTests.swift`, `AccessibilityTextTests.swift`, `ContrastTests.swift`, `KeyboardShortcutTests.swift`, `ModelTextTests.swift`, `PolishOffscreenTests.swift` (new); `PickerTestFaces.swift` (edit: eventual deadline), `MainWindowGeometryTests.swift` (edit: corrected minimum height), `SourceLintTests.swift` (edit: add L1, L2, L4, L8, L9)

### Design

**D1. VoiceOver names (UI-13).** The table says what VoiceOver must announce. Labels are strings in the owning area's text type, so they can be tested. ui-editing.md already fixes several of them (for example `RecipeText.moreActionsAccessibilityLabel`); those win where they differ.

| Control | Role / trait | Label | Value / hint | Owner |
|---|---|---|---|---|
| Recipe card "more" menu | menu button | "More actions for %@" (the family) | — | 502 |
| Recipe card colour dot | image | "Colour %lld in Colour by Font" (ui-editing) | — | 502 |
| Recipe card | group (`.accessibilityElement(children: .contain)`) | "%1$@: %2$@" (role, display name; ui-editing) | the "Draws …" sentence | 502 |
| Picker search field | search field | "Search fonts" | — | 503 |
| Picker list | list | "Fonts" | — | 503 |
| Picker row | cell | "%1$@, %2$@, in your font" (family, native name; ui-editing WP-503), leaving out empty parts | help: "Sample: %@" | 503 |
| Picker section header | native heading role on macOS 26+, static text on earlier supported macOS | its title with "·" replaced by "," (for example "All Chinese fonts, 37"; ui-editing WP-503) | — | 503 |
| Preview text | text area | "Preview text" | — | 504 |
| Preview size slider | slider | "Preview size" | value "%lld points" | 504 |
| Colour by Font toggle | toggle | "Colour by Font" | — | 504 |
| Sample Text menu | pop-up button | "Sample Text" | — | 504 |
| Built-font badge | static text | "Showing the built font" | — | 504 |
| Name / Style fields | text field | "Font name" / "Style name" | — | 505 |
| Build progress | progress indicator | "Building your font" | value "%lld percent" | 505 |
| Status line | static text | the status text (the tone icon is hidden) | — | 505 |
| Notice dismiss | button | "Dismiss" | — | 501 |
| Advanced toolbar button | button | "Show Advanced" / "Hide Advanced" | — | 501 |
| Settings + / − | button | "Add Font Folder" / "Remove Selected Folder" | — | 501 |
| Advanced "Drawn by" picker | pop-up button | the script label | value: the current choice | 506 |

Rules:
- Every icon-only control either is an `IconButton` (§S11) or carries an `.accessibilityLabel`.
- Every decorative image is a `DecorativeSymbol` or has `.accessibilityHidden(true)`.
- SwiftUI section headers get `.accessibilityAddTraits(.isHeader)`. The AppKit picker uses the native heading role on macOS 26+, when that API is available; earlier supported systems retain its labelled static-text role. VoiceOver behavior is still verified manually.

**D2. The String Catalog.**

- **Converting strings.** Change every remaining `Text("…")`, `Button("…")` and similar literal in FPAppUI to a text-type member built with `String(localized:…, bundle: .module, comment:)` (lint L1 and L2).
- **Completeness test** (`LocalizationCatalogTests`):
  - **(a)** Every key used in `String(localized: "…"` calls in FPAppUI exists in `Localizable.xcstrings`. For the comparison, both the source key and the catalog key are normalised by replacing every `\(…)` interpolation and every format specifier with one placeholder token.
  - **(b)** Every catalog key is used somewhere, so there are no stale keys.
  - **(c)** Every entry has an `en` string unit with state `translated` and a non-empty value.
  - **(d)** No value contains PC wording. The UI-6 regex is `\bCtrl\b|\bAlt\b|\bEnter\b|Windows|Explorer|Show file|admin rights|right-click`, case-sensitive as written.
- **Info.plist strings.** `App/Resources/InfoPlist.xcstrings` must hold `CFBundleDisplayName`, `CFBundleName` and the five usage descriptions from WP-501 D1.
- **`ModelText`** (`Shared/ModelText.swift`, §S8). `public enum ModelText` with one static function per `EnglishText` function FPAppUI calls (grep `EnglishText.` in `Sources/FPAppUI` when this WP starts; at least `problem(_:in:)`, `glyphWarning(_:)`, `unresolvedSummary(_:)`, `replacementOffer(missing:replacement:)`, `groupLabel(_:)`, `languageLabel(_:)`, `languageShortLabel(_:)`, `samplePresetLabel(_:)`, `weightSwap(_:)`), same parameters, English identical to FPCore's. Each case of a typed value maps to its own catalog key (for example `"Family name is empty."`, `"%@: the font file is no longer there"`); numbers inside are formatted exactly as `EnglishText` does (for example the glyph estimate with "," separators independent of locale). Every call site in FPAppUI is switched to `ModelText`; L9 then forbids `EnglishText.` and `.englishText` in `Sources/FPAppUI`.
- **One weight list.** `WeightChoice.standard` (WP-501/506) and `RecipeText.weightChoices` (WP-502) must list the same `(weight, title)` pairs; if they differ, WP-502's list wins and `WeightChoice.standard` is changed to match.

**D3. Increase Contrast and colour contrast (UI-M4).**

- Apply §S9 to `MixPalette`, keeping its API. Its callers, `RecipeColumn` dots and `PreviewStyler` runs, are unchanged. Update ui-editing.md §S3's listing of `MixPalette` in the same PR, so that "exact content" stays true.
- Any custom stroke uses `MixPalette.cardStroke`.
- `AppModel.increaseContrast` follows `SystemEvent.displayOptionsChanged`. ui-editing.md already lists (AC-504-M1) the case where an AppKit view needs to re-apply dynamic colours when the effective appearance changes.

**D4. Keyboard (UI-6).**

- **Shortcuts.** The §S6 shortcuts are already checked (AC-501-18).
- **Cancel and Return.** Esc and ⌘. cancel a build, through Cancel's `.cancelAction`. They also close the picker (WP-503) and dismiss sheets. Return uses the picker's font (WP-503) and presses the default alert button.
- **Picker keys.** The picker handles ⌘↑/⌘↓, Page Up/Page Down and fn+←/→ before plain ↑/↓. That is the UI-6 verifier's order, and WP-503 tests it.
- **Hints.** Hints name Mac keys: "Return uses it." (WP-503) and "⌘Z brings yours back" (WP-504).
- **Tab order with Full Keyboard Access.** Tab reaches, in this order: the sidebar controls, the preview text, Name, Style, the action bar buttons and links, then the inspector controls. Space activates the focused button. The preview routes Tab and Shift-Tab through the native next/previous key-view loop; marked-text commands remain with the input method. Sidebar, preview, action bar and inspector form focus sections. Physical traversal of the complete hosted view remains a manual check.

**D5. Pointer (UI-M5).** Rule L5 forbids cursor code. The audit also checks that no `.onHover` changes the cursor. Link-style buttons keep whatever cursor the system gives them.

### Acceptance criteria
- **AC-507-1** `LocalizationCatalogTests.everyKeyExistsAndIsUsed` covers (a) and (b) of D2.
- **AC-507-2** `LocalizationCatalogTests.everyEntryIsTranslatedEnglish` covers (c). `infoPlistCatalogHasTheBundleStrings` covers the Info.plist strings in D2.
- **AC-507-3** `LocalizationCatalogTests.ui6NoPCKeyNamesInStrings` covers (d). It also asserts that the picker hint contains "Return" and the sample hint contains "⌘Z". (UI-6)
- **AC-507-4** `SourceLintTests` passes L1, L2 and L4–L9 over all FPAppUI files, including those from WP-502–506, and each new rule's positive snippet is detected and its negative snippet is not. This covers no cursor code (UI-M5), no unlabelled `Image(systemName:)`, no empty `IconButton` label (UI-13), and no direct `EnglishText` use.
- **AC-507-5** `AccessibilityTextTests.ui13LabelsForCustomControls` checks every formatted label in the D1 table with sample arguments. For example: (UI-13)
  - the "more" label for "PingFang SC" is "More actions for PingFang SC";
  - the preview size value for 30 is "30 points";
  - the build progress value for 0.45 is "45 percent";
  - a picker row with an empty native name reads "Helvetica, in your font".
- **AC-507-6** `ContrastTests.uiM4PaletteMeetsTheContrastRules` computes the WCAG ratio for every §S9 rule in all four variants, and each meets its threshold. It ports `test_token_pairs_meet_the_contrast_rule` and `test_contrast_ratio_matches_wcag`, using a WCAG ratio function checked on known pairs: black on white is 21.0, and #777777 on #ffffff is 4.48 ± 0.01. `dynamicColoursFollowTheAppearance`: resolving `MixPalette.colour(forMaterialAt: 1)`, `missingBackground` and `cardStroke` to sRGB inside `NSAppearance(named: n)!.performAsCurrentDrawingAppearance` gives the §S9 value of the matching column for `.aqua` and `.darkAqua` (±1 per 8-bit channel). `everyAppearanceMatchSelectsItsPalette` checks the production provider’s pure mapping of all four match names to dark/contrast flags. High-contrast names cannot be constructed directly; the live system switch remains AC-507-M3. (UI-M4)
  - `uiM4IncreaseContrastSwitchesThePalette`: after `ShellFakeSystemActions` sets `increaseContrast = true` and yields `.displayOptionsChanged`, `app.increaseContrast == true`; `MixPalette.cardStrokeHex(dark: false, increasedContrast: true) == 0x6e6e73`; and `MixPalette.hex(forMaterialAt: 5, dark: true, increasedContrast: false) == 0xf5a25d`.
- **AC-507-7** `KeyboardShortcutTests`: (UI-6)
  - `everyCommandIsReachable`: `AppCommands.menuOrder`, the list the `Commands` body iterates, contains every `MenuCommand` case exactly once, and each case's shortcut equals §S6.
  - `cancelButtonUsesCancelAction`: `ActionBarView.cancelShortcut == .cancelAction`. (`KeyboardShortcut` is `Hashable`.)
  - `primaryHasNoShortcut`: `ActionBarView.primaryShortcut == nil`.
- **AC-507-8** `make lint`, `make mac-test` and `make app` pass.
- **AC-507-9** `ModelTextTests.englishMatchesTheSourceText`: for every `RecipeProblem` case (with sample arguments and a two-material recipe), both `GlyphWarning` cases, a `LoadReport` with one and with two unresolved materials, every `ScriptGroup`, every `Languages.all` id, every `Samples.presets` id and one `WeightSwap` in each direction, `ModelText.f(x) == EnglishText.f(x)` under the `en` catalog; and for `.noAccess`, `.folderMissing` and `.folderUnreadable`, `ModelText.catalogIssue(x) == x.englishText`. No `EnglishText.` or `.englishText` remains in `Sources/FPAppUI` (L9, AC-507-4).
- **AC-507-10** `ModelTextTests.weightListsAgree`: `WeightChoice.standard.map { ($0.weight, $0.title) }` equals `RecipeText.weightChoices`.
- **AC-507-M1** (manual, macos) VoiceOver. (UI-13)
  1. Turn VoiceOver on (⌘F5) and walk the main window with VO-→.
  2. Every row of the D1 table is announced with its label, and its value where one is given.
  3. Attach screenshots of the VoiceOver caption panel for the card "more" button, the preview size slider and a picker row.
  4. No control is announced only as "button" or by a symbol name.
- **AC-507-M2** (manual, macos) Keyboard only. (UI-6)
  1. Turn on System Settings › Keyboard › Keyboard navigation.
  2. Without the pointer, do all of the following:
     - press ⌘F, type "Helvetica", and press Return;
     - choose Font › Add Font For › Chinese (Simplified) using ⌃F2 to reach the menu bar;
     - type a name in Name;
     - press ⇧⌘S and save;
     - press ⌥⌘I, then Tab through the inspector's pickers;
     - press Esc to close the picker when it is open.
  3. Write the steps and their results in the PR.
- **AC-507-M3** (manual, macos) Increase Contrast. (UI-M4)
  1. Turn on System Settings › Accessibility › Display › Increase contrast.
  2. Take light and dark screenshots of the recipe column with Colour by Font on and a missing character in the preview.
  3. The colours and strokes are visibly stronger than in screenshots taken with the setting off.
- **AC-507-M4** (manual, macos) Pointer. (UI-M5) Hover over every button, chip, menu button and toggle in the main window, the inspector and Settings. The cursor stays the arrow; links may show the pointing hand.
- **AC-507-M5** (manual, macos) Input methods. This is the UI-17 release check.
  1. With Pinyin, type "nihao" in the picker search and in the preview.
  2. Pressing ↑/↓ in the candidate window does not move the picker selection.
  3. Committing inserts 你好.

### Implementation clarifications

- AppKit exposes its native heading accessibility role starting in macOS 26. Picker section headers use it there, retaining labelled static text on macOS 14/15; SwiftUI headers keep their header trait.
- The native sidebar's initial ideal is 280 pt and the minimum window height is 480 pt. Measurements found a 320-pt sidebar plus the 360-pt detail imposed a 680-pt minimum, violating the half-screen requirement; the compact ideal preserves the 640-pt width. The action-bar inset now declares its own minimum width to prevent zero-width paragraph measurement from inflating the minimum height past 1200 pt. All notes remain complete.
- The integrated UI suite uses a five-second eventual deadline in `PickerTestFaces`; debounce assertions and measured performance thresholds are unchanged. This accommodates concurrent main-actor test scheduling.
- The high-contrast dynamic-resolution test is corrected to the AppKit-supported `bestMatch` contract in S9: all four mappings and WCAG palettes are tested, with native resolution for Aqua/Dark Aqua and live Increase Contrast reserved for manual acceptance.
- The preview's Tab/Shift-Tab commands follow the native key-view loop, with marked-text handling preserved. Dedicated font/style/progress accessibility labels and values supplement visible captions.
- `PolishOffscreenTests.integratedWindowFitsMinimumAndNormalSizes` always verifies the production hosting options, native minimum and descendant split bounds in four size/appearance combinations. Optional `FP_POLISH_SNAPSHOT_DIR` exports supplemental off-screen main-window body renders at minimum and normal sizes in light and dark variants. These are supplemental clipping evidence, not completion of manual VoiceOver, input-method or keyboard acceptance criteria.

### Verification
```bash
make lint
make mac-test
make app
make test
```

### Notes for the implementer
- **Automated checks first.** Start with the lint and catalog tests: they find most gaps mechanically. Then do the manual VoiceOver pass. SwiftUI's accessibility tree can't be inspected offscreen (see the WP-501 notes).
- **FPCore values go through `ModelText`; engine data does not.** Typed FPCore values get catalog strings (§S8). Engine data (report warnings, licence note texts, helper messages, `unsupportedReason`) is shown as given, never through `String(localized:)`.
- **Changing `MixPalette`.** It changes a file ui-editing.md calls "exact content". Update ui-editing.md §S3 in the same PR (AGENTS.md: update the spec text when you deviate).

---

## Finding → acceptance criteria

| Finding | ACs |
|---|---|
| UI-2 | AC-501-18, AC-501-19, AC-501-M3 |
| UI-3 | AC-501-1, AC-501-2, AC-501-M3 |
| UI-4 | AC-501-20, AC-501-M1 |
| UI-11 | AC-501-24, AC-501-M4, AC-505-16 |
| UI-15 | AC-501-23, AC-501-26, AC-501-M6, AC-506-10, AC-506-M2 |
| CRIT-8 | AC-501-21, AC-501-M2, AC-505-M6 |
| UI-9 | AC-505-17, AC-505-M2 |
| UI-10 | AC-501-22, AC-505-14, AC-505-M3, AC-505-M5 |
| UI-M3 | AC-505-4, AC-505-14 (`.hiddenName`) |
| UI-M7 | AC-505-20, AC-505-M2 |
| UI-M8 | AC-505-23, AC-501-33, AC-505-M4 |
| INSTALL-13 | AC-505-14, AC-505-16 |
| UI-13 | AC-507-4, AC-507-5, AC-507-M1 |
| UI-M4 | AC-507-6, AC-501-33, AC-507-M3 |
| UI-6 | AC-501-18, AC-507-3, AC-507-7, AC-507-M2 |
| CRIT-2 (UI side; closed by WP-305) | AC-501-3, AC-501-9, AC-501-13, AC-501-25 |
| INSTALL-6 (UI side; closed by WP-401/403) | AC-505-8, AC-505-11, AC-505-15 |

## Test porting map (reference `tests/test_app.py`, `tests/test_theme.py`)

| Reference test | Destination |
|---|---|
| test_app.py: test_preference_helpers_fall_back_to_defaults | AC-501-3 `SettingsStoreTests.invalidValuesFallBackToDefaults` |
| test_trial_text_says_what_is_being_tried | WP-503 (ui-editing.md AC-503-30) |
| test_starts_empty_and_scans_into_the_picker_catalog | AC-501-6 (plus WP-503 for the picker) |
| test_main_font_then_the_prompt_then_a_chinese_font, test_the_preview_tries_the_current_font_and_forgets_it_on_cancel, test_change_replaces_a_font_in_place | WP-502/503/504 |
| test_install_end_to_end_then_update | AC-505-8, AC-505-10 |
| test_building_locks_the_recipe_and_closes_the_picker | AC-505-6 (plus AC-501-5 for the seam) |
| test_start_over_clears_the_recipe | AC-501-17 |
| test_advanced_opens_one_dialog | AC-506-10 |
| test_theme_choice_retints_every_part_and_persists | AC-501-4 (appearance applied and saved; native colours need no retint) |
| test_preview_preferences_persist | AC-501-4 (storage); WP-504 (view) |
| test_the_recipe_is_restored_after_the_scan | AC-501-8 |
| test_closing_during_a_scan_keeps_the_stored_recipe | AC-501-10 |
| test_malformed_settings_do_not_break_startup | AC-501-11 |
| test_close_while_building_asks_first | AC-501-22, AC-505-M5 |
| test_rescan_keeps_the_recipe | AC-501-14 |
| test_the_menu_has_every_action | AC-501-18 |
| test_theme.py: test_token_pairs_meet_the_contrast_rule, test_contrast_ratio_matches_wcag | AC-507-6 |
| test_mix_colours_repeat_every_four_fonts | AC-501-5 |
| test_templates_have_no_hardcoded_colours_and_render_in_both_themes | AC-501-29 (rule L6) |
| test_themes_have_the_same_lowercase_tokens, test_palette_comes_from_the_tokens, test_placeholder_html_uses_the_muted_token, test_render_rejects_an_unknown_token, test_tint_and_retint, test_manager_* | not ported (no custom palette or theme manager; the system appearance is used) |
