import Foundation

public enum Languages {
    public static let all: [Language] = [
        Language(
            id: .latin, groups: [.latin], minimums: [.init(group: .latin, count: 90)], markers: "",
            pickerSample: "Aa Bb Cc 0123", textSample: "The quick brown fox jumps over the lazy dog 0123456789"),
        Language(
            id: .chineseSimplified, groups: [.han], minimums: [.init(group: .han, count: 2500)], markers: "们这说国门来",
            pickerSample: "你好世界 永和九年 Aa 123", textSample: "你好，世界！欢迎使用字体游乐场。"),
        Language(
            id: .chineseTraditional, groups: [.han], minimums: [.init(group: .han, count: 2500)], markers: "們這說國門來",
            pickerSample: "你好世界 永和九年 Aa 123", textSample: "歡迎使用字體遊樂場。"),
        Language(
            id: .japanese, groups: [.kana],
            minimums: [.init(group: .kana, count: 150), .init(group: .han, count: 1000)], markers: "",
            pickerSample: "あいうえお 漢字 Aa", textSample: "こんにちは、カタカナとひらがな。"),
        Language(
            id: .korean, groups: [.hangul], minimums: [.init(group: .hangul, count: 2000)], markers: "",
            pickerSample: "한글 안녕 Aa", textSample: "안녕하세요, 세계!"),
        Language(
            id: .greek, groups: [.greek], minimums: [.init(group: .greek, count: 60)], markers: "",
            pickerSample: "Αα Ββ Γγ Δδ", textSample: "Γειά σου Κόσμε"),
        Language(
            id: .cyrillic, groups: [.cyrillic], minimums: [.init(group: .cyrillic, count: 60)], markers: "",
            pickerSample: "Аа Бб Вв Гг", textSample: "Привет, мир"),
        Language(
            id: .armenianGeorgian, groups: [.armenianGeorgian], minimums: [.init(group: .armenianGeorgian, count: 40)],
            markers: "", pickerSample: "Աա Բբ ა ბ", textSample: "Բարեւ աշխարհ გამარჯობა"),
        Language(
            id: .hebrew, groups: [.hebrew], minimums: [.init(group: .hebrew, count: 27)], markers: "",
            pickerSample: "שלום Aa", textSample: "שלום עולם"),
        Language(
            id: .arabic, groups: [.arabic], minimums: [.init(group: .arabic, count: 40)], markers: "",
            pickerSample: "مرحبا Aa", textSample: "مرحبا بالعالم"),
        Language(
            id: .indic, groups: [.indic], minimums: [.init(group: .indic, count: 60)], markers: "",
            pickerSample: "नमस्ते Aa", textSample: "नमस्ते दुनिया"),
        Language(
            id: .southeastAsian, groups: [.southeastAsian], minimums: [.init(group: .southeastAsian, count: 60)],
            markers: "", pickerSample: "สวัสดี Aa", textSample: "สวัสดีชาวโลก"),
        Language(
            id: .symbols, groups: [.symbols, .emoji], minimums: [.init(group: .symbols, count: 300)], markers: "",
            pickerSample: "→ ✓ ☺ ★ ①", textSample: "→ ✓ ☺ ★ ♫ ① ②"),
        Language(id: .any, groups: [], minimums: [], markers: "", pickerSample: "Aa 你好 あ 한", textSample: ""),
    ]

    public static let minShare = 0.01
    public static let maxPhrases = 5
    public static let maxRoleLanguages = 2
    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    private static let order = Dictionary(uniqueKeysWithValues: all.enumerated().map { ($1.id, $0) })

    public static func language(_ id: LanguageID) -> Language { byID[id]! }
    public static func language(rawID: String) -> Language? { LanguageID(rawValue: rawID).map(language) }

    public static func coversWell(_ face: FaceRecord, _ language: Language) -> Bool {
        language.minimums.allSatisfy { face.count(of: $0.group) >= $0.count }
            && language.markers.unicodeScalars.allSatisfy { face.plannableCoverage.contains($0) }
    }

    public static func languagesForMissing(_ scalars: [Unicode.Scalar]) -> [Language] {
        var tally: [LanguageID: Int] = [:]
        for scalar in scalars {
            if let id = ScriptGroup.of(scalar).language { tally[id, default: 0] += 1 }
        }
        return tally.keys.sorted {
            tally[$0] == tally[$1] ? order[$0]! < order[$1]! : tally[$0]! > tally[$1]!
        }.map(language)
    }

    private static func rankedGroups(_ tally: [ScriptGroup: Int]) -> [ScriptGroup] {
        tally.keys.filter { tally[$0]! > 0 }.sorted {
            tally[$0] == tally[$1] ? $0 < $1 : tally[$0]! > tally[$1]!
        }
    }

    public static func namedGroups(_ tally: [ScriptGroup: Int]) -> [ScriptGroup] {
        let total = tally.values.reduce(0, +)
        return rankedGroups(tally).enumerated().compactMap { index, group in
            let count = tally[group]!
            let minimum = group.language.flatMap { language($0).minimums.first { $0.group == group }?.count }
            let enoughForLanguage = minimum.map { count >= $0 } ?? false
            return index == 0 || Double(count) >= minShare * Double(total) || enoughForLanguage ? group : nil
        }
    }

    public static func roleTitle(_ tally: [ScriptGroup: Int]) -> RoleTitle {
        let groups = namedGroups(tally)
        guard !groups.isEmpty else { return .addsNothing }
        var seen: Set<LanguageID> = []
        let languages = groups.compactMap(\.language).filter { seen.insert($0).inserted }
        let named = languages.filter { $0 != .symbols }
        let result = named.isEmpty ? languages : named
        return result.isEmpty ? .fillsInTheRest : .forLanguages(result)
    }

    public static func sampleHasLanguage(_ text: String, _ language: Language) -> Bool {
        language.groups.isEmpty
            || TextUtil.visibleScalars(in: text).contains { language.groups.contains(ScriptGroup.of($0)) }
    }

    public static func withLanguageLine(_ text: String, _ language: Language) -> String {
        guard !language.textSample.isEmpty, !sampleHasLanguage(text, language) else { return text }
        var body = text.unicodeScalars
        while body.last == "\n" { body.removeLast() }
        return body.isEmpty ? language.textSample : String(body) + "\n" + language.textSample
    }

    public static func languageOfTally(_ tally: [ScriptGroup: Int]?) -> LanguageID {
        guard let tally, !tally.isEmpty else { return .any }
        let total = tally.values.reduce(0, +)
        let languages = rankedGroups(tally).enumerated().compactMap { index, group in
            index == 0 || Double(tally[group]!) >= minShare * Double(total) ? group.language : nil
        }
        return languages.first { $0 != .symbols } ?? languages.first ?? .any
    }
}
