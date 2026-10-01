import Foundation

public enum Smart {
    public static let defaultWeightClass = 400

    public static func defaultFace(_ faces: [FaceRecord], main: FaceRecord?) -> FaceRecord? {
        let supported = faces.filter(\.supported)
        let candidates = supported.isEmpty ? faces : supported
        let wantItalic = main?.italic ?? false, wantWeight = main?.weightClass ?? defaultWeightClass
        return candidates.enumerated().min {
            let lhs = ($0.element.italic == wantItalic ? 0 : 1, abs($0.element.weightClass - wantWeight), $0.offset)
            let rhs = ($1.element.italic == wantItalic ? 0 : 1, abs($1.element.weightClass - wantWeight), $1.offset)
            return lhs < rhs
        }?.element
    }

    public static func familyStyles(of face: FaceRecord, in catalog: FaceCatalog) -> [FaceRecord] {
        var styles: [String: FaceRecord] = [:]
        for candidate in catalog.faces(family: face.family) where candidate.supported && styles[candidate.style] == nil
        {
            styles[candidate.style] = candidate
        }
        styles[face.style] = face
        return styles.values.sorted {
            ($0.weightClass, $0.italic ? 1 : 0, $0.style) < ($1.weightClass, $1.italic ? 1 : 0, $1.style)
        }
    }
}
