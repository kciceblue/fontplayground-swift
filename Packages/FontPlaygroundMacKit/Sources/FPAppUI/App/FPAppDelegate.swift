import AppKit
import FPMacServices

@MainActor public final class FPAppDelegate: NSObject, NSApplicationDelegate {
    public let model: AppModel
    private var controller: MainWindowController?
    private var quit: QuitCoordinator!
    public override convenience init() {
        self.init(services: .live()); model.platformFontLookup = PlatformFontPreferences.lookUp
    }
    public init(services: AppServices) {
        model = AppModel(services: services)
        super.init()
        quit = QuitCoordinator(
            isBuilding: { [model] in model.isBuilding }, stopBuilding: { [model] in await model.build.cancelAndWait() },
            flush: { [model] in
                model.flushAutosave(); model.flushPreferences()
            }, stopCatalog: { [model] in await model.stopCatalog() }, present: { [model] in model.alert = $0 },
            reply: { NSApp.reply(toApplicationShouldTerminate: $0) },
            closeWindow: { [weak self] in
                self?.controller?.window.close(); NSApp.terminate(nil)
            }, cancelled: { [model] in model.quitWasCancelled() })
    }
    public func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MainWindowController(model: model, quit: quit)
        controller?.window.makeKeyAndOrderFront(nil)
        Task { await model.start() }
    }
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { controller?.window.makeKeyAndOrderFront(nil) }; return true
    }
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quit.shouldTerminate()
    }
    public func applicationWillTerminate(_ notification: Notification) { model.prepareForTermination() }
    public func applicationDidBecomeActive(_ notification: Notification) { model.appDidBecomeActive() }
}
