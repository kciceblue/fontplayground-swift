import FPEngineClient
import Testing

@testable import FPAppUI

extension BuildFlowIntegration {
    @MainActor struct StageTextTests {
        @Test func everyStage() throws {
            let r = try BuildTestRig(); defer { r.cleanup() }
            let stages: [(EngineStage, String?)] = [
                (.validate, "Checking your fonts…"),
                (.plan, "Deciding which font supplies each character…"), (.prepare, "Preparing the fonts…"),
                (.merge, "Combining the fonts…"), (.finish, "Finishing the font…"), (.verify, "Checking the result…"),
                (.done, "Done."), (.scan, nil),
            ]
            for (stage, expected) in stages {
                #expect(StageText.text(for: stage, materialIndex: nil, materials: r.model.recipe.materials) == expected)
            }
            #expect(
                StageText.text(for: .prepare, materialIndex: 1, materials: r.model.recipe.materials)
                    == "Preparing Fixture B Bold…")
            #expect(
                StageText.text(for: .prepare, materialIndex: 7, materials: r.model.recipe.materials)
                    == "Preparing the fonts…")
            #expect(StageText.lowerFirst("Preparing X…") == "preparing X…");
            #expect(StageText.lowerFirst("UI…") == "UI…")
            #expect(StageText.lowerFirst("") == ""); #expect(StageText.lowerFirst("Ångström") == "ångström")
        }
    }

}
