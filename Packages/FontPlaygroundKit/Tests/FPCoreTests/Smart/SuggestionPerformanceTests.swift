import FPCore
import Foundation
import Testing

extension SuggestionTests {
    @Test func suggestionsOverLargeCatalogAreFast() {
        let latin = PlannerBenchmarks.fragmented(.latin, count: 1000, pieces: 60)
        let required = cps(Languages.language(.chineseSimplified).markers + Samples.defaultSample)
            .intersection(ScriptGroup.codepoints(of: .han))
        var ranges = required.ranges
        // Keep exactly 1,500 disjoint ranges, including the language's markers and the sample's Han.
        outer: for block in ScriptGroup.codepoints(of: .han).ranges {
            var cursor = block.lowerBound
            while cursor + 19 <= block.upperBound {
                let piece = cursor...(cursor + 19)
                let surrounding = CodepointSet(ranges: [(cursor - 1)...(cursor + 20)])
                if required.intersection(surrounding).isEmpty { ranges.append(piece) }
                if ranges.count == 1500 { break outer }
                cursor += 21
            }
        }
        let cjk = CodepointSet(ranges: ranges), arabic = CodepointSet(ranges: [0x600...0x6FF])
        var faces = (0..<880).map { fakeFace(latin, path: "latin-\($0).ttf", family: "Latin \($0)") }
        faces += (0..<100).map { fakeFace(cjk, path: "cjk-\($0).ttf", family: "CJK \($0)") }
        faces += (0..<20).map { fakeFace(arabic, path: "arabic-\($0).ttf", family: "Arabic \($0)") }
        #expect(faces.count == 1000)
        #expect(faces.prefix(880).allSatisfy { $0.coverage.ranges.count == 60 })
        #expect(
            faces[880..<980].allSatisfy {
                $0.coverage.ranges.count == 1500 && Languages.coversWell($0, Languages.language(.chineseSimplified))
            })
        let catalog = FaceCatalog(faces)
        var recipe = Recipe(); recipe.add(faces[0])
        #expect(recipe.sampleText == Samples.defaultSample)
        var counts: [Int] = []
        let general = PlannerBenchmarks.medianSeconds { counts.append(recipe.suggestions(in: catalog).count) }
        #expect(counts == Array(repeating: 3, count: 10))
        counts = []
        let chinese = PlannerBenchmarks.medianSeconds {
            counts.append(recipe.suggestions(for: .chineseSimplified, in: catalog).count)
        }
        #expect(counts == Array(repeating: 3, count: 10))
        print(
            "1,000-face suggestions medians: general \(general * 1000) ms; Chinese \(chinese * 1000) ms (100 ms each)")
        #expect(general <= 0.100)
        #expect(chinese <= 0.100)
    }
}
