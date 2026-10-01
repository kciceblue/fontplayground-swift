import FPCore
import Foundation

enum RecipeText {
    static let title = String(localized: "Your font", bundle: .module, comment: "recipe.title")
    static let subtitle = String(
        localized: "Combine installed fonts into one font that every app can use.", bundle: .module,
        comment: "recipe.subtitle")
    static let mainTitle = String(localized: "Main font", bundle: .module, comment: "recipe.main.title")
    static let mainDescription = String(
        localized: "The font you like for letters and numbers. It also sets the line spacing.", bundle: .module,
        comment: "recipe.main.description")
    static let chooseMain = String(localized: "Choose main font…", bundle: .module, comment: "recipe.main.choose")
    static let otherTitle = String(
        localized: "Fonts for other languages", bundle: .module, comment: "recipe.other.title")
    static let otherDescription = String(
        localized: "Chinese, Japanese, Korean… They fill in whatever the main font can't draw.", bundle: .module,
        comment: "recipe.other.description")
    static let mainRole = String(localized: "MAIN FONT", bundle: .module, comment: "recipe.main.role")
    static let lineSpacing = String(localized: "Sets the line spacing.", bundle: .module, comment: "recipe.lineSpacing")
    static let licence = String(
        localized: "Its licence restricts embedding — fine for your own use; check before sharing the result.",
        bundle: .module, comment: "recipe.licence")
    static let missingFont = String(
        localized: "Missing font — replace or remove it.", bundle: .module, comment: "recipe.missingFont")
    static let change = String(localized: "Change…", bundle: .module, comment: "recipe.change")
    static let changeHelp = String(
        localized: "Use another font in its place", bundle: .module, comment: "recipe.change.help")
    static let makeMain = String(localized: "Make Main Font", bundle: .module, comment: "recipe.makeMain")
    static let moveUp = String(localized: "Move Up", bundle: .module, comment: "recipe.moveUp")
    static let moveDown = String(localized: "Move Down", bundle: .module, comment: "recipe.moveDown")
    static let remove = String(localized: "Remove", bundle: .module, comment: "recipe.remove")
    static let style = String(localized: "Style", bundle: .module, comment: "recipe.style")
    static let styleHelp = String(
        localized: "Another style of the same family", bundle: .module, comment: "recipe.style.help")
    static let size = String(localized: "Size", bundle: .module, comment: "recipe.size")
    static let percent = String(localized: "%", bundle: .module, comment: "recipe.size.unit")
    static let sizeHelp = String(
        localized: "Draw this font's characters larger or smaller (100 % keeps them as they are)", bundle: .module,
        comment: "recipe.size.help")
    static let weight = String(localized: "Weight", bundle: .module, comment: "recipe.weight")
    static let weightHelp = String(
        localized: "Make this font bolder or lighter (“As is” keeps it unchanged)", bundle: .module,
        comment: "recipe.weight.help")
    static let add = String(localized: "Add a font for another language…", bundle: .module, comment: "recipe.add")
    static let anyLanguage = String(localized: "Any language…", bundle: .module, comment: "recipe.anyLanguage")
    static let advanced = String(localized: "Advanced…", bundle: .module, comment: "recipe.advanced")
    static let advancedHint = String(
        localized: "who draws what, line spacing", bundle: .module, comment: "recipe.advanced.hint")
    static let appleOnly = String(
        localized: "Apple-only ligatures and alternates in this font won't carry over.", bundle: .module,
        comment: "recipe.appleOnly")
    static let undo = String(localized: "Undo", bundle: .module, comment: "recipe.weight.undo")

    /// A restored recipe can hold any finite JSON number (`1e20`); validation reports it as out of range, so showing
    /// it must not trap in the `Int` conversion.
    static func scalePercent(_ scale: Double?) -> Int {
        guard let percent = scale.map({ ($0 * 100).rounded() }) else { return 100 }
        guard percent.isFinite else { return 100 }
        return Int(min(max(percent, -maxShownPercent), maxShownPercent))
    }
    private static let maxShownPercent = Double(Int32.max)
    static func percentScale(_ percent: Int) -> Double? { percent == 100 ? nil : Double(percent) / 100 }
    static var weightChoices: [(Int?, String)] { WeightChoice.standard.map { ($0.weight, $0.title) } }
    static func weightMenuItems(selected: Int?, locale: Locale = .current) -> [(Int?, String)] {
        var items = weightChoices
        if let selected, !items.contains(where: { $0.0 == selected }) {
            items.append((selected, selected.formatted(.number.locale(locale))))
        }
        return items
    }
    static func familyStyles(_ face: FaceRecord, _ catalog: [FaceRecord]) -> [FaceRecord] {
        Smart.familyStyles(of: face, in: FaceCatalog(catalog))
    }
    static func tallyLanguage(_ tally: [ScriptGroup: Int]) -> String { Languages.languageOfTally(tally).rawValue }
    static var addMenuLanguages: [Language] { Languages.all.filter { $0.id != .any } }
    static func promptText(_ languages: [Language], family: String) -> String {
        let labels = ModelText.joinLabels(languages.map(\.id))
        return String(
            localized: "Your text has \(labels) characters that \(family) can't draw.", bundle: .module,
            comment: "recipe.prompt")
    }
    static func promptButtonTitle(_ language: Language) -> String {
        let label = ModelText.languageShortLabel(language.id)
        return String(localized: "Choose a font for \(label)…", bundle: .module, comment: "recipe.chooseLanguage")
    }
    static func shapingProblem(family: String, language: Language) -> String {
        let label = ModelText.languageShortLabel(language.id)
        return String(
            localized: "\(family) can't shape \(label) in your font: its \(label) shaping is Apple-only.",
            bundle: .module, comment: "recipe.shapingProblem")
    }
    static func cardAccessibilityLabel(role: String, family: String, style: String) -> String {
        String(localized: "\(role): \(family) \(style)", bundle: .module, comment: "recipe.card.accessibility")
    }
    static func dotAccessibilityLabel(index: Int, locale: Locale = .current) -> String {
        let number = (index + 1).formatted(.number.locale(locale))
        return String(
            localized: "Colour \(number) in Colour by Font", bundle: .module, comment: "recipe.dot.accessibility")
    }
    static func moreActionsAccessibilityLabel(family: String) -> String {
        String(localized: "More actions for \(family)", bundle: .module, comment: "recipe.actions.accessibility")
    }
    static func sizeAccessibilityLabel(family: String) -> String {
        String(localized: "Size of \(family), percent", bundle: .module, comment: "recipe.size.accessibility")
    }
    static func weightAccessibilityLabel(family: String) -> String {
        String(localized: "Weight of \(family)", bundle: .module, comment: "recipe.weight.accessibility")
    }
}
