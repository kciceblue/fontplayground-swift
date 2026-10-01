import FPCore
import Foundation
import Observation
import os

@MainActor @Observable final class PickerModel {
    struct Context: Equatable {
        var request: PickRequest
        var main: FaceRecord?
        var recipeKeys: Set<FaceKey>
        var suggestions: [FaceRecord]
        var preferredFamilies: [String: String]
    }
    let locale: Locale
    private let candidateDelay: Duration
    private let refreshInterval: Duration
    /// Times the candidate debounce and the scan refresh throttle. Tests pass a manual clock so they can
    /// check "not yet" and "never" without racing wall-clock sleeps on a busy runner.
    private let clock: any Clock<Duration>
    private(set) var isOpen = false
    private(set) var context = Context(
        request: .init(languageID: "any"), main: nil, recipeKeys: [], suggestions: [], preferredFamilies: [:])
    var languageID = "any" { didSet { if languageID != oldValue { rebuild() } } }
    var query = "" { didSet { if query != oldValue { rebuild() } } }
    var showsUnshapable = false { didSet { if showsUnshapable != oldValue { rebuild() } } }
    private(set) var rows: [PickerRow] = []
    private(set) var currentRowID: PickerRow.ID?
    var chosenStyle: FaceRecord? { didSet { if chosenStyle != oldValue { scheduleCandidate() } } }
    private(set) var status = CatalogStatus()
    private(set) var unshapableCount = 0
    private var listedFamilyCount = 0
    private var catalog: [FaceRecord] = []
    private var index = PickerRows.Index([])
    private var wish: PickerRow.ID?
    private var opening = false
    @ObservationIgnored private var candidateTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored var restoreFocus: () -> Void = {}
    @ObservationIgnored private var openInterval: OSSignpostIntervalState?
    private let signposter = OSSignposter(subsystem: "io.github.kciceblue.fontplayground", category: "Picker")
    @ObservationIgnored var onCandidate: (FaceRecord?) -> Void = { _ in }
    @ObservationIgnored var onUse: (FaceRecord) -> Void = { _ in }
    @ObservationIgnored var onCancel: () -> Void = {}
    @ObservationIgnored var focusSearch: (_ selectAll: Bool) -> Void = { _ in }
    @ObservationIgnored var visibleRowCount: () -> Int = { 10 }
    @ObservationIgnored var insertSearchText: (String) -> Void = { _ in }
    @ObservationIgnored var scanStarted: () -> Void = {}

    init(
        locale: Locale = .current, candidateDelay: Duration = .milliseconds(120),
        refreshInterval: Duration = .milliseconds(300), clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.locale = locale; self.candidateDelay = candidateDelay; self.refreshInterval = refreshInterval
        self.clock = clock
    }
    var language: Language { Languages.language(rawID: languageID) ?? Languages.language(.any) }
    var currentRow: FamilyRow? { rows.first { $0.id == currentRowID }?.familyRow }
    var currentFace: FaceRecord? { currentRow?.unavailableReason == nil ? chosenStyle ?? currentRow?.face : nil }
    var title: String {
        let replaced = context.request.replaceKey.flatMap { key in catalog.first { $0.key == key }?.family }
        return PickerText.title(language: language, main: context.main, replaced: replaced)
    }
    var searchPlaceholder: String { PickerText.placeholder(listedFamilyCount, locale: locale) }
    var statusText: String {
        PickerText.status(
            scanning: status.isScanning, done: status.done, total: status.total, empty: rows.isEmpty,
            query: query.trimmingCharacters(in: .whitespacesAndNewlines), language: language,
            count: catalog.filter { !PickerRows.isHidden($0) && !$0.suspiciousCoverage }.count,
            unreadable: status.unreadable.count, locale: locale)
    }
    var statusHelp: String {
        PickerText.statusHelp(
            unreadable: status.unreadable, hidden: status.hiddenCount, duplicates: status.duplicateCount, locale: locale
        )
    }
    var useTitle: String { PickerText.use(currentFace?.family) }
    var isUseEnabled: Bool { isOpen && currentFace != nil }
    var unshapableTitle: String {
        PickerText.unshapable(language: language, count: unshapableCount, locale: locale, checkbox: true)
    }

    func open(_ context: Context, catalog: [FaceRecord], status: CatalogStatus) {
        cancel()
        openInterval = signposter.beginInterval("PickerOpen")
        self.context = context; self.catalog = catalog; self.status = status; index = .init(catalog)
        languageID = context.request.languageID; query = ""; showsUnshapable = false; chosenStyle = nil
        wish = context.request.replaceKey.flatMap { key in catalog.first { $0.key == key } }.map {
            .init(section: .all, text: $0.family, faceKey: nil)
        }
        isOpen = true; opening = true; rebuild(); opening = false
    }
    func catalogChanged(_ catalog: [FaceRecord], status: CatalogStatus) {
        let started = !self.status.isScanning && status.isScanning
        self.catalog = catalog; index = .init(catalog); self.status = status
        if started { scanStarted() }
        guard isOpen else { return }
        if !status.isScanning { refreshTask?.cancel(); refreshTask = nil; rebuild(); return }
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self, refreshInterval, clock] in
            do { try await clock.sleep(for: refreshInterval) } catch { return }
            guard let self, self.isOpen else { return }
            self.refreshTask = nil; self.rebuild()
        }
    }
    private func rebuild() {
        guard isOpen else { return }
        let result = PickerRows.build(
            catalog: catalog, language: language, query: query, context: context,
            showsUnshapable: showsUnshapable, locale: locale, index: index)
        rows = result.rows; listedFamilyCount = result.listedFamilyCount; unshapableCount = result.unshapableCount
        let selectable = rows.filter(\.isSelectable)
        var selected = selectable.first { $0.id == wish }
        if selected == nil, let wish {
            selected =
                selectable.first { $0.id.text == wish.text && $0.id.section == .all }
                ?? selectable.first { $0.id.text == wish.text }
        }
        if selected == nil, opening, wish == nil, !selectable.contains(where: { $0.id.section == .suggested }),
            let preferred = context.preferredFamilies[languageID]
        {
            selected = selectable.first { $0.id.text == preferred }
        }
        selected = selected ?? selectable.first
        if currentRowID != selected?.id { chosenStyle = nil }
        currentRowID = selected?.id
        // Keep a specific absent wish during a scan, but keep the first live selection when there was no wish.
        if !status.isScanning || wish == nil { wish = currentRowID }
        scheduleCandidate()
    }
    func select(_ id: PickerRow.ID) {
        guard isOpen, rows.contains(where: { $0.id == id && $0.isSelectable }) else { return }
        if currentRowID != id { chosenStyle = nil }
        currentRowID = id; wish = id; scheduleCandidate()
    }
    func move(by delta: Int) {
        let selectable = rows.filter(\.isSelectable)
        guard !selectable.isEmpty else { return }
        let current = selectable.firstIndex { $0.id == currentRowID } ?? 0
        select(selectable[min(max(0, current + delta), selectable.count - 1)].id)
    }
    func moveToStart() { if let row = rows.first(where: \.isSelectable) { select(row.id) } }
    func moveToEnd() { if let row = rows.last(where: \.isSelectable) { select(row.id) } }
    func page(by direction: Int, visibleRows: Int) { move(by: direction * max(1, visibleRows)) }
    func use() -> FaceRecord? {
        guard isOpen, let face = currentFace else { return nil }
        cancel(); return face
    }
    func firstTableDraw() {
        if let openInterval { signposter.endInterval("PickerOpen", openInterval); self.openInterval = nil }
    }
    func cancel() {
        firstTableDraw()
        isOpen = false; candidateTask?.cancel(); candidateTask = nil; refreshTask?.cancel(); refreshTask = nil
    }
    func choose() { if let face = use() { onUse(face) } }
    func requestCancel() { cancel(); onCancel() }
    private func scheduleCandidate() {
        candidateTask?.cancel(); candidateTask = nil
        guard isOpen else { return }
        candidateTask = Task { [weak self, candidateDelay, clock] in
            do { try await clock.sleep(for: candidateDelay) } catch { return }
            guard let self, self.isOpen else { return }
            self.onCandidate(self.currentFace)
        }
    }
}
