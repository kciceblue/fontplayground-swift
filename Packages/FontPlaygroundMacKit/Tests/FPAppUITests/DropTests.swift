import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct DropTests {
    @Test("UI-15: dropping folders adds them and font files are explained") func ui15DroppingFoldersAddsThem()
        async throws
    {
        let rig = try ShellRig(), folder = rig.temp.url.appending(path: "folder"); rig.probe.set(folder, .directory)
        let m = AppModel(services: rig.services); defer { m.prepareForTermination() }
        #expect(
            m.handleDrop([
                folder, rig.temp.url.appending(path: "font.ttf"), rig.temp.url.appending(path: "Other.OTF"),
                rig.temp.url.appending(path: "note.txt"),
            ]))
        await shellEventually { await rig.catalog.refreshModes.count == 1 }
        #expect(
            m.settings.value.extraFolders == [folder.path] && m.notices.filter { $0.kind == .fileDropped }.count == 1)
        m.notices = []; #expect(!m.handleDrop([rig.temp.url.appending(path: "note.txt")]))
        #expect(!m.handleDrop([URL(string: "https://example.com/a.ttf")!]) && m.notices.isEmpty)
        await rig.catalog.finishRefresh(with: ShellSnapshot.make())
    }
}
