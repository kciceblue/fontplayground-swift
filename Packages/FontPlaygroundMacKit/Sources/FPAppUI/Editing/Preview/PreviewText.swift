import FPCore
import Foundation

public struct MissingNote: Equatable {
    public var text: String; public var buttonTitle: String; public var request: PickRequest
}
public enum PreviewText {
    public static var title: String { String(localized: "Preview", bundle: .module, comment: "preview.title") }
    public static var hint: String {
        String(localized: "Click and type to try your own text", bundle: .module, comment: "preview.hint")
    }
    public static var colourByFont: String {
        String(localized: "Colour by Font", bundle: .module, comment: "preview.colourByFont")
    }
    public static var colourHelp: String {
        String(
            localized: "Draw each font's characters in that font's colour", bundle: .module,
            comment: "preview.colourHelp")
    }
    public static var size: String { String(localized: "Size", bundle: .module, comment: "preview.size") }
    public static var sampleText: String {
        String(localized: "Sample Text", bundle: .module, comment: "preview.sampleText")
    }
    public static func sampleSelectionLabel(_ text: String) -> String {
        // Derive the selection from the recipe so typing, undo and document loads stay in sync.
        guard let preset = Samples.presets.first(where: { $0.text == text }) else {
            return String(localized: "Custom Text", bundle: .module, comment: "preview.customText")
        }
        return ModelText.samplePresetLabel(preset.id)
    }
    public static var sampleHelp: String {
        String(
            localized: "Replace the text with a sample (⌘Z brings yours back)", bundle: .module,
            comment: "preview.sampleHelp")
    }
    public static var placeholder: String {
        String(localized: "Type something to see it in your font", bundle: .module, comment: "preview.placeholder")
    }
    public static var builtBadge: String {
        String(localized: "Built font", bundle: .module, comment: "preview.builtBadge")
    }
    public static var findFont: String {
        String(localized: "Find a font…", bundle: .module, comment: "preview.findFont")
    }
    public static var sizeAccessibilityLabel: String {
        String(localized: "Preview size", bundle: .module, comment: "preview.sizeAccessibilityLabel")
    }
    public static var builtBadgeAccessibilityLabel: String {
        String(localized: "Showing the built font", bundle: .module, comment: "preview.builtBadgeAccessibilityLabel")
    }
    public static var editorAccessibilityLabel: String {
        String(localized: "Preview text", bundle: .module, comment: "preview.editorAccessibilityLabel")
    }
    public static var editorHelp: String {
        String(
            localized: "Type to try your own text. Each character is drawn by the font that will draw it in your font.",
            bundle: .module, comment: "preview.editorHelp")
    }
    public static func sizeText(_ size: Int) -> String {
        String(localized: "\(size) pt", bundle: .module, comment: "preview.sizeValue")
    }
    public static func sizeAccessibilityValue(_ size: Int) -> String {
        String(localized: "\(size) points", bundle: .module, comment: "preview.sizeAccessibilityValue")
    }
    public static func builtHelp(_ displayName: String) -> String {
        String(
            localized:
                "Showing \(displayName), the font that was just built. Change your font to go back to the preview of the mix.",
            bundle: .module, comment: "preview.builtHelp")
    }
    public static func addFontButtonTitle(_ language: Language) -> String {
        let label = ModelText.languageShortLabel(language.id)
        return String(localized: "Add a font for \(label)…", bundle: .module, comment: "preview.addFont")
    }
    public static func missingText(_ scalars: [Unicode.Scalar]) -> String {
        var listed = scalars.prefix(12).map { "“\($0)”" }.joined(separator: ModelText.listSeparator)
        if scalars.count > 12 {
            let remainder = scalars.count - 12;
            listed = String(
                localized: "\(listed) and \(remainder) more", bundle: .module, comment: "preview.moreMissing")
        }
        if scalars.count == 1 {
            return String(
                localized: "\(listed) isn't in any of your fonts, so it would show as a box.", bundle: .module,
                comment: "preview.missingOne")
        }
        return String(
            localized: "\(listed) aren't in any of your fonts, so they would show as boxes.", bundle: .module,
            comment: "preview.missingMany")
    }
    public static func missingNote(_ configuration: PreviewConfiguration, text: String) -> MissingNote? {
        let missing = configuration.missingScalars(in: text); guard !missing.isEmpty else { return nil }
        let language = Languages.languagesForMissing(missing).first
        return MissingNote(
            text: missingText(missing), buttonTitle: language.map(addFontButtonTitle) ?? findFont,
            request: PickRequest(languageID: language?.id.rawValue ?? "any"))
    }
}
