import AppKit
import FPCore
import FPMacServices
import SwiftUI
import os

struct FontListView: NSViewRepresentable {
    let model: PickerModel
    let cache: RowFontCache
    func makeCoordinator() -> Coordinator { Coordinator(model: model, cache: cache) }
    func makeNSView(context: Context) -> NSScrollView { context.coordinator.makeScrollView() }
    func updateNSView(_ scroll: NSScrollView, context: Context) { context.coordinator.update() }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let model: PickerModel
        let cache: RowFontCache
        let table = PickerTableView()
        private var previousRows: [PickerRow] = []
        private var previousLanguage: String?
        private var notification: PickerObservationToken?
        private var synchronizing = false
        init(model: PickerModel, cache: RowFontCache) { self.model = model; self.cache = cache; super.init() }
        func makeScrollView() -> NSScrollView {
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
            scroll.scrollerStyle = NSScroller.preferredScrollerStyle
            table.model = model; table.delegate = self; table.dataSource = self
            table.style = .inset; table.headerView = nil; table.selectionHighlightStyle = .regular
            table.floatsGroupRows = false; table.allowsTypeSelect = false; table.usesAutomaticRowHeights = false
            table.rowHeight = 64; table.intercellSpacing = .zero;
            table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
            table.setAccessibilityLabel(PickerText.tableLabel)
            let column = NSTableColumn(identifier: .init("font")); column.resizingMask = .autoresizingMask
            table.addTableColumn(column); table.target = self; table.doubleAction = #selector(doubleClick)
            scroll.documentView = table
            scroll.contentView.postsBoundsChangedNotifications = true
            notification = PickerObservationToken(
                NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: scroll.contentView, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.prefetch() }
                })
            cache.onFontsReady = { [weak self] keys in
                guard let self, !keys.isEmpty else { return }
                let visible = self.table.rows(in: self.table.visibleRect)
                guard visible.location != NSNotFound else { return }
                var indexes = IndexSet()
                for index in visible.location..<min(self.previousRows.count, NSMaxRange(visible)) {
                    if let face = self.previousRows[index].familyRow?.face, keys.contains(face.key) {
                        indexes.insert(index)
                    }
                }
                if !indexes.isEmpty {
                    self.table.reloadData(forRowIndexes: indexes, columnIndexes: IndexSet(integer: 0))
                }
            }
            model.visibleRowCount = { [weak table] in table?.visibleRowCount ?? 1 }
            model.scanStarted = { [weak cache] in cache?.removeAll() }
            update(); return scroll
        }
        func update() {
            let changed = previousRows != model.rows || previousLanguage != model.languageID
            if changed {
                previousRows = model.rows; previousLanguage = model.languageID
                synchronizing = true; table.reloadData(); synchronizing = false
            }
            let current = model.rows.firstIndex { $0.id == model.currentRowID }
            let selectionChanged = table.selectedRow != current
            synchronizing = true
            if let current {
                table.selectRowIndexes(IndexSet(integer: current), byExtendingSelection: false)
                if changed || selectionChanged { table.scrollRowToVisible(current) }
            } else {
                table.deselectAll(nil)
            }
            synchronizing = false
            prefetch()
        }
        func numberOfRows(in tableView: NSTableView) -> Int { previousRows.count }
        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            if case .header = previousRows[row] { true } else { false }
        }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            previousRows[row].familyRow == nil ? 28 : 64
        }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            previousRows.indices.contains(row) && previousRows[row].isSelectable
        }
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { PickerRowView() }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("pickerCell")
            let cell =
                tableView.makeView(withIdentifier: identifier, owner: self) as? FontRowCellView ?? FontRowCellView()
            cell.identifier = identifier;
            cell.configure(
                row: previousRows[row],
                language: Languages.language(rawID: previousLanguage ?? "any") ?? Languages.language(.any), cache: cache
            )
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !synchronizing, previousRows.indices.contains(table.selectedRow) else { return }
            model.select(previousRows[table.selectedRow].id)
        }
        @objc private func doubleClick() { handleDoubleClick(row: table.clickedRow) }
        func handleDoubleClick(row: Int) {
            guard previousRows.indices.contains(row), previousRows[row].isSelectable,
                model.rows.contains(where: { $0.id == previousRows[row].id && $0.isSelectable })
            else { return }
            model.select(previousRows[row].id); model.choose()
        }
        private func prefetch() {
            let visible = table.visibleRect
            guard visible.height > 0 else { return }
            let range = table.rows(in: visible.insetBy(dx: 0, dy: -visible.height))
            guard range.location != NSNotFound else { return }
            let indices = range.location..<min(previousRows.count, NSMaxRange(range))
            cache.prefetch(indices.compactMap { previousRows[$0].familyRow?.face }, sizes: [18, 14, 11])
        }

    }
}

@MainActor final class PickerTableView: NSTableView {
    weak var model: PickerModel?
    var visibleRowCount: Int {
        // An unattached AppKit view may report an unbounded visibleRect; use the viewport's actual height.
        let height = enclosingScrollView?.contentSize.height ?? bounds.height
        guard height.isFinite, height > 0 else { return 1 }
        return max(1, Int(min(height / 64, CGFloat(max(1, model?.rows.count ?? 1)))))
    }
    override func draw(_ dirtyRect: NSRect) { super.draw(dirtyRect); model?.firstTableDraw() }
    override func keyDown(with event: NSEvent) {
        guard let model else { super.keyDown(with: event); return }
        let command = event.modifierFlags.contains(.command)
        let selector: String?
        switch event.keyCode {
        case 126: selector = command ? "moveToBeginningOfDocument:" : "moveUp:"
        case 125: selector = command ? "moveToEndOfDocument:" : "moveDown:"
        case 116: selector = "pageUp:"
        case 121: selector = "pageDown:"
        case 115: selector = "scrollToBeginningOfDocument:"
        case 119: selector = "scrollToEndOfDocument:"
        case 36, 76: selector = "insertNewline:"
        case 53: selector = "cancelOperation:"
        case 47 where command: selector = "cancelOperation:"
        default: selector = nil
        }
        if let selector,
            SearchFieldView.Coordinator.handle(
                NSSelectorFromString(selector), model: model, visibleRows: visibleRowCount)
        {
            return
        }
        if !command, !event.modifierFlags.contains(.control), let text = event.characters, !text.isEmpty,
            text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        {
            model.insertSearchText(text); return
        }
        super.keyDown(with: event)
    }
}

@MainActor final class PickerRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { window?.isKeyWindow ?? false }
        set {}
    }
}

// The token is immutable; Foundation permits removing an observer from any thread.
private final class PickerObservationToken: @unchecked Sendable {
    let token: any NSObjectProtocol
    init(_ token: any NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}
