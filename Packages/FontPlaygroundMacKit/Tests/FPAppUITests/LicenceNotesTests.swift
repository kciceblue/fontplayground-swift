import FPCore
import Testing

@testable import FPAppUI

extension BuildFlowIntegration {
    @MainActor struct LicenceNotesTests {
        @Test func adr12LinesPerNonOpenClass() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }
            func licence(_ index: Int, _ value: FaceRecord.Licence.LicenceClass) {
                r.model.edit { recipe in
                    let key = recipe.keys[index]; var face = recipe.materials[index].face;
                    face.licence.licenceClass = value
                    recipe.replace(key, with: face, keepAdjustments: true)
                }
            }
            #expect(r.build.licenceLines.isEmpty)
            licence(0, .appleSLA); #expect(r.bar.detailLines == [BuildText.appleSLA])
            r.panels.saveAnswers = [nil]; r.build.saveCopy(); await shellEventually { !r.panels.saveRequests.isEmpty }
            #expect(r.panels.saveRequests.last?.message == BuildText.appleSLA)
            licence(1, .unknown); #expect(r.build.licenceLines == [BuildText.appleSLA, BuildText.unknownLicence])
            r.build.build(); await shellEventually { !r.engine.forgeRequests.isEmpty }
            try r.engine.finish(
                report: r.report(licences: [.init(licenceClass: "microsoft-product", materialIndexes: [0], text: "M")]))
            await shellEventually { r.build.state == .built }; #expect(r.build.licenceLines == ["M"])
            r.model.edit { $0.setStyle("Bold", byUser: true) }
            #expect(r.build.licenceLines == [BuildText.appleSLA, BuildText.unknownLicence])
        }
    }

}
