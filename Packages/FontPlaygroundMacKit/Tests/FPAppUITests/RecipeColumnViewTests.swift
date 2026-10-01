import AppKit
import FPCore
import Foundation
import SwiftUI
import Testing

@testable import FPAppUI

@MainActor struct RecipeColumnViewTests {
    @Test func rendersOffScreen() throws {
        _ = NSApplication.shared.setActivationPolicy(.prohibited)
        let rig = try RecipeTestRig(); defer { rig.cleanup() }; let faces = try RecipeTestFaces.coveredNames();
        rig.load(faces)
        let host = NSHostingView(rootView: RecipeColumn(model: rig.model))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let directory = ProcessInfo.processInfo.environment["FP_RECIPE_SNAPSHOT_DIR"] {
            for (name, appearance, scheme) in [
                ("light", NSAppearance.Name.aqua, ColorScheme.light), ("dark", .darkAqua, .dark),
            ] {
                let snapshot = NSHostingView(
                    rootView: RecipeColumn(model: rig.model)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .environment(\.colorScheme, scheme))
                snapshot.appearance = NSAppearance(named: appearance)
                snapshot.frame = host.frame
                window.contentView = snapshot
                snapshot.layoutSubtreeIfNeeded()
                let export = try #require(snapshot.bitmapImageRepForCachingDisplay(in: snapshot.bounds))
                snapshot.cacheDisplay(in: snapshot.bounds, to: export)
                if let data = export.representation(using: .png, properties: [:]) {
                    try AtomicFile.write(
                        data, to: URL(fileURLWithPath: directory).appendingPathComponent("recipe-\(name).png").path)
                }
            }
        }
        #expect(Set(rig.renderer.calls).isSuperset(of: faces.map(\.key)))
        var pixels: Set<String> = []
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 7) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 7) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    pixels.insert(
                        "\(Int(color.redComponent * 255)),\(Int(color.greenComponent * 255)),\(Int(color.blueComponent * 255))"
                    )
                }
            }
        }
        #expect(pixels.count > 1); #expect(!window.isVisible)
    }
    @Test("UI-5: recipe controls use stock native styles") func ui5RecipeControlsUseStockNativeStyles() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/FPAppUI/Editing/Recipe")
        let pattern = try NSRegularExpression(pattern: #"NSComboBox|:\s*(ButtonStyle|MenuStyle|PickerStyle)\s*\{"#)
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil)
        }
    }
}
