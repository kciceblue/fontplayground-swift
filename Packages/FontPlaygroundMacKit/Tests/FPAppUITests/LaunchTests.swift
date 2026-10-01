import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct LaunchTests {
    @Test func startReturnsBeforeScanFinishes() async throws {
        let rig = try ShellRig(), m = AppModel(services: rig.services); defer { m.prepareForTermination() }
        await m.start();
        await shellEventually { await rig.catalog.refreshModes.count == 1 && rig.engine.helloCalls == 1 }
        #expect(m.launchPhase == .loadingFonts)
        #expect(await rig.catalog.folderCalls == [[]])
        #expect(await rig.catalog.refreshModes == [.incremental])
        #expect(await rig.catalog.callOrder == ["folders", "refresh"])
        #expect(await rig.catalog.startObservingCalls == 0)
        #expect(rig.writer.count(m.services.paths.lastRecipe) == 0)
        await m.start(); #expect(rig.engine.helloCalls == 1)
    }
    @Test func sweepsOnlyOldBuildsAndHelperLeftovers() async throws {
        let rig = try ShellRig(); var s = rig.services; let now = Date(timeIntervalSince1970: 1_700_000_000);
        s.now = { now }
        let paths = s.paths, old = paths.builds.appending(path: "forged-old.ttf"),
            young = paths.builds.appending(path: "forged-young.ttf"), other = paths.builds.appending(path: "keep.ttf"),
            outside = rig.temp.url.appending(path: "forged-outside.ttf")
        for (url, age) in [(old, 660.0), (young, 300.0), (other, 660.0), (outside, 660.0)] {
            try rig.temp.write("font", to: url);
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
        }
        let m = AppModel(services: s); await m.start(); defer { m.prepareForTermination() }
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(
            [young, other, outside, paths.helperTemp, paths.builds].allSatisfy {
                FileManager.default.fileExists(atPath: $0.path)
            })
        #expect(
            rig.sweep.calls.count == 1 && rig.sweep.calls[0].0 == paths.helperTemp
                && rig.sweep.calls[0].1 == [paths.builds] && rig.sweep.calls[0].2 == now)
    }
    @Test func engineUnavailableIsNonfatal() async throws {
        let rig = try ShellRig(); rig.engine.helloResult = .failure(.helperNotFound(searched: []));
        let m = AppModel(services: rig.services); defer { m.prepareForTermination() }
        await m.start();
        await shellEventually { await rig.catalog.refreshModes.count == 1 && rig.engine.helloCalls == 1 }
        await rig.catalog.failRefresh(CatalogError.engineUnavailable("x"));
        await shellEventually { m.launchPhase == .ready }
        #expect(m.notices.contains { $0.kind == .engineUnavailable })
        #expect(m.engineStatus == .unavailable("its files are missing from the app"))
        #expect(!m.commandState.canRescan)
    }
    @Test func systemEventsUpdateContrastAndClearBadge() async throws {
        let rig = try ShellRig(), m = AppModel(services: rig.services); await m.start();
        defer { m.prepareForTermination() }
        rig.system.increaseContrast = true; rig.system.send(.displayOptionsChanged); rig.system.send(.didBecomeActive)
        await shellEventually { m.increaseContrast && !rig.system.badges.isEmpty }
        #expect(rig.system.badges.last! == nil)
    }
    @Test func catalogSnapshotMapsEveryPublicStatusField() throws {
        let rig = try ShellRig(), model = AppModel(services: rig.services), face = ShellFaces.make()
        var snapshot = ShellSnapshot.make(
            faces: [face], isComplete: false, scanning: true,
            issues: [
                .unreadable(path: "/bad.ttf", code: "unreadable", message: "broken"),
                .folderMissing(folder: "/missing"), .folderUnreadable(folder: "/folder", message: "denied"),
            ])
        snapshot.counts.hiddenFaces = 4; snapshot.counts.duplicateFaces = 3
        model.receiveSnapshot(snapshot)
        #expect(model.catalogFaces == [face])
        #expect(model.catalogStatus.isScanning && model.catalogStatus.done == 1 && model.catalogStatus.total == 2)
        #expect(
            model.catalogStatus.faceCount == 1 && model.catalogStatus.hiddenCount == 4
                && model.catalogStatus.duplicateCount == 3)
        #expect(model.catalogStatus.unreadable == [.init(path: "/bad.ttf", message: "broken")])
        #expect(model.folderIssues.count == 2)
        model.receiveSnapshot(ShellSnapshot.make(generation: 2))
        #expect(model.catalogStatus == CatalogStatus() && model.folderIssues.isEmpty)
    }

}
