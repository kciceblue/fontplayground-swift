import Foundation

public struct PlatformPreferences: Sendable, Equatable {
    public enum Entry: Sendable, Hashable { case postscriptName(String), family(String) }
    public var entriesByLanguage: [LanguageID: [Entry]]
    public init(_ entriesByLanguage: [LanguageID: [Entry]]) { self.entriesByLanguage = entriesByLanguage }
    public static let none = PlatformPreferences([:])
    // CATALOG-11: platform choices break coverage ties; they never replace missing-glyph coverage.
    public static let macOS = PlatformPreferences([
        .chineseSimplified: [.family("PingFang SC")],
        .chineseTraditional: [.family("PingFang TC"), .family("PingFang HK")],
        .japanese: [.family("Hiragino Sans")],
        .korean: [.family("Apple SD Gothic Neo")],
        .arabic: ["Geeza Pro", "Damascus", "Noto Nastaliq Urdu", "Arial", "Times New Roman", "Tahoma"].map(
            Entry.family),
        .indic: ["Kohinoor Devanagari", "ITF Devanagari", "Devanagari Sangam MN", "Shree Devanagari 714"].map(
            Entry.family),
        .southeastAsian: ["Thonburi", "Sukhumvit Set", "Tahoma"].map(Entry.family),
        .hebrew: ["Arial Hebrew", "Arial", "Times New Roman", "Tahoma"].map(Entry.family),
        .latin: [.family("Helvetica Neue")], .greek: [.family("Helvetica Neue")],
        .cyrillic: [.family("Helvetica Neue")],
    ])

    public func entries(for languages: [LanguageID]) -> [Entry] {
        Self.unique(languages.flatMap { entriesByLanguage[$0] ?? [] })
    }

    public func appending(_ fallback: PlatformPreferences) -> PlatformPreferences {
        var result = entriesByLanguage
        for (language, entries) in fallback.entriesByLanguage {
            result[language] = (result[language] ?? []) + entries
        }
        return PlatformPreferences(result.mapValues(Self.unique))
    }

    public static func rank(of face: FaceRecord, in entries: [Entry]) -> Int {
        entries.firstIndex {
            switch $0 {
            case .postscriptName(let name): face.postscriptName == name
            case .family(let family): face.family == family
            }
        } ?? Int.max
    }

    static func unique(_ entries: [Entry]) -> [Entry] {
        var seen: Set<Entry> = []
        return entries.filter { seen.insert($0).inserted }
    }
}
