import FPCore
import FPEngineClient
import FPMacServices
import Observation
import SwiftUI

public enum LaunchPhase: Equatable, Sendable { case starting, loadingFonts, ready }
public enum EngineStatus: Equatable, Sendable { case unknown, available(EngineHello), unavailable(String) }
public struct CatalogStatus: Equatable, Sendable {
    public struct Unreadable: Equatable, Sendable {
        public var path: String
        public var message: String
        public init(path: String, message: String) { self.path = path; self.message = message }
    }
    public var isScanning = false
    public var done = 0
    public var total = 0
    public var faceCount = 0
    public var unreadable: [Unreadable] = []
    public var hiddenCount = 0
    public var duplicateCount = 0
    public init() {}
}
@MainActor @Observable public final class AppModel {
    public let services: AppServices
    public let settings: SettingsStore
    public let build: BuildController
    public let renderer: any FontRendering
    @ObservationIgnored let previewController = PreviewController()
    public var recipe: Recipe { didSet { recipeDidChange(from: oldValue) } }
    public private(set) var analysis: RecipeAnalysis
    public internal(set) var catalogFaces: [FaceRecord] = []
    public internal(set) var catalogStatus = CatalogStatus()
    public var isBuilding = false {
        didSet { if isBuilding { pickRequest = nil; trial = nil } else { runDeferredReconcile() } }
    }
    public var pickRequest: PickRequest?
    let picker = PickerModel()
    var platformPreferredNames: [String: String] = [:]
    @ObservationIgnored var platformFontLookup: (@Sendable ([String: String]) async -> [String: String])? = nil
    public var trial: PreviewTrial?
    public var builtFont: BuiltFontPreview?
    public var previewPointSize: Int { didSet { if oldValue != previewPointSize { schedulePreferenceSave() } } }
    public var colourByFont: Bool { didSet { if oldValue != colourByFont { schedulePreferenceSave() } } }
    public private(set) var launchPhase: LaunchPhase = .starting
    public private(set) var engineStatus: EngineStatus = .unknown
    public private(set) var increaseContrast: Bool
    public internal(set) var interfaceLanguage: InterfaceLanguage
    /// Set by Quit and Reopen; cleared when the quit is cancelled (localisation.md D5).
    public internal(set) var relaunchRequested = false
    public private(set) var folderIssues: [String: String] = [:]
    public var notices: [AppNotice] = []
    public var alert: AlertContent?
    /// Quit and Reopen after a language change; Settings presents it (localisation.md D5).
    public var languagePrompt: AlertContent?
    public var sheet: SheetContent?
    public var inspectorPresented: Bool {
        didSet { settings.inspectorPresented = inspectorPresented }
    }
    public var sidebarVisibility: NavigationSplitViewVisibility = .automatic
    @ObservationIgnored private var mainWindowContentWidth: Double?
    /// Set by the main window: runs the presentation after the sidebar collapse is laid out, keeping the window's frame.
    @ObservationIgnored var presentInspector: ((@escaping @MainActor () -> Void) -> Void)?
    @ObservationIgnored var inspectorPending = false
    @ObservationIgnored var launchTask: Task<Void, Never>?
    @ObservationIgnored var helloTask: Task<Void, Never>?
    @ObservationIgnored var observationTask: Task<Void, Never>?
    @ObservationIgnored var systemTask: Task<Void, Never>?
    @ObservationIgnored var autosaveTask: Task<Void, Never>?
    @ObservationIgnored var preferenceTask: Task<Void, Never>?
    @ObservationIgnored var autosavePending = false
    @ObservationIgnored var preferencesPending = false
    @ObservationIgnored var autosaveFailureReported = false
    @ObservationIgnored var restorationWarnings: [String] = []
    @ObservationIgnored var pendingDocument: RecipeDocument?
    @ObservationIgnored var pendingLegacy: Data?
    @ObservationIgnored var legacySettingsImported = false
    @ObservationIgnored var handledGeneration = -1
    @ObservationIgnored var deferredSnapshot: CatalogSnapshot?
    @ObservationIgnored var terminated = false
    func updateMainWindowContentWidth(_ width: Double) {
        guard width.isFinite && width > 0 else { return }
        mainWindowContentWidth = width
        if inspectorPresented { makeRoomForInspector() }
    }
    func presentAdvanced() {
        guard !inspectorPresented, !inspectorPending else { return }
        makeRoomForInspector()
        guard let presentInspector else { inspectorPresented = true; return }
        // WP-701 finding H: collapsing the sidebar and presenting the inspector in one update left the
        // inspector collapsed at half-screen width until an unrelated update.
        inspectorPending = true
        presentInspector { [weak self] in
            guard let self, self.inspectorPending else { return }
            self.inspectorPending = false; self.inspectorPresented = true
        }
    }
    func hideAdvanced() { inspectorPending = false; inspectorPresented = false }
    private func makeRoomForInspector() {
        guard let mainWindowContentWidth,
            mainWindowContentWidth < MainWindowGeometry.minWidthWithSidebarAndInspector,
            sidebarVisibility != .detailOnly
        else { return }
        // UI-15: collapse before presentation; native minimum-size propagation otherwise widens the window first.
        sidebarVisibility = .detailOnly
    }
    public init(services: AppServices) {
        self.services = services
        settings = SettingsStore(defaults: services.defaults, probe: services.fileProbe)
        renderer = services.renderer; build = BuildController()
        let empty = Recipe(); recipe = empty; analysis = empty.analyze()
        previewPointSize = settings.value.previewPointSize; colourByFont = settings.value.colourByFont
        inspectorPresented = settings.inspectorPresented; increaseContrast = services.system.increaseContrast
        interfaceLanguage = InterfaceLanguage(override: services.system.languageOverride)
        services.system.applyAppearance(settings.value.appearance)
        build.app = self
        let dropped = settings.loadIssues.compactMap { issue -> String? in
            if case .droppedFolder(let path, _) = issue { return path }
            AppLog.app.notice("A saved setting was reset: \(String(describing: issue), privacy: .public)")
            return nil
        }
        if !dropped.isEmpty { postBadFolders(dropped) }
    }
    @discardableResult public func edit(_ change: (inout Recipe) -> Void) -> Bool {
        guard !isBuilding else { return false }
        var changed = recipe; change(&changed)
        guard changed != recipe else { return false }
        recipe = changed; return true
    }
    func recipeDidChange(from old: Recipe) {
        guard old != recipe else { return }
        analysis = recipe.analyze()
        if launchPhase == .ready { scheduleAutosave() }
    }
    // State transitions live beside private setters; workflow code stays in focused extensions.
    func setLaunchPhase(_ phase: LaunchPhase) { launchPhase = phase }
    func setEngineStatus(_ status: EngineStatus) { engineStatus = status }
    func setFolderIssues(_ issues: [String: String]) { folderIssues = issues }
    public func displayOptionsChanged() { increaseContrast = services.system.increaseContrast }
    public var commandState: CommandState {
        CommandState(
            recipe: recipe, isBuilding: isBuilding, catalogIsEmpty: catalogFaces.isEmpty,
            isScanning: catalogStatus.isScanning, engineStatus: engineStatus, previewPointSize: previewPointSize,
            colourByFont: colourByFont, inspectorPresented: inspectorPresented, helpAvailable: services.helpURL != nil,
            donateAvailable: services.donateURL != nil, build: build.commands)
    }
}
