import FPCore
import Testing

struct RecipeAnalysisTests {
    let a = TestFaces.a, b = TestFaces.b, c = TestFaces.c

    @Test func planFollowsPinsImmediately() {
        var r = recipe([a, b])
        #expect(r.plan().totalCodepoints == 7)
        r.setPin(.latin, to: b.key)
        #expect(r.plan().source(of: 97) == 1)
        r.remove(a.key); r.remove(b.key)
        #expect(r.plan() == .empty)
    }

    @Test func sampleTextAndMissingCharacters() {
        var r = Recipe()
        #expect(r.sampleText == Samples.defaultSample)
        #expect(r.setSampleText("a b漢 →→Ω") && !r.setSampleText("a b漢 →→Ω"))
        #expect(r.missingSampleCharacters() == Array("abΩ→漢".unicodeScalars))
        r.add(a)
        #expect(r.missingSampleCharacters() == Array("Ω→漢".unicodeScalars))
        r.add(c)
        #expect(r.missingSampleCharacters() == ["漢"])
        r.add(b)
        #expect(r.missingSampleCharacters().isEmpty)
    }

    @Test func missingNeverCountsInvisibleCharacters() {
        var r = Recipe(); r.setSampleText("a\u{200D} b\u{FE0F}\u{200B}\u{AD}漢\u{202A}\n")
        #expect(r.missingSampleCharacters() == Array("ab漢".unicodeScalars))
        r.add(a)
        #expect(r.missingSampleCharacters() == ["漢"])
    }

    @Test func glyphBudgetWarnsNearAndBlocksPastLimit() throws {
        var r = Recipe()
        #expect(r.analyze().glyphEstimate == 0 && r.analyze().glyphWarning == nil)
        var main = a; main.glyphCount = 60000
        r.add(main)
        #expect(r.analyze().glyphEstimate == 48001 && r.analyze().glyphWarning == nil && r.analyze().canForge)
        var near = b; near.glyphCount = 40000
        r.add(near)
        #expect(r.analyze().glyphEstimate == 64001 && r.analyze().glyphWarning == .nearLimit && r.analyze().canForge)
        #expect(
            EnglishText.glyphWarning(.nearLimit)
                == "These fonts come close to the 65,535-glyph limit; if forging fails, remove a font or use a smaller build."
        )
        r.remove(near.key); near.glyphCount = 45000; r.add(near)
        let analysis = r.analyze()
        #expect(analysis.glyphEstimate == 66001 && analysis.validity == .glyphLimit(estimate: 66001))
        #expect(!analysis.canForge && analysis.glyphWarning == .overLimit(estimate: 66001))
        let text =
            "Together these fonts need about 66,001 glyphs; a font can hold 65,535. Remove a font or use a smaller (regional) build."
        #expect(EnglishText.problem(try #require(analysis.validity), in: r) == text)
        #expect(EnglishText.glyphWarning(try #require(analysis.glyphWarning)) == text)
        r.remove(b.key)
        #expect(r.analyze().canForge && r.analyze().glyphEstimate == 48001 && r.analyze().glyphWarning == nil)
        r.remove(main.key)
        #expect(r.analyze().glyphEstimate == 0 && r.analyze().glyphWarning == nil)
    }

    @Test func analyzeIsPureAndFast() {
        var r = recipe(
            PlannerBenchmarks.coverages.enumerated().map { fakeFace($0.element, path: "bench\($0.offset).ttf") })
        r.setSampleText(
            String(repeating: "abc漢かな한글 ", count: 250).unicodeScalars.prefix(2000).reduce(into: "") {
                $0.unicodeScalars.append($1)
            })
        let before = r
        let analysis = r.analyze()
        #expect(analysis == r.analyze() && r == before)
        let median = PlannerBenchmarks.medianSeconds { #expect(r.analyze() == analysis) }
        print("Recipe analysis median: \(median * 1000) ms (100 ms budget)")
        #expect(median <= 0.100)
    }
}
