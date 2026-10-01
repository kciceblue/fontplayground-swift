import Foundation
import Testing

@testable import FPCore

struct CodepointSetTests {
    @Test func normalisesUnsortedOverlappingInput() {
        let coverage = CodepointSet(ranges: [5...9, 1...3, 4...4, 20...20])
        #expect(coverage.ranges == [1...9, 20...20])
        #expect(coverage.count == 10)
        #expect(CodepointSet([UInt32(2), 2, 1]).codepoints == [1, 2])
        #expect(CodepointSet.empty.isEmpty && CodepointSet.empty.count == 0)
    }

    @Test func containsUsesBinarySearch() {
        let coverage = CodepointSet(ranges: [1...9, 20...20, 0x10FFFD...0x10FFFF])
        for value: UInt32 in [1, 5, 9, 20, 0x10FFFD, 0x10FFFF] { #expect(coverage.contains(value)) }
        for value: UInt32 in [0, 10, 19, 21, 0x10FFFC, 0x110000, UInt32.max] { #expect(!coverage.contains(value)) }
        #expect(!CodepointSet.empty.contains(UInt32(0)))
        #expect(CodepointSet(scalarsOf: "漢").contains("漢".unicodeScalars.first!))
    }

    @Test func setAlgebraMatchesNaiveSets() {
        var seed: UInt64 = 0xCAFE_F00D
        func next() -> UInt32 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return UInt32(seed >> 32) % 300
        }
        for _ in 0..<200 {
            let a = CodepointSet((0..<Int(next() % 70)).map { _ in next() })
            let b = CodepointSet((0..<Int(next() % 70)).map { _ in next() })
            let left = Set(a.codepoints)
            let right = Set(b.codepoints)
            #expect(Set(a.intersection(b).codepoints) == left.intersection(right))
            #expect(a.intersectionCount(b) == left.intersection(right).count)
            #expect(Set(a.union(b).codepoints) == left.union(right))
            #expect(Set(a.subtracting(b).codepoints) == left.subtracting(right))
            #expect(a.isSuperset(of: b) == left.isSuperset(of: right))
        }
        let all = CodepointSet(ranges: [0...0x10FFFF])
        let ends = CodepointSet(ranges: [0...0, 0x10FFFF...0x10FFFF])
        #expect(all.subtracting(ends).ranges == [1...0x10FFFE])
        #expect(all.subtracting(all).isEmpty)
        #expect(
            CodepointSet(ranges: [1...3, 5...8]).subtracting(CodepointSet(ranges: [2...6])).ranges == [1...1, 7...8])
    }

    @Test(arguments: ["[[3,1]]", "[[0,1114112]]", "[[1]]", "[[1,2,3]]", "[[-1,2]]", "[[1.5,2]]", "[[\"a\",2]]"])
    func rejectsInvalidJSONRanges(_ json: String) {
        do {
            _ = try JSONDecoder().decode(CodepointSet.self, from: Data(json.utf8))
            Issue.record("Invalid coverage decoded: \(json)")
        } catch DecodingError.dataCorrupted {
            // The range wire format rejects malformed entries as data corruption.
        } catch {
            Issue.record("Wrong decoding error: \(error)")
        }
    }

    @Test func jsonRoundTrip() throws {
        let value = CodepointSet(ranges: [2...4, 0xD800...0xDFFF, 0x10FFFF...0x10FFFF])
        let bytes = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(CodepointSet.self, from: bytes) == value)
        #expect(try JSONDecoder().decode(CodepointSet.self, from: Data("[[5,9],[1,4]]".utf8)).ranges == [1...9])
    }
}
