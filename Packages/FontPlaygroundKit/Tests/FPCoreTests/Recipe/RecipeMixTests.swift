import FPCore
import Testing

struct RecipeMixTests {
    let a = TestFaces.a, b = TestFaces.b, c = TestFaces.c

    @Test func mixResolvesAdjustmentsAgainstDefaults() {
        var r = recipe([a, b])
        r.setAdjustments(for: b.key, weight: nil, scale: 0.8); r.setDefaults(weight: 500, scale: 1.2)
        let mix = r.mix()
        #expect(mix.fonts == [MixFont(face: a, weight: 500, scale: 1.2), MixFont(face: b, weight: 500, scale: 0.8)])
        #expect(mix.rules == r.scriptRules() && mix.baseIndex == 0)
        #expect(mix.source(of: "漢") == 1 && mix.source(of: "c") == 0)
        r.reset()
        #expect(r.mix() == .empty)
    }

    @Test func mixTryingNeverChangesTheRecipe() {
        let r = recipe([a, c]), before = r
        let hangul = fakeFace(cps("한글ab"), path: "hangul.ttf", family: "Hangul")
        let added = r.mix(trying: hangul, for: .korean)
        #expect(added.keys == [a.key, c.key, hangul.key] && added.rules[.hangul] == 2)
        #expect(r.mix(trying: hangul, replacing: c.key).keys == [a.key, hangul.key])
        #expect(r.mix(trying: a, replacing: c.key) == r.mix())
        #expect(r.mix(trying: a).keys == [a.key, c.key])
        #expect(r == before)
    }

    @Test func talliesFollowThePlan() {
        var r = recipe([a, b])
        let tallies: [[ScriptGroup: Int]] = [[.latin: 5], [.han: 1, .cjkSymbols: 1]]
        #expect(r.analyze().tallies == tallies)
        r.setFamily("Renamed")
        #expect(r.analyze().tallies == tallies)
        r.setAdjustments(for: b.key, weight: 700, scale: nil)
        #expect(r.analyze().tallies == tallies)
        r.setPin(.latin, to: b.key)
        #expect(r.analyze().tallies == [[.latin: 3], [.latin: 2, .han: 1, .cjkSymbols: 1]])
    }

    @Test func mixTryingEdgeCases() {
        var r = recipe([a])
        #expect(r.mix(trying: c, replacing: FaceKey(path: "nope", index: 0)) == recipe([a, c]).mix())
        r.setAdjustments(for: a.key, weight: 500, scale: nil)
        r.setBase(a.key); r.setPin(.han, to: a.key)
        let trial = r.mix(trying: b, replacing: a.key, for: .japanese)
        #expect(trial.fonts == [MixFont(face: b)] && trial.rules[.kana] == nil)
        #expect(trial.rules[.han] == 0 && trial.baseIndex == 0)
        #expect(r.mix(trying: a) == r.mix())
    }
}
