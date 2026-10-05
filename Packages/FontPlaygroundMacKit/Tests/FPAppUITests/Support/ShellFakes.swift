import AppKit
import CoreText
import FPCore
import FPEngineClient
import FPMacServices
import Foundation

@testable import FPAppUI

struct ShellTestError: LocalizedError, Sendable {
    var errorDescription: String?; init(_ message: String) { errorDescription = message }
}
final class ShellFakeEngine: EngineRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<EngineHello, EngineError> = .success(
        EngineHello(
            fpengineVersion: "0.1.0", python: "3.12", fonttools: "4", platform: "darwin",
            capabilities: ["scan", "forge"]))
    private var calls = 0
    private var requests: [ForgeRequest] = []
    private var continuation: AsyncThrowingStream<ForgeEvent, any Error>.Continuation?
    private var didCancel = false
    private var stopDelay: TimeInterval = 0
    /// Holds the cancelling thread inside `onTermination`, as `HelperRun.cancel()` does until the helper has exited
    /// (NATIVE-7): up to `terminationGrace` plus SIGKILL and reaping when the helper ignores SIGTERM.
    var terminationDelay: TimeInterval {
        get { lock.withLock { stopDelay } }
        set { lock.withLock { stopDelay = newValue } }
    }
    var helloResult: Result<EngineHello, EngineError> {
        get { lock.withLock { result } }
        set { lock.withLock { result = newValue } }
    }
    var helloCalls: Int { lock.withLock { calls } }
    var forgeRequests: [ForgeRequest] { lock.withLock { requests } }
    var cancelled: Bool { lock.withLock { didCancel } }
    func hello() async throws -> EngineHello {
        try lock.withLock {
            calls += 1; return try result.get()
        }
    }
    func scan(files: [String]) -> AsyncThrowingStream<ScanEvent, any Error> { AsyncThrowingStream { $0.finish() } }
    func forge(_ request: ForgeRequest) -> AsyncThrowingStream<ForgeEvent, any Error> {
        AsyncThrowingStream { c in
            lock.withLock {
                requests.append(request); continuation = c
            }
            c.onTermination = { [weak self] state in
                guard case .cancelled = state else { return }
                if let delay = self?.terminationDelay, delay > 0 { Thread.sleep(forTimeInterval: delay) }
                self?.lock.withLock { self?.didCancel = true }; c.finish()
            }
        }
    }
    func emitProgress(_ stage: EngineStage, _ fraction: Double, materialIndex: Int? = nil) {
        let c = lock.withLock { continuation };
        c?.yield(.progress(.init(stage: stage, fraction: fraction, materialIndex: materialIndex)))
    }
    func finish(report: ForgeReport) throws {
        let (request, c) = lock.withLock { (requests.last, continuation) }
        if let request { try AtomicFile.write(Data([0, 1, 2, 3]), to: request.outputPath) }
        c?.yield(.finished(report)); c?.finish()
    }
    func fail(_ error: EngineError) { lock.withLock { continuation }?.finish(throwing: error) }
    func endWithoutResult() { lock.withLock { continuation }?.finish() }
}
actor ShellFakeCatalog: FontCataloging {
    private var snapshot = CatalogSnapshot.empty
    private var folders: [URL] = []
    private var listeners: [UUID: AsyncStream<CatalogSnapshot>.Continuation] = [:]
    private var waiting: [UUID: CheckedContinuation<CatalogSnapshot, any Error>] = [:]
    private(set) var refreshModes: [RefreshMode] = []
    private(set) var folderCalls: [[URL]] = []
    private(set) var callOrder: [String] = []
    private(set) var installedCalls: [URL] = []
    private var noteInstalledError: (any Error)?
    func scriptNoteInstalledError(_ error: (any Error)?) { noteInstalledError = error }
    private(set) var removedCalls: [URL] = []
    private(set) var startObservingCalls = 0
    private(set) var stopObservingCalls = 0
    func currentSnapshot() -> CatalogSnapshot { snapshot }
    func extraFolders() -> [URL] { folders }
    func snapshots() -> AsyncStream<CatalogSnapshot> {
        let id = UUID(), stream = AsyncStream<CatalogSnapshot>.makeStream()
        listeners[id] = stream.continuation; stream.continuation.yield(snapshot)
        stream.continuation.onTermination = { [weak self] _ in Task { await self?.removeListener(id) } }
        return stream.stream
    }
    private func removeListener(_ id: UUID) { listeners[id] = nil }
    func setExtraFolders(_ value: [URL]) { folders = value; folderCalls.append(value); callOrder.append("folders") }
    func refresh(_ mode: RefreshMode) async throws -> CatalogSnapshot {
        refreshModes.append(mode); callOrder.append("refresh")
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { c in waiting[id] = c }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }
    private func cancel(_ id: UUID) { waiting.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
    func cancelRefresh() {
        let pending = waiting; waiting = [:]; for c in pending.values { c.resume(throwing: CancellationError()) }
    }
    func publish(_ value: CatalogSnapshot) { snapshot = value; for c in listeners.values { c.yield(value) } }
    func finishRefresh(with value: CatalogSnapshot) {
        publish(value); let pending = waiting; waiting = [:]; for c in pending.values { c.resume(returning: value) }
    }
    func failRefresh(_ error: any Error) {
        let pending = waiting; waiting = [:]; for c in pending.values { c.resume(throwing: error) }
    }
    func noteInstalled(_ fileURL: URL) throws -> CatalogSnapshot {
        installedCalls.append(fileURL); if let noteInstalledError { throw noteInstalledError }; return snapshot
    }
    func noteRemoved(_ fileURL: URL) -> CatalogSnapshot { removedCalls.append(fileURL); return snapshot }
    func startObservingSystemChanges() { startObservingCalls += 1 }
    func stopObservingSystemChanges() { stopObservingCalls += 1 }
}
enum ShellSnapshot {
    static func make(
        faces: [FaceRecord] = [], isComplete: Bool = true, scanning: Bool = false, generation: Int = 1,
        issues: [CatalogIssue] = []
    ) -> CatalogSnapshot {
        var counts = CatalogCounts(); counts.faces = faces.count
        return CatalogSnapshot(
            generation: generation, faces: faces, annotations: [:], counts: counts, issues: issues,
            isComplete: isComplete,
            activity: scanning ? .refreshing(CatalogProgress(filesDone: 1, filesTotal: 2)) : .idle)
    }
}
final class ShellFakeRenderer: FontRendering, @unchecked Sendable {
    func font(for request: FaceRenderRequest) throws -> RenderedFont {
        make(url: URL(fileURLWithPath: request.face.path), size: request.pointSize)
    }
    func builtFont(at url: URL, pointSize: CGFloat) throws -> RenderedFont { make(url: url, size: pointSize) }
    private func make(url: URL, size: CGFloat) -> RenderedFont {
        RenderedFont(
            ctFont: CTFontCreateUIFontForLanguage(.system, size, nil)!, fileURL: url, postscriptName: "ShellSystem",
            pointSize: size)
    }
    func hasGlyph(for scalar: Unicode.Scalar, in font: RenderedFont) -> Bool { true }
    func missingScalars(in text: String, for font: RenderedFont) -> [Unicode.Scalar] { [] }
    func coverage(of font: RenderedFont) -> CodepointSet { CodepointSet(scalarsOf: "abc") }
    func invalidate(path: String) {}
    func invalidateAll() {}
}
actor ShellFakeInstaller: FontInstalling {
    var conflicts: [InstallConflict] = [.noConflict]
    var conflictError: (any Error)?
    var onConflict: (@Sendable () -> Void)?
    func scriptConflictError(_ error: (any Error)?) { conflictError = error }
    func observeConflict(_ action: @escaping @Sendable () -> Void) { onConflict = action }
    var installResult: Result<InstalledFont, any Error> = .failure(ShellTestError("No scripted install result"))
    var uninstallResult: Result<UninstallOutcome, any Error> = .success(.notInstalled)
    private(set) var queries: [InstallQuery] = []
    private(set) var installs: [(URL, InstallQuery, InstallConflict?)] = []
    private(set) var uninstalls: [InstalledFont] = []
    func scriptConflicts(_ values: [InstallConflict]) { conflicts = values }
    func scriptInstall(_ result: Result<InstalledFont, any Error>) { installResult = result }
    func scriptUninstall(_ result: Result<UninstallOutcome, any Error>) { uninstallResult = result }
    func conflict(for query: InstallQuery) throws -> InstallConflict {
        onConflict?(); queries.append(query); if let conflictError { throw conflictError };
        return conflicts.count > 1 ? conflicts.removeFirst() : (conflicts.first ?? .noConflict)
    }
    func install(_ source: URL, expecting query: InstallQuery, confirmed: InstallConflict?) throws -> InstalledFont {
        installs.append((source, query, confirmed))
        switch installResult {
        case .success(let font):
            try AtomicFile.write(Data(contentsOf: source), to: font.fileURL.path); return font
        case .failure(let error):
            if case InstallError.previousCopyNotRemoved(let font, _, _) = error {
                try AtomicFile.write(Data(contentsOf: source), to: font.fileURL.path)
            }
            throw error
        }
    }
    func uninstall(_ font: InstalledFont) throws -> UninstallOutcome {
        uninstalls.append(font); return try uninstallResult.get()
    }
    func installedFonts() -> [InstalledFont] { [] }
}
@MainActor final class ShellFakeSystemActions: SystemActions {
    var isAppActive = true
    var increaseContrast = false
    var isFontBookAvailable = true
    let events: AsyncStream<SystemEvent>
    let continuation: AsyncStream<SystemEvent>.Continuation
    var appearances: [AppSettings.Appearance] = []
    var revealed: [[URL]] = []
    var openFontBookCalls = 0
    var openedInFontBook: [URL] = []
    var openedURLs: [URL] = []
    var attentionCalls = 0
    var badges: [String?] = []
    var startedActivities: [(ActivityToken, String)] = []
    var endedActivities: [ActivityToken] = []
    var credits: [String] = []
    var copied: [String] = []
    init() {
        let stream = AsyncStream<SystemEvent>.makeStream(); events = stream.stream; continuation = stream.continuation
    }
    func send(_ event: SystemEvent) { continuation.yield(event) }
    func applyAppearance(_ appearance: AppSettings.Appearance) { appearances.append(appearance) }
    func reveal(_ urls: [URL]) { revealed.append(urls) }
    func openFontBook() { openFontBookCalls += 1 }
    func openInFontBook(_ file: URL) { openedInFontBook.append(file) }
    func openURL(_ url: URL) { openedURLs.append(url) }
    func requestAttention() { if !isAppActive { attentionCalls += 1 } }
    func setDockBadge(_ text: String?) { badges.append(text) }
    func beginActivity(reason: String) -> ActivityToken {
        let token = ActivityToken(); startedActivities.append((token, reason)); return token
    }
    func endActivity(_ token: ActivityToken) { endedActivities.append(token) }
    func showAboutPanel(credits: String) { self.credits.append(credits) }
    func copyToPasteboard(_ text: String) { copied.append(text) }
    var runningLanguage = "en"
    var systemLanguages = ["en-US"]
    var languageOverride: [String]?
    var overrides: [[String]?] = []
    var terminateCalls = 0
    var relaunchCalls = 0
    func setLanguageOverride(_ languages: [String]?) { languageOverride = languages; overrides.append(languages) }
    func terminate() { terminateCalls += 1 }
    func relaunchAfterExit() { relaunchCalls += 1 }
}
@MainActor final class ShellFakeFilePanels: FilePanels {
    var saveAnswers: [URL?] = []
    var folderAnswers: [[URL]] = []
    var saveRequests: [SavePanelRequest] = []
    var folderRequests: [FolderPanelRequest] = []
    func chooseSaveLocation(_ request: SavePanelRequest) -> URL? {
        saveRequests.append(request); return saveAnswers.isEmpty ? nil : saveAnswers.removeFirst()
    }
    func chooseFolders(_ request: FolderPanelRequest) -> [URL] {
        folderRequests.append(request); return folderAnswers.isEmpty ? [] : folderAnswers.removeFirst()
    }
}
final class ShellFakeFileProbe: FileSystemProbe, @unchecked Sendable {
    private let lock = NSLock()
    private var kinds: [String: FileKind] = [:]
    func set(_ url: URL, _ kind: FileKind) { lock.withLock { kinds[url.standardized.path] = kind } }
    func kind(of path: String) -> FileKind {
        lock.withLock { kinds[URL(fileURLWithPath: path).standardized.path] ?? .missing }
    }
}
final class ShellFileWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var writes: [URL: Int] = [:]
    private var failure: (any Error)?
    var error: (any Error)? {
        get { lock.withLock { failure } }
        set { lock.withLock { failure = newValue } }
    }
    func count(_ url: URL) -> Int { lock.withLock { writes[url, default: 0] } }
    func write(_ data: Data, to url: URL) throws {
        try lock.withLock {
            writes[url, default: 0] += 1; if let failure { throw failure }; try AtomicFile.write(data, to: url.path)
        }
    }
}
final class ShellSweepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(URL, [URL], Date)] = []
    var calls: [(URL, [URL], Date)] { lock.withLock { values } }
    func sweep(_ url: URL, _ outputs: [URL], _ now: Date) -> Int {
        lock.withLock { values.append((url, outputs, now)) }; return 0
    }
}
extension AppServices {
    @MainActor static func testing(
        root: URL, defaults: UserDefaults, renderer: (any FontRendering)? = nil, catalog: (any FontCataloging)? = nil
    ) -> AppServices {
        let writer = ShellFileWriter(), sweep = ShellSweepRecorder()
        return AppServices(
            engine: ShellFakeEngine(), catalog: catalog ?? ShellFakeCatalog(),
            renderer: renderer ?? ShellFakeRenderer(), installer: ShellFakeInstaller(),
            system: ShellFakeSystemActions(), panels: ShellFakeFilePanels(), fileProbe: ShellFakeFileProbe(),
            paths: .rooted(at: root), defaults: defaults, now: { Date() }, writeFile: { try writer.write($0, to: $1) },
            sweepHelperLeftovers: { sweep.sweep($0, $1, $2) })
    }
}
@MainActor final class ShellRig {
    let temp: ShellTempDirectory
    let engine = ShellFakeEngine()
    let catalog = ShellFakeCatalog()
    let system = ShellFakeSystemActions()
    let probe = ShellFakeFileProbe()
    let writer = ShellFileWriter()
    let sweep = ShellSweepRecorder()
    var services: AppServices {
        var s = AppServices.testing(root: temp.url, defaults: temp.defaults, catalog: catalog)
        s.engine = engine; s.system = system; s.fileProbe = probe
        s.writeFile = { [writer] in try writer.write($0, to: $1) };
        s.sweepHelperLeftovers = { [sweep] in sweep.sweep($0, $1, $2) }
        return s
    }
    init() throws { temp = try ShellTempDirectory() }
    func ready(_ model: AppModel, faces: [FaceRecord] = []) async {
        await model.start(); await shellEventually { await self.catalog.refreshModes.count == 1 }
        await catalog.finishRefresh(with: ShellSnapshot.make(faces: faces))
        await shellEventually { model.launchPhase == .ready }
    }
}
