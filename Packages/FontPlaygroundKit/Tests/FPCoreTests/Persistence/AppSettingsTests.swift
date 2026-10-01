import FPCore
import Foundation
import Testing

struct AppSettingsTests {
    @Test func normalizedDropsInvalidValues() throws {
        let defaults = AppSettings()
        #expect(defaults.appearance == .system && defaults.extraFolders.isEmpty && defaults.previewPointSize == 30)
        #expect(!defaults.colourByFont && defaults.lastSaveDirectory == nil && !defaults.legacyImportDone)
        var settings = defaults
        settings.extraFolders = ["D:/Fonts", "/nope", "/Fonts", "/Fonts/"]
        settings.previewPointSize = 200; settings.lastSaveDirectory = "/gone"
        let result = settings.normalized(using: FakeFileSystem(directories: ["/Fonts"]))
        #expect(result.settings.extraFolders == ["/Fonts"] && result.settings.previewPointSize == 30)
        #expect(result.settings.lastSaveDirectory == nil)
        #expect(
            result.issues == [
                .droppedFolder("D:/Fonts", .windowsPath), .droppedFolder("/nope", .missing),
                .previewSizeReset(200), .lastSaveDirectoryDropped("/gone", .missing),
            ])
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)) == settings)
        var valid = result.settings; valid.lastSaveDirectory = "/Fonts/../Fonts/"
        #expect(valid.normalized(using: FakeFileSystem(directories: ["/Fonts"])).settings.lastSaveDirectory == "/Fonts")
    }
}
