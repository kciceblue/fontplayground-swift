import FPCore
import FPEngineClient
import FPMacServices
import Foundation

extension AppModel {
    public func start() async {
        guard launchPhase == .starting, !terminated else { return }
        let paths = services.paths
        for url in [paths.helperTemp, paths.builds] {
            do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) } catch {
                AppLog.app.error("Couldn't create cache folder: \(error.localizedDescription, privacy: .public)")
            }
        }
        let now = services.now()
        _ = services.sweepHelperLeftovers(paths.helperTemp, [paths.builds], now)
        CacheSweeper.sweepBuilds(paths.builds, olderThan: 600, now: now)
        readRestore()
        setLaunchPhase(.loadingFonts)
        helloTask = Task { [weak self] in
            guard let self else { return }
            do {
                let hello = try await services.engine.hello(); guard !Task.isCancelled else { return };
                setEngineStatus(.available(hello))
            } catch {
                guard !Task.isCancelled else { return }; let reason = EngineErrorText.reason(error);
                setEngineStatus(.unavailable(reason)); postEngineUnavailable(reason)
            }
        }
        observationTask = Task { [weak self] in
            guard let self else { return }
            for await snapshot in await services.catalog.snapshots() {
                guard !Task.isCancelled else { break }
                receiveSnapshot(snapshot)
            }
        }
        launchTask = Task { [weak self] in
            guard let self else { return }
            await services.catalog.setExtraFolders(settings.value.extraFolders.map { URL(fileURLWithPath: $0) })
            guard !Task.isCancelled else { return }
            let snapshot: CatalogSnapshot
            var failed = false
            do { snapshot = try await services.catalog.refresh(.incremental) } catch {
                guard !Task.isCancelled else { return }; failed = true;
                postEngineUnavailable(EngineErrorText.reason(error));
                snapshot = await services.catalog.currentSnapshot()
            }
            guard !Task.isCancelled else { return }
            firstRefreshFinished(snapshot, refreshFailed: failed)
            await services.catalog.startObservingSystemChanges()
        }
        systemTask = Task { [weak self] in
            guard let self else { return }
            for await event in services.system.events {
                guard !Task.isCancelled else { break }
                switch event {
                case .didBecomeActive: appDidBecomeActive();
                case .displayOptionsChanged: displayOptionsChanged()
                }
            }
        }
    }
    private func readRestore() {
        let path = services.paths.lastRecipe
        if FileManager.default.fileExists(atPath: path.path) {
            do { pendingDocument = try RecipeDocument.decode(Data(contentsOf: path)) } catch {
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX");
                formatter.dateFormat = "yyyyMMdd-HHmmss"
                let stem = "last-damaged-" + formatter.string(from: services.now())
                var preserved = path.deletingLastPathComponent().appending(path: stem + ".fontrecipe"), suffix = 2
                while FileManager.default.fileExists(atPath: preserved.path) {
                    preserved = path.deletingLastPathComponent().appending(path: "\(stem)-\(suffix).fontrecipe");
                    suffix += 1
                }
                do { try FileManager.default.moveItem(at: path, to: preserved) } catch {
                    AppLog.app.error(
                        "Couldn't preserve damaged recipe: \(error.localizedDescription, privacy: .public)");
                    preserved = path
                }
                postNotice(
                    AppNotice(
                        kind: .damagedRecipe, text: ShellText.damaged(name: preserved.lastPathComponent),
                        revealURL: preserved))
            }
            return
        }
        guard !settings.value.legacyImportDone,
            services.fileProbe.kind(of: services.paths.legacyFolder.path) == .directory
        else { return }
        let settingsURL = services.paths.legacyFolder.appending(path: LegacyImport.settingsFileName)
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            if let data = try? Data(contentsOf: settingsURL) {
                let imported = LegacyImport.settings(from: data, probe: services.fileProbe)
                if imported.report.readable {
                    settings.update { $0 = imported.settings }
                    previewPointSize = settings.value.previewPointSize; colourByFont = settings.value.colourByFont
                    services.system.applyAppearance(settings.value.appearance)
                    legacySettingsImported = true
                    if !imported.report.ignoredKeys.isEmpty {
                        recordRestorationWarnings([ShellText.ignoredSettings(imported.report.ignoredKeys.count)])
                    }
                    if !imported.report.droppedFolders.isEmpty {
                        postBadFolders(imported.report.droppedFolders.map(\.path))
                    }
                } else {
                    postNotice(AppNotice(kind: .importFailed, text: ShellText.importFailed))
                }
            } else {
                postNotice(AppNotice(kind: .importFailed, text: ShellText.importFailed))
            }
        }
        let recipeURL = services.paths.legacyFolder.appending(path: LegacyImport.recipeFileName)
        if FileManager.default.fileExists(atPath: recipeURL.path) {
            do { pendingLegacy = try Data(contentsOf: recipeURL) } catch {
                postNotice(AppNotice(kind: .importFailed, text: ShellText.importFailed))
            }
        }
        settings.update { $0.legacyImportDone = true }
    }
    func firstRefreshFinished(_ snapshot: CatalogSnapshot, refreshFailed: Bool) {
        receiveSnapshot(snapshot)
        handledGeneration = snapshot.generation
        let catalog = FaceCatalog(catalogFaces)
        var report: LoadReport?
        if let document = pendingDocument {
            let restored = document.makeRecipe(catalog: catalog); recipe = restored.recipe; report = restored.report
        } else if let data = pendingLegacy {
            let imported = LegacyImport.recipe(fromForgeLast: data, catalog: catalog, probe: services.fileProbe)
            if imported.report.readable {
                recipe = imported.recipe; report = imported.report.load
                if let path = imported.report.ignoredOutputPath {
                    recordRestorationWarnings([ShellText.ignoredOutputPath(path)])
                }
                if let directory = imported.report.lastSaveDirectory {
                    settings.update { $0.lastSaveDirectory = directory }
                }
                postNotice(AppNotice(kind: .imported, text: ShellText.imported))
            } else {
                postNotice(AppNotice(kind: .importFailed, text: ShellText.importFailed))
            }
        } else if legacySettingsImported {
            postNotice(AppNotice(kind: .imported, text: ShellText.imported))
        }
        if let report {
            var warnings: [String] = []
            let duplicates = report.outcomes.filter { if case .duplicate = $0 { true } else { false } }.count
            let malformed = report.outcomes.filter { $0 == .malformed }.count
            if duplicates > 0 { warnings.append(ShellText.duplicateEntries(duplicates)) }
            if malformed > 0 { warnings.append(ShellText.invalidEntries(malformed)) }
            if !report.ignoredRules.isEmpty { warnings.append(ShellText.ignoredRules(report.ignoredRules.count)) }
            if report.mainOutOfRange { warnings.append(ShellText.ignoredLineSpacingFont) }
            recordRestorationWarnings(warnings)
        }
        if let report, !report.unresolved.isEmpty, !refreshFailed { postUnresolved(report, catalog: catalog) }
        pendingDocument = nil; pendingLegacy = nil
        setLaunchPhase(.ready)
        scheduleAutosave()
        offerDonationOnce()
    }
    private func recordRestorationWarnings(_ warnings: [String]) {
        guard !warnings.isEmpty else { return }
        restorationWarnings += warnings
        postNotice(
            AppNotice(
                kind: .restorationIssues,
                text: ShellText.restorationIssues(restorationWarnings.joined(separator: ModelText.listSeparator))))
    }
    func receiveSnapshot(_ snapshot: CatalogSnapshot) {
        catalogFaces = snapshot.faces
        var status = CatalogStatus()
        if case .refreshing(let progress) = snapshot.activity {
            status.isScanning = true; status.done = progress.filesDone; status.total = progress.filesTotal
        }
        status.faceCount = snapshot.counts.faces; status.hiddenCount = snapshot.counts.hiddenFaces;
        status.duplicateCount = snapshot.counts.duplicateFaces
        var folders: [String: String] = [:]
        for issue in snapshot.issues {
            switch issue {
            case .unreadable(let path, _, let message): status.unreadable.append(.init(path: path, message: message))
            case .noAccess(let folder), .folderMissing(let folder), .folderUnreadable(let folder, _):
                folders[folder] = ModelText.catalogIssue(issue)
            default: break
            }
        }
        catalogStatus = status; setFolderIssues(folders)
        guard launchPhase == .ready, snapshot.isComplete, snapshot.activity == .idle,
            snapshot.generation > handledGeneration
        else { return }
        if isBuilding { deferredSnapshot = snapshot; return }
        reconcile(snapshot)
    }
    func runDeferredReconcile() { if let snapshot = deferredSnapshot { deferredSnapshot = nil; reconcile(snapshot) } }
    private func reconcile(_ snapshot: CatalogSnapshot) {
        guard snapshot.generation > handledGeneration else { return }
        handledGeneration = snapshot.generation
        let report = recipe.reconcile(with: FaceCatalog(snapshot.faces))
        guard !report.nowMissing.isEmpty || !report.recovered.isEmpty else { return }
        // The notice names every font the recipe misses now, not only this refresh's change: one missing since an
        // earlier refresh stays listed, and one that came back drops out.
        let missing = recipe.materials.filter { !$0.isAvailable }.map(\.face.displayName)
        if missing.isEmpty {
            notices.removeAll { $0.kind == .fontsUnavailable }
        } else if !report.nowMissing.isEmpty || notices.contains(where: { $0.kind == .fontsUnavailable }) {
            postUnavailable(missing)
        }
    }
    func scheduleAutosave() {
        guard !terminated, launchPhase == .ready else { return }
        autosavePending = true; autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)); self?.flushAutosave() } catch {}
        }
    }
    public func flushAutosave() {
        autosaveTask?.cancel(); autosaveTask = nil
        guard autosavePending, launchPhase == .ready else { return }
        autosavePending = false
        do { try services.writeFile(RecipeDocument(recipe: recipe).encoded(), services.paths.lastRecipe) } catch {
            AppLog.app.error("Couldn't save recipe: \(error.localizedDescription, privacy: .public)")
            if !autosaveFailureReported {
                autosaveFailureReported = true;
                postNotice(
                    AppNotice(kind: .autosaveFailed, text: ShellText.autosaveFailed(reason: error.localizedDescription))
                )
            }
        }
    }
    func schedulePreferenceSave() {
        guard !terminated else { return }
        preferencesPending = true; preferenceTask?.cancel()
        preferenceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)); self?.flushPreferences() } catch {}
        }
    }
    public func flushPreferences() {
        preferenceTask?.cancel(); preferenceTask = nil
        guard preferencesPending else { return }; preferencesPending = false
        settings.update {
            $0.previewPointSize = previewPointSize; $0.colourByFont = colourByFont
        }
    }
    /// Stops a running scan and its helper, and system-change observation. Quitting awaits this before AppKit's
    /// reply (QuitCoordinator); the unstructured call in `prepareForTermination` is only a fallback.
    public func stopCatalog() async {
        let catalog = services.catalog
        await catalog.cancelRefresh(); await catalog.stopObservingSystemChanges()
    }
    public func prepareForTermination() {
        terminated = true
        observationTask?.cancel(); launchTask?.cancel(); helloTask?.cancel(); systemTask?.cancel()
        flushAutosave(); flushPreferences(); build.discardResultFiles()
        Task { await stopCatalog() }
        if relaunchRequested { relaunchRequested = false; services.system.relaunchAfterExit() }
    }
}
