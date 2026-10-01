import FPCore
import Foundation
import Testing

struct PlannerTests {
    private let a = fakeFace(cps("abc1"), path: "a.ttf", family: "A")
    private let b = fakeFace(cps("ab漢，"), path: "b.ttf", family: "B")

    @Test func priorityOrderWinsWithoutRules() {
        let plan = Planner.plan(coverages: [a.plannableCoverage, b.plannableCoverage], rules: [:])
        #expect(plan.assignments == [cps("abc1"), cps("漢，")])
        #expect(plan.source(of: 97) == 0)
    }

    @Test func ruleOverridesPriority() {
        let plan = Planner.plan(coverages: [a.plannableCoverage, b.plannableCoverage], rules: [.latin: 1])
        #expect(plan.assignments == [cps("c1"), cps("ab漢，")])
    }

    @Test func ruleFallsBackWhenMaterialLacksChar() {
        let plan = Planner.plan(coverages: [b.plannableCoverage, a.plannableCoverage], rules: [.han: 1])
        #expect(plan.source(of: 0x6F22) == 0)
    }

    @Test func assignmentsAreDisjointAndComplete() {
        let plan = Planner.plan(coverages: [a.plannableCoverage, b.plannableCoverage], rules: [:])
        #expect(plan.assignments[0].intersection(plan.assignments[1]).isEmpty)
        #expect(plan.assignments[0].union(plan.assignments[1]) == a.plannableCoverage.union(b.plannableCoverage))
        #expect(plan.totalCodepoints == 6)
        #expect(plan.tallies() == [[.latin: 4], [.han: 1, .cjkSymbols: 1]])
        #expect(plan.source(of: 0xAC00) == nil)
    }

    @Test func sourceOfPrefersRuleFont() {
        let sets = [cps("a漢"), cps("a漢b")]
        #expect(Planner.sourceOf(0x6F22, coverages: sets, rules: [.han: 1]) == 1)
        #expect(Planner.sourceOf(97, coverages: sets, rules: [.han: 1]) == 0)
    }

    @Test func sourceOfFallsBackThenNil() {
        let sets = [cps("a"), cps("漢")]
        #expect(Planner.sourceOf(0x6F22, coverages: sets, rules: [.han: 0]) == 1)
        #expect(Planner.sourceOf(0xD55C, coverages: sets, rules: [:]) == nil)
        #expect(Planner.sourceOf(97, coverages: sets, rules: [.latin: 7]) == 0)
        #expect(Planner.sourceOf(97, coverages: sets, rules: [.latin: -1]) == 0)
        #expect(Planner.sourceOf(UInt32.max, coverages: sets, rules: [:]) == nil)
    }

    @Test func sweepEqualsPerCodePointReference() {
        var seed: UInt64 = 20260929
        func next(_ upper: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Int(seed >> 32) % upper
        }
        let anchors: [UInt32] = [0x20, 0x370, 0x600, 0x900, 0x2190, 0x3000, 0x3040, 0x4E00, 0xAC00, 0xFF00, 0x1F600]
        for _ in 0..<300 {
            let count = next(4) + 1
            let coverages = (0..<count).map { _ in
                CodepointSet(
                    ranges: (0..<next(7)).map { _ in
                        let start = anchors[next(anchors.count)] + UInt32(next(64))
                        return start...(start + UInt32(next(40)))
                    })
            }
            var rules: [ScriptGroup: Int] = [:]
            for group in ScriptGroup.allCases where next(2) == 0 { rules[group] = [-1, 0, 1, 2, 3, 5][next(6)] }
            let result = Planner.plan(coverages: coverages, rules: rules)
            let union = coverages.reduce(CodepointSet.empty) { $0.union($1) }
            var expected = Array(repeating: [UInt32](), count: count)
            for cp in union.codepoints {
                expected[Planner.sourceOf(cp, coverages: coverages, rules: rules)!].append(cp)
            }
            #expect(result.assignments == expected.map(CodepointSet.init))
            #expect(result.assignments.reduce(CodepointSet.empty) { $0.union($1) } == union)
            #expect(result.totalCodepoints == union.count)
            for left in result.assignments.indices {
                for right in result.assignments.indices where left < right {
                    #expect(result.assignments[left].intersection(result.assignments[right]).isEmpty)
                }
                var tally: [ScriptGroup: Int] = [:]
                for cp in expected[left] { tally[ScriptGroup.of(cp), default: 0] += 1 }
                #expect(result.tallies()[left] == tally)
            }
            for cp in union.codepoints {
                #expect(result.source(of: cp) == Planner.sourceOf(cp, coverages: coverages, rules: rules))
            }
        }
    }

    @Test func emptyInputsAndUnicodeEndpoints() {
        #expect(Planner.plan(coverages: [], rules: [.latin: 8]) == .empty)
        #expect(Planner.plan(coverages: [.empty, .empty], rules: [:]).assignments == [.empty, .empty])
        #expect(Plan.empty.totalCodepoints == 0 && Plan.empty.tallies().isEmpty)
        #expect(Plan.empty.source(of: 0) == nil)
        let all = CodepointSet(ranges: [0...0x10FFFF])
        let plan = Planner.plan(coverages: [all, all], rules: [.han: 1, .other: 1])
        #expect(plan.assignments[1] == ScriptGroup.codepoints(of: .han).union(ScriptGroup.codepoints(of: .other)))
        #expect(plan.totalCodepoints == 0x110000)
        #expect(plan.source(of: 0x10FFFF) == 1)
        #expect(plan.source(of: 0x110000) == nil)
        #expect(Planner.plan(coverages: [all], rules: [:]).assignments == [all])
    }
}
