import Foundation
import Testing

@testable import FPCore

struct ScriptGroupTests {
    @Test(arguments: [
        ("a", ScriptGroup.latin), ("1", .latin), (",", .latin), ("é", .latin), ("Ω", .greek), ("д", .cyrillic),
        ("ب", .arabic), ("א", .hebrew), ("न", .indic), ("ก", .southeastAsian), ("한", .hangul), ("あ", .kana),
        ("漢", .han), ("，", .cjkSymbols), ("、", .cjkSymbols), ("→", .symbols), ("☺", .symbols), ("€", .symbols),
        ("😀", .emoji), ("\u{1200}", .other),
    ])
    func groupOfMatchesReferenceCases(arguments: (String, ScriptGroup)) {
        #expect(ScriptGroup.of(arguments.0.unicodeScalars.first!) == arguments.1)
    }

    @Test func groupsAreOrderedAndLabelled() {
        #expect(ScriptGroup.allCases.count == 15)
        #expect(ScriptGroup.allCases.first == .latin)
        #expect(ScriptGroup.allCases.last == .other)
        #expect(ScriptGroup.allCases.reversed().sorted() == ScriptGroup.allCases)
        #expect(
            ScriptGroup.allCases.map(EnglishText.groupLabel) == [
                "Latin", "Greek", "Cyrillic", "Armenian & Georgian", "Hebrew", "Arabic", "Indic",
                "Thai, Lao, Khmer, Myanmar",
                "Hangul", "Kana", "Han", "CJK symbols & fullwidth", "Punctuation & symbols", "Emoji & pictographs",
                "Everything else",
            ])
    }

    @Test func groupsCoveredInGroupOrder() {
        #expect(ScriptGroup.groupsCovered(cps("漢a，")) == [.latin, .han, .cjkSymbols])
        #expect(ScriptGroup.groupsCovered(.empty).isEmpty)
    }

    @Test func complexGroupsMatchTheEngine() throws {
        struct Fixture: Decodable {
            struct Script: Decodable { let group: String }
            let complexGroups: [String]
            let scripts: [Script]
            private enum CodingKeys: String, CodingKey { case complexGroups = "complex_groups", scripts }
        }
        let fixture = try Fixtures.load(Fixture.self, "shaping/ot_alternatives.json")
        #expect(ScriptGroup.allCases.filter(\.needsShaping).map(\.rawValue) == fixture.complexGroups)
        #expect(fixture.scripts.allSatisfy { ScriptGroup(rawValue: $0.group) != nil })
    }

    @Test func codepointsPartitionTheTable() {
        let sets = ScriptGroup.allCases.map(ScriptGroup.codepoints)
        #expect(sets.reduce(0) { $0 + $1.count } == 0x110000)
        for left in sets.indices {
            for right in sets.indices where left < right { #expect(sets[left].intersection(sets[right]).isEmpty) }
        }
        #expect(ScriptGroup.counts(in: cps("ab漢，")) == [.latin: 2, .han: 1, .cjkSymbols: 1])
    }
}
