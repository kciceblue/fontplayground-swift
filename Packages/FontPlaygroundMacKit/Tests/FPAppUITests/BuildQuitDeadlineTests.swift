import FPCore
import FPMacServices
import Foundation
import Testing

@testable import FPAppUI

extension BuildFlowIntegration {
    @MainActor struct BuildQuitDeadlineTests {
        @Test func quitDeadlineAlsoBoundsAnUncooperativePreflight() async throws {
            let root = try ShellTempDirectory(), installer = BuildSuspendedInstaller()
            var services = AppServices.testing(root: root.url, defaults: root.defaults); services.installer = installer
            let model = AppModel(services: services); defer { model.prepareForTermination() }
            model.edit { $0.add(ShellFaces.make()) }; model.build.install()
            await shellEventually { await installer.waiting }
            let start = ContinuousClock.now
            await model.build.cancelAndWait()
            let elapsed = start.duration(to: .now)
            #expect(elapsed >= .milliseconds(2800) && elapsed < .seconds(3))
            #expect(!model.isBuilding)
            await installer.resume()
            await Task.yield(); #expect(model.build.result == nil)
        }
        @Test("Review M1: the quit deadline holds while the helper ignores SIGTERM")
        func reviewM1QuitDeadlineHoldsWhileTheHelperStops() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; r.engine.terminationDelay = 3.5
            await r.startInstall()
            let start = ContinuousClock.now
            await r.build.cancelAndWait()
            let elapsed = start.duration(to: .now)
            #expect(elapsed >= .milliseconds(2800) && elapsed < .seconds(3))
            #expect(!r.model.isBuilding)
        }
    }
}
private actor BuildSuspendedInstaller: FontInstalling {
    private var continuation: CheckedContinuation<InstallConflict, Never>?
    var waiting: Bool { continuation != nil }
    func conflict(for query: InstallQuery) async throws -> InstallConflict {
        await withCheckedContinuation { continuation = $0 }
    }
    func resume() { continuation?.resume(returning: .noConflict); continuation = nil }
    func install(_ source: URL, expecting query: InstallQuery, confirmed: InstallConflict?) throws -> InstalledFont {
        throw ShellTestError("Unexpected install")
    }
    func uninstall(_ font: InstalledFont) -> UninstallOutcome { .notInstalled }
    func installedFonts() -> [InstalledFont] { [] }
}
