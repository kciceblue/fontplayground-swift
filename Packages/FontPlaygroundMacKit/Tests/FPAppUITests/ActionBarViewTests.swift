import AppKit
import FPCore
import Foundation
import SwiftUI
import Testing

@testable import FPAppUI

extension BuildFlowIntegration {
    @MainActor struct ActionBarViewTests {
        @Test func actionBarRendersNarrowAndWideOffscreen() throws {
            let rig = try BuildTestRig(); defer { rig.cleanup() }
            for (width, name) in [(360.0, "narrow"), (1200, "wide")] {
                let host = NSHostingView(rootView: ActionBarView(model: rig.model))
                host.frame = NSRect(x: 0, y: 0, width: width, height: 220)
                let window = NSWindow(
                    contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: true)
                window.contentView = host; host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                // fittingSize proposes unconstrained width and reports the wide variant's ideal size.
                // Draw at the real constrained width; the exported images support the manual layout check.
                #expect(!window.isVisible && host.frame.width == width && bitmap.pixelsWide > 0)
                #expect(ActionBarView.primaryShortcut == nil && ActionBarView.cancelShortcut == .cancelAction)
                // WP-701 finding A: at half-screen width the status was cut to "Installs in your Fonts f…".
                #expect(
                    ActionBarView.statusLineLimit(saved: false) > 1 && ActionBarView.statusLineLimit(saved: true) == 1)
                if let folder = ProcessInfo.processInfo.environment["FP_BUILD_SNAPSHOT_DIR"],
                    let png = bitmap.representation(using: .png, properties: [:])
                {
                    try AtomicFile.write(
                        png, to: URL(fileURLWithPath: folder).appendingPathComponent("action-bar-\(name).png").path)
                }
            }
        }
    }
}
