import CoreText
import FPCore
import Foundation
import Testing

@testable import FPAppUI

@MainActor struct PickerModelTests {
    typealias F = PickerTestFaces
    @Test func languagePickerListsEveryLanguage() {
        #expect(
            Languages.all.map(\.id.rawValue) == [
                "latin", "chinese_s", "chinese_t", "japanese", "korean", "greek", "cyrillic", "armenian_georgian",
                "hebrew", "arabic", "indic", "southeast_asian", "symbols", "any",
            ])
        #expect(Languages.all.map { EnglishText.languageLabel($0.id) }.count == 14)
    }
    @Test func titlesAndOpenState() {
        let model = F.model("latin"); #expect(model.title == "Choose your main font")
        model.open(F.context("chinese_s", main: F.l), catalog: F.catalog, status: .init())
        #expect(model.title == "Choose a font for Chinese")
        model.languageID = "any"; #expect(model.title == "Choose a font")
        model.query = "latin"
        model.open(F.context("latin", main: F.l, replace: F.z.key), catalog: F.catalog, status: .init())
        #expect(model.title == "Replace Picker Zeta" && model.currentFace == F.z)
        #expect(model.query.isEmpty && model.languageID == "latin")
    }
    @Test func useButtonNamesTheFamily() {
        let model = F.model("latin")
        #expect(model.useTitle == "Use Picker Latin" && model.isUseEnabled)
        model.query = "zeta"; #expect(model.useTitle == "Use Picker Zeta")
        model.query = "absent"; #expect(model.useTitle == "Use" && !model.isUseEnabled)
        #expect(PickerText.use(String(repeating: "a", count: 30)) == "Use " + String(repeating: "a", count: 23) + "…")
    }
    @Test func candidateIsDebounced() async throws {
        let clock = ManualClock(), model = PickerModel(candidateDelay: .milliseconds(50), clock: clock)
        var values: [FaceRecord?] = []
        model.onCandidate = { values.append($0) }
        model.open(F.context(), catalog: F.catalog, status: .init())
        try await pickerEventually { clock.waiting == [.milliseconds(50)] }
        clock.advance(by: .milliseconds(49)); #expect(clock.waiting == [.milliseconds(1)] && values.isEmpty)
        clock.advance(by: .milliseconds(1)); try await pickerEventually { !values.isEmpty }; #expect(values == [F.l])
        values = []
        // Each move restarts the wait, so 90 ms of browsing in 30 ms steps emits nothing.
        for _ in 0..<3 {
            model.move(by: 1); try await pickerEventually { clock.waiting == [.milliseconds(50)] }
            clock.advance(by: .milliseconds(30))
        }
        #expect(values.isEmpty && clock.waiting == [.milliseconds(20)] && clock.cancelled == 2)
        clock.advance(by: .milliseconds(20)); try await pickerEventually { values.count == 1 }; #expect(values == [F.z])
        model.query = "no match"; try await pickerEventually { clock.waiting == [.milliseconds(50)] }
        clock.advance(by: .milliseconds(50)); try await pickerEventually { values.count == 2 }
        #expect(values.last! == nil)
    }
    @Test func noCandidateAfterClose() async throws {
        let clock = ManualClock(), model = F.model(clock: clock); var count = 0
        model.onCandidate = { _ in count += 1 }
        // Closed before the candidate task starts: its sleep throws at once.
        model.cancel(); try await pickerEventually { clock.cancelled == 1 }
        clock.advance(by: .seconds(1)); #expect(count == 0)
        // Closed while the candidate waits: the wait is cancelled, not left to run out.
        model.open(F.context(), catalog: F.catalog, status: .init())
        try await pickerEventually { clock.waiting == [.milliseconds(50)] }
        clock.advance(by: .milliseconds(10)); model.cancel()
        #expect(clock.waiting.isEmpty && clock.cancelled == 2)
        clock.advance(by: .seconds(1)); #expect(count == 0)
    }
    @Test func scanLifecycleTexts() {
        let model = PickerModel(locale: Locale(identifier: "en_US"))
        var status = CatalogStatus(); status.isScanning = true
        model.open(F.context(), catalog: [], status: status); #expect(model.statusText == "Looking for fonts…")
        status.done = 340; status.total = 1101; model.catalogChanged([], status: status)
        #expect(model.statusText == "Looking for fonts… 340 / 1,101")
        status.isScanning = false; status.unreadable = [.init(path: "/x/bad.ttf", message: "TTLibError: bad")]
        model.catalogChanged(F.catalog, status: status)
        #expect(model.statusText == "6 fonts · 1 file couldn't be read")
        #expect(model.statusHelp == "/x/bad.ttf: TTLibError: bad")
        status.unreadable = (0..<3).map { .init(path: "/x/\($0).ttf", message: "bad") }
        model.catalogChanged([F.l], status: status); #expect(model.statusText == "1 font · 3 files couldn't be read")
        #expect(model.statusHelp.split(separator: "\n").count == 3)
        status.hiddenCount = 3; status.duplicateCount = 1; model.catalogChanged([F.l], status: status)
        #expect(model.statusHelp.hasSuffix("3 hidden system fonts and 1 duplicate aren't listed."))
        model.catalogChanged([], status: .init()); #expect(model.statusText == "0 fonts" && model.statusHelp.isEmpty)
    }
    @Test func rowsFollowARunningScanThrottled() async throws {
        let clock = ManualClock()
        let model = PickerModel(
            locale: Locale(identifier: "en_US"), candidateDelay: .milliseconds(50),
            refreshInterval: .milliseconds(300), clock: clock)
        var status = CatalogStatus(); status.isScanning = true
        model.open(F.context("latin"), catalog: [], status: status)
        model.catalogChanged([F.z], status: status)
        try await pickerEventually { clock.waiting == [.milliseconds(50), .milliseconds(300)] }
        clock.advance(by: .milliseconds(299)); #expect(clock.waiting == [.milliseconds(1)] && model.rows.isEmpty)
        clock.advance(by: .milliseconds(1)); try await pickerEventually { model.rows.count == 2 }
        #expect(F.rows(model) == ["All Latin fonts · 1", "Picker Zeta"])
        status.isScanning = false; model.catalogChanged([F.z, F.l], status: status)
        #expect(F.rows(model) == ["All Latin fonts · 2", "Picker Latin", "Picker Zeta"])
        #expect(model.currentFace == F.z && model.statusText == "2 fonts")
    }
    @Test func styleMenuChoosesAnotherStyle() async throws {
        let model = F.model("latin"); var candidates: [FaceRecord?] = []; model.onCandidate = { candidates.append($0) }
        #expect(model.currentRow?.styles == [F.l, F.lb])
        model.chosenStyle = F.lb
        try await pickerEventually { candidates.count == 1 }; #expect(candidates == [F.lb])
        #expect(model.use() == F.lb)
        model.open(F.context("latin"), catalog: F.catalog, status: .init()); model.chosenStyle = F.lb; model.move(by: 1)
        #expect(model.chosenStyle == nil && model.currentRow?.styles.count == 1)
    }
    @Test func trialBannerSaysWhatIsTried() {
        let suffix = " — ↑ ↓ try the next font, Return uses it."
        #expect(
            PickerText.trialBanner(family: "A", languageID: nil, replacedFamily: nil, first: true)
                == "Trying A as your main font" + suffix)
        #expect(
            PickerText.trialBanner(family: "A", languageID: nil, replacedFamily: "B", first: false)
                == "Trying A instead of B" + suffix)
        #expect(
            PickerText.trialBanner(family: "A", languageID: "any", replacedFamily: nil, first: false) == "Trying A"
                + suffix)
        #expect(
            PickerText.trialBanner(family: "A", languageID: "chinese_s", replacedFamily: nil, first: false)
                == "Trying A for Chinese" + suffix)
    }
    @Test func rowFontsRespectTheBudgetAndCache() async throws {
        let renderer = PickerTestRenderer(delay: 0.003), cache = RowFontCache(renderer: renderer)
        let faces = (0..<20).map { F.make("Cache \($0)") }; var ready: Set<FaceKey> = []
        cache.onFontsReady = { ready.formUnion($0) }
        let first = try #require(cache.font(for: faces[0], size: 18))
        for face in faces.dropFirst() { _ = cache.font(for: face, size: 18) }
        #expect(renderer.count <= 3)
        // AC-503-25 bounds synchronous work, not wall time spent waiting behind other MainActor test suites.
        try await pickerEventually(timeout: .seconds(30)) { renderer.count == 20 }
        #expect(!ready.isEmpty && cache.font(for: faces[0], size: 18) === first)
        let lruRenderer = PickerTestRenderer(),
            lru = RowFontCache(renderer: lruRenderer, capacity: 4, budgetPerTurn: .seconds(1))
        for face in faces.prefix(4) { _ = lru.font(for: face, size: 18) }
        _ = lru.font(for: faces[0], size: 18); _ = lru.font(for: faces[4], size: 18)
        _ = lru.font(for: faces[0], size: 18); #expect(lruRenderer.count == 5)
        _ = lru.font(for: faces[1], size: 18); #expect(lruRenderer.count == 6)
        let failingRenderer = PickerTestRenderer(failurePath: F.l.path),
            failing = RowFontCache(renderer: failingRenderer)
        #expect(failing.font(for: F.l, size: 18) == nil); #expect(failing.font(for: F.l, size: 18) == nil)
        #expect(failingRenderer.count == 1)
    }
}
