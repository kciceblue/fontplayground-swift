import Foundation

/// Reference English for the CLI and tests; the UI renders typed values through its String Catalog.
public enum EnglishText {
    public static func groupLabel(_ id: ScriptGroup) -> String {
        switch id {
        case .latin: "Latin"
        case .greek: "Greek"
        case .cyrillic: "Cyrillic"
        case .armenianGeorgian: "Armenian & Georgian"
        case .hebrew: "Hebrew"
        case .arabic: "Arabic"
        case .indic: "Indic"
        case .southeastAsian: "Thai, Lao, Khmer, Myanmar"
        case .hangul: "Hangul"
        case .kana: "Kana"
        case .han: "Han"
        case .cjkSymbols: "CJK symbols & fullwidth"
        case .symbols: "Punctuation & symbols"
        case .emoji: "Emoji & pictographs"
        case .other: "Everything else"
        }
    }

    public static func languageLabel(_ id: LanguageID) -> String {
        switch id {
        case .latin: "Letters (Latin)"
        case .chineseSimplified: "Chinese (Simplified)"
        case .chineseTraditional: "Chinese (Traditional)"
        case .japanese: "Japanese"
        case .korean: "Korean"
        case .greek: "Greek"
        case .cyrillic: "Cyrillic"
        case .armenianGeorgian: "Armenian & Georgian"
        case .hebrew: "Hebrew"
        case .arabic: "Arabic"
        case .indic: "Hindi & Indic"
        case .southeastAsian: "Thai, Lao, Khmer, Myanmar"
        case .symbols: "Symbols & emoji"
        case .any: "Any language"
        }
    }

    public static func languageShortLabel(_ id: LanguageID) -> String {
        switch id {
        case .latin: "Letters"
        case .chineseSimplified: "Chinese"
        case .chineseTraditional: "Chinese"
        case .indic: "Indic"
        case .southeastAsian: "Thai & SE Asian"
        default: languageLabel(id)
        }
    }

    public static func groupPhrase(_ id: ScriptGroup) -> String {
        switch id {
        case .latin: "letters, numbers and punctuation"
        case .han: "Chinese characters"
        case .kana: "Japanese kana"
        case .hangul: "Korean Hangul"
        case .cjkSymbols: "CJK punctuation"
        case .symbols: "symbols"
        case .emoji: "emoji"
        case .indic: "Indic scripts"
        case .southeastAsian: "Thai and Southeast Asian scripts"
        case .other: "other characters"
        default: groupLabel(id)
        }
    }

    public static func samplePresetLabel(_ id: String) -> String {
        switch id {
        case "mixed": "Mixed (English, Chinese, Japanese)"
        case "english": "English"
        case "chinese_s": "Chinese (Simplified)"
        case "chinese_t": "Chinese (Traditional)"
        case "japanese": "Japanese"
        case "korean": "Korean"
        case "all": "All languages"
        default: id
        }
    }

    public static let drawsNothing = "Draws nothing — the fonts above already cover everything it has."

    public static func joinLabels(_ ids: [LanguageID], limit: Int = 2, joiner: String = " and ") -> String {
        var seen: Set<String> = []
        let labels = ids.map(languageShortLabel).filter { seen.insert($0).inserted }
        let count = limit < 0 ? max(0, labels.count + limit) : min(limit, labels.count)
        return labels.prefix(count).joined(separator: joiner)
    }

    public static func draws(_ groups: [ScriptGroup]) -> String {
        guard !groups.isEmpty else { return drawsNothing }
        if groups.contains(.latin) {
            let rest = groups.filter { $0 != .latin }.map(groupPhrase)
            let head = groupPhrase(.latin)
            guard !rest.isEmpty else { return "Draws \(head)." }
            let shown =
                Array(rest.prefix(Languages.maxPhrases - 1)) + (rest.count >= Languages.maxPhrases ? ["more"] : [])
            return "Draws \(head), plus \(joinAnd(shown))."
        }
        let shown =
            groups.prefix(Languages.maxPhrases).map(groupPhrase) + (groups.count > Languages.maxPhrases ? ["more"] : [])
        return "Draws \(joinAnd(shown))."
    }

    public static func roleTitle(_ title: RoleTitle) -> String {
        switch title {
        case .addsNothing: "ADDS NOTHING"
        case .fillsInTheRest: "FILLS IN THE REST"
        case .forLanguages(let ids): "FOR " + joinLabels(ids, joiner: " & ").uppercased()
        }
    }

    private static func joinAnd(_ parts: [String]) -> String {
        guard let last = parts.last else { return "" }
        return parts.count == 1 ? last : parts.dropLast().joined(separator: ", ") + " and " + last
    }
}
