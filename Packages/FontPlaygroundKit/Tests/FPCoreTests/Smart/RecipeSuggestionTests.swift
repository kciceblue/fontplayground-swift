import FPCore
import Foundation
import Testing

struct RecipeSuggestionTests {
    @Test func suggestionsFollowMissingCharacters() {
        var recipe = Recipe(); recipe.setSampleText("a b漢 →→Ω"); recipe.add(TestFaces.a)
        #expect(recipe.suggestions(in: FaceCatalog([]), preferences: .none).isEmpty)
        let catalog = FaceCatalog(TestFaces.all)
        #expect(recipe.suggestions(in: catalog, preferences: .none).map(\.family) == ["Fixture C", "Fixture B"])
        #expect(recipe.suggestions(in: catalog, limit: 1, preferences: .none).map(\.family) == ["Fixture C"])
        recipe.add(TestFaces.c)
        #expect(recipe.suggestions(in: catalog, preferences: .none).map(\.family) == ["Fixture B"])
        recipe.add(TestFaces.b)
        #expect(recipe.suggestions(in: catalog, preferences: .none).isEmpty)
        #expect(Recipe().glyphsNeeded() == 0)
    }

    @Test func suggestionsPassTheGlyphsAlreadyNeeded() {
        var main = TestFaces.a, big = TestFaces.c
        main.glyphCount = 57535; big.glyphCount = 10000
        let sym = fakeFace(cps("→"), path: "sym.ttf", family: "Sym")
        var recipe = Recipe(); recipe.setSampleText("a b漢 →→Ω"); recipe.add(main)
        let catalog = FaceCatalog([main, TestFaces.b, big, sym])
        #expect(recipe.glyphsNeeded() == 57535)
        #expect(recipe.suggestions(in: catalog, preferences: .none).map(\.family) == ["Fixture C", "Sym", "Fixture B"])
        recipe.add(TestFaces.b)
        #expect(recipe.glyphsNeeded() == 57537)
        #expect(recipe.suggestions(in: catalog, preferences: .none).map(\.family) == ["Sym", "Fixture C"])
    }

    @Test func suggestionsForALanguageOnlyOfferFontsThatDrawItWell() {
        let good = fakeFace(SmartFaces.han.union(cps("们这说国门来")), path: "good.ttf", family: "Good")
        let poor = fakeFace(CodepointSet(ranges: [0x4E00...UInt32(0x4E00 + 3009)]), path: "poor.ttf", family: "Poor")
        let catalog = FaceCatalog(TestFaces.all + [good, poor])
        var recipe = Recipe(); recipe.add(TestFaces.a); recipe.setSampleText("abc 一丁")
        #expect(recipe.suggestions(for: .chineseSimplified, in: catalog, preferences: .none).map(\.family) == ["Good"])
        #expect(Set(recipe.suggestions(for: .any, in: catalog, preferences: .none).map(\.family)) == ["Good", "Poor"])
        #expect(recipe.suggestions(for: .latin, in: catalog, preferences: .none).isEmpty)
    }
}
