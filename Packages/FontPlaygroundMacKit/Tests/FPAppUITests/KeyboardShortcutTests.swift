import AppKit
import SwiftUI
import Testing

@testable import FPAppUI

@MainActor struct KeyboardShortcutTests {
    @Test("UI-6: every command is reachable with its intended shortcut") func everyCommandIsReachable() {
        #expect(AppCommands.menuOrder == MenuCommand.allCases)
        #expect(Set(AppCommands.menuOrder).count == MenuCommand.allCases.count)
        let shortcuts: [MenuCommand: KeyboardShortcut] = [
            .startOver: KeyboardShortcut("n"), .addFontFolder: KeyboardShortcut("o"),
            .rescanFonts: KeyboardShortcut("r"), .saveCopy: KeyboardShortcut("s", modifiers: [.shift, .command]),
            .showInFinder: KeyboardShortcut("r", modifiers: [.shift, .command]), .findFont: KeyboardShortcut("f"),
            .bigger: KeyboardShortcut("+"), .smaller: KeyboardShortcut("-"), .actualSize: KeyboardShortcut("0"),
            .sidebar: KeyboardShortcut("s", modifiers: [.control, .command]),
            .advanced: KeyboardShortcut("i", modifiers: [.option, .command]), .help: KeyboardShortcut("?"),
        ]
        for command in MenuCommand.allCases { #expect(command.shortcut == shortcuts[command]) }
    }
    @Test func cancelButtonUsesCancelAction() { #expect(ActionBarView.cancelShortcut == .cancelAction) }
    @Test func primaryHasNoShortcut() { #expect(ActionBarView.primaryShortcut == nil) }
    @Test("UI-6: Tab moves from the preview through the native key-view loop") func tabLeavesThePreview() throws {
        let rig = try ShellRig(), model = AppModel(services: rig.services),
            editor = PreviewTextEditor.makeEditor(model: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let content = NSView(frame: window.contentRect(forFrameRect: window.frame)),
            target = KeyboardTarget(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        content.addSubview(editor.scrollView); content.addSubview(target); window.contentView = content
        editor.textView.nextKeyView = target; target.nextKeyView = editor.textView
        let text = editor.textView.string
        window.makeFirstResponder(editor.textView); editor.textView.insertTab(nil)
        #expect(window.firstResponder === target && editor.textView.string == text)
        window.makeFirstResponder(editor.textView); editor.textView.insertBacktab(nil)
        #expect(window.firstResponder === target && editor.textView.string == text)
        #expect(!window.isVisible)
    }
}
@MainActor private final class KeyboardTarget: NSView { override var acceptsFirstResponder: Bool { true } }
