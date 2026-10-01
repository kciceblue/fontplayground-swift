import AppKit
import FPCore
import FPMacServices
import ObjectiveC
import SwiftUI
import Testing

@testable import FPAppUI

@MainActor struct PickerTableTests {
    typealias F = PickerTestFaces
    @Test("UI-14: native scrollers and selection") func ui14NativeScrollersAndSelection() {
        let rig = PickerTableRig(model: F.model("latin"))
        #expect(rig.table.style == .inset && rig.table.selectionHighlightStyle == .regular)
        #expect(rig.scroll.autohidesScrollers && rig.scroll.scrollerStyle == NSScroller.preferredScrollerStyle)
        let inset = rig.scroll.contentInsets
        #expect(inset.top == 0 && inset.bottom == 0 && inset.left == 0 && inset.right == 0)
        let row = rig.coordinator.tableView(rig.table, rowViewForRow: 1)
        #expect(row is PickerRowView)
        for selector in ["drawSelectionInRect:", "drawBackgroundInRect:", "drawSeparatorInRect:"] {
            let native = class_getInstanceMethod(NSTableRowView.self, NSSelectorFromString(selector))!
            let actual = class_getInstanceMethod(PickerRowView.self, NSSelectorFromString(selector))!
            #expect(method_getImplementation(native) == method_getImplementation(actual))
        }
    }
    @Test func returnDoubleClickAndTyping() {
        let model = F.model("latin"), rig = PickerTableRig(model: F.model("latin"))
        var chosen: FaceRecord?
        rig.model.onUse = { chosen = $0 }; rig.table.keyDown(with: pickerKey(36, "\r"))
        #expect(chosen == F.l)
        rig.model.open(F.context("latin"), catalog: F.catalog, status: .init()); rig.coordinator.update()
        rig.coordinator.handleDoubleClick(row: 2); #expect(chosen == F.z)
        chosen = nil; rig.coordinator.handleDoubleClick(row: 0); #expect(chosen == nil)
        model.onUse = { chosen = $0 }
        let host = NSHostingView(rootView: SearchFieldView(model: model))
        host.frame = NSRect(x: 0, y: 640, width: 360, height: 28); rig.window.contentView?.addSubview(host)
        host.layoutSubtreeIfNeeded()
        @MainActor func search(in view: NSView) -> NSSearchField? {
            if let field = view as? NSSearchField { return field }
            return view.subviews.lazy.compactMap { search(in: $0) }.first
        }
        let field = search(in: host)!
        rig.table.model = model; rig.window.makeFirstResponder(rig.table)
        rig.table.keyDown(with: pickerKey(0, "a"))
        #expect(field.stringValue == "a" && model.query == "a")
        #expect((rig.window.firstResponder as? NSTextView)?.delegate as AnyObject? === field)
    }
    @Test func selectionScrollsAndPendingTableCallbacksUseTheDisplayedSnapshot() {
        let faces = (0..<40).map { F.make("Family \($0)") }
        let rig = PickerTableRig(model: F.model(catalog: faces))
        rig.model.moveToEnd(); rig.coordinator.update()
        #expect(rig.table.visibleRect.intersects(rig.table.rect(ofRow: 40)))
        rig.model.query = "no matches"
        #expect(rig.coordinator.tableView(rig.table, viewFor: rig.table.tableColumns[0], row: 40) != nil)
        var used = false; rig.model.onUse = { _ in used = true }
        rig.coordinator.handleDoubleClick(row: 40); #expect(!used)
        rig.coordinator.update(); #expect(rig.table.numberOfRows == 0)
    }
    @Test func voiceOverLabels() {
        let rig = PickerTableRig(model: F.model(context: F.context("latin", keys: [F.z.key])))
        let zeta = rig.table.view(atColumn: 0, row: 2, makeIfNecessary: true)!
        #expect(zeta.accessibilityLabel() == "Picker Zeta, 测试黑体, in your font")
        #expect(zeta.accessibilityHelp() == "Sample: Aa Bb Cc 0123")
        let header = rig.table.view(atColumn: 0, row: 0, makeIfNecessary: true)!
        #expect(header.accessibilityLabel() == "All Latin fonts, 2")
        #expect(PickerText.searchAccessibilityLabel == "Search fonts")
    }
}

@MainActor final class PickerTableRig {
    let window: NSWindow
    let model: PickerModel
    let cache: RowFontCache
    let coordinator: FontListView.Coordinator
    let scroll: NSScrollView
    var table: PickerTableView { coordinator.table }
    init(model: PickerModel, renderer: any FPMacServices.FontRendering = PickerTestRenderer()) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        self.model = model; cache = RowFontCache(renderer: renderer)
        coordinator = FontListView.Coordinator(model: model, cache: cache)
        scroll = coordinator.makeScrollView(); scroll.frame = NSRect(x: 0, y: 0, width: 360, height: 640)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 680), styleMask: .borderless, backing: .buffered,
            defer: true)
        window.isReleasedWhenClosed = false; window.contentView?.addSubview(scroll)
        table.frame.size.width = scroll.contentSize.width
        coordinator.update(); window.contentView?.layoutSubtreeIfNeeded()
    }
    func draw() {
        scroll.layoutSubtreeIfNeeded()
        if let bitmap = scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds) {
            scroll.cacheDisplay(in: scroll.bounds, to: bitmap)
        }
    }
}
