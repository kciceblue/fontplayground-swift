import FPCore
import SwiftUI

public enum MenuName: String, Sendable { case app, file, edit, view, font, help }
public enum MenuPlacement: Equatable, Sendable {
    case appInfo, newItem, beforeSaveItem, afterPasteboard, beforeToolbar, sidebar, fontMenu, sampleSubmenu,
        addFontForSubmenu, help
}
public enum MenuCommand: Hashable, Sendable, CaseIterable {
    case about, donate, startOver, addFontFolder, rescanFonts, saveCopy, install, showInFinder, openInFontBook,
        uninstall, findFont, colourByFont, bigger, smaller, actualSize, sample(id: String), sidebar, chooseMainFont,
        addFontFor(languageID: String), addFontForAnyLanguage, advanced, help
    public static var allCases: [MenuCommand] {
        var result: [MenuCommand] = [
            .about, .donate, .startOver, .addFontFolder, .rescanFonts, .saveCopy, .install,
            .showInFinder, .openInFontBook, .uninstall, .findFont, .colourByFont, .bigger, .smaller, .actualSize,
        ]
        result += Samples.presets.map { .sample(id: $0.id) }
        result += [.sidebar, .chooseMainFont]
        result += Languages.all.filter { $0.id != .any }.map { .addFontFor(languageID: $0.id.rawValue) }
        result += [.addFontForAnyLanguage, .advanced, .help]
        return result
    }
    public var menu: MenuName {
        switch self {
        case .about, .donate: .app
        case .startOver, .addFontFolder, .rescanFonts, .saveCopy, .install, .showInFinder, .openInFontBook, .uninstall:
            .file
        case .findFont: .edit
        case .colourByFont, .bigger, .smaller, .actualSize, .sample, .sidebar: .view
        case .chooseMainFont, .addFontFor, .addFontForAnyLanguage, .advanced: .font
        case .help: .help
        }
    }
    public var defaultTitle: String {
        switch self {
        case .about: ShellText.about
        case .donate: ShellText.donate
        case .startOver: ShellText.startOver
        case .addFontFolder: ShellText.addFontFolder
        case .rescanFonts: ShellText.rescan
        case .saveCopy: ShellText.saveCopy
        case .install: ShellText.install
        case .showInFinder: ShellText.showInFinder
        case .openInFontBook: ShellText.openInFontBook
        case .uninstall: ShellText.uninstall
        case .findFont: ShellText.findFont
        case .colourByFont: ShellText.colourByFont
        case .bigger: ShellText.bigger
        case .smaller: ShellText.smaller
        case .actualSize: ShellText.actualSize
        case .sample(let id): ModelText.samplePresetLabel(id)
        case .sidebar: ShellText.showSidebar
        case .chooseMainFont: ShellText.chooseMain
        case .addFontFor(let id): LanguageID(rawValue: id).map(ModelText.languageLabel) ?? id
        case .addFontForAnyLanguage: ShellText.anyLanguage
        case .advanced: ShellText.showAdvanced
        case .help: ShellText.help
        }
    }
    public var shortcut: KeyboardShortcut? {
        switch self {
        case .startOver: KeyboardShortcut("n")
        case .addFontFolder: KeyboardShortcut("o")
        case .rescanFonts: KeyboardShortcut("r")
        case .saveCopy: KeyboardShortcut("s", modifiers: [.command, .shift])
        case .showInFinder: KeyboardShortcut("r", modifiers: [.command, .shift])
        case .findFont: KeyboardShortcut("f")
        case .bigger: KeyboardShortcut("+")
        case .smaller: KeyboardShortcut("-")
        case .actualSize: KeyboardShortcut("0")
        case .sidebar: KeyboardShortcut("s", modifiers: [.control, .command])
        case .advanced: KeyboardShortcut("i", modifiers: [.option, .command])
        case .help: KeyboardShortcut("?")
        default: nil
        }
    }
    public var placement: MenuPlacement {
        switch self {
        case .about, .donate: .appInfo
        case .startOver, .addFontFolder, .rescanFonts: .newItem
        case .saveCopy, .install, .showInFinder, .openInFontBook, .uninstall: .beforeSaveItem
        case .findFont: .afterPasteboard
        case .colourByFont, .bigger, .smaller, .actualSize: .beforeToolbar
        case .sample: .sampleSubmenu
        case .sidebar: .sidebar
        case .chooseMainFont, .advanced: .fontMenu
        case .addFontFor, .addFontForAnyLanguage: .addFontForSubmenu
        case .help: .help
        }
    }
}
