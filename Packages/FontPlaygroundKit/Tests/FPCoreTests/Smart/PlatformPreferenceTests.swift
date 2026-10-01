import FPCore
import Foundation
import Testing

struct PlatformPreferenceTests {
    @Test("CATALOG-11: platform defaults win equal coverage") func catalog11PlatformDefaultWinsCoverageTies() {
        let catalog = FaceCatalog([
            SmartFaces.chinese("Lantinghei SC", glyphs: 30001), SmartFaces.chinese("BiauKai", glyphs: 31001),
            SmartFaces.chinese("PingFang SC", glyphs: 40001),
        ])
        var recipe = Recipe(); recipe.add(TestFaces.a); recipe.setSampleText("你好，世界！欢迎使用字体游乐场。")
        #expect(recipe.suggestions(for: .chineseSimplified, in: catalog).first?.family == "PingFang SC")
        #expect(
            recipe.suggestions(for: .chineseSimplified, in: catalog, preferences: .none).map(\.family) == [
                "Lantinghei SC", "BiauKai", "PingFang SC",
            ])
    }

    @Test("CATALOG-11: missing-character coverage outranks preference") func catalog11CoverageStillDominatesPreference()
    {
        let missing = CodepointSet(ranges: [0x9000...0x900B])
        var ping = SmartFaces.chinese("PingFang SC"), other = SmartFaces.chinese("Other")
        ping.coverage = ping.coverage.union(CodepointSet(ranges: [0x9000...0x9009]))
        other.coverage = other.coverage.union(missing)
        #expect(
            Suggestions.suggestMaterials(
                missing: missing, candidates: [ping, other], main: nil,
                preferred: PlatformPreferences.macOS.entries(for: [.chineseSimplified])) == [other, ping])
    }

    @Test func macOSTableMatchesSpec() {
        let expected: [LanguageID: [String]] = [
            .chineseSimplified: ["PingFang SC"], .chineseTraditional: ["PingFang TC", "PingFang HK"],
            .japanese: ["Hiragino Sans"], .korean: ["Apple SD Gothic Neo"],
            .arabic: ["Geeza Pro", "Damascus", "Noto Nastaliq Urdu", "Arial", "Times New Roman", "Tahoma"],
            .indic: ["Kohinoor Devanagari", "ITF Devanagari", "Devanagari Sangam MN", "Shree Devanagari 714"],
            .southeastAsian: ["Thonburi", "Sukhumvit Set", "Tahoma"],
            .hebrew: ["Arial Hebrew", "Arial", "Times New Roman", "Tahoma"],
            .latin: ["Helvetica Neue"], .greek: ["Helvetica Neue"], .cyrillic: ["Helvetica Neue"],
        ]
        for language in LanguageID.allCases {
            #expect(
                PlatformPreferences.macOS.entries(for: [language])
                    == (expected[language] ?? []).map(PlatformPreferences.Entry.family))
        }
        #expect(PlatformPreferences.macOS.entries(for: [.latin, .greek, .cyrillic]) == [.family("Helvetica Neue")])
        #expect(PlatformPreferences.none.entries(for: LanguageID.allCases).isEmpty)
    }

    @Test func postscriptEntriesAndAppending() {
        let preferences = PlatformPreferences([.chineseSimplified: [.postscriptName("PingFangSC-Regular")]]).appending(
            .macOS)
        let entries = preferences.entries(for: [.chineseSimplified])
        #expect(entries == [.postscriptName("PingFangSC-Regular"), .family("PingFang SC")])
        var regular = SmartFaces.chinese("PingFang SC"); regular.postscriptName = "PingFangSC-Regular"
        #expect(PlatformPreferences.rank(of: regular, in: entries) == 0)
        #expect(PlatformPreferences.rank(of: SmartFaces.chinese("PingFang SC"), in: entries) == 1)
        #expect(PlatformPreferences.rank(of: SmartFaces.chinese("Songti SC"), in: entries) == Int.max)
        #expect(preferences.appending(preferences) == preferences)
    }
}
