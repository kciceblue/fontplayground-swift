import FPCore
import Foundation
import Testing

enum PlannerBenchmarks {
    static func fragmented(_ group: ScriptGroup, count: Int, pieces: Int) -> CodepointSet {
        let available = ScriptGroup.codepoints(of: group).ranges
        var index = 0
        var cursor = available[0].lowerBound
        var result: [ClosedRange<UInt32>] = []
        for piece in 0..<pieces {
            let length = UInt32(count / pieces + (piece < count % pieces ? 1 : 0))
            while cursor + length - 1 > available[index].upperBound {
                index += 1
                precondition(index < available.count, "Benchmark script has insufficient coverage")
                cursor = available[index].lowerBound
            }
            result.append(cursor...(cursor + length - 1))
            cursor += length + 1
        }
        return CodepointSet(ranges: result)
    }

    static let coverages: [CodepointSet] = [
        fragmented(.latin, count: 1000, pieces: 60),
        fragmented(.han, count: 30000, pieces: 1500),
        fragmented(.kana, count: 400, pieces: 20).union(fragmented(.han, count: 13000, pieces: 680)),
        fragmented(.hangul, count: 11172, pieces: 160).union(fragmented(.han, count: 2000, pieces: 40)),
    ]
    static let rules: [ScriptGroup: Int] = [.han: 1, .kana: 2, .hangul: 3]

    static func medianSeconds(_ operation: () -> Void) -> Double {
        let clock = ContinuousClock()
        let samples = (0..<10).map { _ in
            let start = clock.now
            operation()
            let duration = start.duration(to: clock.now).components
            return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        }.sorted()
        return (samples[4] + samples[5]) / 2
    }
}

struct PlannerPerformanceTests {
    @Test func panCJKPlanIsFast() {
        let coverages = PlannerBenchmarks.coverages
        #expect(coverages.map(\.count) == [1000, 30000, 13400, 13172])
        #expect(coverages.map { $0.ranges.count } == [60, 1500, 700, 200])
        #expect(ScriptGroup.counts(in: coverages[0]) == [.latin: 1000])
        #expect(ScriptGroup.counts(in: coverages[1]) == [.han: 30000])
        #expect(ScriptGroup.counts(in: coverages[2]) == [.kana: 400, .han: 13000])
        #expect(ScriptGroup.counts(in: coverages[3]) == [.hangul: 11172, .han: 2000])
        let expectedCount = coverages.reduce(CodepointSet.empty) { $0.union($1) }.count
        var counts: [Int] = []
        let median = PlannerBenchmarks.medianSeconds {
            counts.append(Planner.plan(coverages: coverages, rules: PlannerBenchmarks.rules).totalCodepoints)
        }
        #expect(counts == Array(repeating: expectedCount, count: 10))
        print("Pan-CJK planner median: \(median * 1000) ms (50 ms budget)")
        #expect(median <= 0.050)
    }
}
