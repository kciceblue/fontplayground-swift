import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct ReconcileFlowTests {
    @Test func rescanKeepsTheRecipe() async throws {
        let rig = try ShellRig(), face = ShellFaces.make(), m = AppModel(services: rig.services);
        defer { m.prepareForTermination() }; await rig.ready(m, faces: [face]); m.edit { $0.add(face) }
        let before = m.recipe; m.rescanFonts(); await shellEventually { await rig.catalog.refreshModes.count == 2 }
        #expect(await rig.catalog.refreshModes == [.incremental, .full])
        await rig.catalog.finishRefresh(with: ShellSnapshot.make(faces: [face], generation: 2));
        await shellEventually { m.handledGeneration == 2 }
        #expect(m.recipe == before && m.notices.isEmpty)
    }
    @Test("CATALOG-7: moved asset keeps the material") func catalog7MovedAssetKeepsTheMaterial() async throws {
        let rig = try ShellRig(), face = ShellFaces.make(), m = AppModel(services: rig.services);
        defer { m.prepareForTermination() }; await rig.ready(m, faces: [face]); m.edit { $0.add(face) }
        var moved = face; moved.path = "/relocated.ttf";
        await rig.catalog.publish(ShellSnapshot.make(faces: [moved], generation: 2));
        await shellEventually { m.handledGeneration == 2 }
        #expect(m.recipe.materials[0].face == moved && m.notices.isEmpty)
    }
    @Test func vanishedFontIsKeptAndReported() async throws {
        let rig = try ShellRig(), face = ShellFaces.make(), m = AppModel(services: rig.services);
        defer { m.prepareForTermination() }; await rig.ready(m, faces: [face]); m.edit { $0.add(face) }
        await rig.catalog.publish(ShellSnapshot.make(generation: 2)); await shellEventually { m.handledGeneration == 2 }
        #expect(m.recipe.materials.count == 1 && m.recipe.materials[0].availability == .fileGone)
        #expect(m.notices.first { $0.kind == .fontsUnavailable }?.text.contains(face.displayName) == true)
    }
    @Test func unavailableNoticeListsEveryFontMissingNow() async throws {
        let rig = try ShellRig(), m = AppModel(services: rig.services)
        let a = ShellFaces.make("Fixture A"), b = ShellFaces.make("Fixture B", path: "/fixture/B.ttf")
        defer { m.prepareForTermination() }; await rig.ready(m, faces: [a, b]);
        m.edit {
            $0.add(a); $0.add(b)
        }
        func notice() -> String? { m.notices.first { $0.kind == .fontsUnavailable }?.text }
        for (generation, faces, expected) in [
            (2, [b], ShellText.unavailableOne(name: a.displayName)),
            (3, [], ShellText.unavailableMany(count: 2, names: ShellText.quoted([a.displayName, b.displayName]))),
            (4, [a], ShellText.unavailableOne(name: b.displayName)),
        ] {
            await rig.catalog.publish(ShellSnapshot.make(faces: faces, generation: generation))
            await shellEventually { m.handledGeneration == generation }
            #expect(notice() == expected)
        }
        await rig.catalog.publish(ShellSnapshot.make(faces: [a, b], generation: 5))
        await shellEventually { m.handledGeneration == 5 }
        #expect(notice() == nil && m.recipe.materials.allSatisfy(\.isAvailable))
    }
    @Test func whileBuildingReconcileWaits() async throws {
        let rig = try ShellRig(), face = ShellFaces.make(), m = AppModel(services: rig.services);
        defer { m.prepareForTermination() }; await rig.ready(m, faces: [face]); m.edit { $0.add(face) }
        m.isBuilding = true; await rig.catalog.publish(ShellSnapshot.make(generation: 2));
        await shellEventually { m.deferredSnapshot != nil }
        #expect(m.recipe.materials[0].availability == .available)
        m.isBuilding = false; #expect(m.recipe.materials[0].availability == .fileGone && m.handledGeneration == 2)
        await rig.catalog.publish(ShellSnapshot.make(faces: [face], isComplete: false, generation: 3));
        await shellEventually { m.catalogFaces.count == 1 }
        #expect(m.recipe.materials[0].availability == .fileGone && m.handledGeneration == 2)
    }
    @Test func folderIssuesKeepInaccessibleFoldersVisible() async throws {
        let rig = try ShellRig(), folder = rig.temp.url.appending(path: "permission-denied");
        rig.probe.set(folder, .directory)
        rig.temp.defaults.set([folder.path], forKey: "extraFontFolders")
        let m = AppModel(services: rig.services); defer { m.prepareForTermination() }; await rig.ready(m)
        await rig.catalog.publish(ShellSnapshot.make(generation: 2, issues: [.noAccess(folder: folder.path)]))
        await shellEventually { m.folderIssues[folder.path] != nil }
        #expect(m.settings.value.extraFolders == [folder.path])
        #expect(m.folderIssues[folder.path] == CatalogIssue.noAccess(folder: folder.path).englishText)
    }
}
