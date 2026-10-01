import FPCore
import Foundation
import Testing

@testable import FPAppUI

@MainActor struct AdvancedModelTests {
    static func recipe() -> Recipe {
        var recipe = Recipe()
        recipe.add(ShellFaces.make(text: "abcde"))
        recipe.add(ShellFaces.make("Fixture B", style: "Bold", path: "/fixture/B.otf", text: "ab你，"))
        return recipe
    }
    static func state(
        _ recipe: Recipe, showAll: Bool = false, locked: Bool = false,
        report: ForgeReport? = nil, error: String? = nil
    ) -> AdvancedModel {
        AdvancedModel(
            recipe: recipe, showAll: showAll, isLocked: locked, lastReport: report, lastErrorDetail: error,
            locale: Locale(identifier: "en_US"))
    }
    @Test func shortNamesUseTheFamilyUnlessShared() {
        let a = ShellFaces.make("Segoe UI"), b = ShellFaces.make("YaHei", path: "/b.ttf")
        let bold = ShellFaces.make("YaHei", style: "Bold", path: "/bold.ttf")
        #expect(AdvancedModel.shortNames([a, b]) == [a.key: "Segoe UI", b.key: "YaHei"])
        #expect(
            AdvancedModel.shortNames([a, b, bold]) == [
                a.key: "Segoe UI", b.key: "YaHei Regular", bold.key: "YaHei Bold",
            ])
    }
    @Test func rowsListOnlyCoveredScriptsUntilShowAll() throws {
        let state = Self.state(Self.recipe())
        #expect(state.rows.map(\.id) == [.latin, .han, .cjkSymbols])
        #expect(state.rows.map(\.label) == ["Latin", "Han", "CJK symbols & fullwidth"])
        let latin = try #require(state.rows.first)
        #expect(latin.countsText == "Fixture A 5 · Fixture B 2")
        #expect(latin.choices.map(\.title) == ["Auto → Fixture A Regular", "Fixture A Regular", "Fixture B Bold"])
        #expect(state.rows[1].drawnByText == "Auto → Fixture B Bold")
        let all = Self.state(Self.recipe(), showAll: true)
        #expect(all.rows.map(\.id) == ScriptGroup.allCases && all.rows.count == 15)
        let arabic = try #require(all.rows.first { $0.id == .arabic })
        #expect(!arabic.isCovered && arabic.choices.isEmpty)
        #expect(arabic.drawnByText == "nobody" && arabic.countsText == "—")
    }
    @Test func choosingAFontPinsAndAutoUnpins() throws {
        var recipe = Self.recipe()
        let pin = try #require(Self.state(recipe).pin(.latin, choiceIndex: 2))
        pin(&recipe)
        #expect(recipe.pins[.latin] == recipe.keys[1])
        let pinned = Self.state(recipe)
        #expect(pinned.rows[0].selectedIndex == 2)
        #expect(pinned.rows[0].countsText == "Fixture B 2 · Fixture A 5")
        let unpin = try #require(pinned.pin(.latin, choiceIndex: 0))
        unpin(&recipe)
        #expect(recipe.pins[.latin] == nil && Self.state(recipe).rows[0].selectedIndex == 0)
    }
    @Test func rowsFollowTheRecipe() {
        var recipe = Self.recipe()
        recipe.remove(recipe.keys[1]); #expect(Self.state(recipe).rows.map(\.id) == [.latin])
        recipe.reset(); #expect(Self.state(recipe).rows.isEmpty)
    }
    @Test func lineSpacingSetsTheBase() {
        var recipe = Self.recipe()
        let state = Self.state(recipe), b = recipe.keys[1]
        #expect(state.lineSpacingChoices == ["Main font", "Fixture A Regular", "Fixture B Bold"])
        #expect(state.lineSpacingIndex == 0 && state.lineSpacingEnabled)
        state.lineSpacing(index: 2)(&recipe); #expect(recipe.baseKey == b)
        recipe.move(b, to: 0)
        let moved = Self.state(recipe)
        #expect(moved.lineSpacingChoices[moved.lineSpacingIndex] == "Fixture B Bold")
        moved.lineSpacing(index: 0)(&recipe); #expect(recipe.baseKey == nil)
        recipe.reset(); #expect(!Self.state(recipe).lineSpacingEnabled)
    }
    @Test func defaultsSetTheRecipe() {
        var recipe = Self.recipe()
        let initial = Self.state(recipe)
        #expect(initial.weightChoices.count == 7)
        #expect(initial.weightChoices.prefix(2).map(\.title) == ["As is", "Light (300)"])
        initial.defaults(weightIndex: 5, sizePercent: nil)(&recipe)
        #expect(recipe.defaultWeight == 700 && recipe.defaultScale == 1)
        Self.state(recipe).defaults(weightIndex: nil, sizePercent: 90)(&recipe)
        #expect(recipe.defaultWeight == 700 && recipe.defaultScale == 0.9)
        Self.state(recipe).defaults(weightIndex: 0, sizePercent: nil)(&recipe)
        #expect(recipe.defaultWeight == nil && recipe.defaultScale == 0.9)
        recipe.setDefaults(weight: 650, scale: 1.25)
        let custom = Self.state(recipe)
        #expect(custom.weightChoices[custom.weightIndex].title == "650" && custom.sizePercent == 125)
    }
    @Test func lastBuildReport() {
        let recipe = Self.recipe()
        #expect(Self.state(recipe).reportText == "No build yet.")
        let report = ForgeReport(
            outputPath: "/temporary/Fixture.ttf", totalCodepoints: 5, totalGlyphs: 6,
            materials: [.init(name: "Fixture A Regular", path: "/fixture/A.ttf", codepoints: 5, groups: ["latin"])],
            warnings: ["Glyph names were dropped."])
        #expect(Self.state(recipe, report: report, error: "older error").reportText == ReportText.render(report))
        let error = "Couldn't read B.otf\nTraceback: …"
        #expect(Self.state(recipe, error: error).reportText == error)
    }
    @Test func lockedDisablesWhatChangesTheFont() {
        var recipe = Self.recipe()
        let before = recipe, state = Self.state(recipe, locked: true, error: "report remains selectable")
        #expect(!state.controlsEnabled && !state.lineSpacingEnabled)
        #expect(state.reportText == "report remains selectable")
        #expect(state.pin(.latin, choiceIndex: 2) == nil)
        state.lineSpacing(index: 2)(&recipe); state.defaults(weightIndex: 5, sizePercent: 90)(&recipe)
        #expect(recipe == before)
    }
    @Test("ADR-8: fonts that cannot shape are not offered") func adr8FontsThatCannotShapeAreNotOffered() throws {
        var geeza = ShellFaces.make("Geeza Pro", text: "ابت"),
            noto = ShellFaces.make("Noto Naskh", path: "/noto.ttf", text: "ابت")
        geeza.shapesGroups = []; geeza.groupCounts = [:]; noto.shapesGroups = [.arabic]
        var recipe = Recipe(); recipe.add(geeza); recipe.add(noto)
        let state = Self.state(recipe), arabic = try #require(state.rows.first { $0.id == .arabic })
        #expect(arabic.choices[1].title == "Geeza Pro Regular — can't shape Arabic" && arabic.choices[1].isDisabled)
        let before = recipe
        #expect(state.pin(.arabic, choiceIndex: 1) == nil && recipe == before)
        let pin = try #require(state.pin(.arabic, choiceIndex: 2))
        pin(&recipe)
        #expect(recipe.pins[.arabic] == noto.key)
    }
    @Test func countsUseGroupingSeparators() throws {
        var pingfang = ShellFaces.make("PingFang SC", text: "你"); pingfang.groupCounts = [.han: 30_000]
        var recipe = Recipe(); recipe.add(pingfang)
        let row = try #require(Self.state(recipe).rows.first)
        #expect(row.countsText == "PingFang SC 30,000")
    }
    @Test func unavailableAndSuspiciousFacesCountNothingAndTiesKeepRecipeOrder() {
        var recipe = Self.recipe()
        _ = recipe.reconcile(with: FaceCatalog([recipe.materials[0].face]))
        #expect(Self.state(recipe).rows.map(\.id) == [.latin])
        var suspicious = ShellFaces.make("Suspicious", path: "/suspicious.ttf", text: "אב你好")
        suspicious.suspiciousCoverage = true; recipe.add(suspicious)
        #expect(Self.state(recipe).rows.map(\.id) == [.latin])
        var tied = Recipe()
        tied.add(ShellFaces.make("First", text: "abc"));
        tied.add(ShellFaces.make("Second", path: "/second.ttf", text: "abc"))
        #expect(Self.state(tied).rows[0].countsText == "First 3 · Second 3")
    }
    @Test func invalidChoicesDoNotChangeRecipeAndSizeStaysInRange() {
        var recipe = Self.recipe(); let original = recipe, state = Self.state(recipe)
        #expect(state.pin(.latin, choiceIndex: -1) == nil && state.pin(.latin, choiceIndex: 20) == nil)
        state.lineSpacing(index: -1)(&recipe); state.lineSpacing(index: 20)(&recipe)
        state.defaults(weightIndex: 20, sizePercent: nil)(&recipe); #expect(recipe == original)
        state.defaults(weightIndex: nil, sizePercent: 1)(&recipe); #expect(recipe.defaultScale == 0.1)
        state.defaults(weightIndex: nil, sizePercent: 2000)(&recipe); #expect(recipe.defaultScale == 10)
    }
}
