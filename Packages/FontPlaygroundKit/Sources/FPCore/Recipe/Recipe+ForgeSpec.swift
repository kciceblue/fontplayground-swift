import Foundation

extension Recipe {
    public func scriptRules() -> [ScriptGroup: Int] {
        RuleResolver.resolveRules(
            order: keys, pins: pins,
            counts: Dictionary(uniqueKeysWithValues: materials.map { ($0.key, RuleResolver.counts(for: $0)) }))
    }

    public func mix() -> Mix {
        Mix(
            fonts: materials.map {
                MixFont(
                    face: $0.face, weight: $0.weight ?? defaultWeight, scale: $0.scale ?? defaultScale,
                    isAvailable: $0.isAvailable)
            }, rules: scriptRules(), baseIndex: baseIndex ?? 0)
    }

    public func mix(trying face: FaceRecord, replacing: FaceKey? = nil, for language: LanguageID? = nil) -> Mix {
        var trial = self
        if let replacing, contains(replacing) {
            trial.replace(replacing, with: face)
        } else {
            trial.add(face, for: language)
        }
        return trial.mix()
    }

    public func forgeSpec() -> ForgeSpec {
        ForgeSpec(
            materials: materials.map {
                ForgeSpec.MaterialSpec(
                    path: $0.face.path, index: $0.face.index, weight: $0.weight, scale: $0.scale,
                    expect: .init(postscriptName: $0.face.postscriptName, size: $0.face.size, mtime: $0.face.mtime))
            }, baseIndex: baseIndex ?? 0, scriptRules: scriptRules(), defaultWeight: defaultWeight,
            defaultScale: defaultScale, familyName: names.family, styleName: names.style)
    }

    public func forgeRequest(outputPath: String) -> ForgeRequest {
        ForgeRequest(spec: forgeSpec(), outputPath: outputPath)
    }
    public func missingSampleCharacters() -> [Unicode.Scalar] { mix().missingCharacters(in: sampleText) }
    public func plan() -> Plan { mix().plan() }
}
