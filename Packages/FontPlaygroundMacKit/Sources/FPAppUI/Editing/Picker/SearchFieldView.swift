import AppKit
import SwiftUI

struct SearchFieldView: NSViewRepresentable {
    let model: PickerModel
    var visibleRows: @MainActor () -> Int = { 10 }
    func makeCoordinator() -> Coordinator { Coordinator(model: model, visibleRows: visibleRows) }
    func makeNSView(context: Context) -> NSSearchField {
        let field = PickerSearchField()
        field.delegate = context.coordinator
        field.placeholderString = model.searchPlaceholder
        field.setAccessibilityLabel(PickerText.searchAccessibilityLabel)
        field.sendsSearchStringImmediately = true
        model.focusSearch = { [weak field] selectAll in
            guard let field, let window = field.window else { return }
            window.makeFirstResponder(field)
            if selectAll { field.selectText(nil) }
        }
        model.insertSearchText = { [weak field, weak model] text in
            guard let field, let model else { return }
            model.focusSearch(false)
            if let editor = field.currentEditor() as? NSTextView {
                editor.insertText(text, replacementRange: editor.selectedRange())
                model.query = field.stringValue
            } else {
                field.stringValue += text; model.query = field.stringValue
            }
        }
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) {
        field.placeholderString = model.searchPlaceholder
        if (field.currentEditor() as? NSTextView)?.hasMarkedText() != true, field.stringValue != model.query {
            field.stringValue = model.query
        }
    }
    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        let model: PickerModel
        let visibleRows: @MainActor () -> Int
        init(model: PickerModel, visibleRows: @escaping @MainActor () -> Int) {
            self.model = model; self.visibleRows = visibleRows
        }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField,
                (field.currentEditor() as? NSTextView)?.hasMarkedText() != true
            else { return }
            model.query = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            return Self.handle(commandSelector, model: model, visibleRows: visibleRows())
        }
        static func handle(_ selector: Selector, model: PickerModel, visibleRows: Int) -> Bool {
            switch NSStringFromSelector(selector) {
            case "moveUp:": model.move(by: -1)
            case "moveDown:": model.move(by: 1)
            case "scrollPageUp:", "pageUp:": model.page(by: -1, visibleRows: visibleRows)
            case "scrollPageDown:", "pageDown:": model.page(by: 1, visibleRows: visibleRows)
            case "moveToBeginningOfDocument:", "scrollToBeginningOfDocument:": model.moveToStart()
            case "moveToEndOfDocument:", "scrollToEndOfDocument:": model.moveToEnd()
            case "insertNewline:": model.choose()
            case "cancelOperation:": model.requestCancel()
            default: return false
            }
            return true
        }
    }
}

@MainActor private final class PickerSearchField: NSSearchField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.makeFirstResponder(self)
    }
}
