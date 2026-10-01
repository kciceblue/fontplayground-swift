import AppKit
import FPCore
import SwiftUI
import Testing

@testable import FPAppUI

/// Supplemental render evidence; these images cannot verify VoiceOver or interactive manual criteria.
@MainActor struct PolishOffscreenTests {
    @Test func integratedWindowFitsMinimumAndNormalSizes() async throws {
        let directory = ProcessInfo.processInfo.environment["FP_POLISH_SNAPSHOT_DIR"]
        for (name, appearance, scheme) in [
            ("light", NSAppearance.Name.aqua, ColorScheme.light), ("dark", .darkAqua, .dark),
        ] {
            for (sizeName, size) in [
                ("minimum", MainWindowGeometry.minContentSize), ("normal", NSSize(width: 1200, height: 800)),
            ] {
                let fixtures = try PreviewFixtureFonts(),
                    model = fixtures.model([fixtures.a, fixtures.b], text: "abc 1, 漢 한\nabc漢abc漢")
                model.colourByFont = true; model.catalogFaces = [fixtures.a, fixtures.b]
                model.setLaunchPhase(.ready); model.recipe.setFamily("Preview Study", byUser: true)
                defer { model.terminated = true; model.autosaveTask?.cancel(); model.preferenceTask?.cancel() }
                let controller = NSHostingController(
                    rootView: MainWindowView(model: model).environment(\.colorScheme, scheme).background(
                        Color(nsColor: .windowBackgroundColor)))
                controller.sizingOptions = [.minSize]
                controller.sceneBridgingOptions = [.toolbars, .title]
                let window = NSWindow(contentViewController: controller)
                window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
                window.contentMinSize = MainWindowGeometry.minContentSize
                let host = controller.view
                window.isReleasedWhenClosed = false
                let named = try #require(NSAppearance(named: appearance)); window.appearance = named;
                host.appearance = named
                window.setContentSize(size); host.layoutSubtreeIfNeeded()
                for _ in 0..<3 {
                    window.setContentSize(size)
                    host.needsLayout = true; host.layoutSubtreeIfNeeded()
                    window.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(30))
                }
                host.layoutSubtreeIfNeeded()
                print(
                    "POLISH_RENDER \(name) \(sizeName) requested=\(size), actual=\(host.bounds.size), minimum=\(window.contentMinSize)"
                )
                #expect(window.contentMinSize.width <= size.width && window.contentMinSize.height <= size.height)
                #expect(host.bounds.size == size)
                func checkSplits(_ view: NSView) {
                    if view is NSSplitView {
                        #expect(view.bounds.width <= size.width && view.bounds.height <= size.height)
                    }
                    for child in view.subviews { checkSplits(child) }
                }
                checkSplits(host)
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                named.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: bitmap) }
                #expect(!window.isVisible && bitmap.pixelsWide > 0)
                if let directory {
                    // Native column hosts inherit the process appearance before an offscreen window draws.
                    let previousAppearance = NSApp.appearance; NSApp.appearance = named
                    defer { NSApp.appearance = previousAppearance }
                    // Window sizing above uses the production host. A body-only host avoids AppKit's
                    // offscreen toolbar/sidebar compositing limitation in the supplemental bitmap.
                    let snapshot = NSHostingView(
                        rootView: MainWindowView(model: model)
                            .preferredColorScheme(scheme).frame(width: size.width, height: size.height)
                            .background(Color(nsColor: .windowBackgroundColor)))
                    snapshot.appearance = named
                    let surface = NSWindow(
                        contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless], backing: .buffered, defer: true)
                    surface.isReleasedWhenClosed = false; surface.appearance = named
                    surface.contentView = snapshot; snapshot.layoutSubtreeIfNeeded()
                    let capture = try #require(snapshot.bitmapImageRepForCachingDisplay(in: snapshot.bounds))
                    named.performAsCurrentDrawingAppearance { snapshot.cacheDisplay(in: snapshot.bounds, to: capture) }
                    let png = try #require(capture.representation(using: .png, properties: [:]))
                    defer { surface.close() }
                    try AtomicFile.write(
                        png, to: URL(fileURLWithPath: directory).appending(path: "main-\(sizeName)-\(name).png").path)
                }
                window.close()
            }
        }
    }

    /// WP-701 finding C: the picker's wrapping title and note, measured at zero width, raised the window's minimum
    /// height past the screen (778–798 pt for Thai and Symbols), so AppKit grew the window under the Dock.
    @Test func pickerKeepsTheMinimumWindowSize() throws {
        let fixtures = try PreviewFixtureFonts(),
            model = fixtures.model([fixtures.a, fixtures.b], text: "abc 1, 漢")
        model.catalogFaces = [fixtures.a, fixtures.b]; model.setLaunchPhase(.ready)
        defer { model.terminated = true; model.autosaveTask?.cancel(); model.preferenceTask?.cancel() }
        for languageID in ["southeast_asian", "symbols", "chinese_s"] {
            model.openPicker(PickRequest(languageID: languageID))
            #expect(model.pickRequest != nil)
            // A zero proposal is how the window's minimum is measured.
            let minimum = NSHostingController(rootView: FontPickerView(model: model)).sizeThatFits(in: .zero)
            print("PICKER_MINIMUM \(languageID) \(minimum)")
            #expect(minimum.height <= MainWindowGeometry.minContentSize.height, "\(languageID)")
            model.cancelPicker()
        }
    }
    @Test func missingNoteButtonKeepsItsTitle() {
        // WP-701 finding G: at half-screen width the button was squeezed to "Add a font for Chines…".
        let note = MissingNote(
            text: "“ก”, “ข” and 30 more aren't in any of your fonts, so they would show as boxes.",
            buttonTitle: "Add a font for Thai & SE Asian…", request: PickRequest(languageID: "southeast_asian"))
        let button = NSHostingController(rootView: Button(note.buttonTitle) {}.buttonStyle(.bordered))
            .sizeThatFits(in: CGSize(width: CGFloat.infinity, height: .infinity))
        let strip = NSHostingController(rootView: MissingNoteStrip(note: note, disabled: false) {})
        let minimum = strip.sizeThatFits(in: .zero)
        print("MISSING_NOTE button=\(button) minimum=\(minimum)")
        // The strip's 10-pt padding on both sides, and the button at its full title width.
        #expect(minimum.width >= button.width + 20)
    }
}
