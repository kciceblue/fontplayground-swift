import AppKit
import FPCore
import SwiftUI
import Testing

@testable import FPAppUI

@MainActor struct AdvancedInspectorLayoutTests {
    @Test("UI-15: opening Advanced finishes the native display cycle", arguments: [false, true])
    func ui15InspectorLayoutFinishesAfterBuild(hasBuiltFont: Bool) async throws {
        // A main-actor timeout cannot interrupt AppKit's synchronous layout loop.
        // Fail the test process if layout never returns, instead of wedging the test runner.
        let completion = DispatchSemaphore(value: 0)
        DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
            if completion.wait(timeout: .now()) == .timedOut {
                FileHandle.standardError.write(
                    Data("UI-15: Advanced inspector layout did not complete within 60 seconds.\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        defer { completion.signal() }
        let rig = try BuildTestRig(), model = rig.model
        defer { rig.cleanup() }
        model.setLaunchPhase(.ready)
        if hasBuiltFont {
            try await rig.install()
            #expect(model.build.state == .installed && model.build.isFresh)
            model.build.lastReport = rig.report(
                warnings: Array(
                    repeating:
                        "A long report warning that wraps across several lines in the narrow inspector.", count: 20))
        } else {
            model.recipe.reset()
        }
        let quit = QuitCoordinator(
            isBuilding: { false }, stopBuilding: {}, flush: {}, stopCatalog: {}, present: { _ in }, reply: { _ in },
            closeWindow: {})
        // Exercise the production window delegate, while disabling real frame-preference reads/writes.
        let controller = MainWindowController(model: model, quit: quit, frameAutosaveName: nil)
        let window = controller.window, host = try #require(controller.window.contentView)
        defer { window.close() }
        // Cover both placements in the same two transitions, so the native display-cycle
        // regression does not duplicate expensive MainActor work in a second test suite.
        // WP-701 finding H: at half-screen width the inspector stayed collapsed after the sidebar collapsed,
        // and with the sidebar already hidden it widened the window by its stale 580-pt width.
        let placements: [(Double, NavigationSplitViewVisibility)] = [(1216, .all), (676, .all), (676, .detailOnly)]
        for (width, sidebar) in placements {
            let halfScreen = width == 676
            let size = NSSize(width: width, height: 680)
            model.sidebarVisibility = sidebar
            window.setContentSize(size)
            try await settle(window, host: host)
            #expect(host.bounds.size == size)
            model.showAdvanced()
            try await settle(window, host: host)
            #expect(model.inspectorPresented)
            #expect(model.sidebarVisibility == (halfScreen ? .detailOnly : .all))
            #expect(!window.isVisible)
            #expect(host.bounds.size == size)
            #expect(window.contentMinSize.width <= width)
            checkSplits(host, fitting: size)
            let inspector = trailingPanes(host)
            #expect(inspector.contains { !$0.isHidden && (260...420).contains($0.frame.width) }, "\(width)")
            #expect(inspector.allSatisfy { !$0.isHidden }, "\(width)")
            print("INSPECTOR_LAYOUT built=\(hasBuiltFont) requested=\(size) actual=\(host.bounds.size)")
            model.toggleAdvanced()
            try await settle(window, host: host)
            if halfScreen {
                window.setContentSize(NSSize(width: 640, height: 680))
                try await settle(window, host: host)
            }
            #expect(!model.inspectorPresented)
            if halfScreen { #expect(host.bounds.width == 640) }
        }
        if hasBuiltFont { #expect(model.build.state == .installed && model.build.isFresh) }
        if !hasBuiltFont {
            model.settings.inspectorPresented = true
            for width in [676.0, 1216.0] {
                let restored = AppModel(services: model.services)
                #expect(restored.inspectorPresented)
                let restoredController = MainWindowController(
                    model: restored, quit: quit, frameAutosaveName: nil,
                    initialFrame: NSRect(x: 0, y: 0, width: width, height: 730))
                let restoredWindow = restoredController.window
                let restoredHost = try #require(restoredWindow.contentView)
                defer { restoredWindow.close() }
                try await settle(restoredWindow, host: restoredHost)
                #expect(restored.inspectorPresented)
                #expect(restored.sidebarVisibility == (width == 676 ? .detailOnly : .all))
                #expect(!restoredWindow.isVisible)
                #expect(abs(restoredHost.bounds.width - width) < 0.5)
                #expect(restoredWindow.contentMinSize.width <= width)
                checkSplits(restoredHost, fitting: restoredHost.bounds.size)
                print("INSPECTOR_RESTORE requested=\(width) actual=\(restoredHost.bounds.width)")
            }
        }
    }

    private func checkSplits(_ view: NSView, fitting size: NSSize) {
        if view is NSSplitView {
            #expect(view.bounds.width <= size.width && view.bounds.height <= size.height)
        }
        for child in view.subviews { checkSplits(child, fitting: size) }
    }
    /// The last pane of every split view; the inspector is the trailing pane of the detail split.
    private func trailingPanes(_ view: NSView) -> [NSView] {
        var panes = view.subviews.flatMap(trailingPanes)
        if let split = view as? NSSplitView, let last = split.arrangedSubviews.last { panes.append(last) }
        return panes
    }
    private func settle(_ window: NSWindow, host: NSView) async throws {
        for _ in 0..<3 {
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
            window.layoutIfNeeded()
            drainDisplayCycle()
            try await Task.sleep(for: .milliseconds(30))
        }
    }
    private func drainDisplayCycle() {
        // layoutSubtreeIfNeeded alone misses the inspector's deferred split-view animation.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        CATransaction.flush()
    }
}
