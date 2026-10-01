import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct SettingsActionsTests {
    @Test("UI-11: Show Settings Folder reveals the folder itself") func ui11ShowSettingsFolderRevealsIt() throws {
        let rig = try ShellRig(), m = AppModel(services: rig.services)
        #expect(!FileManager.default.fileExists(atPath: m.services.paths.applicationSupport.path))
        m.showSettingsFolderInFinder()
        #expect(FileManager.default.fileExists(atPath: m.services.paths.applicationSupport.path))
        #expect(rig.system.revealed == [[m.services.paths.applicationSupport]])
        m.getMoreFonts(); #expect(rig.system.openFontBookCalls == 1)
    }
}
