import Foundation

public enum RecipeProblem: Sendable, Equatable {
    case empty
    case materialUnavailable(index: Int, Material.Availability)
    case baseOutOfRange
    case unsupported(index: Int, reason: String?)
    case familyNameEmpty
    case styleNameEmpty
    case familyNameStartsWithDot
    case familyNameHasControlCharacter
    case styleNameHasControlCharacter
    case ruleOutOfRange(ScriptGroup)
    case scaleOutOfRange(index: Int, scale: Double)
    case scaleTooLarge(index: Int, scale: Double, baseUPM: Int)
    case weightOutOfRange(index: Int, weight: Int)
    case cannotShape(index: Int, group: ScriptGroup)
    case glyphLimit(estimate: Int)
}

public enum GlyphWarning: Sendable, Equatable { case nearLimit, overLimit(estimate: Int) }

public struct RecipeAnalysis: Sendable, Equatable {
    public let mix: Mix
    public let plan: Plan
    public let tallies: [[ScriptGroup: Int]]
    public let glyphEstimate: Int
    public let glyphWarning: GlyphWarning?
    public let problems: [RecipeProblem]
    public let missingSampleCharacters: [Unicode.Scalar]
    public var validity: RecipeProblem? { problems.first }
    public var canForge: Bool { problems.isEmpty }
}
