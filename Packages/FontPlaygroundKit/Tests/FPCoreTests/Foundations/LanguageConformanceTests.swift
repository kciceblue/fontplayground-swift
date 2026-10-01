import FPCore
import Foundation
import Testing

struct LanguageConformanceTests {
    private struct Fixture: Decodable {
        struct Entry: Decodable {
            struct Minimum: Decodable {
                let group: ScriptGroup
                let count: Int
                init(from decoder: Decoder) throws {
                    var values = try decoder.unkeyedContainer()
                    group = try values.decode(ScriptGroup.self); count = try values.decode(Int.self)
                }
            }
            let id: LanguageID
            let label: String
            let shortLabel: String
            let groups: [ScriptGroup]
            let minCounts: [Minimum]
            let markers: String
            let pickerSample: String
            let textSample: String
            private enum CodingKeys: String, CodingKey {
                case id, label, groups, markers
                case shortLabel = "short_label", minCounts = "min_counts", pickerSample = "picker_sample", textSample =
                    "text_sample"
            }
        }
        struct Constants: Decodable {
            let minShare: Double
            let maxPhrases: Int
            let maxRoleLanguages: Int
            private enum CodingKeys: String, CodingKey {
                case minShare = "min_share", maxPhrases = "max_phrases", maxRoleLanguages = "max_role_languages"
            }
        }
        let languages: [Entry]
        let groupLanguage: [ScriptGroup: LanguageID]
        let groupPhrases: [ScriptGroup: String]
        let groupLabels: [ScriptGroup: String]
        let defaultSample: String
        let oldDefaultSample: String
        let samples: [[String]]
        let constants: Constants
        private enum CodingKeys: String, CodingKey {
            case languages, samples, constants
            case groupLanguage = "group_language", groupPhrases = "group_phrases", groupLabels = "group_labels"
            case defaultSample = "default_sample", oldDefaultSample = "old_default_sample"
        }
    }

    @Test func tableMatchesFixture() throws {
        let fixture = try Fixtures.load(Fixture.self, "languages/languages.json")
        #expect(Languages.all.map(\.id) == fixture.languages.map(\.id))
        for (actual, expected) in zip(Languages.all, fixture.languages) {
            #expect(actual.groups == expected.groups)
            #expect(actual.minimums.map(\.group) == expected.minCounts.map(\.group))
            #expect(actual.minimums.map(\.count) == expected.minCounts.map(\.count))
            #expect(Array(actual.markers.utf8) == Array(expected.markers.utf8))
            #expect(Array(actual.pickerSample.utf8) == Array(expected.pickerSample.utf8))
            #expect(Array(actual.textSample.utf8) == Array(expected.textSample.utf8))
            #expect(Array(EnglishText.languageLabel(actual.id).utf8) == Array(expected.label.utf8))
            #expect(Array(EnglishText.languageShortLabel(actual.id).utf8) == Array(expected.shortLabel.utf8))
        }
        for group in ScriptGroup.allCases {
            #expect(group.language == fixture.groupLanguage[group])
            #expect(EnglishText.groupLabel(group) == fixture.groupLabels[group])
            #expect(EnglishText.groupPhrase(group) == (fixture.groupPhrases[group] ?? fixture.groupLabels[group]))
        }
        #expect(Array(Samples.defaultSample.utf8) == Array(fixture.defaultSample.utf8))
        #expect(Array(Samples.oldDefaultSample.utf8) == Array(fixture.oldDefaultSample.utf8))
        #expect(Samples.presets.count == fixture.samples.count)
        for (actual, expected) in zip(Samples.presets, fixture.samples) {
            #expect(actual.id == expected[0])
            #expect(Array(EnglishText.samplePresetLabel(actual.id).utf8) == Array(expected[1].utf8))
            #expect(Array(actual.text.utf8) == Array(expected[2].utf8))
        }
        #expect(Languages.minShare == fixture.constants.minShare)
        #expect(Languages.maxPhrases == fixture.constants.maxPhrases)
        #expect(Languages.maxRoleLanguages == fixture.constants.maxRoleLanguages)
    }

    @Test func coverageBoundariesMatchFixture() throws {
        struct Fixture: Decodable {
            struct Row: Decodable {
                let name: String
                let coverage: CodepointSet
                let groupCounts: [ScriptGroup: Int]
                let language: LanguageID
                let expected: Bool
                private enum CodingKeys: String, CodingKey {
                    case name, coverage, language, expected
                    case groupCounts = "group_counts"
                }
            }
            let cases: [Row]
        }
        let fixture = try Fixtures.load(Fixture.self, "languages/covers-well.json")
        for row in fixture.cases {
            let face = fakeFace(row.coverage)
            #expect(ScriptGroup.allCases.allSatisfy { face.count(of: $0) == row.groupCounts[$0, default: 0] })
            #expect(Languages.coversWell(face, Languages.language(row.language)) == row.expected, "\(row.name)")
        }
    }

    @Test func phrasesMatchFixture() throws {
        struct Fixture: Decodable {
            struct Missing: Decodable { let codepoints: [UInt32]; let expected: [LanguageID] }
            struct Joined: Decodable {
                let languages: [LanguageID]; let limit: Int; let joiner: String; let expected: String
            }
            struct Tally: Decodable { let tally: [ScriptGroup: Int]; let expected: String }
            struct HasLanguage: Decodable { let text: String; let language: LanguageID; let expected: Bool }
            struct AddedLine: Decodable { let text: String; let language: LanguageID; let expected: String }
            let languagesForMissing: [Missing]
            let joinLabels: [Joined]
            let drawsText: [Tally]
            let roleTitle: [Tally]
            let sampleHasLanguage: [HasLanguage]
            let withLanguageLine: [AddedLine]
            private enum CodingKeys: String, CodingKey {
                case languagesForMissing = "languages_for_missing", joinLabels = "join_labels", drawsText = "draws_text"
                case roleTitle = "role_title", sampleHasLanguage = "sample_has_language", withLanguageLine =
                    "with_language_line"
            }
        }
        let fixture = try Fixtures.load(Fixture.self, "languages/phrases.json")
        for row in fixture.languagesForMissing {
            #expect(
                Languages.languagesForMissing(row.codepoints.compactMap(Unicode.Scalar.init)).map(\.id) == row.expected)
        }
        for row in fixture.joinLabels {
            #expect(EnglishText.joinLabels(row.languages, limit: row.limit, joiner: row.joiner) == row.expected)
        }
        for row in fixture.drawsText { #expect(EnglishText.draws(Languages.namedGroups(row.tally)) == row.expected) }
        for row in fixture.roleTitle { #expect(EnglishText.roleTitle(Languages.roleTitle(row.tally)) == row.expected) }
        for row in fixture.sampleHasLanguage {
            #expect(Languages.sampleHasLanguage(row.text, Languages.language(row.language)) == row.expected)
        }
        for row in fixture.withLanguageLine {
            #expect(
                Array(Languages.withLanguageLine(row.text, Languages.language(row.language)).utf8)
                    == Array(row.expected.utf8))
        }
    }
}
