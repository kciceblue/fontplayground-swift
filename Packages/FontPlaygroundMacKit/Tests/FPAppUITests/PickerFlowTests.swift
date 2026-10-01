import AppKit
import FPCore
import Foundation
import Testing

@testable import FPAppUI

@MainActor struct PickerFlowTests {
    typealias F = PickerTestFaces
    private func model(_ temp: ShellTempDirectory) -> AppModel {
        let model = AppModel(
            services: .testing(root: temp.url, defaults: temp.defaults, renderer: PickerTestRenderer()))
        let latin = Array(UInt32(0x20)...0x7E) + Array(UInt32(0xA0)...0x17F)
        let han =
            latin + F.han + "你好世界，。！、".unicodeScalars.map(\.value) + Array(UInt32(0x3041)...0x3096)
            + Array(UInt32(0x30A1)...0x30FA)
        model.catalogFaces = [
            F.make("Latin Sans", points: latin), F.make("Han Sans", points: han),
            F.make("Hangul Sans", points: latin + Array(UInt32(0xAC00)..<0xAC00 + 2100)),
        ]
        model.recipe.setSampleText("Hello 你好 あ")
        return model
    }
    private func choose(_ family: String, in model: AppModel) async throws {
        model.picker.query = family
        try await pickerEventually { model.picker.currentFace?.family == family }
        let coordinator = SearchFieldView.Coordinator(model: model.picker, visibleRows: { 10 })
        #expect(
            coordinator.control(
                NSSearchField(), textView: NSTextView(), doCommandBy: NSSelectorFromString("insertNewline:")))
    }
    @Test func chooseTryCancelAndReplace() async throws {
        let temp = try ShellTempDirectory(), app = model(temp)
        app.perform(.chooseMain); #expect(app.picker.languageID == "latin")
        try await choose("Latin Sans", in: app)
        #expect(
            app.recipe.materials.map(\.face.family) == ["Latin Sans"] && app.recipe.pins.isEmpty
                && app.pickRequest == nil)
        let prompt = try #require(
            RecipeColumnState.make(recipe: app.recipe, catalog: app.catalogFaces, isBuilding: false).prompt)
        app.openPicker(prompt.request); #expect(app.picker.languageID == "chinese_s")
        try await choose("Han Sans", in: app)
        #expect(app.recipe.materials.map(\.face.family) == ["Latin Sans", "Han Sans"])
        #expect(app.recipe.pins[.han] == app.catalogFaces[1].key)

        let trying = model(temp); trying.recipe.add(trying.catalogFaces[0])
        trying.openPicker(.init(languageID: "korean")); #expect(trying.recipe.sampleText.contains("안녕"))
        trying.picker.query = "Hangul"
        try await pickerEventually { trying.trial?.banner.hasPrefix("Trying Hangul Sans for Korean") == true }
        #expect(trying.trial?.mix.fonts.count == 2 && trying.recipe.materials.count == 1)
        let coordinator = SearchFieldView.Coordinator(model: trying.picker, visibleRows: { 10 })
        #expect(
            coordinator.control(
                NSSearchField(), textView: NSTextView(), doCommandBy: NSSelectorFromString("cancelOperation:")))
        #expect(trying.trial == nil && trying.pickRequest == nil && trying.recipe.materials.count == 1)

        let replacing = model(temp); replacing.recipe.add(replacing.catalogFaces[0]);
        replacing.recipe.add(replacing.catalogFaces[2], for: .korean)
        let state = RecipeColumnState.make(recipe: replacing.recipe, catalog: replacing.catalogFaces, isBuilding: false)
        replacing.perform(.pick(state.cards[1].changeRequest))
        #expect(replacing.pickRequest?.replaceKey == replacing.catalogFaces[2].key)
        replacing.picker.languageID = "chinese_s"; try await choose("Han Sans", in: replacing)
        #expect(replacing.recipe.materials.map(\.face.family) == ["Latin Sans", "Han Sans"])
        #expect(replacing.recipe.pins[.hangul] == replacing.catalogFaces[1].key)
    }
    @Test func buildingClosesAndBlocksThePicker() async throws {
        let temp = try ShellTempDirectory(), app = model(temp)
        app.openPicker(.init(languageID: "latin"))
        try await pickerEventually { app.trial != nil }
        app.picker.query = "Latin"; app.isBuilding = true
        #expect(app.pickRequest == nil && app.trial == nil)
        try await Task.sleep(for: .milliseconds(200)); #expect(app.trial == nil)
        app.openPicker(.init(languageID: "latin")); #expect(app.pickRequest == nil)
    }
    @Test func escapeBackAndCancel() async throws {
        let temp = try ShellTempDirectory(), app = model(temp)
        for action in 0..<4 {
            app.openPicker(.init(languageID: "latin")); try await pickerEventually { app.trial != nil }
            if action == 0 {
                _ = SearchFieldView.Coordinator(model: app.picker, visibleRows: { 10 }).control(
                    NSSearchField(), textView: NSTextView(), doCommandBy: NSSelectorFromString("cancelOperation:"))
            } else if action == 1 {
                let table = PickerTableView(); table.model = app.picker
                table.keyDown(with: pickerKey(53, "\u{1b}"))
            } else {
                app.cancelPicker()
            }  // Both Back and Cancel use this same action.
            #expect(!app.picker.isOpen && app.pickRequest == nil && app.trial == nil)
        }
    }
    @Test("CATALOG-11: platform preference breaks ties and selects the initial row")
    func catalog11PlatformFontBreaksTiesAndIsTheInitialRow() throws {
        let temp = try ShellTempDirectory(), app = model(temp)
        let lanting = F.make("Lantinghei SC", points: F.han), pingfang = F.make("PingFang SC", points: F.han)
        app.catalogFaces = [app.catalogFaces[0], lanting, pingfang]
        app.recipe.add(app.catalogFaces[0]); app.recipe.setSampleText("Hello 你好")
        app.platformPreferredNames = ["chinese_s": "PingFangSC-Regular"]
        #expect(app.platformFontLookup == nil)
        app.openPicker(.init(languageID: "chinese_s"))
        #expect(app.picker.rows[1].familyRow?.family == "PingFang SC" && app.picker.rows[1].id.section == .suggested)
        #expect(
            app.recipe.suggestions(for: .chineseSimplified, in: FaceCatalog(app.catalogFaces), preferences: .none)
                .first?.family == "Lantinghei SC")
        app.cancelPicker(); app.recipe = Recipe(); app.recipe.add(F.make("Combined", points: F.latin + F.han))
        app.recipe.setSampleText("Hello 你好"); app.openPicker(.init(languageID: "chinese_s"))
        #expect(!app.picker.rows.contains { $0.id.section == .suggested })
        #expect(app.picker.currentFace?.family == "PingFang SC")
    }
    @Test func findFontReusesSearchAndLookupRunsOnce() async throws {
        let temp = try ShellTempDirectory(), app = model(temp)
        let counter = PickerLookupCounter()
        app.platformFontLookup = { probes in await counter.lookup(probes) }
        app.findFont(); #expect(app.pickRequest?.languageID == "latin")
        var focuses = 0; app.picker.focusSearch = { if $0 { focuses += 1 } }
        app.findFont(); #expect(focuses == 1)
        app.cancelPicker(); app.openPicker(.init(languageID: "unknown")); #expect(app.pickRequest?.languageID == "any")
        for _ in 0..<100 {
            if await counter.calls > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let calls = await counter.calls
        #expect(calls == 1)
    }
}
private actor PickerLookupCounter {
    var calls = 0
    func lookup(_ probes: [String: String]) -> [String: String] { calls += 1; return [:] }
}

@MainActor func pickerKey(_ code: UInt16, _ characters: String, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
        windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
        isARepeat: false, keyCode: code)!
}
