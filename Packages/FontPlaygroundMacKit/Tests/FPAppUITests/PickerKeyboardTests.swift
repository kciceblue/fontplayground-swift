import AppKit
import Testing

@testable import FPAppUI

@MainActor struct PickerKeyboardTests {
    typealias F = PickerTestFaces
    @Test func commandsMoveSkippingHeaders() {
        let model = F.model(context: F.context("latin", suggestions: [F.z]))
        let coordinator = SearchFieldView.Coordinator(model: model, visibleRows: { 3 })
        let field = NSSearchField(), editor = NSTextView()
        for (command, row) in [
            ("moveDown:", 3), ("moveDown:", 4), ("moveDown:", 4), ("moveUp:", 3), ("moveUp:", 1), ("moveUp:", 1),
            ("scrollPageDown:", 4), ("scrollPageUp:", 1), ("moveToEndOfDocument:", 4),
            ("moveToBeginningOfDocument:", 1),
            ("scrollToEndOfDocument:", 4), ("scrollToBeginningOfDocument:", 1),
        ] {
            #expect(coordinator.control(field, textView: editor, doCommandBy: NSSelectorFromString(command)))
            #expect(model.currentRowID == model.rows[row].id)
        }
        #expect(!coordinator.control(field, textView: editor, doCommandBy: NSSelectorFromString("insertText:")))
    }
    @Test func returnUsesTheFamilysDefaultFace() {
        for main in [nil, F.lb] {
            let model = F.model(context: F.context("latin", main: main)); var chosen: String?
            model.onUse = { chosen = $0.style }
            let coordinator = SearchFieldView.Coordinator(model: model, visibleRows: { 3 })
            #expect(
                coordinator.control(
                    NSSearchField(), textView: NSTextView(), doCommandBy: NSSelectorFromString("insertNewline:")))
            #expect(chosen == (main == nil ? "Regular" : "Bold"))
        }
    }
}
