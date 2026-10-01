import AppKit

final class PreviewTextView: NSTextView {
    var pointSize = PreviewZoom.defaultSize
    var onZoom: (Int) -> Void = { _ in }
    private var startSize = PreviewZoom.defaultSize
    private var magnification = 0.0
    private var scrollCarry = 0.0
    // UI-6: Tab follows the window key-view loop; marked-text commands still belong to the input method.
    override func insertTab(_ sender: Any?) {
        if hasMarkedText() { super.insertTab(sender) } else { window?.selectNextKeyView(self) }
    }
    override func insertBacktab(_ sender: Any?) {
        if hasMarkedText() { super.insertBacktab(sender) } else { window?.selectPreviousKeyView(self) }
    }
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { [.string] }
    override func magnify(with event: NSEvent) {
        if event.phase.contains(.began) { startSize = pointSize; magnification = 0 }
        magnification += Double(event.magnification)
        onZoom(PreviewZoom.size(from: startSize, magnification: magnification))
    }
    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else { super.scrollWheel(with: event); return }
        let steps = PreviewZoom.scrollSteps(
            delta: Double(event.scrollingDeltaY), precise: event.hasPreciseScrollingDeltas, carry: &scrollCarry)
        if steps != 0 { onZoom(min(96, max(10, pointSize + steps))) }
    }
}
