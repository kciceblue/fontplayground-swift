import Foundation

public struct MixFont: Sendable, Equatable {
    public let face: FaceRecord
    public let weight: Int?
    public let scale: Double
    public let isAvailable: Bool

    public init(face: FaceRecord, weight: Int? = nil, scale: Double = 1.0, isAvailable: Bool = true) {
        self.face = face; self.weight = weight; self.scale = scale; self.isAvailable = isAvailable
    }

    // ENGINE-2: preview, missing characters and planning share the engine's shapeable coverage.
    public var effectiveCoverage: CodepointSet { isAvailable ? face.plannableCoverage : .empty }
}

public struct MixRun: Sendable, Equatable {
    public let utf16Range: Range<Int>
    public let scalarRange: Range<Int>
    public let source: Int?

    public init(utf16Range: Range<Int>, scalarRange: Range<Int>, source: Int?) {
        self.utf16Range = utf16Range; self.scalarRange = scalarRange; self.source = source
    }
}

public struct Mix: Sendable, Equatable {
    public static let empty = Mix()
    public let fonts: [MixFont]
    public let rules: [ScriptGroup: Int]
    public let baseIndex: Int
    private let coverages: [CodepointSet]

    public init(fonts: [MixFont] = [], rules: [ScriptGroup: Int] = [:], baseIndex: Int = 0) {
        self.fonts = fonts; self.rules = rules; self.baseIndex = baseIndex
        coverages = fonts.map(\.effectiveCoverage)
    }

    public static func == (lhs: Mix, rhs: Mix) -> Bool {
        lhs.fonts == rhs.fonts && lhs.rules == rhs.rules && lhs.baseIndex == rhs.baseIndex
    }

    public var keys: [FaceKey] { fonts.map { $0.face.key } }
    public func source(of cp: UInt32) -> Int? { Planner.sourceOf(cp, coverages: coverages, rules: rules) }
    public func source(of scalar: Unicode.Scalar) -> Int? { source(of: scalar.value) }
    public func plan() -> Plan { Planner.plan(coverages: coverages, rules: rules) }

    public func runs(in text: String) -> [MixRun] {
        var result: [MixRun] = []
        var utf16Offset = 0
        var scalarOffset = 0
        var runUTF16Start = 0
        var runScalarStart = 0
        var runSource: Int?
        for scalar in text.unicodeScalars {
            let rawSource = source(of: scalar)
            // Unmapped joiners and controls stay with the preceding font, including a preceding missing run.
            let source = rawSource == nil && TextUtil.isIgnorable(scalar) ? runSource : rawSource
            if scalarOffset > 0 && source != runSource {
                result.append(
                    MixRun(
                        utf16Range: runUTF16Start..<utf16Offset, scalarRange: runScalarStart..<scalarOffset,
                        source: runSource))
                runUTF16Start = utf16Offset; runScalarStart = scalarOffset
            }
            runSource = source
            utf16Offset += scalar.value > 0xFFFF ? 2 : 1
            scalarOffset += 1
        }
        if scalarOffset > 0 {
            result.append(
                MixRun(
                    utf16Range: runUTF16Start..<utf16Offset, scalarRange: runScalarStart..<scalarOffset,
                    source: runSource))
        }
        return result
    }

    public func missingCharacters(in text: String) -> [Unicode.Scalar] {
        TextUtil.visibleScalars(in: text).filter { source(of: $0) == nil }
    }
}
