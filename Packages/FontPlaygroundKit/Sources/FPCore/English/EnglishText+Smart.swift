import Foundation

extension EnglishText {
    public static func weightSwap(_ swap: WeightSwap) -> String {
        let direction = swap.requestedWeight < swap.from.weightClass ? "lighter" : "bolder"
        return "Using \(swap.to.displayName) instead of making \(swap.from.displayName) \(direction)."
    }

    public static func weightNote(_ note: WeightNote) -> String {
        switch note {
        case .syntheticBold(_, let delta): "Made bolder synthetically (+\(delta))"
        case .cannotMakeLighter: "Can't be made lighter; weight left as is"
        }
    }
}
