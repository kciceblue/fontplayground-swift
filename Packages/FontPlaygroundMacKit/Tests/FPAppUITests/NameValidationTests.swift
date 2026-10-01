import FPCore
import Foundation
import Testing

@testable import FPAppUI

extension BuildFlowIntegration {
    @MainActor struct NameValidationTests {
        @Test("UI-M3: names that macOS would hide are rejected") func uiM3NamesThatMacOSWouldHideAreRejected()
            async throws
        {
            let cases = [
                (
                    ".MyFont", "Regular",
                    "Family name can't start with “.”: macOS hides fonts whose names start with a dot."
                ),
                ("Test", ".Bold", "A style name can't start with a dot."),
                (String(repeating: "a", count: 64), "Regular", "Use a font name of at most 63 characters."),
                ("Test", String(repeating: "a", count: 64), "Use a style name of at most 63 characters."),
                ("A\u{0007}", "Regular", "Family name contains a control character."),
            ]
            for (family, style, message) in cases {
                let r = try BuildTestRig(); defer { r.cleanup() }
                r.model.edit {
                    $0.setFamily(family, byUser: true); $0.setStyle(style, byUser: true)
                }
                #expect(r.bar.status == message); #expect(!r.bar.primaryEnabled && !r.bar.saveCopyEnabled)
                r.build.install(); r.build.saveCopy(); await Task.yield()
                #expect(await r.installer.queries.isEmpty); #expect(r.panels.saveRequests.isEmpty)
            }
            #expect(NameValidation.problem(family: "A\u{0007}", style: "Regular") == nil)
            #expect(NameValidation.problem(family: String(repeating: "a", count: 63), style: "Regular") == nil)
            #expect(NameValidation.problem(family: String(repeating: "e\u{301}", count: 63), style: "Regular") == nil)
        }
        @Test("UI-M3: suggested file names never start with a dot") func uiM3SuggestedFileNameNeverStartsWithADot()
            throws
        {
            let r = try BuildTestRig(); defer { r.cleanup() }
            r.model.edit { $0.setFamily(".Apple SD Gothic NeoI Forged", byUser: true) }
            let request = SaveCopy.request(
                for: r.model.recipe, settings: r.model.settings.value, paths: r.model.services.paths, probe: r.probe)
            #expect(request.suggestedFileName == "Apple SD Gothic NeoI Forged-Regular.ttf")
        }
    }

}
