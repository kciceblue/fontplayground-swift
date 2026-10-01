import FPCore
import Testing

struct GlyphBudgetTests {
    let big = fakeFace(CodepointSet(0..<100), path: "big.ttf", glyphCount: 1000)
    let small = fakeFace(cps("abc"), path: "small.ttf")
    let empty = fakeFace(.empty, path: "empty.ttf", glyphCount: 7)

    @Test func glyphShareScalesByPlannedCharacters() {
        #expect(GlyphBudget.faceGlyphShare(big, assigned: 100) == 800)
        #expect(GlyphBudget.faceGlyphShare(big, assigned: 50) == 400)
        #expect(GlyphBudget.faceGlyphShare(big, assigned: 0) == 0)
        #expect(GlyphBudget.faceGlyphShare(small, assigned: 1) == 1)
        #expect(GlyphBudget.faceGlyphShare(empty, assigned: 0) == 0)
    }

    @Test func estimateAddsNotdefAndShares() {
        #expect(
            GlyphBudget.estimate(
                faces: [big, small, empty], plan: Plan(assignments: [CodepointSet(0..<50), cps("a"), .empty])) == 402)
        #expect(GlyphBudget.estimate(faces: [big, small], plan: Plan(assignments: [CodepointSet(0..<100)])) == 801)
        #expect(GlyphBudget.estimate(faces: [], plan: .empty) == 1)
        #expect(GlyphBudget.warnAt == 55000 && GlyphBudget.maxGlyphs == 65535)
    }

    @Test func faceGlyphShareRoundsHalfToEven() {
        #expect(GlyphBudget.faceGlyphShare(fakeFace(CodepointSet(0..<8), glyphCount: 5), assigned: 5) == 2)
    }
}
