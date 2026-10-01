import FPCore
import Foundation
import Testing

struct MixRunsTests {
    private let a = MixFont(face: fakeFace(cps("abc1,"), path: "a.ttf", family: "A"))
    private let b = MixFont(face: fakeFace(cps("ab漢，"), path: "b.ttf", family: "B"))

    @Test func runsFollowSourcesAndScalarOffsets() {
        let mix = Mix(fonts: [a, b])
        #expect(
            mix.runs(in: "ab漢c") == [
                MixRun(utf16Range: 0..<2, scalarRange: 0..<2, source: 0),
                MixRun(utf16Range: 2..<3, scalarRange: 2..<3, source: 1),
                MixRun(utf16Range: 3..<4, scalarRange: 3..<4, source: 0),
            ])
        #expect(mix.runs(in: "").isEmpty)
        #expect(
            mix.runs(in: "\n漢") == [
                MixRun(utf16Range: 0..<1, scalarRange: 0..<1, source: nil),
                MixRun(utf16Range: 1..<2, scalarRange: 1..<2, source: 1),
            ])
    }

    @Test func surrogatePairsCountAsTwoUTF16Units() {
        #expect(
            Mix(fonts: [a]).runs(in: "a😀b") == [
                MixRun(utf16Range: 0..<1, scalarRange: 0..<1, source: 0),
                MixRun(utf16Range: 1..<3, scalarRange: 1..<2, source: nil),
                MixRun(utf16Range: 3..<4, scalarRange: 2..<3, source: 0),
            ])
    }

    @Test func unmappedIgnorablesStayWithTheCurrentRun() {
        let mix = Mix(fonts: [a])
        #expect(mix.runs(in: "a\u{200D}b") == [MixRun(utf16Range: 0..<3, scalarRange: 0..<3, source: 0)])
        #expect(mix.runs(in: "a\u{E0100}b") == [MixRun(utf16Range: 0..<4, scalarRange: 0..<3, source: 0)])
        #expect(mix.runs(in: "\u{200D}\u{FE0F}") == [MixRun(utf16Range: 0..<2, scalarRange: 0..<2, source: nil)])
        let mappedJoiner = MixFont(face: fakeFace(cps("\u{200D}")))
        #expect(Mix(fonts: [a, mappedJoiner]).runs(in: "a\u{200D}b").map(\.source) == [0, 1, 0])
    }

    @Test func randomRunsPartitionScalarAndUTF16Text() {
        var seed: UInt64 = 0xA11CE
        func next(_ upper: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Int(seed >> 32) % upper
        }
        let alphabet = Array("ab漢c\n😀\u{200D}\u{FE0F}Ωe\u{301}\u{E0100}".unicodeScalars)
        let mix = Mix(fonts: [a, b], rules: [.han: 1])
        for _ in 0..<100 {
            let scalars = (0..<next(80)).map { _ in alphabet[next(alphabet.count)] }
            let text = String(String.UnicodeScalarView(scalars))
            let runs = mix.runs(in: text)
            var utf16 = 0
            var scalar = 0
            var actual: [Int?] = []
            for run in runs {
                #expect(run.utf16Range.lowerBound == utf16 && run.scalarRange.lowerBound == scalar)
                #expect(!run.utf16Range.isEmpty && !run.scalarRange.isEmpty)
                let segment = String(String.UnicodeScalarView(scalars[run.scalarRange]))
                #expect(run.utf16Range.count == segment.utf16.count)
                actual += Array(repeating: run.source, count: run.scalarRange.count)
                utf16 = run.utf16Range.upperBound; scalar = run.scalarRange.upperBound
            }
            #expect(utf16 == text.utf16.count && scalar == scalars.count)
            #expect(zip(runs, runs.dropFirst()).allSatisfy { $0.source != $1.source })
            var expected: [Int?] = []
            var previous: Int?
            for scalar in scalars {
                let mapped = mix.source(of: scalar)
                if mapped != nil || !TextUtil.isIgnorable(scalar) { previous = mapped }
                expected.append(previous)
            }
            #expect(actual == expected)
        }
    }

    @Test func runsForLongTextAreFast() {
        let fonts = PlannerBenchmarks.coverages.enumerated().map {
            MixFont(face: fakeFace($1, path: "font\($0).ttf"))
        }
        let mix = Mix(fonts: fonts, rules: PlannerBenchmarks.rules)
        let alphabet = Array("abc漢字かなカナ한글".unicodeScalars)
        let text = String(String.UnicodeScalarView((0..<5000).map { alphabet[$0 % alphabet.count] }))
        #expect(text.unicodeScalars.count == 5000)
        var results: [[MixRun]] = []
        let median = PlannerBenchmarks.medianSeconds { results.append(mix.runs(in: text)) }
        #expect(
            results.allSatisfy {
                $0.last?.utf16Range.upperBound == text.utf16.count && $0.last?.scalarRange.upperBound == 5000
            })
        print("5,000-scalar mix runs median: \(median * 1000) ms (50 ms budget)")
        #expect(median <= 0.050)
    }
}
