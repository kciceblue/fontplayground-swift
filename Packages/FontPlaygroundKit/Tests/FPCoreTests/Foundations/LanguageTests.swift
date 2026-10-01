import FPCore
import Foundation
import Testing

/// The first `count` unified ideographs.
private func hanPrefix(_ count: UInt32) -> CodepointSet {
    CodepointSet(ranges: [0x4E00...0x4E00 + count - 1])
}

struct LanguageTests {
    private let han3000 = hanPrefix(3000)
    private let kana = CodepointSet(ranges: [0x3041...0x3096, 0x30A1...0x30FA])

    @Test func uniqueIDsAndKnownGroups() {
        let ids = Languages.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.first == .latin && ids.last == .any)
        #expect(ids == LanguageID.allCases)
        for language in Languages.all {
            #expect(language.groups.allSatisfy { ScriptGroup.allCases.contains($0) })
            #expect(language.minimums.allSatisfy { ScriptGroup.allCases.contains($0.group) })
        }
        #expect(Languages.language(.korean).groups == [.hangul])
        #expect(Languages.language(.japanese).groups == [.kana])
        #expect(Languages.language(rawID: "klingon") == nil)
    }

    @Test func coversWellNeedsCountsAndMarkers() {
        let simplified = Languages.language(.chineseSimplified)
        let markers = cps(simplified.markers)
        #expect(Languages.coversWell(fakeFace(han3000.union(markers)), simplified))
        #expect(!Languages.coversWell(fakeFace(han3000), simplified))
        #expect(
            !Languages.coversWell(fakeFace(hanPrefix(100).union(markers)), simplified))
        let japanese = Languages.language(.japanese)
        #expect(Languages.coversWell(fakeFace(kana.union(hanPrefix(1000))), japanese))
        #expect(!Languages.coversWell(fakeFace(kana), japanese))
        #expect(Languages.coversWell(fakeFace(cps("a")), Languages.language(.any)))
    }

    @Test func languagesForMissingOrderByCount() {
        #expect(
            Languages.languagesForMissing(Array("한글漢字字あ\u{E0001}".unicodeScalars)).map(\.id) == [
                .chineseSimplified, .korean, .japanese,
            ])
        #expect(Languages.languagesForMissing(Array("，☺".unicodeScalars)).map(\.id) == [.chineseSimplified, .symbols])
        #expect(Languages.languagesForMissing([]).isEmpty)
    }

    @Test func joinLabelsUsesShortLabelsWithoutRepeats() {
        #expect(EnglishText.joinLabels([.chineseSimplified, .japanese]) == "Chinese and Japanese")
        #expect(EnglishText.joinLabels([.chineseSimplified, .chineseTraditional, .korean]) == "Chinese and Korean")
        #expect(EnglishText.joinLabels([.korean]) == "Korean")
        #expect(EnglishText.joinLabels([]).isEmpty)
        #expect(EnglishText.joinLabels([.latin, .korean, .japanese], limit: 1, joiner: " / ") == "Letters")
        #expect(EnglishText.joinLabels([.latin, .korean, .japanese], limit: -1, joiner: " / ") == "Letters / Korean")
    }

    @Test func drawsTextInPlainWords() {
        #expect(
            EnglishText.draws(Languages.namedGroups([.han: 28195, .cjkSymbols: 465, .kana: 300, .symbols: 100]))
                == "Draws Chinese characters, CJK punctuation and Japanese kana.")
        #expect(
            EnglishText.draws(
                Languages.namedGroups([
                    .latin: 1386, .arabic: 674, .symbols: 481, .cyrillic: 432, .greek: 368, .armenianGeorgian: 269,
                ])) == "Draws letters, numbers and punctuation, plus Arabic, symbols, Cyrillic, Greek and more.")
        #expect(EnglishText.draws(Languages.namedGroups([.latin: 95])) == "Draws letters, numbers and punctuation.")
        #expect(EnglishText.draws(Languages.namedGroups([.hangul: 3])) == "Draws Korean Hangul.")
        #expect(
            EnglishText.draws(Languages.namedGroups([:]))
                == "Draws nothing — the fonts above already cover everything it has.")
    }

    @Test func roleTitle() {
        let cases: [([ScriptGroup: Int], String)] = [
            ([.han: 28195, .cjkSymbols: 465, .kana: 300, .symbols: 340], "FOR CHINESE & JAPANESE"),
            ([.hangul: 11000, .han: 20], "FOR KOREAN"),
            ([.han: 28195, .cjkSymbols: 465, .symbols: 340, .kana: 198], "FOR CHINESE & JAPANESE"),
            ([.symbols: 40], "FOR SYMBOLS & EMOJI"), ([:], "ADDS NOTHING"), ([.other: 5], "FILLS IN THE REST"),
        ]
        for (tally, expected) in cases { #expect(EnglishText.roleTitle(Languages.roleTitle(tally)) == expected) }
        #expect(
            Languages.roleTitle([.han: 28195, .cjkSymbols: 465, .symbols: 340, .kana: 198])
                == .forLanguages([.chineseSimplified, .japanese]))
    }

    @Test func sampleLinesAddedOnlyWhenMissing() {
        let korean = Languages.language(.korean)
        #expect(Languages.withLanguageLine("Hello", korean) == "Hello\n" + korean.textSample)
        #expect(Languages.withLanguageLine("Hello\n", korean) == "Hello\n" + korean.textSample)
        #expect(Languages.withLanguageLine("", korean) == korean.textSample)
        #expect(Languages.withLanguageLine("안녕", korean) == "안녕")
        #expect(Languages.sampleHasLanguage("x 漢", Languages.language(.chineseSimplified)))
        #expect(!Languages.sampleHasLanguage("x", Languages.language(.chineseSimplified)))
        #expect(Languages.sampleHasLanguage("", Languages.language(.any)))
        #expect(Languages.withLanguageLine("x", Languages.language(.any)) == "x")
        #expect(Languages.withLanguageLine("Hello \r\n\n", korean) == "Hello \r\n" + korean.textSample)
    }

    @Test func samples() {
        #expect(Samples.presets.first { $0.id == "mixed" }?.text == Samples.defaultSample)
        #expect(Samples.presets.first { $0.id == "all" }?.text == Samples.oldDefaultSample)
        #expect(Samples.oldDefaultSample.contains("한글"))
        #expect(!Samples.defaultSample.contains("한"))
        #expect(Samples.presets.allSatisfy { !$0.text.isEmpty && !EnglishText.samplePresetLabel($0.id).isEmpty })
    }

    @Test func languageOfTallyPortsTallyLanguage() {
        #expect(Languages.languageOfTally(nil) == .any)
        #expect(Languages.languageOfTally([:]) == .any)
        #expect(Languages.languageOfTally([.han: 28195, .kana: 300]) == .chineseSimplified)
        #expect(Languages.languageOfTally([.symbols: 40]) == .symbols)
        #expect(Languages.languageOfTally([.other: 5]) == .any)
        #expect(Languages.languageOfTally([.symbols: 30000, .kana: 198]) == .symbols)
        #expect(Languages.roleTitle([.symbols: 30000, .kana: 198]) == .forLanguages([.japanese]))
    }

    @Test("ENGINE-2: language eligibility uses shapeable coverage and markers")
    func engine2CoverageThresholdsAndMarkersExcludeUnshaped() {
        let simplified = Languages.language(.chineseSimplified)
        let coverage = han3000.union(cps(simplified.markers))
        let face = fakeFace(coverage, unshaped: cps("这"))
        #expect(face.count(of: .han) >= 2500)
        #expect(!Languages.coversWell(face, simplified))
        let hebrew = Languages.language(.hebrew)
        let unshaped = ScriptGroup.codepoints(of: .hebrew)
        #expect(!Languages.coversWell(fakeFace(unshaped, unshaped: unshaped, shapesGroups: []), hebrew))
    }
}
