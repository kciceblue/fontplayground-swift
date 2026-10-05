import FPCore
import FPEngineClient
import FPMacServices
import Foundation
import Testing

@testable import FPAppUI

extension BuildFlowIntegration {
    @MainActor struct BuildControllerTests {
        @Test func namesAreTwoWay() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }
            ActionBarView.familyBinding(r.model).wrappedValue = "Mine"
            ActionBarView.styleBinding(r.model).wrappedValue = "Two"
            #expect(r.model.recipe.names.family == "Mine" && r.model.recipe.names.familyEdited)
            #expect(r.model.recipe.names.style == "Two" && r.model.recipe.names.styleEdited)
            r.model.edit { $0.setFamily("Other", byUser: true) }
            #expect(ActionBarView.familyBinding(r.model).wrappedValue == "Other")
            await r.startInstall(); ActionBarView.familyBinding(r.model).wrappedValue = "Blocked"
            #expect(r.model.recipe.names.family == "Other"); await r.build.cancelAndWait()
        }
        @Test func buildingShowsProgressAndLocksTheNames() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; r.model.openPicker(.init(languageID: "any"))
            await r.startInstall()
            #expect(r.model.isBuilding && r.model.pickRequest == nil)
            #expect(r.bar.primaryTitle == "Installing…" && !r.bar.primaryEnabled)
            #expect(r.bar.status == "Building your font — starting…")
            r.engine.emitProgress(.prepare, 0.4, materialIndex: 1)
            await shellEventually { r.bar.progress == 0.4 }
            #expect(r.bar.status == "Building your font — preparing Fixture B Bold…")
            #expect(r.bar.showsCancel && r.bar.cancelEnabled && !r.bar.showsSaveCopy && !r.bar.namesEditable)
            #expect(!r.model.edit { $0.setStyle("No", byUser: true) }); await r.build.cancelAndWait()
        }
        @Test func savingShowsSaving() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }
            r.panels.saveAnswers = [r.temp.url.appendingPathComponent("x.ttf")]; r.build.saveCopy()
            await shellEventually { !r.engine.forgeRequests.isEmpty }
            #expect(r.bar.primaryTitle == "Saving…"); await r.build.cancelAndWait()
        }
        @Test func cancelStopsTheBuild() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; await r.startInstall()
            let output = try #require(r.engine.forgeRequests.first?.outputPath)
            try AtomicFile.write(Data([1]), to: output)
            r.build.cancel(); #expect(r.bar.status == "Building your font — stopping…"); #expect(!r.bar.cancelEnabled)
            r.engine.emitProgress(.merge, 0.9)
            await shellEventually { r.build.state == .cancelled }
            #expect(r.engine.cancelled && !r.model.isBuilding && !FileManager.default.fileExists(atPath: output))
            #expect(r.bar.status == "Cancelled." && r.bar.primaryTitle == "Install")
            #expect(await r.installer.installs.isEmpty)
        }
        @Test("Review M1: Stop returns while the helper is still stopping")
        func reviewM1StopDoesNotWaitOnTheMainThread() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; r.engine.terminationDelay = 0.5
            await r.startInstall()
            let start = ContinuousClock.now; r.build.cancel()
            #expect(start.duration(to: .now) < .milliseconds(100))
            #expect(r.bar.status == "Building your font — stopping…")
            await shellEventually { r.build.state == .cancelled }
            #expect(r.engine.cancelled && !r.model.isBuilding)
        }
        @Test func installIsIgnoredWhileBusyOrInvalid() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; await r.startInstall()
            r.build.install(); r.build.saveCopy(); await Task.yield()
            #expect(r.engine.forgeRequests.count == 1); #expect(await r.installer.queries.count == 1)
            #expect(r.panels.saveRequests.isEmpty); await r.build.cancelAndWait()
            r.model.edit { $0 = Recipe() }; r.build.install(); r.build.saveCopy(); await Task.yield()
            #expect(await r.installer.queries.count == 1); #expect(r.panels.saveRequests.isEmpty)
            let offline = try ShellRig(); let model = AppModel(services: offline.services)
            defer { model.prepareForTermination() }
            model.edit { $0.add(ShellFaces.make()) };
            offline.engine.helloResult = .failure(.helperNotFound(searched: []))
            await model.start();
            await shellEventually { if case .unavailable = model.engineStatus { true } else { false } }
            model.build.install(); model.build.saveCopy(); await Task.yield()
            #expect(offline.engine.forgeRequests.isEmpty)
            #expect((model.services.panels as? ShellFakeFilePanels)?.saveRequests.isEmpty == true)
        }
        @Test("INSTALL-6: installing builds once and updates the catalog")
        func install6BuildsThenInstallsUnderTheFontName()
            async throws
        {
            let r = try BuildTestRig(); defer { r.cleanup() }
            let order = BuildOrderRecorder()
            await r.installer.observeConflict { [engine = r.engine] in order.record(engine.forgeRequests.count) }
            await r.startInstall()
            #expect(order.counts == [0])
            #expect(
                await r.installer.queries == [
                    .init(
                        family: "Test Mix", style: "Regular",
                        postscriptName: Naming.postscriptName(family: "Test Mix", style: "Regular"))
                ])
            let request = try #require(r.engine.forgeRequests.first), url = URL(fileURLWithPath: request.outputPath)
            #expect(url.deletingLastPathComponent().path == r.model.services.paths.builds.path)
            #expect(
                url.lastPathComponent.range(of: #"^forged-[0-9a-f-]{36}\.ttf$"#, options: .regularExpression) != nil)
            #expect(request == r.model.recipe.forgeRequest(outputPath: request.outputPath))
            try await r.finishInstall()
            let calls = await r.installer.installs
            #expect(calls.count == 1 && calls[0].0 == url && calls[0].2 == nil)
            #expect(calls[0].1.fullName == "Test Mix Regular")
            #expect(r.bar.status == "Installed as “Test Mix Regular”.")
            #expect(
                r.bar.detailLines.first
                    == "Choose it in any app's font list — apps that were already open may need to be reopened.")
            #expect(r.bar.links == [.showInFinder, .uninstall, .notes(1)])
            #expect(r.bar.primaryTitle == "Installed" && !r.bar.primaryEnabled && r.bar.primaryIsDone)
            #expect(r.model.builtFont?.url == url); #expect(await r.catalog.installedCalls == [r.font().fileURL])
        }
        @Test func catalogRefreshFailureDoesNotHideTheInstalledFont() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }
            await r.catalog.scriptNoteInstalledError(ShellTestError("scan failed"))
            try await r.install()
            #expect(r.build.state == .installed && r.build.installed?.font == r.font())
            #expect(
                r.model.notices.contains {
                    $0.text == "The font is installed, but Font Playground couldn't refresh its font list: scan failed"
                })
        }
        @Test func aFreshResultInstallsAtOnce() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; try await r.forge()
            await r.installer.scriptInstall(.success(r.font())); r.build.install()
            await shellEventually { r.build.state == .installed }; #expect(r.engine.forgeRequests.count == 1)
        }
        @Test func aNewResultTheControllerDidNotInstallIsAnUpdate() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; try await r.install(); try await r.forge()
            #expect(r.bar.primaryTitle == "Update Installed Font" && r.bar.primaryEnabled)
        }
        @Test func aChangeOffersAnUpdate() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; try await r.install()
            r.model.edit { $0.setAdjustments(for: $0.keys[1], weight: 600, scale: nil) }
            #expect(r.build.state == .installed && r.bar.primaryTitle == "Update Installed Font")
            #expect(r.model.builtFont?.isStale(for: r.model.recipe) == true)
            await r.installer.scriptConflicts([.replaceOurs(r.font())]); await r.startInstall();
            #expect(r.model.alert == nil)
            try await r.finishInstall(); let calls = await r.installer.installs
            #expect(calls.count == 2 && calls.last?.2 == .replaceOurs(r.font()))
            #expect(await r.installer.uninstalls.isEmpty); #expect(r.bar.primaryTitle == "Installed")
        }
        @Test func updatingUnderANewNameRemovesTheOldFont() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; try await r.install()
            r.model.edit { $0.setStyle("Bold", byUser: true) }; await r.startInstall(); try await r.finishInstall()
            #expect(await r.installer.uninstalls == [r.font()]);
            #expect(await r.catalog.removedCalls == [r.font().fileURL])
            #expect(r.build.installed?.font.fullName == "Test Mix Bold")
        }
        @Test func oldFontThatCannotBeRemovedStaysOnRecord() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; try await r.install()
            r.model.edit { $0.setStyle("Bold", byUser: true) }
            await r.installer.scriptUninstall(.failure(ShellTestError("access denied"))); await r.startInstall()
            try r.engine.finish(report: r.report()); await r.failed()
            #expect(r.bar.status == "Installed “Test Mix Bold”, but couldn't remove “Test Mix Regular”: access denied")
            #expect(
                r.build.installed?.font.fullName == "Test Mix Bold" && r.bar.primaryTitle == "Update Installed Font")
            await r.installer.scriptUninstall(.success(.notInstalled)); r.build.install()
            await shellEventually { r.build.state == .installed }
            #expect(await r.installer.uninstalls.count == 2); #expect(await r.installer.installs.count == 2)
            #expect(r.engine.forgeRequests.count == 2)
        }
        @Test func anotherUpdateNeverForgetsAPendingRemoval() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; try await r.install()
            r.model.edit { $0.setStyle("Bold", byUser: true) }
            await r.installer.scriptUninstall(.failure(ShellTestError("busy"))); await r.startInstall()
            try r.engine.finish(report: r.report()); await r.failed()
            r.model.edit { $0.setStyle("Heavy", byUser: true) }; r.build.install()
            await shellEventually { await r.installer.uninstalls.count == 2 }
            #expect(r.build.pendingRemoval == r.font())
            #expect(r.engine.forgeRequests.count == 2)
            await r.installer.scriptUninstall(.success(.notInstalled)); await r.startInstall();
            try await r.finishInstall()
            #expect(await r.installer.uninstalls == [r.font(), r.font(), r.font(), r.font(style: "Bold")])
            #expect(r.build.pendingRemoval == nil && r.build.installed?.font.fullName == "Test Mix Heavy")
        }
        @Test func previousCopyNotRemovedIsReported() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; try await r.forge()
            let new = r.font(), old = r.font(style: "Old")
            await r.installer.scriptInstall(
                .failure(InstallError.previousCopyNotRemoved(installed: new, previous: old, message: "busy")))
            r.build.install(); await r.failed()
            #expect(r.build.installed?.font == new && r.build.pendingRemoval == old)
            #expect(r.bar.status == "Installed “Test Mix Regular”, but couldn't remove “Test Mix Old”: busy")
        }
        @Test func installErrorsFailPlainly() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; try await r.forge()
            await r.installer.scriptInstall(
                .failure(InstallError.fileSystem(operation: "copy", message: "the font folder is locked")))
            r.build.install(); await r.failed();
            #expect(r.bar.status == "Couldn't install the font: the font folder is locked")
            #expect(r.build.installed == nil && r.bar.tone == .danger)
            await r.installer.scriptInstall(.success(r.font())); r.build.install()
            await shellEventually { r.build.state == .installed }; #expect(r.engine.forgeRequests.count == 1)
        }
        @Test func aFailedBuildSaysWhy() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; await r.startInstall()
            r.engine.fail(
                .helperFailed(
                    .init(
                        code: .mergeFailed, stage: .merge, materialIndex: nil, message: "the fonts disagree",
                        detail: "Traceback…")))
            await r.failed(); #expect(r.bar.status == "Couldn't build the font: the fonts disagree")
            #expect(r.bar.tone == .danger && r.bar.links == [.details]); #expect(r.build.result == nil)
            r.build.showReport();
            if case .report(let text) = r.model.sheet {
                #expect(text.contains("Traceback…") && text.hasPrefix(r.bar.status))
            } else {
                Issue.record("No report")
            }
            let materials = r.model.recipe.materials
            for index in [0, nil] {
                let failure = EngineError.helperFailed(
                    .init(code: .staleMaterial, stage: .validate, materialIndex: index, message: "changed", detail: nil)
                )
                #expect(
                    EngineErrorText.buildFailure(failure, materials: materials).message
                        == (index == nil ? BuildText.staleUnknown : BuildText.staleMaterial("Fixture A Regular")))
            }
            for error in [
                EngineError.crashed(exitCode: 1, signal: nil, stderrTail: "boom"),
                .timedOut(after: .seconds(1), stderrTail: "slow"),
            ] {
                await r.startInstall(); r.engine.fail(error); await r.failed()
                #expect(
                    r.bar.status
                        == BuildText.buildError(
                            { if case .timedOut = error { BuildText.timedOut } else { BuildText.engineStopped } }()))
            }
            await r.startInstall(); r.engine.endWithoutResult(); await r.failed()
            #expect(r.bar.status == "Couldn't build the font: the font engine stopped unexpectedly.")
            try await r.forge(); r.build.showReport();
            #expect(r.model.sheet == .report(ReportText.render(try #require(r.build.lastReport))))
        }
        @Test func uninstallMovesToTheTrashAndSaysSo() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; try await r.install()
            await r.installer.scriptUninstall(.success(.movedToTrash(nil))); r.build.uninstall()
            await shellEventually { r.build.state == .idle }
            #expect(r.bar.status == "Removed from your fonts — it's in the Trash." && r.bar.tone == .muted)
            #expect(r.bar.links.isEmpty && r.bar.primaryEnabled);
            #expect(await r.catalog.removedCalls == [r.font().fileURL])
            r.build.install(); await shellEventually { r.build.state == .installed };
            #expect(r.engine.forgeRequests.count == 1)
            await r.installer.scriptUninstall(.success(.notInstalled)); r.build.uninstall()
            await shellEventually { r.build.state == .idle };
            #expect(r.bar.status == "That font was no longer installed.")
            r.build.uninstall(); await Task.yield(); #expect(await r.installer.uninstalls.count == 2)
            r.build.install(); await shellEventually { r.build.state == .installed }
            await r.installer.scriptUninstall(.failure(InstallError.notOurs(name: "Test Mix Regular")));
            r.build.uninstall(); await r.failed()
            #expect(
                r.bar.status
                    == "Couldn't remove the font: Font Playground didn't install “Test Mix Regular”, so it won't remove it"
            )
            #expect(r.build.installed != nil)
        }
        @Test func uninstallResolvesThePendingOldFontBeforeTheCurrentFont() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; try await r.install()
            r.model.edit { $0.setStyle("Bold", byUser: true) }
            await r.installer.scriptUninstall(.failure(ShellTestError("access denied"))); await r.startInstall()
            try r.engine.finish(report: r.report()); await r.failed()
            await r.installer.scriptUninstall(.failure(ShellTestError("still busy"))); r.build.uninstall()
            let failure = "Installed “Test Mix Bold”, but couldn't remove “Test Mix Regular”: still busy"
            await shellEventually { r.build.state == .failed(message: failure) }
            #expect(r.build.pendingRemoval == r.font() && r.build.installed?.font == r.font(style: "Bold"))
            #expect(r.bar.status == failure && r.build.lastErrorDetail?.contains(failure) == true)
            #expect(await r.installer.uninstalls == [r.font(), r.font()])
            #expect(await r.catalog.removedCalls.isEmpty)
            await r.installer.scriptUninstall(.success(.movedToTrash(nil))); r.build.uninstall()
            await shellEventually { r.build.state == .idle }
            #expect(await r.installer.uninstalls == [r.font(), r.font(), r.font(), r.font(style: "Bold")])
            #expect(await r.catalog.removedCalls == [r.font().fileURL, r.font(style: "Bold").fileURL])
            #expect(r.build.installed == nil && r.build.pendingRemoval == nil && r.build.lastErrorDetail == nil)
            #expect(r.bar.status == "Removed from your fonts — it's in the Trash.")
            #expect(r.build.isFresh && r.engine.forgeRequests.count == 2)
        }
        @Test("INSTALL-13 / UI-11: Show in Finder reveals the file") func install13ShowInFinderRevealsTheFile()
            async throws
        {
            let r = try BuildTestRig(); defer { r.cleanup() }; try await r.install(); r.build.showInFinder()
            #expect(r.system.revealed == [[r.font().fileURL]])
            let saved = r.temp.url.appendingPathComponent("Copy.ttf"); try await r.save(saved); r.build.showInFinder()
            #expect(r.system.revealed.last == [saved]); try FileManager.default.removeItem(at: saved);
            r.build.showInFinder()
            #expect(r.build.notice == "That file is no longer there." && r.system.revealed.count == 2)
            #expect(r.bar.status == "That file is no longer there." && r.bar.tone == .muted)
            try AtomicFile.write(Data([1]), to: saved.path); r.build.showInFinder()
            #expect(r.build.notice == nil && r.system.revealed.count == 3)
        }
        @Test func resetForgetsEverything() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; try await r.install(); r.build.uninstall()
            await shellEventually { r.build.state == .idle }; r.build.install();
            await shellEventually { r.build.state == .installed }
            let url = try #require(r.build.result?.url); r.build.reset()
            #expect(
                r.build.state == .idle && r.build.result == nil && r.build.installed == nil
                    && r.build.pendingRemoval == nil
            )
            #expect(
                r.build.savedURL == nil && r.build.notice == nil && r.build.lastReport == nil
                    && r.build.lastErrorDetail == nil)
            #expect(r.model.builtFont == nil && !FileManager.default.fileExists(atPath: url.path))
            #expect(FileManager.default.fileExists(atPath: r.font().fileURL.path))
        }
        @Test func startOverDuringABuildStaysIdle() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; await r.startInstall()
            r.build.reset(); try r.engine.finish(report: r.report()); await Task.yield()
            await shellEventually {
                (try? FileManager.default.contentsOfDirectory(atPath: r.model.services.paths.builds.path))?.isEmpty
                    == true
            }
            #expect(r.build.state == .idle && r.build.result == nil)
        }
        @Test func cancelAndWaitStopsTheBuildForQuit() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; await r.startInstall()
            let url = try #require(r.engine.forgeRequests.first?.outputPath); try AtomicFile.write(Data([1]), to: url)
            let clock = ContinuousClock(), start = ContinuousClock.now; await r.build.cancelAndWait()
            #expect(clock.now - start < .seconds(3));
            #expect(!r.model.isBuilding && !FileManager.default.fileExists(atPath: url))
        }
    }
    private final class BuildOrderRecorder: @unchecked Sendable {
        private let lock = NSLock(); private var values: [Int] = []
        var counts: [Int] { lock.withLock { values } }
        func record(_ n: Int) { lock.withLock { values.append(n) } }
    }

}
