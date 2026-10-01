import FPCore
import Foundation
import Testing

struct MixTests {
    private let a = fakeFace(cps("abc1,"), path: "a.ttf", family: "A")
    private let b = fakeFace(cps("ab漢，"), path: "b.ttf", family: "B")

    @Test func sourceOfAgreesWithThePlan() {
        let mix = Mix(fonts: [MixFont(face: a), MixFont(face: b)], rules: [.latin: 1, .han: 1])
        let plan = mix.plan()
        for cp in a.plannableCoverage.union(b.plannableCoverage).codepoints {
            #expect(mix.source(of: cp) == plan.source(of: cp))
        }
        #expect(mix.source(of: "한".unicodeScalars.first!) == nil)
    }

    @Test func mixBasics() {
        let fonts = [MixFont(face: a, weight: 700, scale: 0.9), MixFont(face: b)]
        let mix = Mix(fonts: fonts, baseIndex: 1)
        #expect(mix.keys == [a.key, b.key])
        #expect(mix.fonts[0].weight == 700 && mix.fonts[0].scale == 0.9)
        #expect(mix.fonts[1].scale == 1.0 && mix.fonts[1].weight == nil)
        #expect(mix.baseIndex == 1 && mix == Mix(fonts: fonts, baseIndex: 1))
        #expect(mix != Mix(fonts: fonts, baseIndex: 0))
        #expect(mix != Mix(fonts: fonts, rules: [.han: 1], baseIndex: 1))
        #expect(mix != Mix(fonts: [fonts[1], fonts[0]], baseIndex: 1))
        #expect(Mix.empty.fonts.isEmpty && Mix.empty.keys.isEmpty)
        #expect(Mix.empty.source(of: 97) == nil && Mix.empty.plan() == .empty)
    }

    @Test func unavailableFontDrawsNothing() {
        let unavailable = MixFont(face: a, isAvailable: false)
        let mix = Mix(fonts: [unavailable, MixFont(face: b)], rules: [.latin: 0])
        #expect(unavailable.effectiveCoverage.isEmpty)
        #expect(mix.source(of: 97) == 1 && mix.source(of: 99) == nil)
        #expect(mix.missingCharacters(in: "ac").map(\.value) == [99])
        #expect(mix.plan().assignments == [.empty, b.plannableCoverage])
    }

    @Test func missingCharactersAreVisibleSortedUnique() {
        let text = "a\u{200D} b\u{FE0F}\u{200B}\u{AD}漢\u{202A}\n"
        #expect(Mix.empty.missingCharacters(in: text).map(\.value) == [97, 98, 0x6F22])
        #expect(Mix(fonts: [MixFont(face: a)]).missingCharacters(in: text).map(\.value) == [0x6F22])
        #expect(Mix.empty.missingCharacters(in: "漢漢a漢e\u{301}").map(\.value) == [97, 101, 0x301, 0x6F22])
    }

    @Test func unshapedCharactersGoToTheNextFontOrAreMissing() {
        let arabic = CodepointSet(ranges: [0x0627...0x064A])
        let geeza = fakeFace(
            cps("ab").union(arabic), path: "geeza.ttc", family: "Geeza Pro", unshaped: arabic, shapesGroups: [])
        let damascus = fakeFace(arabic, path: "damascus.ttc", family: "Damascus", shapesGroups: [.arabic])
        let text = "aمرحبا"
        let onlyGeeza = Mix(fonts: [MixFont(face: geeza)])
        #expect(onlyGeeza.missingCharacters(in: text).map(\.value) == cps("مرحبا").codepoints)
        #expect(
            onlyGeeza.runs(in: text) == [
                MixRun(utf16Range: 0..<1, scalarRange: 0..<1, source: 0),
                MixRun(utf16Range: 1..<6, scalarRange: 1..<6, source: nil),
            ])
        let both = Mix(fonts: [MixFont(face: geeza), MixFont(face: damascus)], rules: [.arabic: 0])
        #expect("مرحبا".unicodeScalars.allSatisfy { both.source(of: $0) == 1 })
        #expect(both.missingCharacters(in: text).isEmpty)
        #expect(both.plan().assignments == [cps("ab"), arabic])
    }

    @Test("ENGINE-2: partial shaping coverage and unavailable alternatives stay honest")
    func engine2PartiallyShapeableAndUnavailableAlternatives() {
        let first = fakeFace(cps("اب"), unshaped: cps("ب"), shapesGroups: [.arabic])
        let unavailable = MixFont(face: fakeFace(cps("ب")), isAvailable: false)
        let mix = Mix(fonts: [MixFont(face: first), unavailable], rules: [.arabic: 0])
        #expect(mix.missingCharacters(in: "اب").map(\.value) == cps("ب").codepoints)
        #expect(mix.plan().assignments == [cps("ا"), .empty])
    }
}
