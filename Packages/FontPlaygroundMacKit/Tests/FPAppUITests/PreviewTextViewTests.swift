import AppKit
import CoreText
import FPCore
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct PreviewTextViewTests {
    @Test func productionEditorDoesNotRetainEditingHistory() throws {
        let rig = try ShellRig(), model = AppModel(services: rig.services)
        model.recipe.setSampleText("")
        let editor = PreviewTextEditor.makeEditor(model: model)
        for _ in 0..<100 { editor.textView.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0)) }
        #expect(model.recipe.sampleText.count == 100)
        #expect(editor.coordinator.recipeUpdates.isEmpty && editor.coordinator.styler.restyledRanges.isEmpty)
        #expect(editor.textView.textLayoutManager != nil)
    }
    @Test func editorIsTextKit2WithSubstitutionsOff() throws {
        let rig = try ShellRig(), m = AppModel(services: rig.services),
            e = PreviewTextEditor.makeEditor(model: m, recordHistory: true),
            v = e.textView
        #expect(v.textLayoutManager != nil && v.isRichText && v.allowsUndo)
        #expect(
            !v.usesFontPanel && !v.usesRuler && !v.usesInspectorBar && !v.importsGraphics && !v.allowsImageEditing
                && !v.allowsDocumentBackgroundColorChange)
        #expect(
            !v.isAutomaticQuoteSubstitutionEnabled && !v.isAutomaticDashSubstitutionEnabled
                && !v.isAutomaticTextReplacementEnabled && !v.isAutomaticSpellingCorrectionEnabled)
        #expect(
            !v.isContinuousSpellCheckingEnabled && !v.isGrammarCheckingEnabled && !v.isAutomaticLinkDetectionEnabled
                && !v.isAutomaticDataDetectionEnabled && !v.isAutomaticTextCompletionEnabled
                && !v.smartInsertDeleteEnabled)
        #expect(m.previewPointSize == 30 && !m.colourByFont && m.previewConfiguration.mode == .empty)
        #expect(PreviewText.placeholder == "Type something to see it in your font")
        #expect(v.textContainerInset == NSSize(width: 14, height: 14))
    }
    @Test func eachParagraphIsRestyledOnItsOwn() throws {
        let f = try PreviewFixtureFonts(), m = f.model([f.a], text: "a\n漢\nb"),
            e = PreviewTextEditor.makeEditor(model: m, recordHistory: true), v = e.textView
        #expect(v.textStorage!.attribute(.backgroundColor, at: 2, effectiveRange: nil) != nil)
        #expect(
            [0, 1, 3, 4].allSatisfy { v.textStorage!.attribute(.backgroundColor, at: $0, effectiveRange: nil) == nil })
        e.coordinator.styler.resetRestyleLog(); v.insertText("c", replacementRange: NSRange(location: 4, length: 1))
        #expect(e.coordinator.styler.restyledRanges == [NSRange(location: 4, length: 1)])
        #expect(v.textLayoutManager != nil)
    }
    @Test func markedTextKeepsWorkingWhileRestyled() throws {
        let f = try PreviewFixtureFonts(), m = f.model([f.a, f.b], text: "ab"),
            e = PreviewTextEditor.makeEditor(model: m, recordHistory: true), v = e.textView
        v.setSelectedRange(NSRange(location: 2, length: 0))
        v.setMarkedText(
            "h", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        v.setMarkedText(
            "ha", selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(v.markedRange() == NSRange(location: 2, length: 2) && m.recipe.sampleText == "ab")
        #expect(v.textStorage!.attribute(.font, at: 2, effectiveRange: nil) != nil)
        v.insertText("漢", replacementRange: v.markedRange())
        #expect(!v.hasMarkedText() && m.recipe.sampleText == "ab漢")
        #expect(previewURL(previewFont(v, at: 2))?.path == f.b.path)
        #expect(e.coordinator.recipeUpdates == ["ab漢"] && v.textLayoutManager != nil)
    }
    @Test func pasteIsPlainText() throws {
        let f = try PreviewFixtureFonts(), m = f.model([f.a], text: ""),
            e = PreviewTextEditor.makeEditor(model: m, recordHistory: true),
            v = e.textView
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("fp-preview-" + UUID().uuidString));
        defer { pasteboard.releaseGlobally() }
        let rich = NSAttributedString(
            string: "bold big", attributes: [.font: NSFont.boldSystemFont(ofSize: 40), .foregroundColor: NSColor.red])
        let rtf = try rich.data(
            from: NSRange(location: 0, length: rich.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        pasteboard.declareTypes([.rtf, .string], owner: nil); pasteboard.setData(rtf, forType: .rtf);
        pasteboard.setString("bold big", forType: .string)
        #expect(v.readSelection(from: pasteboard)); #expect(v.string == "bold big")
        #expect(v.readablePasteboardTypes == [.string] && v.acceptableDragTypes == [.string])
        #expect(CTFontGetSize(previewFont(v, at: 0)) == 30 && previewURL(previewFont(v, at: 0))?.path == f.a.path)
        #expect(!CTFontGetSymbolicTraits(previewFont(v, at: 0)).contains(.boldTrait))
        #expect(v.textStorage!.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .textColor)
        #expect(v.textLayoutManager != nil)
    }
    @Test func editsSamplesAndUndo() throws {
        let f = try PreviewFixtureFonts(), m = f.model([f.a, f.b], text: "original"),
            e = PreviewTextEditor.makeEditor(model: m, recordHistory: true), v = e.textView
        m.recipe.setSampleText("ab"); e.coordinator.refresh(); e.coordinator.refresh()
        #expect(e.coordinator.recipeUpdates.isEmpty && !v.undoManager!.canUndo)
        v.setSelectedRange(NSRange(location: 2, length: 0));
        v.insertText("c", replacementRange: NSRange(location: NSNotFound, length: 0));
        v.insertText("1", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(e.coordinator.recipeUpdates == ["abc", "abc1"])
        #expect([2, 3].allSatisfy { v.textStorage!.attribute(.font, at: $0, effectiveRange: nil) != nil })
        let canUndo = v.undoManager!.canUndo; m.colourByFont = true; m.previewPointSize = 20; e.coordinator.refresh()
        #expect(e.coordinator.recipeUpdates == ["abc", "abc1"] && v.undoManager!.canUndo == canUndo)
        // A menu action arrives in its own AppKit event, after the typing event closes.
        while v.undoManager!.groupingLevel > 0 { v.undoManager!.endUndoGrouping() }
        v.undoManager!.beginUndoGrouping()
        m.applySample(id: "korean"); #expect(m.recipe.sampleText == Samples.presets.first { $0.id == "korean" }!.text)
        #expect(PreviewText.sampleSelectionLabel(m.recipe.sampleText) == "Korean")
        v.undoManager!.undo(); #expect(v.string == "abc1"); #expect(m.recipe.sampleText == "abc1")
        #expect(PreviewText.sampleSelectionLabel(m.recipe.sampleText) == "Custom Text")
        v.undoManager!.redo();
        #expect(v.string == Samples.presets.first { $0.id == "korean" }!.text && m.recipe.sampleText == v.string)
        #expect(PreviewText.sampleSelectionLabel(m.recipe.sampleText) == "Korean")
        #expect(v.textLayoutManager != nil)
    }
    @Test("UI-M6: pinch, command-scroll and keys zoom") func uiM6PinchScrollAndKeysZoom() throws {
        #expect(
            PreviewZoom.size(from: 30, magnification: 0.5) == 45
                && PreviewZoom.size(from: 30, magnification: -0.9) == 10
                && PreviewZoom.size(from: 90, magnification: 0.5) == 96)
        var carry = 0.0; #expect(PreviewZoom.scrollSteps(delta: 7, precise: true, carry: &carry) == 0);
        #expect(PreviewZoom.scrollSteps(delta: 10, precise: true, carry: &carry) == 2 && carry == 1)
        let rig = try ShellRig(), m = AppModel(services: rig.services),
            e = PreviewTextEditor.makeEditor(model: m, recordHistory: true),
            origin = e.scrollView.contentView.bounds.origin
        let cg = try #require(
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 16, wheel2: 0, wheel3: 0));
        cg.flags = .maskCommand
        e.textView.scrollWheel(with: try #require(NSEvent(cgEvent: cg)))
        #expect(m.previewPointSize == 32 && e.scrollView.contentView.bounds.origin == origin)
        cg.flags = []; e.textView.scrollWheel(with: try #require(NSEvent(cgEvent: cg)));
        #expect(m.previewPointSize == 32)
        m.previewPointSize = 30; m.zoomPreviewIn(); #expect(m.previewPointSize == 36)
        m.previewPointSize = 30; m.zoomPreviewOut(); #expect(m.previewPointSize == 24)
        m.resetPreviewZoom(); #expect(m.previewPointSize == 30); m.previewPointSize = 96; m.zoomPreviewIn();
        #expect(m.previewPointSize == 96); m.previewPointSize = 10; m.zoomPreviewOut();
        #expect(m.previewPointSize == 10)
        #expect(e.textView.textLayoutManager != nil)
    }
}
