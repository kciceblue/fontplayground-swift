import FPCore
import Foundation
import Testing

struct PlannerConformanceTests {
    private struct Fixture: Decodable {
        struct Case: Decodable {
            struct Query: Decodable {
                let cp: UInt32
                let source: Int?
                init(from decoder: Decoder) throws {
                    var values = try decoder.unkeyedContainer()
                    cp = try values.decode(UInt32.self); source = try values.decode(Int?.self)
                }
            }
            let name: String
            let coverages: [CodepointSet]
            let rules: [ScriptGroup: Int?]
            let assignments: [CodepointSet]
            let queries: [Query]
        }
        let cases: [Case]
    }

    @Test func everyFixtureCaseMatches() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: Fixtures.url("planner"), includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
        #expect(!files.isEmpty)
        var count = 0
        for file in files {
            let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: file))
            for example in fixture.cases {
                count += 1
                let rules = example.rules.compactMapValues { $0 }
                let plan = Planner.plan(coverages: example.coverages, rules: rules)
                #expect(plan.assignments.map(\.ranges) == example.assignments.map(\.ranges), "\(example.name)")
                for query in example.queries {
                    #expect(
                        Planner.sourceOf(query.cp, coverages: example.coverages, rules: rules) == query.source,
                        "\(example.name)")
                    #expect(plan.source(of: query.cp) == query.source, "\(example.name)")
                }
            }
        }
        #expect(count >= 50)
        print("Planner conformance: \(count) cases from \(files.count) fixture files")
    }
}
