import Foundation

extension Recipe {
    public func glyphsNeeded() -> Int {
        guard let main else { return 0 }
        let plan = plan()
        return main.glyphCount
            + materials.enumerated().dropFirst().reduce(0) { sum, pair in
                sum + GlyphBudget.faceGlyphShare(pair.element.face, assigned: plan.assignments[pair.offset].count)
            }
    }

    public func suggestions(
        in catalog: FaceCatalog, limit: Int = 3, preferences: PlatformPreferences = .macOS
    ) -> [FaceRecord] {
        let missing = missingSampleCharacters()
        return Suggestions.suggestMaterials(
            missing: CodepointSet(missing.map(\.value)), candidates: catalog.faces, main: main, limit: limit,
            excluding: Set(keys), mainGlyphs: glyphsNeeded(),
            preferred: preferences.entries(for: Languages.languagesForMissing(missing).map(\.id)))
    }

    public func suggestions(
        for language: LanguageID, in catalog: FaceCatalog, limit: Int = 3,
        preferences: PlatformPreferences = .macOS
    ) -> [FaceRecord] {
        let candidates =
            language == .any
            ? catalog.faces
            : catalog.faces.filter {
                Languages.coversWell($0, Languages.language(language))
            }
        return Suggestions.suggestMaterials(
            missing: CodepointSet(missingSampleCharacters().map(\.value)), candidates: candidates, main: main,
            limit: limit, excluding: Set(keys), mainGlyphs: glyphsNeeded(),
            preferred: preferences.entries(for: [language]))
    }

    @discardableResult public mutating func applyRealWeights(in catalog: FaceCatalog) -> [WeightSwap] {
        let plan = plan()
        var swaps: [WeightSwap] = []
        for index in materials.indices {
            let material = materials[index]
            guard material.isAvailable, let weight = material.weight ?? defaultWeight,
                let face = Smart.nearestRealWeight(
                    for: material.face, requested: weight, mustCover: plan.assignments[index], in: catalog,
                    excluding: Set(keys).subtracting([material.key]))
            else { continue }
            if replace(material.key, with: face, keepAdjustments: true) {
                let delta = weight - face.weightClass
                swaps.append(
                    .init(
                        index: index, from: material.face, to: face, requestedWeight: weight,
                        remainingSyntheticBold: face.hasWeightAxis || delta < 50 ? 0 : min(delta, 500)))
            }
        }
        return swaps
    }

    public func weightNotes() -> [WeightNote] {
        materials.enumerated().compactMap { index, material in
            guard material.isAvailable, !material.face.hasWeightAxis, let weight = material.weight ?? defaultWeight
            else { return nil }
            let delta = weight - material.face.weightClass
            if delta >= 50 { return .syntheticBold(index: index, delta: min(delta, 500)) }
            return delta <= -50 ? .cannotMakeLighter(index: index) : nil
        }
    }
}
