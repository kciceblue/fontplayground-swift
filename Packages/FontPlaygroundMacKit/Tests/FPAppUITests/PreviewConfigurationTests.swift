import AppKit
import CoreText
import FPCore
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct PreviewConfigurationTests {
    @Test func trialOverridesTheMixUntilCleared() throws {
        let rig = try ShellRig(), m = AppModel(services: rig.services), a = ShellFaces.make(text: "ab"),
            b = ShellFaces.make("B", path: "/B", text: "漢")
        m.edit { $0.add(a) }; m.trial = PreviewTrial(mix: Mix(fonts: [.init(face: a), .init(face: b)]), banner: "try")
        #expect(m.previewConfiguration.source(of: "漢") == 1)
        m.edit { $0.remove(a.key) }; #expect(m.previewConfiguration.source(of: "漢") == 1)
        m.trial = nil; #expect(m.previewConfiguration.mode == .empty)
    }
    @Test func builtFontUntilTheRecipeChanges() throws {
        let f = try PreviewFixtureFonts(), m = f.model([f.a, f.b])
        m.builtFont = BuiltFontPreview(
            url: URL(fileURLWithPath: f.a.path), displayName: f.a.displayName, spec: m.recipe.forgeSpec())
        #expect(m.previewConfiguration.isBuilt && m.previewConfiguration.source(of: "漢") == nil)
        let e = PreviewTextEditor.makeEditor(model: m)
        #expect((0..<4).allSatisfy { previewURL(previewFont(e.textView, at: $0))?.path == f.a.path })
        m.trial = PreviewTrial(mix: m.recipe.mix(), banner: "try");
        #expect(!m.previewConfiguration.isBuilt && m.previewConfiguration.source(of: "漢") == 1)
        m.trial = nil; m.recipe.setSampleText("abc"); #expect(m.previewConfiguration.isBuilt)
        m.edit { $0.setAdjustments(for: f.b.key, weight: nil, scale: 0.8) }
        #expect(!m.previewConfiguration.isBuilt && m.builtFont?.isStale(for: m.recipe) == true)
        let staleURL = f.root.appending(path: "missing.ttf")
        m.builtFont = BuiltFontPreview(url: staleURL, displayName: "missing", spec: m.recipe.forgeSpec())
        #expect(!m.previewConfiguration.isBuilt)
    }
}
