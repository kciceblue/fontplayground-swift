import FPCore
import Foundation
import Testing

struct TextUtilTests {
    @Test func ignorableRangesAndCategories() {
        for scalar in "\u{200D}\u{FE0F}\u{200B}\u{00AD}\u{202A}\n\t\u{3000}".unicodeScalars {
            #expect(TextUtil.isIgnorable(scalar))
        }
        for scalar in "a漢😀".unicodeScalars { #expect(!TextUtil.isIgnorable(scalar)) }
    }

    @Test func visibleScalarsAreSortedUniqueCodePoints() {
        #expect(TextUtil.visibleScalars(in: "a b漢 →→Ω").map(\.value) == [97, 98, 0x3A9, 0x2192, 0x6F22])
        #expect(TextUtil.visibleScalars(in: "e\u{301}").map(\.value) == [0x65, 0x301])
        #expect(TextUtil.visibleScalars(in: "👩‍💻").map(\.value) == [0x1F469, 0x1F4BB])
    }

    @Test func matchesPythonForSharedUnicodeVersion() throws {
        struct Fixture: Decodable {
            let unicodeVersion: String
            let ignorable: CodepointSet
            private enum CodingKeys: String, CodingKey { case unicodeVersion = "unicode_version", ignorable }
        }
        let fixture = try Fixtures.load(Fixture.self, "text/ignorable.json")
        let parts = fixture.unicodeVersion.split(separator: ".").map { Int($0)! }
        var newer = 0
        var unexplained: [UInt32] = []
        let allowList: Set<UInt32> = []
        for cp in UInt32(0)...0x10FFFF {
            guard let scalar = Unicode.Scalar(cp) else { continue }
            if let age = scalar.properties.age,
                Int(age.major) > parts[0] || (Int(age.major) == parts[0] && Int(age.minor) > parts[1])
            {
                newer += 1
                continue
            }
            if TextUtil.isIgnorable(scalar) != fixture.ignorable.contains(cp), !allowList.contains(cp) {
                unexplained.append(cp)
            }
        }
        print("Unicode conformance: \(newer) newer code points excluded; \(unexplained.count) unexplained mismatches")
        #expect(allowList.isEmpty)
        #expect(unexplained.isEmpty, "Unexplained code points: \(unexplained.prefix(20))")
    }
}
