import FPCore
import Foundation
import Testing

@testable import FPAppUI

extension BuildFlowIntegration {
    @MainActor struct SaveCopyTests {
        @Test("UI-9: Save a Copy uses a sheet request with TTF") func ui9SaveACopyUsesASheetWithTTF() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }
            r.panels.saveAnswers = [nil]; r.build.saveCopy(); await shellEventually { r.panels.saveRequests.count == 1 }
            #expect(r.engine.forgeRequests.isEmpty)
            let request = try #require(r.panels.saveRequests.first)
            #expect(request.suggestedFileName == "Test Mix-Regular.ttf" && request.allowedExtension == "ttf")
            #expect(request.directory == r.model.services.paths.documents)
            let folder = r.temp.url.appendingPathComponent("copies"), url = folder.appendingPathComponent("Mine.ttf")
            r.probe.set(folder, .directory); try await r.save(url)
            #expect(try Data(contentsOf: url) == Data(contentsOf: try #require(r.build.result?.url)))
            #expect(r.writer.count(url) == 1)
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Mine.ttf"])
            #expect(
                r.bar.status == "Saved to " + url.path && r.bar.links == [.showInFinder, .openInFontBook, .notes(1)])
            try await r.save(folder.appendingPathComponent("Next"))
            #expect(r.panels.saveRequests.last?.directory.path == folder.path)
            #expect(r.build.savedURL == folder.appendingPathComponent("Next.ttf"))
            try await r.save(folder.appendingPathComponent("Last.TTF"));
            #expect(r.build.savedURL?.lastPathComponent == "Last.TTF")
            #expect(r.engine.forgeRequests.count == 1)
        }
        @Test func aChangeAfterSavingNoLongerSaysSaved() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() };
            try await r.save(r.temp.url.appendingPathComponent("Mine.ttf"))
            r.model.edit { $0.setStyle("Bold", byUser: true) }
            #expect(r.bar.status == BuildText.idle && r.bar.links.isEmpty)
        }
        @Test func saveErrorsFailPlainly() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; try await r.forge()
            r.writer.error = ShellTestError("the disk is full");
            r.panels.saveAnswers = [r.temp.url.appendingPathComponent("Mine.ttf")]
            r.build.saveCopy(); await r.failed(); #expect(r.bar.status == "Couldn't save the font: the disk is full")
        }
        @Test("UI-M7: Font Book can install a saved copy") func uiM7OpenInFontBookAfterSaving() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; let url = r.temp.url.appendingPathComponent("Mine.ttf")
            try await r.save(url); r.build.openInFontBook(); #expect(r.system.openedInFontBook == [url])
            r.system.isFontBookAvailable = false
            #expect(!r.bar.links.contains(.openInFontBook) && !r.build.commands.canOpenInFontBook)
            r.build.openInFontBook(); #expect(r.system.openedInFontBook == [url])
        }
    }

}
