import AppKit
import SwiftUI

struct PreviewTextEditor: NSViewRepresentable {
    let model: AppModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSScrollView {
        Self.buildEditor(model: model, coordinator: context.coordinator).scrollView
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) { context.coordinator.refresh() }
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        if coordinator.model.previewController.textView === coordinator.textView {
            coordinator.model.previewController.textView = nil
        }
    }
    @MainActor static func makeEditor(model: AppModel, recordHistory: Bool = false) -> (
        scrollView: NSScrollView, textView: PreviewTextView, coordinator: Coordinator
    ) {
        let coordinator = Coordinator(model: model)
        coordinator.recordsHistory = recordHistory
        let editor = buildEditor(model: model, coordinator: coordinator)
        return (editor.scrollView, editor.textView, coordinator)
    }
    private static func buildEditor(model: AppModel, coordinator: Coordinator) -> (
        scrollView: NSScrollView, textView: PreviewTextView
    ) {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false; scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder; scroll.drawsBackground = true; scroll.backgroundColor = .textBackgroundColor
        scroll.wantsLayer = true; scroll.layer?.cornerRadius = 8
        let view = PreviewTextView(usingTextLayoutManager: true)
        view.identifier = NSUserInterfaceItemIdentifier("FPPreviewTextView")
        view.frame = scroll.contentView.bounds; view.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false; view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true;
        view.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        view.isRichText = true; view.isEditable = true; view.isSelectable = true; view.allowsUndo = true
        view.usesFontPanel = false; view.usesRuler = false; view.usesInspectorBar = false; view.importsGraphics = false
        view.allowsImageEditing = false; view.allowsDocumentBackgroundColorChange = false
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false; view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false; view.isGrammarCheckingEnabled = false
        view.isAutomaticLinkDetectionEnabled = false; view.isAutomaticDataDetectionEnabled = false
        view.isAutomaticTextCompletionEnabled = false; view.smartInsertDeleteEnabled = false
        view.textContainerInset = NSSize(width: 14, height: 14); view.backgroundColor = .textBackgroundColor
        view.setAccessibilityLabel(PreviewText.editorAccessibilityLabel);
        view.setAccessibilityHelp(PreviewText.editorHelp)
        view.delegate = coordinator; coordinator.textView = view; scroll.documentView = view
        view.string = model.recipe.sampleText
        coordinator.styler = PreviewStyler(
            textView: view, renderer: model.renderer, configuration: model.previewConfiguration,
            recordsHistory: coordinator.recordsHistory)
        view.pointSize = model.previewPointSize
        view.onZoom = { [weak model, weak view] size in
            model?.previewPointSize = size; view?.pointSize = size
        }
        model.previewController.textView = view
        return (scroll, view)
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        let model: AppModel
        weak var textView: PreviewTextView?
        var styler: PreviewStyler!
        private let undo = UndoManager()
        private var isApplyingModelText = false
        var recordsHistory = false
        private(set) var recipeUpdates: [String] = []
        init(model: AppModel) {
            self.model = model
            super.init()
            // TextKit may restore undo text without textDidChange, notably in an off-screen editor.
            for name in [Notification.Name.NSUndoManagerDidUndoChange, Notification.Name.NSUndoManagerDidRedoChange] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(undoDidFinish(_:)), name: name, object: undo)
            }
        }
        @objc private func undoDidFinish(_ notification: Notification) { textDidChange(notification) }
        func undoManager(for view: NSTextView) -> UndoManager? { undo }
        func textDidChange(_ notification: Notification) {
            guard !isApplyingModelText, let view = textView, !view.hasMarkedText(),
                view.string != model.recipe.sampleText
            else { return }
            model.recipe.setSampleText(view.string)
            if recordsHistory { recipeUpdates.append(view.string) }
        }
        func refresh() {
            guard let view = textView else { return }
            if !view.hasMarkedText(), view.string != model.recipe.sampleText {
                isApplyingModelText = true
                undo.disableUndoRegistration()
                view.textStorage?.replaceCharacters(
                    in: NSRange(location: 0, length: (view.string as NSString).length), with: model.recipe.sampleText)
                undo.enableUndoRegistration(); undo.removeAllActions(); isApplyingModelText = false
            }
            styler.apply(model.previewConfiguration); view.pointSize = model.previewPointSize
        }
    }
}
