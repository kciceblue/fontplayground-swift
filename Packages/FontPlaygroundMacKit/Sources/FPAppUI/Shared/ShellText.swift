import Foundation

public enum ShellText {
    public static let removeFolderAccessibilityLabel = String(
        localized: "Remove Selected Folder", bundle: .module, comment: "shell.removeFolder.accessibility")
    public static let addFontFolderAccessibilityLabel = String(
        localized: "Add Font Folder", bundle: .module, comment: "shell.addFolder.accessibility")
    public static var windowTitle: String {
        String(localized: "Font Playground", bundle: .module, comment: "shell.windowTitle")
    }
    public static var about: String {
        String(localized: "About Font Playground", bundle: .module, comment: "shell.about")
    }
    public static var donate: String { String(localized: "Donate…", bundle: .module, comment: "shell.donate") }
    public static var donateTitle: String {
        String(localized: "Support Font Playground", bundle: .module, comment: "shell.donate.title")
    }
    public static var donateMessage: String {
        String(
            localized:
                "Font Playground is free. If you find it useful, you can buy me a coffee to support its development. You won't see this message again, but Font Playground › Donate… is always there.",
            bundle: .module, comment: "shell.donate.message")
    }
    public static var buyMeACoffee: String {
        String(localized: "Buy Me a Coffee", bundle: .module, comment: "shell.donate.confirm")
    }
    public static var noThanks: String {
        String(localized: "No Thanks", bundle: .module, comment: "shell.donate.decline")
    }
    public static var startOver: String { String(localized: "Start Over", bundle: .module, comment: "shell.startOver") }
    public static var cancel: String { String(localized: "Cancel", bundle: .module, comment: "shell.cancel") }
    public static var addFontFolder: String {
        String(localized: "Add Font Folder…", bundle: .module, comment: "shell.addFontFolder")
    }
    public static var rescan: String { String(localized: "Rescan Fonts", bundle: .module, comment: "shell.rescan") }
    public static var saveCopy: String { String(localized: "Save a Copy…", bundle: .module, comment: "shell.saveCopy") }
    public static var install: String { String(localized: "Install", bundle: .module, comment: "shell.install") }
    public static var showInFinder: String {
        String(localized: "Show in Finder", bundle: .module, comment: "shell.showInFinder")
    }
    public static var openInFontBook: String {
        String(localized: "Open in Font Book", bundle: .module, comment: "shell.openInFontBook")
    }
    public static var uninstall: String {
        String(localized: "Uninstall Font", bundle: .module, comment: "shell.uninstall")
    }
    public static var findFont: String { String(localized: "Find Font…", bundle: .module, comment: "shell.findFont") }
    public static var colourByFont: String {
        String(localized: "Colour by Font", bundle: .module, comment: "shell.colourByFont")
    }
    public static var bigger: String { String(localized: "Bigger", bundle: .module, comment: "shell.bigger") }
    public static var smaller: String { String(localized: "Smaller", bundle: .module, comment: "shell.smaller") }
    public static var actualSize: String {
        String(localized: "Actual Size", bundle: .module, comment: "shell.actualSize")
    }
    public static var sampleText: String {
        String(localized: "Sample Text", bundle: .module, comment: "shell.sampleText")
    }
    public static var showSidebar: String {
        String(localized: "Show Sidebar", bundle: .module, comment: "shell.showSidebar")
    }
    public static var chooseMain: String {
        String(localized: "Choose Main Font…", bundle: .module, comment: "shell.chooseMain")
    }
    public static var changeMain: String {
        String(localized: "Change Main Font…", bundle: .module, comment: "shell.changeMain")
    }
    public static var addFontFor: String {
        String(localized: "Add Font For", bundle: .module, comment: "shell.addFontFor")
    }
    public static var anyLanguage: String {
        String(localized: "Any Language…", bundle: .module, comment: "shell.anyLanguage")
    }
    public static var showAdvanced: String {
        String(localized: "Show Advanced", bundle: .module, comment: "shell.showAdvanced")
    }
    public static var hideAdvanced: String {
        String(localized: "Hide Advanced", bundle: .module, comment: "shell.hideAdvanced")
    }
    public static var help: String { String(localized: "Font Playground Help", bundle: .module, comment: "shell.help") }
    public static var fontMenu: String { String(localized: "Font", bundle: .module, comment: "shell.fontMenu") }
    public static var quitTitle: String {
        String(localized: "Your font is still being built. Quit anyway?", bundle: .module, comment: "shell.quitTitle")
    }
    public static var quit: String { String(localized: "Quit", bundle: .module, comment: "shell.quit") }
    public static var keepBuilding: String {
        String(localized: "Keep Building", bundle: .module, comment: "shell.keepBuilding")
    }
    public static var startOverTitle: String {
        String(localized: "Start over?", bundle: .module, comment: "shell.startOverTitle")
    }
    public static var startOverMessage: String {
        String(
            localized:
                "This clears your fonts and names. Your sample text stays, and fonts you saved or installed are not affected.",
            bundle: .module, comment: "shell.startOverMessage")
    }
    public static var startOverBuilding: String {
        String(localized: " The build in progress will stop.", bundle: .module, comment: "shell.startOverBuilding")
    }
    public static var addFolder: String { String(localized: "Add Folder", bundle: .module, comment: "shell.addFolder") }
    public static var folderMessage: String {
        String(
            localized: "Choose folders that contain fonts. The fonts don't need to be installed.", bundle: .module,
            comment: "shell.folderMessage")
    }
    public static var appearance: String {
        String(localized: "Appearance", bundle: .module, comment: "shell.appearance")
    }
    public static var system: String { String(localized: "System", bundle: .module, comment: "shell.system") }
    public static var light: String { String(localized: "Light", bundle: .module, comment: "shell.light") }
    public static var dark: String { String(localized: "Dark", bundle: .module, comment: "shell.dark") }
    public static var language: String { String(localized: "Language", bundle: .module, comment: "shell.language") }
    public static var languageFooter: String {
        String(
            localized: "Font Playground uses a new language after it reopens.", bundle: .module,
            comment: "shell.languageFooter")
    }
    public static func reopenTitle(language: String) -> String {
        String(localized: "Reopen Font Playground in \(language)?", bundle: .module, comment: "shell.reopenTitle")
    }
    public static var reopenMessage: String {
        String(localized: "Your recipe is saved first.", bundle: .module, comment: "shell.reopenMessage")
    }
    public static var quitAndReopen: String {
        String(localized: "Quit and Reopen", bundle: .module, comment: "shell.quitAndReopen")
    }
    public static var later: String { String(localized: "Later", bundle: .module, comment: "shell.later") }
    public static var fontFolders: String {
        String(localized: "Font folders", bundle: .module, comment: "shell.fontFolders")
    }
    public static var removeFolder: String {
        String(localized: "Remove Folder", bundle: .module, comment: "shell.removeFolder")
    }
    public static var folderFooter: String {
        String(
            localized: "Fonts in these folders show up in Font Playground without being installed.", bundle: .module,
            comment: "shell.folderFooter")
    }
    public static var showSettingsFolder: String {
        String(localized: "Show Settings Folder in Finder", bundle: .module, comment: "shell.showSettingsFolder")
    }
    public static var getMoreFonts: String {
        String(localized: "Get More Fonts…", bundle: .module, comment: "shell.getMoreFonts")
    }
    public static var fontBookFooter: String {
        String(
            localized: "Font Book can download more fonts that come with macOS.", bundle: .module,
            comment: "shell.fontBookFooter")
    }
    public static var dismiss: String { String(localized: "Dismiss", bundle: .module, comment: "shell.dismiss") }
    public static var done: String { String(localized: "Done", bundle: .module, comment: "shell.done") }
    public static var copy: String { String(localized: "Copy", bundle: .module, comment: "shell.copy") }
    public static var reportTitle: String {
        String(localized: "Build Report", bundle: .module, comment: "shell.reportTitle")
    }
    public static var fileDropped: String {
        String(
            localized:
                "To use a font file, add the folder it's in with File › Add Font Folder…, or install it with Font Book.",
            bundle: .module, comment: "shell.fileDropped")
    }
    public static var imported: String {
        String(
            localized: "Imported your last recipe and settings from the earlier version of Font Playground.",
            bundle: .module, comment: "shell.imported")
    }
    public static var importFailed: String {
        String(
            localized: "Font Playground found settings from an earlier version but couldn't read them.",
            bundle: .module, comment: "shell.importFailed")
    }
    public static var licenceNote: String {
        String(
            localized:
                "Font Playground doesn't include or sell any fonts. Fonts you forge keep their sources' licences; Font Playground tells you what it knows about them, but it is up to you to respect them.",
            bundle: .module, comment: "shell.licenceNote")
    }
    public static var acknowledgements: String {
        String(localized: "Acknowledgements", bundle: .module, comment: "shell.acknowledgements")
    }
    public static var engineMissing: String {
        String(localized: "its files are missing from the app", bundle: .module, comment: "shell.engineMissing")
    }
    public static var engineLaunchFailed: String {
        String(localized: "it couldn't be started", bundle: .module, comment: "shell.engineLaunchFailed")
    }
    public static var engineTimedOut: String {
        String(localized: "it didn't answer in time", bundle: .module, comment: "shell.engineTimedOut")
    }
    public static var engineStopped: String {
        String(localized: "it stopped unexpectedly", bundle: .module, comment: "shell.engineStopped")
    }
    public static var licence: String { String(localized: "Licence:", bundle: .module, comment: "shell.licence") }
    public static var warnings: String { String(localized: "Warnings:", bundle: .module, comment: "shell.warnings") }
    public static var asIs: String { String(localized: "As is", bundle: .module, comment: "shell.asIs") }
    /// A context key (localisation.md §L2): weight 300 stays "Light" in Chinese, while the Appearance "Light" is 浅色.
    public static var weightLight: String {
        String(localized: "weight.light", defaultValue: "Light", bundle: .module, comment: "shell.weightLight")
    }
    public static var regular: String { String(localized: "Regular", bundle: .module, comment: "shell.regular") }
    public static var medium: String { String(localized: "Medium", bundle: .module, comment: "shell.medium") }
    public static var semibold: String { String(localized: "Semibold", bundle: .module, comment: "shell.semibold") }
    public static var bold: String { String(localized: "Bold", bundle: .module, comment: "shell.bold") }
    public static var heavy: String { String(localized: "Heavy", bundle: .module, comment: "shell.heavy") }
    public static func suggestion(missing: String, replacement: String) -> String {
        String(
            localized: "\(missing) isn't on this Mac. Use \(replacement) instead?", bundle: .module,
            comment: "shell.suggestion")
    }
    public static func unavailableOne(name: String) -> String {
        String(
            localized:
                "“\(name)” is no longer available. It stays in your font, marked as missing, until you replace or remove it.",
            bundle: .module, comment: "shell.unavailableOne")
    }
    public static func unavailableMany(count: Int, names: String) -> String {
        String(
            localized:
                "\(count) fonts are no longer available: \(names). They stay in your font, marked as missing, until you replace or remove them.",
            bundle: .module, comment: "shell.unavailableMany")
    }
    public static func damaged(name: String) -> String {
        String(
            localized:
                "Your last recipe couldn't be read, so Font Playground started with an empty one. The file was kept as “\(name)”.",
            bundle: .module, comment: "shell.damaged")
    }
    public static func engineUnavailable(reason: String) -> String {
        String(
            localized: "Font Playground can't start its font engine, so it can't list or build fonts: \(reason)",
            bundle: .module, comment: "shell.engineUnavailable")
    }
    public static func badFolders(paths: String) -> String {
        String(
            localized: "Some saved font folders were ignored because they aren't valid on this Mac: \(paths).",
            bundle: .module, comment: "shell.badFolders")
    }
    public static func autosaveFailed(reason: String) -> String {
        String(
            localized: "Font Playground couldn't save your recipe: \(reason)", bundle: .module,
            comment: "shell.autosaveFailed")
    }
    public static func useReplacement(name: String) -> String {
        String(localized: "Use \(name)", bundle: .module, comment: "shell.useReplacement")
    }
    public static func engineIncompatible(reported: Int, supported: Int) -> String {
        String(
            localized: "it's a different version (protocol \(reported), expected \(supported))", bundle: .module,
            comment: "shell.engineIncompatible")
    }
    public static func engineVersion(engine: String, fonttools: String, python: String) -> String {
        String(
            localized: "Font engine: fpengine \(engine), fontTools \(fonttools), Python \(python)", bundle: .module,
            comment: "shell.engineVersion")
    }
    public static func reportFont(name: String) -> String {
        String(localized: "Font: \(name)", bundle: .module, comment: "shell.reportFont")
    }
    public static func reportPostscript(name: String) -> String {
        String(localized: " (PostScript name \(name))", bundle: .module, comment: "shell.reportPostscript")
    }
    public static func reportCounts(characters: Int, glyphs: Int) -> String {
        String(
            localized: "Characters: \(characters)   Glyphs: \(glyphs)", bundle: .module, comment: "shell.reportCounts")
    }
    public static func reportDuration(seconds: String) -> String {
        String(localized: "Built in \(seconds) s", bundle: .module, comment: "shell.reportDuration")
    }
    public static func reportMaterial(name: String, count: Int, groups: String) -> String {
        String(localized: "\(name): \(count) characters  [\(groups)]", bundle: .module, comment: "shell.reportMaterial")
    }
    public static func reportWarning(message: String) -> String {
        String(localized: "    warning: \(message)", bundle: .module, comment: "shell.reportWarning")
    }
    public static func quoted(_ names: [String]) -> String {
        names.map { "“\($0)”" }.joined(separator: ModelText.listSeparator)
    }
    public static func shortPath(_ path: String, home: String = FileManager.default.homeDirectoryForCurrentUser.path)
        -> String
    { path.hasPrefix(home + "/") ? "~/" + String(path.dropFirst(home.count + 1)) : path }
    public static func restorationIssues(_ details: String) -> String {
        String(
            localized: "Some saved entries couldn't be used: \(details).", bundle: .module,
            comment: "shell.notice.restorationIssues")
    }
    public static func duplicateEntries(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 duplicate font entry", bundle: .module, comment: "shell.restore.duplicateOne")
            : String(
                localized: "\(count) duplicate font entries", bundle: .module, comment: "shell.restore.duplicateMany")
    }
    public static func invalidEntries(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 invalid font entry", bundle: .module, comment: "shell.restore.invalidOne")
            : String(localized: "\(count) invalid font entries", bundle: .module, comment: "shell.restore.invalidMany")
    }
    public static func ignoredRules(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 font rule", bundle: .module, comment: "shell.restore.ruleOne")
            : String(localized: "\(count) font rules", bundle: .module, comment: "shell.restore.ruleMany")
    }
    public static func ignoredSettings(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 setting", bundle: .module, comment: "shell.restore.settingOne")
            : String(localized: "\(count) settings", bundle: .module, comment: "shell.restore.settingMany")
    }
    public static var ignoredLineSpacingFont: String {
        String(localized: "the saved line-spacing font", bundle: .module, comment: "shell.restore.lineSpacing")
    }
    public static func ignoredOutputPath(_ path: String) -> String {
        String(localized: "the saved output path “\(path)”", bundle: .module, comment: "shell.restore.outputPath")
    }

}
