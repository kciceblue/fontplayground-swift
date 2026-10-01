import FPCore
import Foundation
import Testing

@testable import FPAppUI

@MainActor struct AdvancedInspectorToggleTests {
    @Test("UI-15: Advanced is an inspector") func ui15AdvancedIsAnInspector() throws {
        let temp = try ShellTempDirectory()
        let services = AppServices.testing(root: temp.url, defaults: temp.defaults)
        let app = AppModel(services: services)
        #expect(!app.inspectorPresented)
        app.toggleAdvanced(); #expect(app.inspectorPresented)
        app.toggleAdvanced(); #expect(!app.inspectorPresented)
        app.showAdvanced(); app.showAdvanced(); #expect(app.inspectorPresented)
        app.settings.showAllScriptGroups = true
        let restored = AppModel(services: services)
        #expect(restored.inspectorPresented && restored.settings.showAllScriptGroups)
        restored.toggleAdvanced(); restored.settings.showAllScriptGroups = false
        let hidden = AppModel(services: services)
        #expect(!hidden.inspectorPresented && !hidden.settings.showAllScriptGroups)
    }
    @Test("WP-701 finding H: Advanced is presented after the sidebar collapse")
    func wp701FindingHPresentsAfterTheSidebarCollapse() throws {
        let temp = try ShellTempDirectory()
        let app = AppModel(services: .testing(root: temp.url, defaults: temp.defaults))
        var queued: [@MainActor () -> Void] = []
        app.presentInspector = { queued.append($0) }
        app.sidebarVisibility = .all; app.updateMainWindowContentWidth(676)
        app.showAdvanced()
        #expect(app.sidebarVisibility == .detailOnly && !app.inspectorPresented && queued.count == 1)
        app.showAdvanced(); #expect(queued.count == 1)
        queued.removeFirst()(); #expect(app.inspectorPresented)
        app.toggleAdvanced(); #expect(!app.inspectorPresented)
        // Hiding before the presentation runs cancels it.
        app.toggleAdvanced(); app.toggleAdvanced()
        queued.removeFirst()(); #expect(!app.inspectorPresented && queued.isEmpty)
    }
    @Test("ENGINE-4: default boldness prefers real weights") func defaultBoldnessPrefersRealWeights() throws {
        let temp = try ShellTempDirectory()
        let app = AppModel(services: .testing(root: temp.url, defaults: temp.defaults))
        let main = ShellFaces.make("Main", text: "abc")
        let regular = ShellFaces.make("Fam", path: "/fam.ttf", text: "你好")
        var bold = ShellFaces.make("Fam", style: "Bold", path: "/bold.ttf", text: "你好"); bold.weightClass = 700
        app.catalogFaces = [main, regular, bold]
        app.edit { recipe in
            recipe.add(main); recipe.add(regular); recipe.setSampleText("abc你好")
        }
        let before = app.recipe
        let swaps = AdvancedIntents.applyDefaults(app, weightIndex: 5, sizePercent: nil)
        #expect(app.recipe.keys == [main.key, bold.key] && app.recipe.defaultWeight == 700)
        #expect(swaps.count == 1)
        #expect(AdvancedModel.weightSwapNotes(swaps) == ["Using Fam Bold instead of making Fam Regular bolder."])
        app.edit { $0 = before }; #expect(app.recipe == before)
        app.isBuilding = true
        #expect(AdvancedIntents.applyDefaults(app, weightIndex: 5, sizePercent: 90).isEmpty)
        #expect(app.recipe == before)
        app.isBuilding = false
    }
    @Test func allIntentsUseTheLockedRecipeSeam() throws {
        let temp = try ShellTempDirectory()
        let app = AppModel(services: .testing(root: temp.url, defaults: temp.defaults))
        app.recipe = AdvancedModelTests.recipe()
        AdvancedIntents.pin(app, group: .latin, choiceIndex: 2)
        AdvancedIntents.lineSpacing(app, index: 2)
        #expect(app.recipe.pins[.latin] == app.recipe.keys[1] && app.recipe.baseKey == app.recipe.keys[1])
        let before = app.recipe
        app.isBuilding = true
        AdvancedIntents.pin(app, group: .latin, choiceIndex: 0); AdvancedIntents.lineSpacing(app, index: 0)
        #expect(app.recipe == before)
        app.build.lastErrorDetail = "The file could not be read."
        app.settings.showAllScriptGroups = true
        let state = AdvancedIntents.state(app)
        #expect(state.rows.count == 15 && state.reportText == "The file could not be read.")
        app.isBuilding = false
    }
}
