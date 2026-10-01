import Foundation
import Testing

@testable import FPCore

struct ScriptGroupTableTests {
    private struct Fixture: Decodable {
        struct Run: Decodable {
            let start: UInt32
            let end: UInt32
            let group: String
            init(from decoder: Decoder) throws {
                var row = try decoder.unkeyedContainer()
                start = try row.decode(UInt32.self); end = try row.decode(UInt32.self);
                group = try row.decode(String.self)
            }
        }
        let groups: [String]
        let ranges: [Run]
    }

    @Test func generatedTableMatchesFixture() throws {
        let fixture = try Fixtures.load(Fixture.self, "scripts/group-ranges.json")
        #expect(fixture.groups == ScriptGroup.allCases.map(\.rawValue))
        #expect(fixture.ranges.map(\.start) == ScriptGroupTable.starts)
        #expect(
            fixture.ranges.map { fixture.groups.firstIndex(of: $0.group).map(UInt8.init) }
                == ScriptGroupTable.groups.map(Optional.some))
        for range in fixture.ranges {
            #expect(ScriptGroup.of(range.start).rawValue == range.group)
            #expect(ScriptGroup.of(range.end).rawValue == range.group)
        }
    }

    @Test func tableCoversEveryCodePoint() throws {
        let fixture = try Fixtures.load(Fixture.self, "scripts/group-ranges.json")
        #expect(ScriptGroupTable.starts.first == 0)
        #expect(zip(ScriptGroupTable.starts, ScriptGroupTable.starts.dropFirst()).allSatisfy { $0 < $1 })
        #expect(fixture.ranges.last?.end == 0x10FFFF)
        #expect(ScriptGroup.of(0x110000) == .other)
        #expect(ScriptGroup.of(UInt32.max) == .other)
        var failures = 0
        for range in fixture.ranges {
            for cp in range.start...range.end where ScriptGroup.of(cp).rawValue != range.group { failures += 1 }
        }
        #expect(failures == 0)
    }
}
