import AppKit
import SwiftUI

@MainActor final class MainWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let quit: QuitCoordinator
    private let model: AppModel
    /// The frame the window keeps while the inspector is being presented.
    private var presentationFrame: NSRect?
    init(
        model: AppModel, quit: QuitCoordinator, frameAutosaveName: NSWindow.FrameAutosaveName? = "FPMainWindow",
        initialFrame: NSRect? = nil
    ) {
        self.quit = quit
        self.model = model
        let host = NSHostingController(rootView: MainWindowView(model: model))
        host.sizingOptions = [.minSize]; host.sceneBridgingOptions = [.toolbars, .title]
        window = NSWindow(contentViewController: host)
        super.init()
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = ShellText.windowTitle; window.contentMinSize = MainWindowGeometry.minContentSize
        window.collectionBehavior.insert(.fullScreenPrimary); window.tabbingMode = .disallowed
        window.isRestorable = false; window.isReleasedWhenClosed = false
        if let initialFrame {
            window.setFrame(initialFrame, display: false)
        } else if frameAutosaveName.map({ window.setFrameUsingName($0) }) != true {
            let frame =
                NSScreen.main.map {
                    MainWindowGeometry.initialFrame(
                        visibleFrame: $0.visibleFrame,
                        chromeHeight: window.frame.height - window.contentLayoutRect.height)
                } ?? CGRect(origin: .zero, size: MainWindowGeometry.preferredFrameSize)
            window.setFrame(frame, display: false)
        }
        if let frameAutosaveName { window.setFrameAutosaveName(frameAutosaveName) }
        model.updateMainWindowContentWidth(window.contentLayoutRect.width)
        window.delegate = self
        model.presentInspector = { [weak self] present in
            // WP-701 finding H: present on the next turn, once the sidebar collapse has been applied.
            DispatchQueue.main.async { self?.presentKeepingFrame(present) ?? present() }
        }
    }
    private func presentKeepingFrame(_ present: @MainActor () -> Void) {
        // WP-701 finding H: uncollapsing restores the inspector's stale width (580 pt), and when the preview
        // can't give that up AppKit widens the window past a half-screen tile. Keep the frame instead,
        // widening only as far as the inspector needs.
        var frame = window.frame
        frame.size.width += max(0, MainWindowGeometry.minWidthWithInspector - window.contentLayoutRect.width)
        presentationFrame = frame
        present()
        window.contentView?.layoutSubtreeIfNeeded()
        if window.frame != frame { window.setFrame(frame, display: false) }
        DispatchQueue.main.async { [weak self] in self?.presentationFrame = nil }
    }
    func windowDidResize(_ notification: Notification) {
        if let presentationFrame, window.frame != presentationFrame {
            window.setFrame(presentationFrame, display: false); return
        }
        model.updateMainWindowContentWidth(window.contentLayoutRect.width)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { quit.windowShouldClose() }
}
