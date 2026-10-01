import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct RestoreTests {
    func save(_ recipe: Recipe, rig: ShellRig) throws {
        try AtomicFile.write(RecipeDocument(recipe: recipe).encoded(), to: rig.services.paths.lastRecipe.path)
    }
    @Test func recipeIsRestoredAfterFirstRefresh() async throws {
        let rig = try ShellRig(), a = ShellFaces.make(), b = ShellFaces.make("B", path: "/fixture/B.ttf")
        var r = Recipe(); r.add(a); r.add(b); r.setPin(.han, to: b.key); r.setSampleText("mine 你好");
        try save(r, rig: rig)
        let m = AppModel(services: rig.services); defer { m.prepareForTermination() };
        await rig.ready(m, faces: [a, b])
        #expect(m.recipe == r && m.notices.isEmpty)
        await shellEventually { await rig.catalog.startObservingCalls == 1 }
    }
    @Test("CRIT-2: unresolved fonts stay and CRIT-3 replacements require a click")
    func crit2UnresolvedFontsStayAndAreReported() async throws {
        let rig = try ShellRig(), a = ShellFaces.make("Georgia", path: "/old/G.ttf"),
            missing = ShellFaces.make("Microsoft YaHei", path: "/old/Y.ttf"),
            replacement = ShellFaces.make("PingFang SC", path: "/new/P.ttc")
        var moved = a; moved.path = "/new/G.ttf"; var r = Recipe(); r.add(a); r.add(missing); try save(r, rig: rig)
        let m = AppModel(services: rig.services); defer { m.prepareForTermination() };
        await rig.ready(m, faces: [moved, replacement])
        #expect(m.recipe.materials[0].face == moved && m.recipe.materials[1].availability == .notFound)
        let notice = try #require(m.notices.first { $0.kind == .unresolvedFonts })
        #expect(
            notice.text
                == "1 font could not be found: Microsoft YaHei Regular. Microsoft YaHei Regular isn't on this Mac. Use PingFang SC Regular instead?"
        )
        #expect(notice.replacements.count == 1); m.applyReplacement(notice.replacements[0])
        #expect(m.recipe.materials[1].face == replacement && m.notices.isEmpty)
    }
    @Test func refreshFailedSuppressesTheUnresolvedNotice() async throws {
        let rig = try ShellRig(); var r = Recipe(); r.add(ShellFaces.make());
        r.add(ShellFaces.make("B", path: "/B.ttf")); try save(r, rig: rig)
        let m = AppModel(services: rig.services); defer { m.prepareForTermination() }; await m.start();
        await shellEventually { await rig.catalog.refreshModes.count == 1 }
        await rig.catalog.failRefresh(CatalogError.engineUnavailable("x"));
        await shellEventually { m.launchPhase == .ready }
        #expect(m.recipe.materials.count == 2 && m.recipe.materials.allSatisfy { $0.availability == .notFound })
        #expect(
            m.notices.contains { $0.kind == .engineUnavailable } && !m.notices.contains { $0.kind == .unresolvedFonts })
    }
    @Test func quitBeforeRestoreKeepsTheStoredRecipe() async throws {
        let rig = try ShellRig(); var r = Recipe(); r.add(ShellFaces.make()); try save(r, rig: rig)
        let before = try Data(contentsOf: rig.services.paths.lastRecipe), m = AppModel(services: rig.services)
        await m.start(); m.prepareForTermination()
        #expect(try Data(contentsOf: rig.services.paths.lastRecipe) == before)
        #expect(rig.writer.count(rig.services.paths.lastRecipe) == 0)
    }
    @Test func damagedRecipeIsKeptAndReported() async throws {
        let rig = try ShellRig(), path = rig.services.paths.lastRecipe; let broken = "{\"materials\": \"nope\"";
        try rig.temp.write(broken, to: path)
        rig.temp.defaults.set("bad", forKey: "previewPointSize"); let m = AppModel(services: rig.services);
        defer { m.prepareForTermination() }; await rig.ready(m)
        #expect(m.recipe == Recipe() && !FileManager.default.fileExists(atPath: path.path))
        let kept = try FileManager.default.contentsOfDirectory(
            at: path.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        #expect(
            kept.count == 1
                && kept[0].lastPathComponent.range(
                    of: "^last-damaged-[0-9]{8}-[0-9]{6}\\.fontrecipe$", options: .regularExpression) != nil
        )
        #expect(try String(contentsOf: kept[0], encoding: .utf8) == broken)
        let revealed = m.notices.first { $0.kind == .damagedRecipe }?.revealURL
        #expect(revealed?.standardizedFileURL.path == kept[0].standardizedFileURL.path)
    }
    @Test func autosaveIsDebouncedAndAtomic() async throws {
        let rig = try ShellRig(), m = AppModel(services: rig.services); defer { m.prepareForTermination() };
        await rig.ready(m)
        m.edit { $0.add(ShellFaces.make()) }; m.edit { $0.setFamily("One") }; m.edit { $0.setFamily("Two") };
        m.flushAutosave()
        let path = m.services.paths.lastRecipe; #expect(rig.writer.count(path) == 1)
        m.flushAutosave(); #expect(rig.writer.count(path) == 1)
        #expect(try RecipeDocument.decode(Data(contentsOf: path)) == RecipeDocument(recipe: m.recipe))
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: path.deletingLastPathComponent().path).allSatisfy {
                !$0.hasSuffix(".tmp")
            })
        m.recipe.setSampleText("saved too"); m.flushAutosave(); #expect(rig.writer.count(path) == 2)
        rig.writer.error = ShellTestError("disk full"); m.edit { $0.setFamily("Three") }; m.flushAutosave();
        m.edit { $0.setFamily("Four") }; m.flushAutosave()
        #expect(m.notices.filter { $0.kind == .autosaveFailed }.count == 1)
    }
    @Test func legacyImportRunsOnce() async throws {
        let rig = try ShellRig(), paths = rig.services.paths; rig.probe.set(paths.legacyFolder, .directory)
        try rig.temp.write(
            #"{"theme":"dark","extra_dirs":["D:/Fonts"]}"#,
            to: paths.legacyFolder.appending(path: LegacyImport.settingsFileName))
        try rig.temp.write(
            #"{"materials":[{"path":"C:/Windows/Fonts/georgia.ttf","index":0},{"path":"C:/Windows/Fonts/simsun.ttc","index":0}]}"#,
            to: paths.legacyFolder.appending(path: LegacyImport.recipeFileName))
        let m = AppModel(services: rig.services); await m.start()
        #expect(m.settings.value.legacyImportDone && m.settings.value.appearance == .dark)
        await shellEventually { await rig.catalog.refreshModes.count == 1 }
        await rig.catalog.finishRefresh(
            with: ShellSnapshot.make(faces: [
                ShellFaces.make("Georgia"), ShellFaces.make("Songti SC", path: "/Songti.ttc"),
            ]))
        await shellEventually { m.launchPhase == .ready }
        #expect(m.recipe.materials.map(\.face.family) == ["Georgia", "SimSun"])
        #expect(m.notices.contains { $0.kind == .settingsIssues && $0.text.contains("D:/Fonts") })
        #expect(m.notices.contains { $0.kind == .unresolvedFonts && $0.text.contains("Use Songti SC Regular") })
        #expect(m.notices.contains { $0.kind == .imported }); m.prepareForTermination()
        try FileManager.default.removeItem(at: paths.lastRecipe)
        var s = rig.services; let secondCatalog = ShellFakeCatalog(); s.catalog = secondCatalog
        let next = AppModel(services: s); defer { next.prepareForTermination() }; await next.start();
        await shellEventually { await secondCatalog.refreshModes.count == 1 };
        await secondCatalog.finishRefresh(with: ShellSnapshot.make());
        await shellEventually { next.launchPhase == .ready }
        #expect(next.recipe.materials.isEmpty && next.notices.isEmpty)
    }
    @Test func unreadableLegacySettingsReportImportFailed() async throws {
        let rig = try ShellRig(); rig.probe.set(rig.services.paths.legacyFolder, .directory)
        try rig.temp.write("nope", to: rig.services.paths.legacyFolder.appending(path: LegacyImport.settingsFileName))
        let m = AppModel(services: rig.services); await m.start(); defer { m.prepareForTermination() }
        #expect(m.settings.value.legacyImportDone && m.notices.contains { $0.kind == .importFailed })
    }
    @Test("Architecture no-silent-drops: ignored portable recipe entries are reported")
    func ignoredRecipeEntriesAreCountedAndReported() async throws {
        let rig = try ShellRig(), face = ShellFaces.make()
        var recipe = Recipe(); recipe.add(face)
        var document = RecipeDocument(recipe: recipe)
        document.materials.append(document.materials[0]); document.main = 99; document.rules[.han] = 99
        try AtomicFile.write(document.encoded(), to: rig.services.paths.lastRecipe.path)
        let model = AppModel(services: rig.services); defer { model.prepareForTermination() }
        await rig.ready(model, faces: [face])
        #expect(model.recipe.materials.count == 1)
        let notice = try #require(model.notices.first { $0.kind == .restorationIssues })
        #expect(
            notice.text
                == "Some saved entries couldn't be used: 1 duplicate font entry, 1 font rule, the saved line-spacing font."
        )
        #expect(!model.notices.contains { $0.kind == .unresolvedFonts })
    }
    @Test("Architecture no-silent-drops: legacy settings and recipe omissions are reported")
    func ignoredLegacyEntriesAreCountedAndReported() async throws {
        let rig = try ShellRig(), paths = rig.services.paths, face = ShellFaces.make()
        rig.probe.set(paths.legacyFolder, .directory)
        try rig.temp.write(
            #"{"theme":"sepia","preview_size":999,"colour_by_font":1,"extra_dirs":[false]}"#,
            to: paths.legacyFolder.appending(path: LegacyImport.settingsFileName))
        try rig.temp.write(
            #"{"materials":[{"path":"/fixture/A.ttf","index":0},{"path":"/fixture/A.ttf","index":0},"bad"],"base_index":99,"script_rules":{"bogus":0},"output_path":"C:/Missing/Font.ttf","names_edited":{"output":true}}"#,
            to: paths.legacyFolder.appending(path: LegacyImport.recipeFileName))
        let model = AppModel(services: rig.services); defer { model.prepareForTermination() }
        await rig.ready(model, faces: [face])
        #expect(model.recipe.materials.count == 1 && model.settings.value.legacyImportDone)
        let notices = model.notices.filter { $0.kind == .restorationIssues }
        #expect(notices.count == 1)
        #expect(
            notices.first?.text
                == "Some saved entries couldn't be used: 4 settings, the saved output path “C:/Missing/Font.ttf”, 1 duplicate font entry, 1 invalid font entry, 1 font rule, the saved line-spacing font."
        )
    }

}
