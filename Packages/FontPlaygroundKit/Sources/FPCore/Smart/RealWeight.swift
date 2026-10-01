import Foundation

public struct WeightSwap: Sendable, Equatable {
    public let index: Int
    public let from: FaceRecord
    public let to: FaceRecord
    public let requestedWeight: Int
    public let remainingSyntheticBold: Int
    public init(index: Int, from: FaceRecord, to: FaceRecord, requestedWeight: Int, remainingSyntheticBold: Int) {
        self.index = index; self.from = from; self.to = to
        self.requestedWeight = requestedWeight; self.remainingSyntheticBold = remainingSyntheticBold
    }
}

public enum WeightNote: Sendable, Equatable {
    case syntheticBold(index: Int, delta: Int)
    case cannotMakeLighter(index: Int)
}

extension Smart {
    public static func nearestRealWeight(
        for face: FaceRecord, requested weight: Int, mustCover drawn: CodepointSet,
        in catalog: FaceCatalog, excluding: Set<FaceKey>
    ) -> FaceRecord? {
        guard !face.hasWeightAxis, !drawn.isEmpty, abs(weight - face.weightClass) >= 50 else { return nil }
        func distance(_ face: FaceRecord) -> Int {
            if let axis = face.axes.first(where: { $0.tag == "wght" }),
                axis.min <= Double(weight), Double(weight) <= axis.max
            {
                return 0
            }
            return abs(weight - face.weightClass)
        }
        let candidates = catalog.faces(family: face.family).enumerated().filter { _, candidate in
            candidate.key != face.key && candidate.italic == face.italic
                && Suggestions.eligible(candidate, excluding: excluding)
                // ENGINE-4: heavier Apple faces may have smaller coverage; preserve every planned character.
                && candidate.plannableCoverage.isSuperset(of: drawn)
        }
        let best = candidates.min {
            (distance($0.element), $0.element.weightClass >= weight ? 0 : 1, $0.offset)
                < (distance($1.element), $1.element.weightClass >= weight ? 0 : 1, $1.offset)
        }?.element
        guard let best, distance(best) < distance(face) else { return nil }
        return best
    }
}
