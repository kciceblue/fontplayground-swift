import Foundation

public enum Suggestions {
    public static func suggestMaterials(
        missing: CodepointSet, candidates: [FaceRecord], main: FaceRecord?, limit: Int = 3,
        excluding: Set<FaceKey> = [], mainGlyphs: Int = 0, preferred: [PlatformPreferences.Entry] = []
    ) -> [FaceRecord] {
        guard !missing.isEmpty, limit > 0 else { return [] }
        let covered = candidates.enumerated().compactMap { order, face -> Candidate? in
            guard eligible(face, excluding: excluding) else { return nil }
            // ENGINE-2: mapped but unshapeable characters cannot improve the forged font.
            let count = missing.intersectionCount(face.plannableCoverage)
            return count > 0 ? Candidate(face: face, covered: count, order: order) : nil
        }
        let families = familyChoices(covered, near: main)
        func rank(_ candidate: Candidate) -> (Int, Int, Int, Int, Int) {
            (
                GlyphBudget.exceedsGlyphBudget(candidate.face, mainGlyphs: mainGlyphs) ? 1 : 0,
                -candidate.covered, PlatformPreferences.rank(of: candidate.face, in: preferred),
                candidate.face.glyphCount, candidate.order
            )
        }
        return families.sorted { rank($0) < rank($1) }.prefix(limit).map(\.face)
    }

    struct Candidate {
        var face: FaceRecord
        var covered: Int
        var order: Int
    }

    static func eligible(_ face: FaceRecord, excluding: Set<FaceKey>) -> Bool {
        // CATALOG-2: never suggest hidden or implausibly broad fallback faces such as LastResort.
        face.supported && !face.hidden && !face.suspiciousCoverage && !excluding.contains(face.key)
    }

    static func familyChoices(_ candidates: [Candidate], near main: FaceRecord?) -> [Candidate] {
        let wantItalic = main?.italic ?? false, wantWeight = main?.weightClass ?? Smart.defaultWeightClass
        var positions: [String: Int] = [:]
        var families: [Candidate] = []
        func rank(_ face: FaceRecord) -> (Int, Int) {
            (face.italic == wantItalic ? 0 : 1, abs(face.weightClass - wantWeight))
        }
        for candidate in candidates {
            if let index = positions[candidate.face.family] {
                if rank(candidate.face) < rank(families[index].face) {
                    // The family retains its first eligible catalog position even when another style wins.
                    families[index].face = candidate.face
                    families[index].covered = candidate.covered
                }
            } else {
                positions[candidate.face.family] = families.count
                families.append(candidate)
            }
        }
        return families
    }
}
