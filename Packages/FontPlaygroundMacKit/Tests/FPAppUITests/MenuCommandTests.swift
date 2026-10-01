import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import SwiftUI
import Testing

@testable import FPAppUI

@MainActor struct MenuCommandTests {
    @Test("UI-2: menu bar has every command in order") func ui2MenuBarHasEveryCommand() {
        var rows: [(MenuCommand, MenuName, String, KeyboardShortcut?, MenuPlacement)] = [
            (.about, .app, "About Font Playground", nil, .appInfo),
            (.donate, .app, "Donate…", nil, .appInfo),
            (.startOver, .file, "Start Over", KeyboardShortcut("n"), .newItem),
            (.addFontFolder, .file, "Add Font Folder…", KeyboardShortcut("o"), .newItem),
            (.rescanFonts, .file, "Rescan Fonts", KeyboardShortcut("r"), .newItem),
            (.saveCopy, .file, "Save a Copy…", KeyboardShortcut("s", modifiers: [.shift, .command]), .beforeSaveItem),
            (.install, .file, "Install", nil, .beforeSaveItem),
            (
                .showInFinder, .file, "Show in Finder", KeyboardShortcut("r", modifiers: [.shift, .command]),
                .beforeSaveItem
            ), (.openInFontBook, .file, "Open in Font Book", nil, .beforeSaveItem),
            (.uninstall, .file, "Uninstall Font", nil, .beforeSaveItem),
            (.findFont, .edit, "Find Font…", KeyboardShortcut("f"), .afterPasteboard),
            (.colourByFont, .view, "Colour by Font", nil, .beforeToolbar),
            (.bigger, .view, "Bigger", KeyboardShortcut("+"), .beforeToolbar),
            (.smaller, .view, "Smaller", KeyboardShortcut("-"), .beforeToolbar),
            (.actualSize, .view, "Actual Size", KeyboardShortcut("0"), .beforeToolbar),
        ]
        rows += Samples.presets.map {
            (.sample(id: $0.id), .view, EnglishText.samplePresetLabel($0.id), nil, .sampleSubmenu)
        }
        rows += [
            (.sidebar, .view, "Show Sidebar", KeyboardShortcut("s", modifiers: [.control, .command]), .sidebar),
            (.chooseMainFont, .font, "Choose Main Font…", nil, .fontMenu),
        ]
        rows += Languages.all.filter { $0.id != .any }.map {
            (.addFontFor(languageID: $0.id.rawValue), .font, EnglishText.languageLabel($0.id), nil, .addFontForSubmenu)
        }
        rows += [
            (.addFontForAnyLanguage, .font, "Any Language…", nil, .addFontForSubmenu),
            (.advanced, .font, "Show Advanced", KeyboardShortcut("i", modifiers: [.option, .command]), .fontMenu),
            (.help, .help, "Font Playground Help", KeyboardShortcut("?"), .help),
        ]
        #expect(MenuCommand.allCases == rows.map { $0.0 } && AppCommands.menuOrder == MenuCommand.allCases)
        for (command, menu, title, shortcut, placement) in rows {
            #expect(
                command.menu == menu && command.defaultTitle == title && command.shortcut == shortcut
                    && command.placement == placement)
        }
    }
    @Test("UI-6: shortcuts are unique and avoid system keys") func shortcutsAreUniqueAndAvoidSystemKeys() {
        var seen = Set<KeyboardShortcut>()
        let reserved: Set<KeyEquivalent> = ["h", "q", "m", "w", ",", "z"]
        for command in MenuCommand.allCases {
            if let shortcut = command.shortcut {
                #expect(seen.insert(shortcut).inserted);
                #expect(shortcut.modifiers != .command || !reserved.contains(shortcut.key))
            }
        }
        #expect(MenuCommand.install.shortcut == nil)
    }
}
