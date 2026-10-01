import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct SettingsStoreTests {
    @Test func invalidValuesFallBackToDefaults() throws {
        let rig = try ShellRig(), d = rig.temp.defaults
        let empty = SettingsStore(defaults: d, probe: rig.probe)
        #expect(empty.value == AppSettings() && empty.loadIssues.isEmpty)
        #expect(!empty.inspectorPresented && !empty.showAllScriptGroups)
        d.set("sepia", forKey: "appearance"); d.set(400, forKey: "previewPointSize");
        d.set("yes", forKey: "colourByFont")
        d.set(["D:/Fonts"], forKey: "extraFontFolders"); d.set("/missing", forKey: "lastSaveDirectory")
        let m = AppModel(services: rig.services)
        #expect(m.settings.value.appearance == .system && m.previewPointSize == 30 && !m.colourByFont)
        #expect(m.settings.value.extraFolders.isEmpty && m.settings.value.lastSaveDirectory == nil)
        #expect(m.notices.count == 1 && m.notices[0].text.contains("“D:/Fonts”"))
        #expect(d.stringArray(forKey: "extraFontFolders") == [])
        d.set(true, forKey: "previewPointSize"); d.set(1, forKey: "colourByFont")
        let wrong = SettingsStore(defaults: d, probe: rig.probe)
        #expect(wrong.value.previewPointSize == 30 && !wrong.value.colourByFont)
        d.set("dark", forKey: "appearance"); d.set(40, forKey: "previewPointSize"); d.set(true, forKey: "colourByFont")
        let valid = SettingsStore(defaults: d, probe: rig.probe)
        #expect(valid.value.appearance == .dark && valid.value.previewPointSize == 40 && valid.value.colourByFont)
    }
    @Test func appearanceAppliesAtInitAndOnChange() throws {
        let rig = try ShellRig(); rig.temp.defaults.set("dark", forKey: "appearance");
        let m = AppModel(services: rig.services)
        #expect(rig.system.appearances == [.dark])
        m.setAppearance(.light); #expect(rig.system.appearances == [.dark, .light])
        m.previewPointSize = 44; m.colourByFont = true; m.inspectorPresented = true; m.flushPreferences()
        let next = AppModel(services: rig.services)
        #expect(next.previewPointSize == 44 && next.colourByFont && next.inspectorPresented)
        #expect(next.settings.value.appearance == .light)
        #expect(ShellText.shortPath("/Users/a/Fonts", home: "/Users/a") == "~/Fonts")
        #expect(ShellText.shortPath("/Users/abc/Fonts", home: "/Users/a") == "/Users/abc/Fonts")
        #expect(ShellText.shortPath("/Users/a", home: "/Users/a") == "/Users/a")
    }
}
