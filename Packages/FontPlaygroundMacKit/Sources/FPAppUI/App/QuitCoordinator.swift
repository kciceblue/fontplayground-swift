import AppKit

@MainActor final class QuitCoordinator {
    private let isBuilding: () -> Bool
    private let stopBuilding: () async -> Void
    private let flush: () -> Void
    private let stopCatalog: () async -> Void
    private let present: (AlertContent) -> Void
    private let reply: (Bool) -> Void
    private let closeWindow: () -> Void
    private let cancelled: () -> Void
    private var showingAlert = false
    private var stopping = false
    private var allowClose = false
    init(
        isBuilding: @escaping () -> Bool, stopBuilding: @escaping () async -> Void, flush: @escaping () -> Void,
        stopCatalog: @escaping () async -> Void, present: @escaping (AlertContent) -> Void,
        reply: @escaping (Bool) -> Void, closeWindow: @escaping () -> Void, cancelled: @escaping () -> Void = {}
    ) {
        self.isBuilding = isBuilding; self.stopBuilding = stopBuilding; self.flush = flush;
        self.stopCatalog = stopCatalog; self.present = present; self.reply = reply; self.closeWindow = closeWindow
        self.cancelled = cancelled
    }
    func shouldTerminate() -> NSApplication.TerminateReply {
        guard !showingAlert, !stopping else { return .terminateCancel }
        guard isBuilding() else { finish(); return .terminateLater }
        show(close: false); return .terminateLater
    }
    /// Holds the AppKit reply until a running catalog scan has stopped, so its helper never outlives the app.
    private func finish() {
        stopping = true; flush()
        Task {
            await stopCatalog(); stopping = false; reply(true)
        }
    }
    func windowShouldClose() -> Bool {
        if allowClose { return true }
        guard !showingAlert else { return false }
        guard isBuilding() else { return true }
        show(close: true); return false
    }
    private func show(close: Bool) {
        showingAlert = true
        present(
            AlertContent(
                title: ShellText.quitTitle,
                buttons: [
                    AlertButton(title: ShellText.quit, isDefault: true) { [weak self] in
                        guard let self else { return }
                        Task {
                            await stopBuilding(); showingAlert = false;
                            if close { allowClose = true; closeWindow() } else { finish() }
                        }
                    },
                    AlertButton(title: ShellText.keepBuilding, role: .cancel) { [weak self] in
                        guard let self else { return }; showingAlert = false; if !close { cancelled(); reply(false) }
                    },
                ]))
    }
}
