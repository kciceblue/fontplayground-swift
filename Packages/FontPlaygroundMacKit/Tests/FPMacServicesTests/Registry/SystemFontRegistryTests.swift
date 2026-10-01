import Foundation
import Testing

@testable import FPMacServices

extension InstallationIntegration {
    @Suite(.serialized)
    struct SystemFontRegistryTests {
        @Test(.enabled(if: TestEnv.appleFonts)) func enumeratesWithoutNameLookups() {
            let registry = CoreTextFontRegistry()
            let start = ContinuousClock.now
            let files = registry.registeredFontFiles()
            let menu = registry.menuVisiblePostScriptNames()
            let faces = registry.registeredFaces(includeDisabled: true)
            let elapsed = start.duration(to: .now)
            #expect(files.contains { $0.path.hasSuffix("/Helvetica.ttc") && $0.postscriptNames.contains("Helvetica") })
            #expect(files.allSatisfy { $0.path.hasPrefix("/") && !$0.path.contains("#") })
            #expect(menu.contains("Helvetica") && !menu.contains("LastResort"))
            #expect(!faces.isEmpty && faces.filter { $0.path != nil }.allSatisfy { $0.priority > 0 })
            print("WP-403 registry three enumerations: \(elapsed)")
            #expect(elapsed < .seconds(0.5))
        }

        @Test func registeredFixturesAreFoundByIdentityIncludingPrivateTmpAlias() throws {
            for privateTmp in [false, true] {
                let directory =
                    privateTmp
                    ? URL(fileURLWithPath: "/private/tmp").appendingPathComponent("fpmac-\(UUID())")
                    : try TestEnv.temporaryDirectory()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                let family = "FPRegistry" + TestEnv.tag()
                let url = try FixtureFonts.build([.init(file: "Registry.ttf", family: family)], in: directory)[0]
                let identity = try #require(InstallerFileStat(url.path)?.identity)
                let registry = CoreTextFontRegistry()
                try ProcessScopeFonts.register(url)
                defer { ProcessScopeFonts.unregister(url) }
                #expect(registry.fingerprintSnapshot().paths.contains { InstallerFileStat($0)?.identity == identity })
                let files = registry.registeredFontFiles()
                #expect(
                    files.contains {
                        InstallerFileStat($0.path)?.identity == identity
                            && $0.postscriptNames.contains(family + "-Regular")
                    })
                ProcessScopeFonts.unregister(url)
                #expect(!registry.fingerprintSnapshot().paths.contains { InstallerFileStat($0)?.identity == identity })
                #expect(!registry.registeredFontFiles().contains { InstallerFileStat($0.path)?.identity == identity })
            }
        }
    }
}
