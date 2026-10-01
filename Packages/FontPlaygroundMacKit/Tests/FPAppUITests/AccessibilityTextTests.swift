import AppKit
import FPCore
import Testing

@testable import FPAppUI

@MainActor struct AccessibilityTextTests {
    @Test("UI-13: custom controls expose meaningful labels") func ui13LabelsForCustomControls() throws {
        #expect(RecipeText.moreActionsAccessibilityLabel(family: "PingFang SC") == "More actions for PingFang SC")
        #expect(
            RecipeText.dotAccessibilityLabel(index: 1, locale: Locale(identifier: "en")) == "Colour 2 in Colour by Font"
        )
        #expect(
            RecipeText.cardAccessibilityLabel(role: "MAIN FONT", family: "Helvetica", style: "Regular")
                == "MAIN FONT: Helvetica Regular")
        #expect(PickerText.searchAccessibilityLabel == "Search fonts" && PickerText.tableLabel == "Fonts")
        #expect(
            PickerText.rowAccessibilityLabel(family: "Helvetica", nativeName: "", inRecipe: true)
                == "Helvetica, in your font")
        #expect(
            PickerText.rowAccessibilityLabel(family: "PingFang SC", nativeName: "苹方", inRecipe: true)
                == "PingFang SC, 苹方, in your font")
        #expect(PickerText.sampleHelp("abc") == "Sample: abc")
        #expect(PickerText.headerAccessibilityLabel("All Chinese fonts · 37") == "All Chinese fonts, 37")
        #expect(PreviewText.editorAccessibilityLabel == "Preview text")
        #expect(
            PreviewText.sizeAccessibilityLabel == "Preview size"
                && PreviewText.sizeAccessibilityValue(30) == "30 points")
        #expect(PreviewText.colourByFont == "Colour by Font" && PreviewText.sampleText == "Sample Text")
        #expect(PreviewText.builtBadgeAccessibilityLabel == "Showing the built font")
        #expect(BuildText.nameAccessibilityLabel == "Font name" && BuildText.styleAccessibilityLabel == "Style name")
        #expect(
            BuildText.progressAccessibilityLabel == "Building your font"
                && BuildText.progressAccessibilityValue(0.45) == "45 percent")
        #expect(
            ShellText.dismiss == "Dismiss" && ShellText.showAdvanced == "Show Advanced"
                && ShellText.hideAdvanced == "Hide Advanced")
        #expect(
            ShellText.addFontFolderAccessibilityLabel == "Add Font Folder"
                && ShellText.removeFolderAccessibilityLabel == "Remove Selected Folder")
        let rig = try ShellRig(), model = AppModel(services: rig.services)
        model.edit { $0.add(ShellFaces.make(text: "a")) }
        let row = try #require(AdvancedIntents.state(model).rows.first)
        #expect(row.label == ModelText.groupLabel(row.id) && !row.drawnByText.isEmpty)
    }
}
