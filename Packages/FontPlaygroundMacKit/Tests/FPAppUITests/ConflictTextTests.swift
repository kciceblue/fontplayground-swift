import FPMacServices
import Testing

@testable import FPAppUI

extension BuildFlowIntegration {
    @MainActor struct ConflictTextTests {
        @Test("INSTALL-13: conflict texts use macOS wording") func install13ConflictTextsUseMacOSWording() throws {
            let reasons: [ConflictReason] = [
                .systemHas(name: "Helvetica"), .installedForEveryone(name: "Example"),
                .youHave(name: "Example"), .internalNameInUse(postscriptName: "PS"),
                .internalNameUsedByYourFont(postscriptName: "PS", fullName: "Mine Regular"), .hiddenName,
                .appleOffersDownload(name: "Download"),
            ]
            for reason in reasons {
                for conflict in [InstallConflict.block(reason), .ask(reason)] {
                    let candidate = ConflictText.alert(for: conflict, onChangeName: {}, onConfirm: {})
                    let alert = try #require(candidate)
                    #expect(alert.title == reason.englishText)
                    let blocking: Bool = { if case .block = conflict { true } else { false } }()
                    #expect(alert.buttons.map(\.title) == (blocking ? ["Change Name"] : ["Install Anyway", "Cancel"]))
                    #expect(alert.buttons[0].isDefault)
                    #expect(alert.buttons.allSatisfy { !["Yes", "No", "OK"].contains($0.title) })
                }
            }
            let r = try BuildTestRig(); defer { r.cleanup() }
            let replacement = ConflictText.alert(for: .replaceOurs(r.font()), onChangeName: {}, onConfirm: {})
            let replace = try #require(replacement)
            #expect(replace.title == "Replace the “Test Mix Regular” you installed earlier?")
            #expect(
                replace.message == "The new font takes its place."
                    && replace.buttons.map(\.title) == ["Replace", "Cancel"])
            #expect(ConflictText.alert(for: .noConflict, onChangeName: {}, onConfirm: {}) == nil)
        }
        @Test("UI-10: conflict prompts use verb buttons") func ui10ConflictPromptsUseVerbButtons() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }
            await r.installer.scriptConflicts([.block(.systemHas(name: "Helvetica"))]); r.build.install()
            await shellEventually { r.model.alert != nil }
            #expect(r.model.alert?.title == "macOS already has a font called “Helvetica” — choose another name.")
            try r.click(0); #expect(r.build.nameFocusRequest == 1 && r.engine.forgeRequests.isEmpty)
            let conflict = InstallConflict.replaceOurs(r.font())
            await r.installer.scriptConflicts([conflict]); r.build.install();
            await shellEventually { r.model.alert != nil }
            try r.click(1); #expect(r.engine.forgeRequests.isEmpty)
            r.build.install(); await shellEventually { r.model.alert != nil };
            await r.installer.scriptInstall(.success(r.font()))
            try r.click(0); await shellEventually { r.engine.forgeRequests.count == 1 }; try await r.finishInstall()
            #expect(await r.installer.installs.last?.2 == conflict)
            r.build.reset(); let download = InstallConflict.ask(.appleOffersDownload(name: "Test Mix"))
            await r.installer.scriptConflicts([download]); r.build.install();
            await shellEventually { r.model.alert != nil }
            #expect(r.model.alert?.buttons.map(\.title) == ["Install Anyway", "Cancel"])
            #expect(r.model.alert?.message == "If that font is downloaded later, apps may confuse it with yours.")
            try r.click(0); await shellEventually { r.engine.forgeRequests.count == 2 }; try await r.finishInstall()
            #expect(await r.installer.installs.last?.2 == download)
        }
        @Test func raceDetectedByTheInstallerAsksAgain() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; try await r.forge()
            await r.installer.scriptInstall(.failure(InstallError.conflict(.block(.youHave(name: "Test Mix")))))
            r.build.install(); await shellEventually { r.model.alert != nil }
            #expect(
                r.model.alert?.title == "You already have a font called “Test Mix” installed — choose another name.")
            #expect(r.build.installed == nil && r.build.isFresh && r.build.state == .built)
        }
        @Test func conflictLookupFailuresAreSurfaced() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() };
            await r.installer.scriptConflictError(ShellTestError("registry unreadable"))
            r.build.install(); await r.failed()
            #expect(r.bar.status == "Couldn't install the font: registry unreadable" && r.engine.forgeRequests.isEmpty)
        }
        @Test func staleConfirmationDoesNotAuthorizeAnotherName() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }
            await r.installer.scriptConflicts([
                .ask(.appleOffersDownload(name: "Test Mix")), .block(.systemHas(name: "Helvetica")),
            ])
            r.build.install(); await shellEventually { r.model.alert != nil }
            r.model.edit { $0.setFamily("Helvetica", byUser: true) }; try r.click(0)
            await shellEventually { r.model.alert != nil }
            #expect(r.model.alert?.buttons.map(\.title) == ["Change Name"] && r.engine.forgeRequests.isEmpty)
        }
    }

}
