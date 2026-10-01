import Foundation

/// Compact Unicode coverage; set operations work on ranges, never expanded glyph sets.
public struct CodepointSet: Hashable, Codable, Sendable {
    public private(set) var ranges: [ClosedRange<UInt32>]
    public let count: Int
    public static let empty = CodepointSet()
    public var isEmpty: Bool { ranges.isEmpty }

    public init() {
        self.init(normalized: [])
    }

    public init<S: Sequence>(_ codepoints: S) where S.Element == UInt32 {
        self.init(ranges: codepoints.map { $0...$0 })
    }

    public init(scalarsOf text: String) {
        self.init(text.unicodeScalars.map(\.value))
    }

    public init(ranges: [ClosedRange<UInt32>]) {
        var merged: [ClosedRange<UInt32>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            precondition(range.upperBound <= 0x10FFFF, "Coverage must contain Unicode code points")
            Self.append(range, to: &merged)
        }
        self.init(normalized: merged)
    }

    private init(normalized ranges: [ClosedRange<UInt32>]) {
        self.ranges = ranges
        count = ranges.reduce(0) { $0 + Int($1.upperBound - $1.lowerBound) + 1 }
    }

    private static func append(_ range: ClosedRange<UInt32>, to result: inout [ClosedRange<UInt32>]) {
        if let last = result.last, range.lowerBound <= last.upperBound + 1 {
            result[result.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
        } else {
            result.append(range)
        }
    }

    public func contains(_ cp: UInt32) -> Bool {
        var low = 0
        var high = ranges.count
        while low < high {
            let middle = low + (high - low) / 2
            if ranges[middle].lowerBound <= cp {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low > 0 && cp <= ranges[low - 1].upperBound
    }

    public func contains(_ scalar: Unicode.Scalar) -> Bool { contains(scalar.value) }

    public func isSuperset(of other: CodepointSet) -> Bool {
        var index = 0
        for range in other.ranges {
            while index < ranges.count && ranges[index].upperBound < range.lowerBound { index += 1 }
            guard index < ranges.count, ranges[index].lowerBound <= range.lowerBound,
                ranges[index].upperBound >= range.upperBound
            else { return false }
        }
        return true
    }

    public func intersection(_ other: CodepointSet) -> CodepointSet {
        var result: [ClosedRange<UInt32>] = []
        var left = 0
        var right = 0
        while left < ranges.count && right < other.ranges.count {
            let a = ranges[left]
            let b = other.ranges[right]
            let lower = max(a.lowerBound, b.lowerBound)
            let upper = min(a.upperBound, b.upperBound)
            if lower <= upper { result.append(lower...upper) }
            if a.upperBound < b.upperBound { left += 1 } else { right += 1 }
        }
        return CodepointSet(normalized: result)
    }

    public func intersectionCount(_ other: CodepointSet) -> Int { intersection(other).count }

    public func union(_ other: CodepointSet) -> CodepointSet {
        var result: [ClosedRange<UInt32>] = []
        var left = 0
        var right = 0
        while left < ranges.count || right < other.ranges.count {
            if right == other.ranges.count
                || (left < ranges.count && ranges[left].lowerBound <= other.ranges[right].lowerBound)
            {
                Self.append(ranges[left], to: &result)
                left += 1
            } else {
                Self.append(other.ranges[right], to: &result)
                right += 1
            }
        }
        return CodepointSet(normalized: result)
    }

    public func subtracting(_ other: CodepointSet) -> CodepointSet {
        var result: [ClosedRange<UInt32>] = []
        var index = 0
        for range in ranges {
            var cursor = range.lowerBound
            while index < other.ranges.count && other.ranges[index].upperBound < cursor { index += 1 }
            while index < other.ranges.count && other.ranges[index].lowerBound <= range.upperBound {
                let cut = other.ranges[index]
                if cut.lowerBound > cursor { result.append(cursor...(cut.lowerBound - 1)) }
                cursor = max(cursor, cut.upperBound + 1)
                if cursor > range.upperBound { break }
                index += 1
            }
            if cursor <= range.upperBound { result.append(cursor...range.upperBound) }
        }
        return CodepointSet(normalized: result)
    }

    /// Expand only for small text sets, diagnostics and tests.
    public var codepoints: [UInt32] { ranges.flatMap { Array($0) } }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let pairs: [[UInt32]]
        do {
            pairs = try container.decode([[UInt32]].self)
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Coverage requires integer pairs")
        }
        var ranges: [ClosedRange<UInt32>] = []
        for pair in pairs {
            guard pair.count == 2, pair[0] <= pair[1], pair[1] <= 0x10FFFF else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Invalid Unicode coverage range")
            }
            ranges.append(pair[0]...pair[1])
        }
        self.init(ranges: ranges)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(ranges.map { [$0.lowerBound, $0.upperBound] })
    }
}
