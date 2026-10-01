import FPCore
import Foundation
import Testing

enum SmartFaces {
    static let han = CodepointSet(ranges: [0x4E00...UInt32(0x4E00 + 2999)])
    static let hangul = CodepointSet(ranges: [0xAC00...UInt32(0xAC00 + 99)])
    static func catalog() -> [FaceRecord] {
        [
            fakeFace(cps("abc"), path: "latin.ttf", family: "Latin Only"),
            fakeFace(han.union(cps("a")), path: "han.ttf", family: "Han Font"),
            fakeFace(hangul.union(han), path: "kr-bold.ttf", family: "Korean", style: "Bold", weight: 700),
            fakeFace(hangul.union(han), path: "kr.ttf", family: "Korean"),
            fakeFace(hangul, path: "kr-light.ttf", family: "Korean", style: "Light", weight: 300),
            fakeFace(cps("☺→"), path: "sym.ttf", family: "Symbols"),
            fakeFace(
                hangul.union(han).union(cps("☺→")), path: "color.ttf", family: "Colour Everything", hasColor: true),
        ]
    }
    static func chinese(_ name: String, glyphs: Int = 3001) -> FaceRecord {
        fakeFace(
            han.union(cps(Languages.language(.chineseSimplified).markers)).union(cps("你好，世界！欢迎使用字体游乐场。")),
            path: "\(name).ttf", family: name, glyphCount: glyphs)
    }
}

struct SuggestionTests {
    @Test func ranksFamiliesByCoverageOneFacePerFamily() {
        let missing = SmartFaces.hangul.union(cps("一丁☺"))
        let main = fakeFace(cps("a"), path: "main.ttf", family: "Main")
        let got = Suggestions.suggestMaterials(
            missing: missing, candidates: SmartFaces.catalog(), main: main, preferred: [])
        #expect(got.map(\.family) == ["Korean", "Han Font", "Symbols"])
        #expect(got[0].style == "Regular")
    }

    @Test func prefersMainItalicAndWeight() {
        let catalog = SmartFaces.catalog()
        var italic = catalog[3]; italic.italic = true; italic.style = "Italic"; italic.path = "kr-italic.ttf"
        var main = fakeFace(cps("a"), path: "main.ttf", family: "Main", weight: 700)
        #expect(
            Suggestions.suggestMaterials(
                missing: SmartFaces.hangul, candidates: catalog + [italic], main: main, limit: 1) == [catalog[2]])
        main.italic = true
        #expect(
            Suggestions.suggestMaterials(
                missing: SmartFaces.hangul, candidates: catalog + [italic], main: main, limit: 1) == [italic])
        #expect(
            Suggestions.suggestMaterials(missing: SmartFaces.hangul, candidates: catalog, main: nil, limit: 1) == [
                catalog[3]
            ])
    }

    @Test func limitExclusionsAndEmptyCases() {
        let catalog = SmartFaces.catalog(), missing = SmartFaces.hangul.union(cps("☺"))
        #expect(
            Suggestions.suggestMaterials(missing: missing, candidates: catalog, main: nil, limit: 1) == [catalog[3]])
        #expect(Suggestions.suggestMaterials(missing: missing, candidates: catalog, main: nil, limit: 0).isEmpty)
        #expect(Suggestions.suggestMaterials(missing: .empty, candidates: catalog, main: nil).isEmpty)
        let excluded = Set(catalog.filter { $0.family == "Korean" }.map(\.key))
        #expect(
            Suggestions.suggestMaterials(missing: missing, candidates: catalog, main: nil, excluding: excluded).map(
                \.family) == ["Symbols"])
        #expect(Suggestions.suggestMaterials(missing: cps("z"), candidates: catalog, main: nil).isEmpty)
    }

    @Test func keepsCatalogOrderOnTies() {
        let first = fakeFace(cps("x"), path: "first.ttf", family: "First")
        let second = fakeFace(cps("x"), path: "second.ttf", family: "Second")
        for catalog in [[first, second], [second, first]] {
            #expect(Suggestions.suggestMaterials(missing: cps("x"), candidates: catalog, main: nil) == catalog)
        }
        var bold = first; bold.path = "bold.ttf"; bold.weightClass = 700
        #expect(
            Suggestions.suggestMaterials(missing: cps("x"), candidates: [bold, second, first], main: nil) == [
                first, second,
            ])
    }

    @Test func prefersFewerGlyphsOnEqualCoverage() {
        let lean = fakeFace(cps("x"), path: "lean.ttf", family: "Lean", glyphCount: 50)
        let heavy = fakeFace(cps("x"), path: "heavy.ttf", family: "Heavy", glyphCount: 500)
        for catalog in [[lean, heavy], [heavy, lean]] {
            #expect(Suggestions.suggestMaterials(missing: cps("x"), candidates: catalog, main: nil) == [lean, heavy])
        }
        let bigger = fakeFace(cps("xy"), path: "bigger.ttf", family: "Bigger")
        #expect(
            Suggestions.suggestMaterials(missing: cps("xy"), candidates: [heavy, lean, bigger], main: nil) == [
                bigger, lean, heavy,
            ])
    }

    @Test func demotesFacesPastTheGlyphLimit() {
        let huge = fakeFace(
            SmartFaces.hangul.union(SmartFaces.han), path: "huge.ttf", family: "Huge", glyphCount: 60000)
        let catalog = SmartFaces.catalog() + [huge], missing = SmartFaces.hangul.union(cps("一丁☺"))
        #expect(
            Suggestions.suggestMaterials(missing: missing, candidates: catalog, main: nil, limit: 4).map(\.family) == [
                "Korean", "Huge", "Han Font", "Symbols",
            ])
        #expect(!GlyphBudget.exceedsGlyphBudget(huge, mainGlyphs: 17535))
        #expect(GlyphBudget.exceedsGlyphBudget(huge, mainGlyphs: 17536))
        #expect(
            Suggestions.suggestMaterials(missing: missing, candidates: catalog, main: nil, limit: 4, mainGlyphs: 17535)[
                1] == huge)
        #expect(
            Suggestions.suggestMaterials(missing: missing, candidates: catalog, main: nil, limit: 4, mainGlyphs: 20000)
                .map(\.family) == ["Korean", "Han Font", "Symbols", "Huge"])
        #expect(
            Suggestions.suggestMaterials(missing: missing, candidates: catalog, main: nil, mainGlyphs: 20000).map(
                \.family) == ["Korean", "Han Font", "Symbols"])
        #expect(
            Suggestions.suggestMaterials(missing: SmartFaces.han, candidates: [huge], main: nil, mainGlyphs: 20000) == [
                huge
            ])
    }

    @Test("CATALOG-2: hidden and suspicious faces are never suggested")
    func catalog2HiddenAndSuspiciousFacesAreNeverSuggested() {
        let last = fakeFace(
            CodepointSet(ranges: [0...0x10FFFF]), path: "last.ttf", family: ".LastResort", glyphCount: 7, hidden: true,
            suspiciousCoverage: true)
        let suspect = fakeFace(
            last.coverage, path: "suspect.ttf", family: "Suspicious", glyphCount: 7, suspiciousCoverage: true)
        let good = SmartFaces.chinese("Hiragino Sans GB")
        #expect(
            Suggestions.suggestMaterials(missing: SmartFaces.han, candidates: [last, suspect, good], main: nil) == [
                good
            ])
        var recipe = Recipe(); recipe.setSampleText("你好")
        #expect(recipe.suggestions(for: .chineseSimplified, in: FaceCatalog([last, suspect, good])) == [good])
    }

    @Test("ENGINE-2: AAT-only faces cannot contribute unshapeable Arabic")
    func aatOnlyFacesAreNotSuggestedForScriptsTheyCannotShape() {
        let coverage = CodepointSet(ranges: [0x600...0x6FF])
        var geeza = fakeFace(coverage, path: "geeza.ttf", family: "Geeza Pro", unshaped: coverage, shapesGroups: [])
        let damascus = fakeFace(coverage, path: "damascus.ttf", family: "Damascus", shapesGroups: [.arabic])
        var recipe = Recipe(); recipe.add(TestFaces.a); recipe.setSampleText("مرحبا")
        #expect(recipe.suggestions(in: FaceCatalog([geeza, damascus])) == [damascus])
        #expect(recipe.suggestions(for: .arabic, in: FaceCatalog([geeza, damascus])) == [damascus])
        geeza.unshaped = .empty
        #expect(
            recipe.suggestions(for: .arabic, in: FaceCatalog([geeza, damascus])).map(\.family) == [
                "Geeza Pro", "Damascus",
            ])
    }
}
