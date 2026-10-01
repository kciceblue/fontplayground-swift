import FPCore
import FPMacServices
import Foundation

/// Catalog-backed presentation of typed model values; engine messages remain verbatim.
public enum ModelText {
    public static func groupLabel(_ id: ScriptGroup) -> String {
        switch id {
        case .latin: String(localized: "Latin", bundle: .module, comment: "model.text")
        case .greek: String(localized: "Greek", bundle: .module, comment: "model.text")
        case .cyrillic: String(localized: "Cyrillic", bundle: .module, comment: "model.text")
        case .armenianGeorgian: String(localized: "Armenian & Georgian", bundle: .module, comment: "model.text")
        case .hebrew: String(localized: "Hebrew", bundle: .module, comment: "model.text")
        case .arabic: String(localized: "Arabic", bundle: .module, comment: "model.text")
        case .indic: String(localized: "Indic", bundle: .module, comment: "model.text")
        case .southeastAsian: String(localized: "Thai, Lao, Khmer, Myanmar", bundle: .module, comment: "model.text")
        case .hangul: String(localized: "Hangul", bundle: .module, comment: "model.text")
        case .kana: String(localized: "Kana", bundle: .module, comment: "model.text")
        case .han: String(localized: "Han", bundle: .module, comment: "model.text")
        case .cjkSymbols: String(localized: "CJK symbols & fullwidth", bundle: .module, comment: "model.text")
        case .symbols: String(localized: "Punctuation & symbols", bundle: .module, comment: "model.text")
        case .emoji: String(localized: "Emoji & pictographs", bundle: .module, comment: "model.text")
        case .other: String(localized: "Everything else", bundle: .module, comment: "model.text")
        }
    }

    public static func languageLabel(_ id: LanguageID) -> String {
        switch id {
        case .latin: String(localized: "Letters (Latin)", bundle: .module, comment: "model.text")
        case .chineseSimplified: String(localized: "Chinese (Simplified)", bundle: .module, comment: "model.text")
        case .chineseTraditional: String(localized: "Chinese (Traditional)", bundle: .module, comment: "model.text")
        case .japanese: String(localized: "Japanese", bundle: .module, comment: "model.text")
        case .korean: String(localized: "Korean", bundle: .module, comment: "model.text")
        case .greek: String(localized: "Greek", bundle: .module, comment: "model.text")
        case .cyrillic: String(localized: "Cyrillic", bundle: .module, comment: "model.text")
        case .armenianGeorgian: String(localized: "Armenian & Georgian", bundle: .module, comment: "model.text")
        case .hebrew: String(localized: "Hebrew", bundle: .module, comment: "model.text")
        case .arabic: String(localized: "Arabic", bundle: .module, comment: "model.text")
        case .indic: String(localized: "Hindi & Indic", bundle: .module, comment: "model.text")
        case .southeastAsian: String(localized: "Thai, Lao, Khmer, Myanmar", bundle: .module, comment: "model.text")
        case .symbols: String(localized: "Symbols & emoji", bundle: .module, comment: "model.text")
        case .any: String(localized: "Any language", bundle: .module, comment: "model.text")
        }
    }

    public static func languageShortLabel(_ id: LanguageID) -> String {
        switch id {
        case .latin: String(localized: "Letters", bundle: .module, comment: "model.text")
        case .chineseSimplified: String(localized: "Chinese", bundle: .module, comment: "model.text")
        case .chineseTraditional: String(localized: "Chinese", bundle: .module, comment: "model.text")
        case .indic: String(localized: "Indic", bundle: .module, comment: "model.text")
        case .southeastAsian: String(localized: "Thai & SE Asian", bundle: .module, comment: "model.text")
        default: languageLabel(id)
        }
    }

    public static func groupPhrase(_ id: ScriptGroup) -> String {
        switch id {
        case .latin: String(localized: "letters, numbers and punctuation", bundle: .module, comment: "model.text")
        case .han: String(localized: "Chinese characters", bundle: .module, comment: "model.text")
        case .kana: String(localized: "Japanese kana", bundle: .module, comment: "model.text")
        case .hangul: String(localized: "Korean Hangul", bundle: .module, comment: "model.text")
        case .cjkSymbols: String(localized: "CJK punctuation", bundle: .module, comment: "model.text")
        case .symbols: String(localized: "symbols", bundle: .module, comment: "model.text")
        case .emoji: String(localized: "emoji", bundle: .module, comment: "model.text")
        case .indic: String(localized: "Indic scripts", bundle: .module, comment: "model.text")
        case .southeastAsian:
            String(localized: "Thai and Southeast Asian scripts", bundle: .module, comment: "model.text")
        case .other: String(localized: "other characters", bundle: .module, comment: "model.text")
        default: groupLabel(id)
        }
    }

    public static func samplePresetLabel(_ id: String) -> String {
        switch id {
        case "mixed": String(localized: "Mixed (English, Chinese, Japanese)", bundle: .module, comment: "model.text")
        case "english": String(localized: "English", bundle: .module, comment: "model.text")
        case "chinese_s": String(localized: "Chinese (Simplified)", bundle: .module, comment: "model.text")
        case "chinese_t": String(localized: "Chinese (Traditional)", bundle: .module, comment: "model.text")
        case "japanese": String(localized: "Japanese", bundle: .module, comment: "model.text")
        case "korean": String(localized: "Korean", bundle: .module, comment: "model.text")
        case "all": String(localized: "All languages", bundle: .module, comment: "model.text")
        default: id
        }
    }

    public static var drawsNothing: String {
        String(
            localized: "Draws nothing — the fonts above already cover everything it has.", bundle: .module,
            comment: "model.text")
    }

    public static var labelJoiner: String { String(localized: " and ", bundle: .module, comment: "model.joiner") }
    /// Separates the items of a user-visible list (localisation.md §L6): ", " in English, "、" in Chinese.
    public static var listSeparator: String {
        String(localized: ", ", bundle: .module, comment: "model.listSeparator")
    }
    public static func joinLabels(
        _ ids: [LanguageID], limit: Int = 2,
        joiner: String = ModelText.labelJoiner
    ) -> String {
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
            guard !rest.isEmpty else {
                return String(localized: "Draws \(head).", bundle: .module, comment: "model.text")
            }
            let shown =
                Array(rest.prefix(Languages.maxPhrases - 1))
                + (rest.count >= Languages.maxPhrases
                    ? [String(localized: "more", bundle: .module, comment: "model.text")] : [])
            return String(localized: "Draws \(head), plus \(joinAnd(shown)).", bundle: .module, comment: "model.text")
        }
        let shown =
            groups.prefix(Languages.maxPhrases).map(groupPhrase)
            + (groups.count > Languages.maxPhrases
                ? [String(localized: "more", bundle: .module, comment: "model.text")] : [])
        return String(localized: "Draws \(joinAnd(shown)).", bundle: .module, comment: "model.text")
    }

    public static func roleTitle(_ title: RoleTitle) -> String {
        switch title {
        case .addsNothing: return String(localized: "ADDS NOTHING", bundle: .module, comment: "model.text")
        case .fillsInTheRest: return String(localized: "FILLS IN THE REST", bundle: .module, comment: "model.text")
        case .forLanguages(let ids):
            let labels = joinLabels(ids, joiner: String(localized: " & ", bundle: .module, comment: "model.text"))
                .uppercased()
            return String(localized: "FOR \(labels)", bundle: .module, comment: "model.text")
        }
    }

    private static func joinAnd(_ parts: [String]) -> String {
        guard let last = parts.last else { return "" }
        guard parts.count > 1 else { return last }
        let leading = parts.dropLast().joined(separator: listSeparator)
        return String(localized: "\(leading) and \(last)", bundle: .module, comment: "model.text")
    }
}

extension ModelText {
    public static func problem(_ problem: RecipeProblem, in recipe: Recipe) -> String {
        func display(_ index: Int) -> String { recipe.materials[index].face.displayName }
        switch problem {
        case .empty:
            return String(localized: "Add at least one font.", bundle: .module, comment: "model.problem.empty")
        case .materialUnavailable(let index, let availability):
            let name = display(index)
            if availability == .notFound {
                return String(
                    localized: "\(name): this font is not on this Mac", bundle: .module,
                    comment: "model.problem.notFound")
            }
            return String(
                localized: "\(name): the font file is no longer there", bundle: .module,
                comment: "model.problem.unavailable")
        case .baseOutOfRange:
            return String(localized: "Base material is out of range.", bundle: .module, comment: "model.problem.base")
        case .unsupported(let index, let reason):
            let name = display(index), detail = reason ?? ""
            return String(localized: "\(name): \(detail)", bundle: .module, comment: "model.problem.unsupported")
        case .familyNameEmpty:
            return String(localized: "Family name is empty.", bundle: .module, comment: "model.problem.familyEmpty")
        case .styleNameEmpty:
            return String(localized: "Style name is empty.", bundle: .module, comment: "model.problem.styleEmpty")
        case .familyNameStartsWithDot:
            return String(
                localized: "Family name can't start with “.”: macOS hides fonts whose names start with a dot.",
                bundle: .module, comment: "model.problem.hidden")
        case .familyNameHasControlCharacter:
            return String(
                localized: "Family name contains a control character.", bundle: .module,
                comment: "model.problem.familyControl")
        case .styleNameHasControlCharacter:
            return String(
                localized: "Style name contains a control character.", bundle: .module,
                comment: "model.problem.styleControl")
        case .ruleOutOfRange(let group):
            let name = group.rawValue
            return String(
                localized: "Rule for \(name) points to a missing material.", bundle: .module,
                comment: "model.problem.rule")
        case .scaleOutOfRange(let index, let scale):
            let name = display(index), number = String(format: "%g", scale)
            return String(
                localized: "\(name): scale \(number) must be between 0.1 and 10.", bundle: .module,
                comment: "model.problem.scale")
        case .scaleTooLarge(let index, let scale, let upem):
            let name = display(index), number = String(format: "%g", scale * 100), units = String(upem),
                maximum = String(format: "%.0f", 16384 / Double(upem) * 100)
            return String(
                localized: "\(name): scale \(number)% is too large for a \(units)-unit base (maximum \(maximum)%).",
                bundle: .module, comment: "model.problem.scaleLarge")
        case .weightOutOfRange(let index, let weight):
            let name = display(index), number = String(weight)
            return String(
                localized: "\(name): weight \(number) must be between 1 and 1000.", bundle: .module,
                comment: "model.problem.weight")
        case .cannotShape(let index, let group):
            let name = display(index), script = groupLabel(group), language = languageShortLabel(group.language!)
            if recipe.materials[index].face.aat.morx {
                return String(
                    localized:
                        "\(name) can't draw \(script) in the forged font: it shapes it with Apple-only rules (AAT) that can't be carried over. Choose another font for \(language).",
                    bundle: .module, comment: "model.problem.aat")
            }
            return String(
                localized:
                    "\(name) can't draw \(script) in the forged font: it has no OpenType shaping rules for it. Choose another font for \(language).",
                bundle: .module, comment: "model.problem.shaping")
        case .glyphLimit(let estimate): return glyphLimitText(estimate)
        }
    }
    public static func glyphWarning(_ warning: GlyphWarning) -> String {
        switch warning {
        case .nearLimit:
            String(
                localized:
                    "These fonts come close to the 65,535-glyph limit; if forging fails, remove a font or use a smaller build.",
                bundle: .module, comment: "model.glyph.near")
        case .overLimit(let estimate): glyphLimitText(estimate)
        }
    }
    private static func glyphLimitText(_ estimate: Int) -> String {
        let digits = Array(String(estimate))
        let grouped = digits.enumerated().reduce(into: "") { text, pair in
            if pair.offset > 0 && (digits.count - pair.offset) % 3 == 0 { text.append(",") }
            text.append(pair.element)
        }
        return String(
            localized:
                "Together these fonts need about \(grouped) glyphs; a font can hold 65,535. Remove a font or use a smaller (regional) build.",
            bundle: .module, comment: "model.glyph.limit")
    }
    public static func unresolvedSummary(_ report: LoadReport) -> String {
        guard !report.unresolved.isEmpty else { return "" }
        let count = String(report.unresolved.count),
            names = report.unresolved.map(\.displayName).joined(separator: listSeparator)
        if report.unresolved.count == 1 {
            return String(
                localized: "\(count) font could not be found: \(names)", bundle: .module, comment: "model.restore.one")
        }
        return String(
            localized: "\(count) fonts could not be found: \(names)", bundle: .module, comment: "model.restore.many")
    }
    public static func replacementOffer(missing: String, replacement: String) -> String {
        String(
            localized: "\(missing) isn't on this Mac. Use \(replacement) instead?", bundle: .module,
            comment: "model.restore.replacement")
    }
    public static func weightSwap(_ swap: WeightSwap) -> String {
        let to = swap.to.displayName, from = swap.from.displayName
        if swap.requestedWeight < swap.from.weightClass {
            return String(
                localized: "Using \(to) instead of making \(from) lighter.", bundle: .module,
                comment: "model.weight.lighter")
        }
        return String(
            localized: "Using \(to) instead of making \(from) bolder.", bundle: .module, comment: "model.weight.bolder")
    }
    public static func weightNote(_ note: WeightNote) -> String {
        switch note {
        case .syntheticBold(_, let delta):
            let amount = String(delta)
            return String(
                localized: "Made bolder synthetically (+\(amount))", bundle: .module, comment: "model.weight.synthetic")
        case .cannotMakeLighter:
            return String(
                localized: "Can't be made lighter; weight left as is", bundle: .module,
                comment: "model.weight.cannotLighten")
        }
    }
    public static func catalogIssue(_ issue: CatalogIssue) -> String {
        switch issue {
        case .noAccess(let folder):
            return String(
                localized: "Font Playground has no access to “\(folder)”.", bundle: .module,
                comment: "model.catalog.access")
        case .folderMissing(let folder):
            return String(
                localized: "The font folder is missing: \(folder)", bundle: .module, comment: "model.catalog.missing")
        case .folderUnreadable(let path, let message), .unreadable(let path, _, let message):
            return String(localized: "\(path): \(message)", bundle: .module, comment: "model.catalog.unreadable")
        case .skipped(let path, let reason):
            let reason = reason.rawValue
            return String(localized: "\(path): \(reason)", bundle: .module, comment: "model.catalog.skipped")
        case .duplicate(_, let dropped, let name):
            let path = dropped.description
            return String(localized: "\(path): duplicate \(name)", bundle: .module, comment: "model.catalog.duplicate")
        case .disabledUnlocated(let name):
            return String(
                localized: "Disabled font could not be located: \(name)", bundle: .module,
                comment: "model.catalog.disabled")
        }
    }
}
