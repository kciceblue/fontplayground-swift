import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct EditingSeamsTests {
    @Test func seamsStartEmptyAndStayConnected() throws {
        let rig = try ShellRig(), renderer = ShellFakeRenderer(); var s = rig.services; s.renderer = renderer
        let m = AppModel(services: s)
        #expect(m.recipe == Recipe() && m.catalogFaces.isEmpty && m.catalogStatus == CatalogStatus())
        #expect(m.pickRequest == nil && m.trial == nil && m.builtFont == nil && !m.isBuilding)
        #expect(m.renderer as AnyObject === renderer)
        m.openPicker(.init(languageID: "han")); #expect(m.pickRequest?.languageID == "any")
        m.trial = PreviewTrial(mix: Mix.empty, banner: "trial")
        m.isBuilding = true; #expect(m.pickRequest == nil && m.trial == nil)
        m.openPicker(.init(languageID: "latin")); #expect(m.pickRequest == nil)
        #expect(m.edit { $0.add(ShellFaces.make()) } == false)
        m.applySample(id: Samples.presets[0].id); #expect(m.recipe.sampleText == Samples.presets[0].text)
        let before = m.recipe; m.applySample(id: "missing"); #expect(m.recipe == before)
        m.isBuilding = false; m.findFont(); #expect(m.pickRequest?.languageID == "latin")
        m.cancelPicker(); m.edit { $0.add(ShellFaces.make()) }; m.findFont();
        #expect(m.pickRequest?.languageID == "any")
        m.previewPointSize = 10; var sizes = [m.previewPointSize]
        for _ in 0..<10 { m.zoomPreviewIn(); sizes.append(m.previewPointSize) }
        #expect(sizes == [10, 12, 14, 18, 24, 30, 36, 48, 64, 72, 96]); m.zoomPreviewIn();
        #expect(m.previewPointSize == 96)
        for expected in sizes.dropLast().reversed() { m.zoomPreviewOut(); #expect(m.previewPointSize == expected) }
        m.zoomPreviewOut(); #expect(m.previewPointSize == 10); m.resetPreviewZoom(); #expect(m.previewPointSize == 30)
        m.showAdvanced(); #expect(m.inspectorPresented && m.settings.inspectorPresented)
        #expect(MixPalette.colour(forMaterialAt: 4) == MixPalette.colour(forMaterialAt: 0))
        let font = try renderer.font(for: .init(face: ShellFaces.make(), pointSize: 23))
        #expect(
            font.pointSize == 23 && font.postscriptName == "ShellSystem" && font.variation.isEmpty
                && font.syntheticBold == nil && font.weightNote == nil)
    }
}
