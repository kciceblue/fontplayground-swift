import Foundation

public enum ScriptGroup: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable, Comparable {
    case latin, greek, cyrillic, armenianGeorgian = "armenian_georgian", hebrew, arabic, indic
    case southeastAsian = "southeast_asian", hangul, kana, han, cjkSymbols = "cjk_symbols", symbols, emoji, other

    private static let order = Dictionary(uniqueKeysWithValues: allCases.enumerated().map { ($1, $0) })
    private static let tableGroups = ScriptGroupTable.groups.map { allCases[Int($0)] }
    private static let coverage: [ScriptGroup: CodepointSet] = {
        var ranges: [ScriptGroup: [ClosedRange<UInt32>]] = [:]
        for index in ScriptGroupTable.starts.indices {
            let end = index + 1 < ScriptGroupTable.starts.count ? ScriptGroupTable.starts[index + 1] - 1 : 0x10FFFF
            ranges[tableGroups[index], default: []].append(ScriptGroupTable.starts[index]...end)
        }
        return ranges.mapValues { CodepointSet(ranges: $0) }
    }()

    public static func < (lhs: ScriptGroup, rhs: ScriptGroup) -> Bool { order[lhs]! < order[rhs]! }

    public static func of(_ cp: UInt32) -> ScriptGroup {
        guard cp <= 0x10FFFF else { return .other }
        var low = 0
        var high = ScriptGroupTable.starts.count
        while low < high {
            let middle = low + (high - low) / 2
            if ScriptGroupTable.starts[middle] <= cp { low = middle + 1 } else { high = middle }
        }
        return tableGroups[low - 1]
    }

    public static func of(_ scalar: Unicode.Scalar) -> ScriptGroup { of(scalar.value) }

    public static func groupsCovered(_ set: CodepointSet) -> [ScriptGroup] {
        allCases.filter { set.intersectionCount(codepoints(of: $0)) > 0 }
    }

    public static func codepoints(of group: ScriptGroup) -> CodepointSet { coverage[group] ?? .empty }

    public static func counts(in set: CodepointSet) -> [ScriptGroup: Int] {
        var result: [ScriptGroup: Int] = [:]
        for group in allCases {
            let count = set.intersectionCount(codepoints(of: group))
            if count > 0 { result[group] = count }
        }
        return result
    }

    // ENGINE-2: the engine determines per-face support within these complex groups.
    public var needsShaping: Bool {
        switch self {
        case .hebrew, .arabic, .indic, .southeastAsian: true
        default: false
        }
    }

    public var language: LanguageID? {
        switch self {
        case .latin: .latin
        case .greek: .greek
        case .cyrillic: .cyrillic
        case .armenianGeorgian: .armenianGeorgian
        case .hebrew: .hebrew
        case .arabic: .arabic
        case .indic: .indic
        case .southeastAsian: .southeastAsian
        case .hangul: .korean
        case .kana: .japanese
        case .han, .cjkSymbols: .chineseSimplified
        case .symbols, .emoji: .symbols
        case .other: nil
        }
    }
}
