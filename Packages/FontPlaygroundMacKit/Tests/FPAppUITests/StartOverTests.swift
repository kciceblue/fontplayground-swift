import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct StartOverTests {
    @Test func startOverAsksThenClears() throws {
        let rig = try ShellRig(), m = AppModel(services: rig.services);
        m.edit {
            $0.add(ShellFaces.make()); $0.setSampleText("keep this")
        }; m.pickRequest = PickRequest(languageID: "any")
        m.startOver(); let first = try #require(m.alert)
        #expect(first.title == "Start over?" && first.buttons.map(\.title) == ["Start Over", "Cancel"])
        first.buttons[1].action(); #expect(m.recipe.materials.count == 1 && m.pickRequest != nil)
        m.startOver(); m.alert?.buttons[0].action()
        #expect(
            m.recipe.materials.isEmpty && m.recipe.sampleText == "keep this" && m.pickRequest == nil && m.trial == nil)
        #expect(!m.commandState.canStartOver)
        m.isBuilding = true; m.startOver();
        #expect(m.alert?.message?.hasSuffix("The build in progress will stop.") == true)
    }
}
