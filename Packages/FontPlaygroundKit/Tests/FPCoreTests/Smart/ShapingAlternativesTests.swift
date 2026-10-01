import FPCore
import Foundation
import Testing

struct ShapingAlternativesTests {
    @Test func offersOpenTypeFontsForAATOnlyArabic() {
        let coverage = CodepointSet(ranges: [0x600...0x6FF])
        let arial = fakeFace(coverage, path: "arial.ttf", family: "Arial", shapesGroups: [.arabic])
        let geeza = fakeFace(coverage, path: "geeza.ttf", family: "Geeza Pro", unshaped: coverage, shapesGroups: [])
        let noto = fakeFace(coverage, path: "noto.ttf", family: "Noto Nastaliq Urdu", shapesGroups: [.arabic])
        let damascus = fakeFace(coverage, path: "damascus.ttf", family: "Damascus", shapesGroups: [.arabic])
        let small = fakeFace(
            CodepointSet(ranges: [0x620...0x629]), path: "small.ttf", family: "Small", shapesGroups: [.arabic])
        let catalog = FaceCatalog([arial, geeza, noto, damascus, small])
        for preferences in [PlatformPreferences.macOS, .none] {
            #expect(
                Suggestions.shapingAlternatives(for: .arabic, near: geeza, in: catalog, preferences: preferences).map(
                    \.family) == ["Damascus", "Noto Nastaliq Urdu", "Arial"])
        }
        #expect(Suggestions.shapingAlternatives(for: .arabic, near: geeza, in: catalog, limit: 1) == [damascus])
        #expect(Suggestions.shapingAlternatives(for: .latin, near: nil, in: catalog).isEmpty)
        #expect(
            Suggestions.shapingAlternatives(for: .arabic, near: nil, in: catalog, excluding: [damascus.key]) == [
                noto, arial,
            ])
        #expect(Suggestions.shapingAlternatives(for: .arabic, near: nil, in: catalog, limit: 0).isEmpty)
    }

    @Test func tableMatchesEngineFixture() throws {
        struct Fixture: Decodable {
            struct Script: Decodable { var script: String; var group: ScriptGroup }
            struct Alternative: Decodable {
                var family: String; var postscriptName: String
                enum CodingKeys: String, CodingKey { case family, postscriptName = "postscript_name" }
            }
            var scripts: [Script]
            var alternatives: [String: [Alternative]]
        }
        let fixture = try Fixtures.load(Fixture.self, "shaping/ot_alternatives.json")
        let expected = fixture.scripts.map { row in
            ScriptAlternatives(
                script: row.script, group: row.group,
                alternatives: (fixture.alternatives[row.script] ?? []).map {
                    .init(family: $0.family, postscriptName: $0.postscriptName)
                })
        }
        #expect(Suggestions.otAlternatives == expected)
        #expect(Suggestions.otAlternatives.first { $0.script == "Tibt" }?.alternatives == [])
        #expect(
            Suggestions.alternativeEntries(for: .arabic).prefix(4) == [
                .postscriptName("Damascus"), .family("Damascus"), .postscriptName("NotoNastaliqUrdu"),
                .family("Noto Nastaliq Urdu"),
            ])
    }
}
