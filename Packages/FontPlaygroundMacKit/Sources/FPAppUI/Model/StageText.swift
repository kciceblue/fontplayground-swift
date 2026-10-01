import FPCore
import FPEngineClient

public enum StageText {
    public static func text(for stage: EngineStage, materialIndex: Int?, materials: [Material]) -> String? {
        switch stage {
        case .validate: BuildText.validate
        case .plan: BuildText.plan
        case .prepare:
            if let index = materialIndex, materials.indices.contains(index) {
                BuildText.prepare(materials[index].face.displayName)
            } else {
                BuildText.prepareAny
            }
        case .merge: BuildText.merge
        case .finish: BuildText.finish
        case .verify: BuildText.verify
        case .done: BuildText.done
        default: nil
        }
    }
    public static func lowerFirst(_ text: String) -> String {
        guard text.count > 1, text[text.index(after: text.startIndex)].isLowercase else { return text }
        return text.prefix(1).lowercased() + text.dropFirst()
    }
}
