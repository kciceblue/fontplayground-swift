import FPCore
import FPEngineClient
import FPMacServices
import Foundation
import Observation

@MainActor @Observable public final class BuildController {
    weak var app: AppModel?
    public private(set) var state: BuildState = .idle { didSet { app?.isBuilding = state.isBusy } }
    public private(set) var result: BuildResult?
    public private(set) var installed: InstalledRecord?
    public private(set) var pendingRemoval: InstalledFont?
    public private(set) var savedURL: URL?
    public private(set) var notice: String?
    public internal(set) var lastReport: ForgeReport?
    public internal(set) var lastErrorDetail: String?
    public private(set) var nameFocusRequest = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var runID = UUID()
    @ObservationIgnored private var outputURL: URL?
    @ObservationIgnored private var activity: ActivityToken?
    @ObservationIgnored private var pendingOperation = false
    public init() {}

    public var isFresh: Bool {
        guard let result, let app else { return false }
        return FileManager.default.fileExists(atPath: result.url.path) && result.spec == app.recipe.forgeSpec()
    }
    public var isStale: Bool { result != nil && !isFresh }
    public var isUpdate: Bool {
        installed != nil && (result == nil || !isFresh || installed?.resultID != result?.id || pendingRemoval != nil)
    }
    public var isBusy: Bool { state.isBusy }
    public var shownFile: URL? { state == .saved ? savedURL : (installed?.font.fileURL ?? savedURL) }
    public var snapshot: BuildControllerSnapshot {
        .init(
            state: state, isFresh: isFresh, isUpdate: isUpdate, installedFullName: installed?.font.fullName,
            savedPath: savedURL?.path, hasShownFile: shownFile != nil, notice: notice,
            notesCount: Set((lastReport?.warnings ?? []) + (lastReport?.licenceNotes.map(\.text) ?? [])).count)
    }
    public var licenceLines: [String] {
        if isFresh, let result { return result.report.licenceNotes.map(\.text) }
        return LicenceNotes.lines(for: app?.recipe.materials.filter(\.isAvailable).map(\.face) ?? [])
    }
    public var problem: String? {
        guard let app else { return nil }
        return NameValidation.problem(family: app.recipe.names.family, style: app.recipe.names.style)
            ?? app.analysis.validity.map { ModelText.problem($0, in: app.recipe) }
    }
    public var engineMissing: Bool { if case .unavailable = app?.engineStatus { true } else { false } }
    public var actionBarState: ActionBarState {
        .make(
            problem: problem, engineMissing: engineMissing,
            glyphWarning: app?.analysis.glyphWarning.map(ModelText.glyphWarning), build: snapshot,
            licenceLines: licenceLines, fontBookAvailable: app?.services.system.isFontBookAvailable ?? false,
            home: NSHomeDirectory())
    }
    public var commands: BuildCommands {
        let bar = actionBarState
        return .init(
            canSaveCopy: bar.saveCopyEnabled, canInstall: bar.primaryEnabled,
            canShowInFinder: shownFile != nil,
            canOpenInFontBook: state == .saved && isFresh && (app?.services.system.isFontBookAvailable ?? false),
            canUninstall: installed != nil && !isBusy,
            installTitle: isUpdate ? BuildText.update : BuildText.install)
    }
    private var mayStart: Bool {
        !isBusy && !pendingOperation && app?.analysis.canForge == true && problem == nil && !engineMissing
    }

    public func install() {
        guard mayStart, let app else { return }
        let spec = app.recipe.forgeSpec()
        operation { id in
            var prior = self.state
            if self.pendingRemoval != nil {
                let removalOnly = self.isFresh && self.installed?.resultID == self.result?.id
                guard await self.removePrevious(id: id, notify: removalOnly) else { return }
                if removalOnly { return }
                prior = self.state
            }
            let names = app.recipe.names
            let query = InstallQuery(
                family: Naming.cleanName(names.family), style: Naming.cleanName(names.style),
                postscriptName: Naming.postscriptName(family: names.family, style: names.style))
            do {
                let conflict = try await app.services.installer.conflict(for: query)
                guard self.current(id), app.recipe.forgeSpec() == spec else { return }
                if case .replaceOurs(let font) = conflict, font.fileURL == self.installed?.font.fileURL {
                    await self.continueInstall(confirmed: conflict, prior: prior, id: id)
                } else if conflict == .noConflict {
                    await self.continueInstall(confirmed: nil, prior: prior, id: id)
                } else {
                    self.present(conflict, prior: prior, spec: spec, id: id)
                }
            } catch { if self.current(id) { self.fail(BuildText.installError(error.localizedDescription)) } }
        }
    }
    private func present(_ conflict: InstallConflict, prior: BuildState, spec: ForgeSpec, id: UUID) {
        guard let app, current(id) else { return }
        state = prior
        app.alert = ConflictText.alert(
            for: conflict, onChangeName: { [weak self] in self?.nameFocusRequest += 1 },
            onConfirm: { [weak self] in
                guard let self, self.current(id), self.mayStart else { return }
                // A confirmation applies to the name and recipe it described, never to later edits.
                guard self.app?.recipe.forgeSpec() == spec else { self.install(); return }
                self.operation { next in await self.continueInstall(confirmed: conflict, prior: prior, id: next) }
            })
    }
    private func continueInstall(confirmed: InstallConflict?, prior: BuildState, id: UUID) async {
        if !isFresh { guard await forge(intent: .install, id: id) else { return } }
        guard current(id), let result, let app else { return }
        enter(.installing)
        let report = result.report
        do {
            let font = try await app.services.installer.install(
                result.url,
                expecting: .init(
                    family: report.familyName, style: report.styleName,
                    postscriptName: report.postscriptName, fullName: report.fullName), confirmed: confirmed)
            guard current(id) else { return }
            let previous = installed
            installed = .init(font: font, resultID: result.id)
            await noteInstalled(font, id: id)
            guard current(id) else { return }
            if let previous, previous.font.fullName.caseInsensitiveCompare(font.fullName) != .orderedSame {
                pendingRemoval = previous.font; _ = await removePrevious(id: id)
            } else {
                state = .installed; attention()
            }
        } catch InstallError.conflict(let conflict) {
            present(conflict, prior: prior, spec: result.spec, id: id)
        } catch InstallError.previousCopyNotRemoved(let new, let old, let message) {
            guard current(id) else { return }
            installed = .init(font: new, resultID: result.id); pendingRemoval = old
            await noteInstalled(new, id: id)
            if current(id) { fail(BuildText.replaceError(new.fullName, old.fullName, message)) }
        } catch { if current(id) { fail(BuildText.installError(error.localizedDescription)) } }
    }
    private func noteInstalled(_ font: InstalledFont, id: UUID) async {
        guard let app else { return }
        do { _ = try await app.services.catalog.noteInstalled(font.fileURL) } catch {
            // Installation succeeded; expose the incremental scan failure without pretending the copy failed.
            if current(id) {
                app.postNotice(
                    .init(
                        kind: .engineUnavailable,
                        text: BuildText.installedCatalogWarning(EngineErrorText.reason(error))))
            }
        }
    }
    private func removePrevious(id: UUID, notify: Bool = true) async -> Bool {
        guard let old = pendingRemoval, let installed, let app else { return false }
        enter(.installing)
        do {
            _ = try await app.services.installer.uninstall(old)
            guard current(id) else { return false }
            _ = await app.services.catalog.noteRemoved(old.fileURL)
            guard current(id) else { return false }
            pendingRemoval = nil; state = .installed; if notify { attention() }; return true
        } catch {
            if current(id) {
                fail(BuildText.replaceError(installed.font.fullName, old.fullName, error.localizedDescription))
            }
        }
        return false
    }
    public func saveCopy() {
        guard mayStart, let app else { return }
        operation { id in
            let request = SaveCopy.request(
                for: app.recipe, settings: app.settings.value, paths: app.services.paths,
                probe: app.services.fileProbe, licenceLines: self.licenceLines)
            guard let selected = await app.services.panels.chooseSaveLocation(request), self.current(id) else { return }
            guard app.analysis.canForge, self.problem == nil, !self.engineMissing else { return }
            let url = SaveCopy.enforcingExtension(selected)
            app.settings.update { $0.lastSaveDirectory = url.deletingLastPathComponent().path }
            if !self.isFresh { guard await self.forge(intent: .save(url), id: id) else { return } }
            guard self.current(id), let result = self.result else { return }
            self.enter(.saving)
            do {
                try app.services.writeFile(Data(contentsOf: result.url), url)
                self.savedURL = url; self.state = .saved; self.attention()
            } catch { self.fail(BuildText.saveError(error.localizedDescription)) }
        }
    }
    func build() {
        guard mayStart else { return }
        operation { id in
            if await self.forge(intent: nil, id: id), self.current(id) { self.state = .built; self.attention() }
        }
    }
    private func operation(_ body: @escaping @MainActor (UUID) async -> Void) {
        let id = UUID(); runID = id; pendingOperation = true
        task = Task { @MainActor in
            await body(id)
            if self.current(id) { self.pendingOperation = false; self.task = nil }
        }
    }
    private func current(_ id: UUID) -> Bool { id == runID }
    private func enter(_ state: BuildState) { notice = nil; lastErrorDetail = nil; self.state = state }
    private func forge(intent: BuildIntent?, id: UUID) async -> Bool {
        guard let app, current(id) else { return false }
        let recipe = app.recipe, services = app.services
        enter(.building(intent: intent, stage: BuildText.starting, fraction: 0, stopping: false))
        let token = services.system.beginActivity(reason: BuildText.activity); activity = token
        var output: URL?
        var kept = false
        defer {
            if activity == token { endActivity() }
            if !kept, let output { BuildOutputs.delete(output, builds: services.paths.builds) }
            if current(id) { outputURL = nil }
        }
        do {
            let url = try BuildOutputs.make(in: services.paths.builds); output = url; outputURL = url
            let request = recipe.forgeRequest(outputPath: url.path)
            var report: ForgeReport?
            for try await event in services.engine.forge(request) {
                // Keep iterating until the stream ends: a superseded run's cancel arrives from another thread, and
                // leaving early would drop the stream without stopping its helper.
                guard current(id) else { continue }
                switch event {
                case .progress(let progress):
                    if case .building(_, let previous, _, false) = state {
                        let stage =
                            StageText.text(
                                for: progress.stage, materialIndex: progress.materialIndex,
                                materials: recipe.materials) ?? previous
                        state = .building(intent: intent, stage: stage, fraction: progress.fraction, stopping: false)
                    }
                case .finished(let value): report = value
                }
            }
            guard current(id) else { return false }
            guard !Task.isCancelled, !stopping else { state = .cancelled; return false }
            guard let report else {
                throw EngineError.protocolViolation("helper exited without a result", stderrTail: "")
            }
            if let previous = result { BuildOutputs.delete(previous.url, builds: services.paths.builds) }
            result = .init(id: UUID(), url: url, report: report, spec: recipe.forgeSpec()); kept = true
            lastReport = report; lastErrorDetail = nil
            app.builtFont = .init(url: url, displayName: report.fullName, spec: recipe.forgeSpec())
            return true
        } catch {
            guard current(id) else { return false }
            if Task.isCancelled || stopping || error is CancellationError {
                state = .cancelled
            } else {
                let failure = EngineErrorText.buildFailure(error, materials: recipe.materials)
                fail(failure.message, detail: failure.detail)
            }
            return false
        }
    }
    private var stopping: Bool { if case .building(_, _, _, let stopping) = state { stopping } else { false } }
    public func cancel() {
        guard case .building(let intent, _, let fraction, false) = state else { return }
        state = .building(intent: intent, stage: BuildText.stopping, fraction: fraction, stopping: true)
        Self.cancelOffMainThread(task)
    }
    /// Swift runs the engine stream's `onTermination` on the thread that cancels its consumer, and that handler returns
    /// only once the helper has exited (NATIVE-7): up to `terminationGrace` plus SIGKILL and reaping when the helper
    /// ignores SIGTERM. Cancelling from elsewhere keeps the window responsive and the quit deadline running (review M1).
    private nonisolated static func cancelOffMainThread(_ task: Task<Void, Never>?) {
        guard let task else { return }
        DispatchQueue.global(qos: .userInitiated).async { task.cancel() }
    }
    public func cancelAndWait() async {
        guard let task else { return }
        let id = runID, output = outputURL
        cancel(); Self.cancelOffMainThread(task)
        await withCheckedContinuation { continuation in
            let race = BuildWaitRace(continuation)
            Task {
                await task.value; race.finish()
            }
            Task {
                // Leave cleanup and main-actor scheduling headroom inside the three-second quit deadline.
                try? await Task.sleep(for: .milliseconds(2800)); race.finish()
            }
        }
        if current(id) {
            runID = UUID(); self.task = nil; pendingOperation = false
            if isBusy { state = .cancelled }
            if let output, let app { BuildOutputs.delete(output, builds: app.services.paths.builds) }
            outputURL = nil; endActivity()
        }
    }
    public func uninstall() {
        guard let installed, !isBusy, !pendingOperation, let app else { return }
        operation { id in
            if self.pendingRemoval != nil {
                guard await self.removePrevious(id: id, notify: false) else { return }
            }
            do {
                let outcome = try await app.services.installer.uninstall(installed.font)
                guard self.current(id) else { return }
                _ = await app.services.catalog.noteRemoved(installed.font.fileURL)
                guard self.current(id) else { return }
                self.notice = outcome == .notInstalled ? BuildText.notInstalled : BuildText.removed
                self.installed = nil; self.pendingRemoval = nil; self.lastErrorDetail = nil; self.state = .idle
            } catch { if self.current(id) { self.fail(BuildText.removeError(error.localizedDescription)) } }
        }
    }
    public func showInFinder() {
        guard let file = shownFile, FileManager.default.fileExists(atPath: file.path) else {
            notice = BuildText.fileGone; return
        }
        notice = nil; app?.services.system.reveal([file])
    }
    public func openInFontBook() {
        guard commands.canOpenInFontBook, let savedURL else { return }; app?.services.system.openInFontBook(savedURL)
    }
    public func showReport() {
        if case .failed = state, let lastErrorDetail {
            app?.sheet = .report(lastErrorDetail)
        } else if let lastReport {
            app?.sheet = .report(ReportText.render(lastReport))
        }
    }
    public func reset() {
        Self.cancelOffMainThread(task); runID = UUID(); task = nil; pendingOperation = false; endActivity()
        if let outputURL, let app { BuildOutputs.delete(outputURL, builds: app.services.paths.builds) }
        outputURL = nil; discardResultFiles(); installed = nil; pendingRemoval = nil; savedURL = nil
        notice = nil; lastReport = nil; lastErrorDetail = nil; state = .idle
    }
    public func discardResultFiles() {
        if let result, let app { BuildOutputs.delete(result.url, builds: app.services.paths.builds) }
        result = nil; app?.builtFont = nil
    }
    private func endActivity() {
        if let activity { app?.services.system.endActivity(activity) }; activity = nil
    }
    private func fail(_ message: String, detail: String? = nil) {
        lastErrorDetail = ReportText.failure(message: message, detail: detail ?? ""); state = .failed(message: message);
        attention()
    }
    private func attention() {
        guard let system = app?.services.system, !system.isAppActive else { return }
        system.requestAttention(); system.setDockBadge("1")
    }
}
@MainActor private final class BuildWaitRace {
    private var continuation: CheckedContinuation<Void, Never>?
    init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }
    func finish() { continuation?.resume(); continuation = nil }
}
public struct BuildCommands: Equatable, Sendable {
    public var canSaveCopy, canInstall, canShowInFinder, canOpenInFontBook, canUninstall: Bool
    public var installTitle: String
    public init(
        canSaveCopy: Bool, canInstall: Bool, canShowInFinder: Bool, canOpenInFontBook: Bool,
        canUninstall: Bool, installTitle: String
    ) {
        self.canSaveCopy = canSaveCopy; self.canInstall = canInstall; self.canShowInFinder = canShowInFinder
        self.canOpenInFontBook = canOpenInFontBook; self.canUninstall = canUninstall; self.installTitle = installTitle
    }
    public static var unavailable: BuildCommands {
        .init(
            canSaveCopy: false, canInstall: false, canShowInFinder: false, canOpenInFontBook: false,
            canUninstall: false, installTitle: BuildText.install)
    }
}
