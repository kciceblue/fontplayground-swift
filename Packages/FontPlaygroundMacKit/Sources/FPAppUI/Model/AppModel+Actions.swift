import FPCore
import FPEngineClient
import FPMacServices
import Foundation

extension AppModel {
    public func postNotice(_ notice: AppNotice) {
        if let index = notices.firstIndex(where: { $0.kind == notice.kind }) {
            notices[index] = notice
        } else {
            notices.append(notice)
        }
    }
    public func dismissNotice(_ id: UUID) { notices.removeAll { $0.id == id } }
    public func revealNotice(_ notice: AppNotice) { if let url = notice.revealURL { services.system.reveal([url]) } }
    func postBadFolders(_ paths: [String]) {
        postNotice(AppNotice(kind: .settingsIssues, text: ShellText.badFolders(paths: ShellText.quoted(paths))))
    }
    func postEngineUnavailable(_ reason: String) {
        postNotice(AppNotice(kind: .engineUnavailable, text: ShellText.engineUnavailable(reason: reason)))
    }
    func postUnavailable(_ names: [String]) {
        postNotice(
            AppNotice(
                kind: .fontsUnavailable,
                text: names.count == 1
                    ? ShellText.unavailableOne(name: names[0])
                    : ShellText.unavailableMany(count: names.count, names: ShellText.quoted(names))))
    }
    func postUnresolved(_ report: LoadReport, catalog: FaceCatalog) {
        var text = ModelText.unresolvedSummary(report) + ".", replacements: [AppNotice.Replacement] = [],
            unresolvedIndex = 0
        for outcome in report.outcomes {
            guard case .notFound(let keys) = outcome else { continue }
            defer { unresolvedIndex += 1 }
            guard report.unresolved.indices.contains(unresolvedIndex), let key = keys.first,
                let face = catalog.face(for: key)
            else { continue }
            let missing = report.unresolved[unresolvedIndex]
            let name = [missing.family, missing.style].filter { !$0.isEmpty }.joined(separator: " ")
            text += " " + ShellText.suggestion(missing: name, replacement: face.displayName)
            replacements.append(
                .init(missing: missing.key, missingName: name, replacement: key, replacementName: face.displayName))
        }
        postNotice(AppNotice(kind: .unresolvedFonts, text: text, replacements: replacements))
    }
    public func applyReplacement(_ replacement: AppNotice.Replacement) {
        guard !isBuilding, let face = FaceCatalog(catalogFaces).face(for: replacement.replacement),
            edit({ $0.replace(replacement.missing, with: face) })
        else { return }
        for index in notices.indices { notices[index].replacements.removeAll { $0 == replacement } }
        notices.removeAll { $0.kind == .unresolvedFonts && $0.replacements.isEmpty }
    }
    public func startOver() {
        guard !recipe.materials.isEmpty || isBuilding else { return }
        alert = AlertContent(
            title: ShellText.startOverTitle,
            message: ShellText.startOverMessage + (isBuilding ? ShellText.startOverBuilding : ""),
            buttons: [
                AlertButton(title: ShellText.startOver, isDefault: true) { [weak self] in
                    guard let self else { return }; build.reset(); pickRequest = nil; trial = nil; recipe.reset()
                }, AlertButton(title: ShellText.cancel, role: .cancel) {},
            ])
    }
    public func addFontFolder() {
        Task {
            let folders = await services.panels.chooseFolders(
                FolderPanelRequest(prompt: ShellText.addFolder, message: ShellText.folderMessage));
            addFontFolders(folders)
        }
    }
    public func addFontFolders(_ urls: [URL]) {
        var folders = settings.value.extraFolders, rejected: [String] = []
        for url in urls {
            switch FolderCheck.check(url.path, using: services.fileProbe) {
            case .success(let accepted): if !folders.contains(accepted.path) { folders.append(accepted.path) }
            case .failure: rejected.append(url.path)
            }
        }
        if !rejected.isEmpty { postBadFolders(rejected) }
        guard folders != settings.value.extraFolders else { return }
        settings.update { $0.extraFolders = folders }; refreshFolders(folders)
    }
    public func removeFontFolder(_ folder: String) {
        let folders = settings.value.extraFolders.filter { $0 != folder }
        guard folders != settings.value.extraFolders else { return }
        settings.update { $0.extraFolders = folders }; refreshFolders(folders)
    }
    public func removeFontFolder(_ folder: URL) { removeFontFolder(folder.path) }
    private func refreshFolders(_ folders: [String]) {
        Task {
            await services.catalog.setExtraFolders(folders.map { URL(fileURLWithPath: $0) });
            await refreshCatalog(.incremental)
        }
    }
    public func rescanFonts() { Task { await refreshCatalog(.full) } }
    private func refreshCatalog(_ mode: RefreshMode) async {
        do { let snapshot = try await services.catalog.refresh(mode); receiveSnapshot(snapshot) } catch {
            if !Task.isCancelled { postEngineUnavailable(EngineErrorText.reason(error)) }
        }
    }
    public func setAppearance(_ appearance: AppSettings.Appearance) {
        settings.update { $0.appearance = appearance }; services.system.applyAppearance(appearance)
    }
    /// Stores the choice for the next launch, and offers to reopen when that changes the language (localisation.md D5).
    public func setInterfaceLanguage(_ choice: InterfaceLanguage) {
        services.system.setLanguageOverride(choice.override); interfaceLanguage = choice
        let next = choice.resolved(systemLanguages: services.system.systemLanguages)
        guard next != services.system.runningLanguage else { return }
        languagePrompt = AlertContent(
            title: ShellText.reopenTitle(language: InterfaceLanguage.title(ofResolved: next)),
            message: ShellText.reopenMessage,
            buttons: [
                AlertButton(title: ShellText.quitAndReopen, isDefault: true) { [weak self] in self?.requestRelaunch() },
                AlertButton(title: ShellText.later, role: .cancel) {},
            ])
    }
    /// Quits through the normal path (autosave, catalog stop, the question while building), then reopens.
    public func requestRelaunch() { relaunchRequested = true; services.system.terminate() }
    public func quitWasCancelled() { relaunchRequested = false }
    public func toggleAdvanced() { inspectorPresented || inspectorPending ? hideAdvanced() : presentAdvanced() }
    public func showAbout() {
        let hello: FPEngineClient.EngineHello?;
        if case .available(let value) = engineStatus { hello = value } else { hello = nil };
        services.system.showAboutPanel(
            credits: AboutCredits.make(hello: hello, acknowledgements: services.acknowledgements))
    }
    public func openHelp() { if let url = services.helpURL { services.system.openURL(url) } }
    public func openDonation() { if let url = services.donateURL { services.system.openURL(url) } }
    /// Offers the donation page once per user, on the first launch that reaches `.ready`. When another alert is up,
    /// it waits for a later launch instead of replacing that alert; Donate… in the app menu stays available.
    func offerDonationOnce() {
        guard services.donateURL != nil, !settings.donationOffered, alert == nil else { return }
        settings.donationOffered = true
        alert = AlertContent(
            title: ShellText.donateTitle, message: ShellText.donateMessage,
            buttons: [
                AlertButton(title: ShellText.buyMeACoffee, isDefault: true) { [weak self] in self?.openDonation() },
                AlertButton(title: ShellText.noThanks, role: .cancel) {},
            ])
    }
    public func showSettingsFolderInFinder() {
        do {
            try FileManager.default.createDirectory(
                at: services.paths.applicationSupport, withIntermediateDirectories: true);
            services.system.reveal([services.paths.applicationSupport])
        } catch { AppLog.app.error("Couldn't create settings folder: \(error.localizedDescription, privacy: .public)") }
    }
    public func getMoreFonts() { services.system.openFontBook() }
    @discardableResult public func handleDrop(_ urls: [URL]) -> Bool {
        var folders: [URL] = [], font = false
        for url in urls where url.isFileURL {
            if services.fileProbe.kind(of: url.path) == .directory {
                folders.append(url)
            } else if ["ttf", "otf", "ttc", "otc", "dfont"].contains(url.pathExtension.lowercased()) {
                font = true
            }
        }
        if !folders.isEmpty { addFontFolders(folders) }
        if font { postNotice(AppNotice(kind: .fileDropped, text: ShellText.fileDropped)) }
        return font || !folders.isEmpty
    }
    public func appDidBecomeActive() { services.system.setDockBadge(nil) }
}
