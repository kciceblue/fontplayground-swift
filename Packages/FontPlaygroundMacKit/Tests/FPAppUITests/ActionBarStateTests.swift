import FPCore
import Foundation
import Testing

@testable import FPAppUI

extension BuildFlowIntegration {
    @MainActor struct ActionBarStateTests {
        @Test func idleOffersInstallAndACopy() throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; let s = r.bar
            #expect(s.status == "Installs in your Fonts folder — only for you, no password needed.");
            #expect(s.tone == .muted)
            #expect(s.detailLines.isEmpty); #expect(s.links.isEmpty)
            #expect(s.primaryTitle == "Install" && s.primaryEnabled && s.showsSaveCopy && s.saveCopyEnabled)
            #expect(s.progress == nil && !s.showsCancel)
        }
        @Test func anInvalidRecipeShowsTheProblem() throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; let saved = r.model.recipe
            r.model.edit { $0 = Recipe() }; #expect(r.bar.status == "Add at least one font.")
            #expect(r.bar.tone == .danger && !r.bar.primaryEnabled && !r.bar.saveCopyEnabled)
            r.model.edit { $0 = saved }; #expect(r.bar.primaryEnabled)
        }
        @Test func engineMissingDisablesBuilding() throws {
            let r = try BuildTestRig(); defer { r.cleanup() }
            let bar = ActionBarState.make(
                problem: nil, engineMissing: true, glyphWarning: nil, build: r.build.snapshot,
                licenceLines: [], fontBookAvailable: true, home: "/Users/x")
            #expect(bar.status == "Font Playground can't find its font engine. Reinstall the app.")
            #expect(bar.tone == .danger && !bar.primaryEnabled && !bar.saveCopyEnabled)
        }
        @Test func glyphWarningUsesTheWarnTone() throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; let warning = EnglishText.glyphWarning(.nearLimit)
            let bar = ActionBarState.make(
                problem: nil, engineMissing: false, glyphWarning: warning, build: r.build.snapshot,
                licenceLines: [], fontBookAvailable: true, home: "/Users/x")
            #expect(bar.status == warning && bar.tone == .warn && bar.primaryEnabled)
        }
        @Test func shortPathUsesATildeForTheHomeFolder() {
            #expect(
                ShellText.shortPath("/Users/example/Documents/X.ttf", home: "/Users/example") == "~/Documents/X.ttf")
            for path in ["/Volumes/Fonts/X.ttf", "/Users/example2/X.ttf"] {
                #expect(ShellText.shortPath(path, home: "/Users/example") == path)
            }
        }
        @Test func noNotesLinkWithoutWarnings() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; await r.startInstall();
            try await r.finishInstall(warnings: [])
            #expect(r.bar.links == [.showInFinder, .uninstall])
        }
    }

}
