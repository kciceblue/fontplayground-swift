import Foundation

public struct ShapingAlternative: Sendable, Hashable {
    public let family: String
    public let postscriptName: String
    public init(family: String, postscriptName: String) { self.family = family; self.postscriptName = postscriptName }
}

public struct ScriptAlternatives: Sendable, Hashable {
    public let script: String
    public let group: ScriptGroup
    public let alternatives: [ShapingAlternative]
    public init(script: String, group: ScriptGroup, alternatives: [ShapingAlternative]) {
        self.script = script; self.group = group; self.alternatives = alternatives
    }
}

extension Suggestions {
    // ENGINE-2: checked against the engine's OT_ALTERNATIVES fixture, never resolved by a system name lookup.
    public static let otAlternatives: [ScriptAlternatives] = [
        script(
            "Arab", .arabic,
            [
                ("Damascus", "Damascus"), ("Noto Nastaliq Urdu", "NotoNastaliqUrdu"), ("Arial", "ArialMT"),
                ("Times New Roman", "TimesNewRomanPSMT"), ("Tahoma", "Tahoma"), ("Courier New", "CourierNewPSMT"),
                ("Microsoft Sans Serif", "MicrosoftSansSerif"),
            ]),
        script(
            "Hebr", .hebrew,
            [
                ("Arial Hebrew", "ArialHebrew"), ("Arial Hebrew Scholar", "ArialHebrewScholar"), ("Arial", "ArialMT"),
                ("Times New Roman", "TimesNewRomanPSMT"), ("Tahoma", "Tahoma"),
            ]),
        script(
            "Deva", .indic,
            [
                ("Kohinoor Devanagari", "KohinoorDevanagari-Regular"), ("ITF Devanagari", "ITFDevanagari-Book"),
                ("Devanagari Sangam MN", "DevanagariSangamMN"), ("Shree Devanagari 714", "ShreeDev0714"),
            ]),
        script(
            "Beng", .indic,
            [
                ("Kohinoor Bangla", "KohinoorBangla-Regular"), ("Bangla Sangam MN", "BanglaSangamMN"),
                ("Bangla MN", "BanglaMN"), ("Tiro Bangla", "TiroBangla"),
            ]),
        script("Guru", .indic, [("Gurmukhi Sangam MN", "GurmukhiSangamMN"), ("Gurmukhi MN", "GurmukhiMN")]),
        script(
            "Gujr", .indic,
            [("Kohinoor Gujarati", "KohinoorGujarati-Regular"), ("Gujarati Sangam MN", "GujaratiSangamMN")]),
        script(
            "Orya", .indic,
            [("Oriya Sangam MN", "OriyaSangamMN"), ("Oriya MN", "OriyaMN"), ("Noto Sans Oriya", "NotoSansOriya")]),
        script(
            "Taml", .indic,
            [("Tamil MN", "TamilMN"), ("InaiMathi", "InaiMathi"), ("Tamil Sangam MN", "TamilSangamMN-Medium")]),
        script(
            "Telu", .indic,
            [
                ("Kohinoor Telugu", "KohinoorTelugu-Regular"), ("Telugu Sangam MN", "TeluguSangamMN"),
                ("Telugu MN", "TeluguMN"),
            ]),
        script(
            "Knda", .indic,
            [
                ("Kannada Sangam MN", "KannadaSangamMN"), ("Kannada MN", "KannadaMN"),
                ("Noto Sans Kannada", "NotoSansKannada-Regular"),
            ]),
        script(
            "Mlym", .indic, [("Sama Malayalam", "SamaMalayalam-Regular"), ("Baloo Chettan 2", "BalooChettan2-Regular")]),
        script("Sinh", .indic, [("Sinhala Sangam MN", "SinhalaSangamMN"), ("Sinhala MN", "SinhalaMN")]),
        script(
            "Thai", .southeastAsian,
            [
                ("Sukhumvit Set", "SukhumvitSet-Text"), ("Tahoma", "Tahoma"),
                ("Microsoft Sans Serif", "MicrosoftSansSerif"),
            ]),
        script("Laoo", .southeastAsian, [("Lao Sangam MN", "LaoSangamMN"), ("Lao MN", "LaoMN")]),
        script("Khmr", .southeastAsian, [("Khmer Sangam MN", "KhmerSangamMN"), ("Khmer MN", "KhmerMN")]),
        script(
            "Mymr", .southeastAsian,
            [
                ("Myanmar Sangam MN", "MyanmarSangamMN"), ("Myanmar MN", "MyanmarMN"),
                ("Noto Sans Myanmar", "NotoSansMyanmar-Regular"),
            ]),
        script("Syrc", .other, [("Noto Sans Syriac", "NotoSansSyriac-Regular")]),
        script("Thaa", .other, [("Noto Sans Thaana", "NotoSansThaana-Regular")]),
        script("Nkoo", .other, [("Noto Sans NKo", "NotoSansNKo-Regular")]),
        script("Mong", .other, [("Noto Sans Mongolian", "NotoSansMongolian-Regular")]),
        script("Tibt", .other, []),
        script("Adlm", .other, [("Noto Sans Adlam", "NotoSansAdlam-Regular")]),
        script("Rohg", .other, [("Noto Sans Hanifi Rohingya", "NotoSansHanifiRohingya-Regular")]),
    ]

    private static func script(_ script: String, _ group: ScriptGroup, _ names: [(String, String)])
        -> ScriptAlternatives
    {
        .init(script: script, group: group, alternatives: names.map { .init(family: $0, postscriptName: $1) })
    }

    public static func alternativeEntries(for group: ScriptGroup) -> [PlatformPreferences.Entry] {
        otAlternatives.filter { $0.group == group }.flatMap(\.alternatives).flatMap {
            [.postscriptName($0.postscriptName), .family($0.family)]
        }
    }

    public static func shapingAlternatives(
        for group: ScriptGroup, near face: FaceRecord?, in catalog: FaceCatalog,
        excluding: Set<FaceKey> = [], limit: Int = 3, preferences: PlatformPreferences = .macOS
    ) -> [FaceRecord] {
        guard group.needsShaping, limit > 0, let language = group.language else { return [] }
        let minimum = Languages.language(language).minimums.first { $0.group == group }?.count ?? 1
        let candidates = catalog.faces.enumerated().compactMap { order, candidate -> Candidate? in
            guard eligible(candidate, excluding: excluding), candidate.canShape(group),
                candidate.count(of: group) >= minimum
            else { return nil }
            return Candidate(face: candidate, covered: candidate.count(of: group), order: order)
        }
        let entries = PlatformPreferences.unique(preferences.entries(for: [language]) + alternativeEntries(for: group))
        let families = familyChoices(candidates, near: face)
        return families.sorted {
            (PlatformPreferences.rank(of: $0.face, in: entries), -$0.covered, $0.order)
                < (PlatformPreferences.rank(of: $1.face, in: entries), -$1.covered, $1.order)
        }.prefix(limit).map(\.face)
    }
}
