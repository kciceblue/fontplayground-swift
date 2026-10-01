import Foundation

extension EnglishText {
    public static func problem(_ p: RecipeProblem, in recipe: Recipe) -> String {
        func display(_ index: Int) -> String { recipe.materials[index].face.displayName }
        switch p {
        case .empty: return "Add at least one font."
        case .materialUnavailable(let index, let availability):
            return "\(display(index)): "
                + (availability == .notFound ? "this font is not on this Mac" : "the font file is no longer there")
        case .baseOutOfRange: return "Base material is out of range."
        case .unsupported(let index, let reason): return "\(display(index)): \(reason ?? "")"
        case .familyNameEmpty: return "Family name is empty."
        case .styleNameEmpty: return "Style name is empty."
        case .familyNameStartsWithDot:
            return "Family name can't start with “.”: macOS hides fonts whose names start with a dot."
        case .familyNameHasControlCharacter: return "Family name contains a control character."
        case .styleNameHasControlCharacter: return "Style name contains a control character."
        case .ruleOutOfRange(let group): return "Rule for \(group.rawValue) points to a missing material."
        case .scaleOutOfRange(let index, let scale):
            return "\(display(index)): scale \(String(format: "%g", scale)) must be between 0.1 and 10."
        case .scaleTooLarge(let index, let scale, let upem):
            return
                "\(display(index)): scale \(String(format: "%g", scale * 100))% is too large for a \(upem)-unit base (maximum \(String(format: "%.0f", 16384 / Double(upem) * 100))%)."
        case .weightOutOfRange(let index, let weight):
            return "\(display(index)): weight \(weight) must be between 1 and 1000."
        case .cannotShape(let index, let group):
            let reason =
                recipe.materials[index].face.aat.morx
                ? "it shapes it with Apple-only rules (AAT) that can't be carried over."
                : "it has no OpenType shaping rules for it."
            return
                "\(display(index)) can't draw \(groupLabel(group)) in the forged font: \(reason) Choose another font for \(languageShortLabel(group.language!))."
        case .glyphLimit(let estimate): return glyphLimitText(estimate)
        }
    }

    public static func glyphWarning(_ warning: GlyphWarning) -> String {
        switch warning {
        case .nearLimit:
            "These fonts come close to the 65,535-glyph limit; if forging fails, remove a font or use a smaller build."
        case .overLimit(let estimate): glyphLimitText(estimate)
        }
    }

    private static func glyphLimitText(_ estimate: Int) -> String {
        let digits = Array(String(estimate))
        let grouped = digits.enumerated().reduce(into: "") { text, pair in
            if pair.offset > 0 && (digits.count - pair.offset) % 3 == 0 { text.append(",") }
            text.append(pair.element)
        }
        return
            "Together these fonts need about \(grouped) glyphs; a font can hold 65,535. Remove a font or use a smaller (regional) build."
    }
}
