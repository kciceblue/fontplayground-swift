import Foundation
import Testing

@testable import FPMacServices

struct NameTableTests {
    private struct Record {
        var platform: UInt16 = 3
        var encoding: UInt16 = 1
        var language: UInt16 = 0x409
        var name: UInt16 = 1
        var bytes: Data
        var offset: UInt16? = nil
    }
    private func table(_ records: [Record], format: UInt16 = 0, count: UInt16? = nil) -> Data {
        func word(_ value: UInt16) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 255)] }
        let base = 6 + records.count * 12
        var data = Data(word(format) + word(count ?? UInt16(records.count)) + word(UInt16(base)))
        var strings = Data()
        for record in records {
            for value in [
                record.platform, record.encoding, record.language, record.name,
                UInt16(record.bytes.count), record.offset ?? UInt16(strings.count),
            ] { data.append(contentsOf: word(value)) }
            strings.append(record.bytes)
        }
        data.append(strings)
        return data
    }
    @Test func parsesPlatformsAndEncodings() throws {
        let fixture = try InstallFixture()
        defer { fixture.cleanup() }
        let family = "FP Local " + TestEnv.tag()
        let url = try FixtureFonts.build(
            [
                .init(
                    file: "Local.ttf", family: family,
                    localizedFamily: ["0x0804": "测试字体"])
            ], in: fixture.root)[0]
        let parsed = try #require(NameTable.tables(forFontAt: url).first)
        #expect(Set(parsed.strings(nameID: 1)).isSuperset(of: [family, "测试字体"]))
        #expect(parsed.preferred(nameID: 1) == family)
        #expect(parsed.preferred(nameID: 4) == family + " Regular")
        let bytes = table(
            [
                .init(
                    platform: 1, encoding: 25, language: 33,
                    bytes: Data([0xBB, 0xAA, 0xCE, 0xC4, 0xCB, 0xCE, 0xCC, 0xE5])),
                .init(platform: 1, encoding: 0, language: 0, bytes: Data([0x43, 0x61, 0x66, 0x8E])),
                .init(bytes: Data("English".utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 255)] })),
                .init(bytes: Data([0, 88]), offset: 0xFFFF),
            ], count: 100)
        let malformedRecords = try NameTable(data: bytes)
        #expect(malformedRecords.strings(nameID: 1) == ["华文宋体", "Café", "English"])
        #expect(malformedRecords.preferred(nameID: 1) == "English")
    }

    @Test func rejectsMalformedHeadersAndSkipsUnsupportedRecords() throws {
        for data in [Data(), Data([0, 0, 0, 0, 0]), Data([0, 2, 0, 0, 0, 6]), Data([0, 0, 0, 0, 0, 7])] {
            #expect(throws: NameTableError.malformed) { try NameTable(data: data) }
        }
        let records: [Record] = [
            .init(platform: 2, bytes: Data([65])),
            .init(platform: 1, encoding: 99, bytes: Data([65])),
            .init(bytes: Data()),
            .init(platform: 0, encoding: 4, bytes: Data([0, 65])),
            .init(encoding: 10, bytes: Data([0, 65])),
        ]
        let parsed = try NameTable(data: table(records, format: 1))
        #expect(parsed.records.count == 2)
        #expect(parsed.strings(nameID: 1) == ["A"])
        #expect(parsed.preferred(nameID: 99) == nil)
    }
}
