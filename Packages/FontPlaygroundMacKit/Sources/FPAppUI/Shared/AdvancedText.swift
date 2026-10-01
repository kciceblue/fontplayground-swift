import Foundation

public enum AdvancedText {
    public static var nobody: String { String(localized: "nobody", bundle: .module, comment: "advanced.nobody") }
    public static var noCount: String { String(localized: "—", bundle: .module, comment: "advanced.noCount") }
    public static func auto(_ name: String) -> String {
        String(localized: "Auto → \(name)", bundle: .module, comment: "advanced.auto")
    }
    public static func cannotShape(_ name: String, group: String) -> String {
        String(localized: "\(name) — can't shape \(group)", bundle: .module, comment: "advanced.cantShape")
    }
    public static var who: String { String(localized: "Who draws what", bundle: .module, comment: "advanced.who") }
    public static var drawnByHelp: String {
        String(
            localized: "Which font draws this script. Auto picks the highest font in your list that draws it well.",
            bundle: .module, comment: "advanced.drawnByHelp")
    }
    public static func showAll(_ count: Int) -> String {
        String(localized: "Show all \(count) scripts", bundle: .module, comment: "advanced.showAll")
    }
    public static var showAllHelp: String {
        String(
            localized: "Also list the scripts none of your fonts draws", bundle: .module,
            comment: "advanced.showAllHelp")
    }
    public static var lineSpacingSection: String {
        String(localized: "Line spacing", bundle: .module, comment: "advanced.lineSpacingSection")
    }
    public static var lineSpacing: String {
        String(localized: "Line spacing from", bundle: .module, comment: "advanced.lineSpacing")
    }
    public static var mainFont: String { String(localized: "Main font", bundle: .module, comment: "advanced.mainFont") }
    public static var lineSpacingHelp: String {
        String(
            localized: "Which font's line spacing your font uses (the main font's unless you choose)", bundle: .module,
            comment: "advanced.lineSpacingHelp")
    }
    public static var defaults: String { String(localized: "Defaults", bundle: .module, comment: "advanced.defaults") }
    public static var defaultBoldness: String {
        String(localized: "Default boldness", bundle: .module, comment: "advanced.defaultBoldness")
    }
    public static var defaultSize: String {
        String(localized: "Default size", bundle: .module, comment: "advanced.defaultSize")
    }
    public static func percent(_ value: Int) -> String {
        String(localized: "\(value) %", bundle: .module, comment: "advanced.percent")
    }
    public static var percentSuffix: String {
        String(localized: "%", bundle: .module, comment: "advanced.percentSuffix")
    }
    public static var defaultsNote: String {
        String(localized: "For fonts without their own setting.", bundle: .module, comment: "advanced.defaultsNote")
    }
    public static var defaultBoldnessHelp: String {
        String(
            localized: "Boldness of every font that has no Weight of its own", bundle: .module,
            comment: "advanced.defaultBoldnessHelp")
    }
    public static var defaultSizeHelp: String {
        String(
            localized: "Size of every font that has no Size of its own", bundle: .module,
            comment: "advanced.defaultSizeHelp")
    }
    public static var undo: String { String(localized: "Undo", bundle: .module, comment: "advanced.undo") }
    public static var lastBuild: String {
        String(localized: "Last build", bundle: .module, comment: "advanced.lastBuild")
    }
    public static var noBuild: String {
        String(localized: "No build yet.", bundle: .module, comment: "advanced.noBuild")
    }
}
