import FPCore
import Testing

struct RuleResolverTests {
    let segoe = fakeFace(CodepointSet(ranges: [0x20...0x24F, 0x4E00...0x4E1D]), path: "segoe.ttf", family: "Segoe UI")
    let yahei = fakeFace(
        CodepointSet(ranges: [0x41...0x108, 0x4E00...0x59B7]), path: "yahei.ttc", index: 1, family: "Microsoft YaHei")
    func counts(_ faces: [FaceRecord]) -> [FaceKey: [ScriptGroup: Int]] {
        Dictionary(uniqueKeysWithValues: faces.map { ($0.key, RuleResolver.counts(for: Material(face: $0))) })
    }

    @Test func hanGoesToYaHeiLatinStaysWithSegoe() {
        let counts = counts([segoe, yahei])
        #expect(RuleResolver.smartSupplier(.han, counts: counts, order: [segoe.key, yahei.key]) == yahei.key)
        #expect(RuleResolver.smartSupplier(.latin, counts: counts, order: [segoe.key, yahei.key]) == segoe.key)
        #expect(RuleResolver.smartSupplier(.han, counts: counts, order: [yahei.key, segoe.key]) == yahei.key)
        #expect(RuleResolver.smartSupplier(.latin, counts: counts, order: [yahei.key, segoe.key]) == yahei.key)
    }

    @Test func materialBelowMainNeedsHalfTheBest() {
        let hangul = fakeFace(CodepointSet(ranges: [0xAC00...0xAC63]), path: "hangul.ttf", family: "Hangul Only")
        var counts = counts([hangul, segoe, yahei])
        counts[yahei.key]?[.latin] = 280
        #expect(
            RuleResolver.smartSupplier(.latin, counts: counts, order: [hangul.key, yahei.key, segoe.key]) == yahei.key)
        counts[yahei.key]?[.latin] = 279
        #expect(
            RuleResolver.smartSupplier(.latin, counts: counts, order: [hangul.key, yahei.key, segoe.key]) == segoe.key)
        #expect(
            RuleResolver.smartSupplier(.latin, counts: counts, order: [hangul.key, segoe.key, yahei.key]) == segoe.key)
    }

    @Test func mainKeepsAGroupAtATenth() {
        let symbols = (UInt32(0x2190)..<0x2800).filter { ScriptGroup.of($0) == .symbols }
        let han = CodepointSet(ranges: [0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2019F])
        let georgia = fakeFace(
            CodepointSet(ranges: [0x20...0x24F]).union(CodepointSet(symbols.prefix(120))), path: "georgia.ttf",
            family: "Georgia")
        let cjk = fakeFace(han.union(CodepointSet(symbols.prefix(1200))), path: "cjk.ttf", family: "CJK")
        var counts = counts([georgia, cjk]); let order = [georgia.key, cjk.key]
        #expect(counts[georgia.key]?[.symbols] == 120 && counts[cjk.key]?[.han] == 28000)
        #expect(RuleResolver.smartSupplier(.symbols, counts: counts, order: order) == georgia.key)
        #expect(RuleResolver.smartSupplier(.latin, counts: counts, order: order) == georgia.key)
        #expect(RuleResolver.smartSupplier(.han, counts: counts, order: order) == cjk.key)
        counts[georgia.key]?[.han] = 2
        #expect(RuleResolver.smartSupplier(.han, counts: counts, order: order) == cjk.key)
        counts[cjk.key]?[.symbols] = 1201
        #expect(RuleResolver.smartSupplier(.symbols, counts: counts, order: order) == cjk.key)
        counts[cjk.key]?[.symbols] = 1200
        #expect(
            RuleResolver.smartSupplier(.symbols, counts: counts, order: [FaceKey(path: "third.ttf", index: 0)] + order)
                == cjk.key)
        #expect(RuleResolver.smartSupplier(.symbols, counts: counts, order: order.reversed()) == cjk.key)
    }

    @Test func supplierIsNilWhenNobodyCovers() {
        let counts = counts([segoe, yahei])
        #expect(RuleResolver.smartSupplier(.hangul, counts: counts, order: [segoe.key, yahei.key]) == nil)
        #expect(RuleResolver.smartSupplier(.hangul, counts: counts, order: []) == nil)
        #expect(RuleResolver.smartSupplier(.latin, counts: [:], order: [segoe.key]) == nil)
    }

    @Test func resolveRulesUsesPinsThenSmart() {
        let counts = counts([segoe, yahei]), order = [segoe.key, yahei.key]
        let rules = RuleResolver.resolveRules(order: order, pins: [:], counts: counts)
        #expect(rules[.latin] == 0 && rules[.han] == 1 && rules[.hangul] == nil)
        let pinned = RuleResolver.resolveRules(
            order: order, pins: [.han: segoe.key, .hangul: yahei.key], counts: counts)
        #expect(pinned[.han] == 0 && pinned[.hangul] == 1)
        #expect(
            RuleResolver.resolveRules(
                order: order, pins: [.han: FaceKey(path: "missing.ttf", index: 0)], counts: counts) == rules)
    }

    @Test("CATALOG-2: suspicious coverage cannot capture automatic groups")
    func catalog2SuspiciousFaceNeverTakesAGroup() {
        let main = fakeFace(CodepointSet(ranges: [0x20...0x24F]), path: "main.ttf")
        let cjk = fakeFace(
            CodepointSet(ranges: [0x4E00...0x59B7]).union(
                CodepointSet(ScriptGroup.codepoints(of: .kana).codepoints.prefix(200))
            ).union(CodepointSet(ScriptGroup.codepoints(of: .cjkSymbols).codepoints.prefix(100))), path: "cjk.ttf")
        let lastResort = fakeFace(
            CodepointSet(ranges: [0...0x10FFFF]), path: "lr.ttf", glyphCount: 7, suspiciousCoverage: true)
        var r = recipe([main, cjk, lastResort])
        let rules = r.scriptRules()
        #expect(rules[.han] == 1 && rules[.kana] == 1 && rules[.cjkSymbols] == 1 && rules[.hangul] == nil)
        r.setPin(.han, to: lastResort.key)
        #expect(r.scriptRules()[.han] == 2)
        #expect(RuleResolver.counts(for: Material(face: cjk, availability: .notFound)).isEmpty)
    }
}
