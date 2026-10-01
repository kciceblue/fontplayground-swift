import Foundation

public enum GlyphBudget {
    public static let maxGlyphs = 65_535
    // ENGINE-3: calibrated against the feature-closed engine output (WP-104).
    public static let warnAt = 55_000
    public static let variantFactor = 0.8

    public static func exceedsGlyphBudget(_ face: FaceRecord, mainGlyphs: Int) -> Bool {
        Double(face.glyphCount) * variantFactor + Double(mainGlyphs) > Double(maxGlyphs)
    }

    public static func faceGlyphShare(_ face: FaceRecord, assigned: Int) -> Int {
        Int(
            (Double(face.glyphCount * assigned) / Double(max(face.coverage.count, 1)) * variantFactor).rounded(
                .toNearestOrEven))
    }

    public static func estimate(faces: [FaceRecord], plan: Plan) -> Int {
        1
            + faces.enumerated().reduce(0) { sum, pair in
                sum
                    + faceGlyphShare(
                        pair.element,
                        assigned: plan.assignments.indices.contains(pair.offset)
                            ? plan.assignments[pair.offset].count : 0)
            }
    }
}
