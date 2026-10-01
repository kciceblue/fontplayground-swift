import FPCore
import Foundation

public enum PreviewMode: Equatable {
    case empty
    case mix(Mix)
    case trial(PreviewTrial)
    case built(BuiltFontPreview, coverage: CharacterSet)
}
public struct PreviewConfiguration: Equatable {
    public var mode: PreviewMode
    public var pointSize: Int
    public var colourByFont: Bool
    public init(mode: PreviewMode, pointSize: Int, colourByFont: Bool) {
        self.mode = mode; self.pointSize = pointSize; self.colourByFont = colourByFont
    }
    public static func make(
        recipe: Recipe, trial: PreviewTrial?, built: BuiltFontPreview?, builtCoverage: CharacterSet?, pointSize: Int,
        colourByFont: Bool
    ) -> PreviewConfiguration {
        let mode: PreviewMode
        if let trial {
            mode = .trial(trial)
        } else if let built, !built.isStale(for: recipe), let coverage = builtCoverage {
            mode = .built(built, coverage: coverage)
        } else if recipe.materials.isEmpty {
            mode = .empty
        } else {
            mode = .mix(recipe.mix())
        }
        return .init(mode: mode, pointSize: pointSize, colourByFont: colourByFont)
    }
    public func source(of scalar: Unicode.Scalar) -> Int? {
        switch mode {
        case .empty: 0
        case .mix(let mix): mix.source(of: scalar)
        case .trial(let trial): trial.mix.source(of: scalar)
        case .built(_, let coverage): coverage.contains(scalar) ? 0 : nil
        }
    }
    public func missingScalars(in text: String) -> [Unicode.Scalar] {
        if case .empty = mode { return [] }
        return TextUtil.visibleScalars(in: text).filter { source(of: $0) == nil }
    }
    var mix: Mix? {
        switch mode {
        case .mix(let mix): mix;
        case .trial(let trial): trial.mix;
        default: nil
        }
    }
    var isBuilt: Bool { if case .built = mode { true } else { false } }
}
