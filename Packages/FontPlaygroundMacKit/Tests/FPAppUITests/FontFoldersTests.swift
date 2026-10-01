import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct FontFoldersTests {
    @Test func addRemoveAndValidateFolders() async throws {
        let rig = try ShellRig(), a = rig.temp.url.appending(path: "a"), b = rig.temp.url.appending(path: "b"),
            missing = rig.temp.url.appending(path: "missing")
        rig.probe.set(a, .directory); rig.probe.set(b, .directory)
        let m = AppModel(services: rig.services); defer { m.prepareForTermination() }
        m.addFontFolders([a, a.appending(path: "."), b, missing]);
        await shellEventually { await rig.catalog.refreshModes.count == 1 }
        #expect(m.settings.value.extraFolders == [a.path, b.path])
        #expect(await rig.catalog.folderCalls == [[a, b]])
        #expect(await rig.catalog.callOrder == ["folders", "refresh"])
        #expect(m.notices.filter { $0.kind == .settingsIssues }.count == 1 && m.notices[0].text.contains(missing.path))
        await rig.catalog.finishRefresh(with: ShellSnapshot.make()); m.addFontFolders([a]);
        #expect(await rig.catalog.folderCalls.count == 1)
        m.removeFontFolder(a); await shellEventually { await rig.catalog.refreshModes.count == 2 }
        #expect(m.settings.value.extraFolders == [b.path])
        #expect(await rig.catalog.folderCalls == [[a, b], [b]])
        #expect(await rig.catalog.refreshModes == [.incremental, .incremental])
        await rig.catalog.finishRefresh(with: ShellSnapshot.make(generation: 2))
    }
}
