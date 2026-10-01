import AppKit
import CoreText
import FPCore
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct PreviewPaneTests {
    @Test func sampleSelectionFollowsPresetAndModelText() throws {
        let rig = try ShellRig(), model = AppModel(services: rig.services)
        #expect(PreviewText.sampleSelectionLabel(model.recipe.sampleText) == "Mixed (English, Chinese, Japanese)")
        for preset in Samples.presets {
            model.applySample(id: preset.id)
            #expect(PreviewText.sampleSelectionLabel(model.recipe.sampleText) == ModelText.samplePresetLabel(preset.id))
            model.recipe.setSampleText(preset.text + " edited")
            #expect(PreviewText.sampleSelectionLabel(model.recipe.sampleText) == "Custom Text")
            model.recipe.setSampleText(preset.text)
            #expect(PreviewText.sampleSelectionLabel(model.recipe.sampleText) == ModelText.samplePresetLabel(preset.id))
        }
        model.recipe.setSampleText("")
        #expect(PreviewText.sampleSelectionLabel(model.recipe.sampleText) == "Custom Text")
    }
    func configuration(empty: Bool = false) -> PreviewConfiguration {
        .init(
            mode: empty ? .empty : .mix(Mix(fonts: [.init(face: ShellFaces.make(text: "abc1, "))])), pointSize: 30,
            colourByFont: false)
    }
    @Test func missingNote() {
        let c = configuration()
        #expect(PreviewText.missingNote(c, text: "abc 1,\n​") == nil)
        #expect(PreviewText.missingNote(c, text: "abc 한")?.buttonTitle == "Add a font for Korean…")
        #expect(PreviewText.missingNote(c, text: "abc 한")?.request == PickRequest(languageID: "korean"))
        #expect(PreviewText.missingNote(c, text: "a 가나다라마바사아자차카타파하 가")?.text.contains(" and 2 more") == true)
        #expect(PreviewText.missingNote(c, text: "a漢字한")?.buttonTitle == "Add a font for Chinese…")
        #expect(PreviewText.missingNote(c, text: "aሀ")?.request.languageID == "any")
        #expect(PreviewText.missingNote(c, text: "aሀ")?.buttonTitle == "Find a font…")
        #expect(PreviewText.missingNote(configuration(empty: true), text: "한𠀀") == nil)
    }
    @Test func missingTextWording() {
        #expect(
            PreviewText.missingText(Array("한".unicodeScalars))
                == "“한” isn't in any of your fonts, so it would show as a box.")
        #expect(
            PreviewText.missingText(Array("안녕하".unicodeScalars))
                == "“안”, “녕”, “하” aren't in any of your fonts, so they would show as boxes.")
        let twelve = (0xAC00..<0xAC0C).compactMap(Unicode.Scalar.init)
        #expect(!PreviewText.missingText(twelve).contains("more"))
        #expect(
            PreviewText.missingText(twelve + ["x"]).hasPrefix(
                twelve.map { "“\($0)”" }.joined(separator: ", ") + " and 1 more aren't"))
    }
    @Test func bannerOnlyDuringATrial() throws {
        let rig = try ShellRig(), m = AppModel(services: rig.services), a = ShellFaces.make(text: "a"),
            b = ShellFaces.make("B", path: "/B", text: "漢")
        m.edit {
            $0.add(a); $0.setSampleText("a漢")
        }
        let banner = "Trying Fixture B for Chinese — ↑ ↓ try the next font, Return uses it."
        m.trial = PreviewTrial(mix: Mix(fonts: [.init(face: a), .init(face: b)]), banner: banner)
        #expect(
            m.trial?.banner == banner
                && PreviewText.missingNote(m.previewConfiguration, text: m.recipe.sampleText) == nil)
        m.trial = nil; #expect(PreviewText.missingNote(m.previewConfiguration, text: m.recipe.sampleText) != nil)
    }
    @Test func voiceOverLabels() throws {
        let rig = try ShellRig(), m = AppModel(services: rig.services), e = PreviewTextEditor.makeEditor(model: m)
        #expect(e.textView.accessibilityLabel() == "Preview text")
        #expect(
            PreviewText.sizeAccessibilityLabel == "Preview size"
                && PreviewText.sizeAccessibilityValue(30) == "30 points")
        #expect(PreviewText.builtBadgeAccessibilityLabel == "Showing the built font")
    }
}
