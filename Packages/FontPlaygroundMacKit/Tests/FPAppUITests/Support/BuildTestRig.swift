import FPCore
import FPEngineClient
import FPMacServices
import Foundation
import Testing

@testable import FPAppUI

@MainActor final class BuildTestRig {
    let temp: ShellTempDirectory
    let engine = ShellFakeEngine(), catalog = ShellFakeCatalog(), installer = ShellFakeInstaller()
    let system = ShellFakeSystemActions(), panels = ShellFakeFilePanels()
    let writer = ShellFileWriter(), probe = ShellFakeFileProbe()
    let model: AppModel
    var build: BuildController { model.build }
    var bar: ActionBarState { build.actionBarState }
    init() throws {
        temp = try ShellTempDirectory()
        var services = AppServices.testing(root: temp.url, defaults: temp.defaults, catalog: catalog)
        services.engine = engine; services.installer = installer; services.system = system; services.panels = panels
        services.writeFile = { [writer] in try writer.write($0, to: $1) }; services.fileProbe = probe
        model = AppModel(services: services)
        model.edit { recipe in
            recipe.add(ShellFaces.make(path: temp.url.appendingPathComponent("A.ttf").path, text: "abc1,"))
            recipe.add(
                ShellFaces.make(
                    "Fixture B", style: "Bold", path: temp.url.appendingPathComponent("B.ttf").path, text: "ab漢，"))
            for material in recipe.materials {
                var face = material.face; face.licence.licenceClass = .open;
                recipe.replace(material.key, with: face, keepAdjustments: true)
            }
            recipe.setFamily("Test Mix", byUser: true); recipe.setStyle("Regular", byUser: true)
        }
    }
    func cleanup() { model.prepareForTermination() }
    func report(warnings: [String] = ["one note"], licences: [ForgeReport.LicenceNote] = []) -> ForgeReport {
        .init(
            outputPath: engine.forgeRequests.last?.outputPath ?? "", familyName: model.recipe.names.family,
            styleName: model.recipe.names.style,
            postscriptName: Naming.postscriptName(family: model.recipe.names.family, style: model.recipe.names.style),
            fullName: model.recipe.names.family + " " + model.recipe.names.style, totalCodepoints: 7, totalGlyphs: 8,
            licenceNotes: licences, warnings: warnings)
    }
    func font(style: String = "Regular") -> InstalledFont {
        .init(
            fileURL: model.services.paths.userFonts.appendingPathComponent("Test Mix-\(style).ttf"),
            family: "Test Mix", style: style, fullName: "Test Mix \(style)",
            postscriptName: Naming.postscriptName(family: "Test Mix", style: style), sha256: "test", size: 4,
            installedAt: Date(timeIntervalSince1970: 0))
    }
    func startInstall() async {
        await installer.scriptInstall(.success(font(style: model.recipe.names.style)))
        let before = engine.forgeRequests.count
        build.install(); await shellEventually { self.engine.forgeRequests.count == before + 1 }
    }
    func finishInstall(warnings: [String] = ["one note"]) async throws {
        try engine.finish(report: report(warnings: warnings)); await shellEventually { self.build.state == .installed }
    }
    func install() async throws { await startInstall(); try await finishInstall() }
    func forge() async throws {
        let count = engine.forgeRequests.count
        build.build(); await shellEventually { self.engine.forgeRequests.count == count + 1 }
        try engine.finish(report: report()); await shellEventually { self.build.state == .built }
    }
    func save(_ url: URL) async throws {
        let wasFresh = build.isFresh, count = engine.forgeRequests.count
        panels.saveAnswers = [url]; build.saveCopy()
        if !wasFresh {
            await shellEventually { self.engine.forgeRequests.count == count + 1 }; try engine.finish(report: report())
        }
        await shellEventually { self.build.state == .saved && self.build.savedURL == SaveCopy.enforcingExtension(url) }
    }
    func failed() async { await shellEventually { if case .failed = self.build.state { true } else { false } } }
    func click(_ index: Int) throws {
        let alert = try #require(model.alert); model.alert = nil; alert.buttons[index].action()
    }
}

@Suite(.serialized) struct BuildFlowIntegration {}
