import Foundation

public enum SpecValidation {
    public static func problems(_ spec: ForgeSpec, faces: [FaceRecord]) -> [RecipeProblem] {
        precondition(faces.count == spec.materials.count)
        guard !faces.isEmpty else { return [.empty] }
        var problems: [RecipeProblem] = []
        let validBase = faces.indices.contains(spec.baseIndex)
        if !validBase { problems.append(.baseOutOfRange) }
        for (index, face) in faces.enumerated() where !face.supported {
            problems.append(.unsupported(index: index, reason: face.unsupportedReason))
        }
        let family = Naming.cleanName(spec.familyName), style = Naming.cleanName(spec.styleName)
        if family.isEmpty { problems.append(.familyNameEmpty) }
        if style.isEmpty { problems.append(.styleNameEmpty) }
        if family.hasPrefix(".") { problems.append(.familyNameStartsWithDot) }
        if hasControl(family) { problems.append(.familyNameHasControlCharacter) }
        if hasControl(style) { problems.append(.styleNameHasControlCharacter) }
        for group in ScriptGroup.allCases {
            if let index = spec.scriptRules[group], !faces.indices.contains(index) {
                problems.append(.ruleOutOfRange(group))
            }
        }
        for index in faces.indices {
            let scale = spec.resolvedScale(index)
            if !(0.1...10).contains(scale) {
                problems.append(.scaleOutOfRange(index: index, scale: scale))
            } else if validBase && (Double(faces[spec.baseIndex].upem) * scale).rounded(.toNearestOrEven) > 16384 {
                problems.append(.scaleTooLarge(index: index, scale: scale, baseUPM: faces[spec.baseIndex].upem))
            }
            if let weight = spec.resolvedWeight(index), !(1...1000).contains(weight) {
                problems.append(.weightOutOfRange(index: index, weight: weight))
            }
        }
        return problems
    }

    private static func hasControl(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value <= 0x1F || $0.value == 0x7F }
    }
}
