import Foundation
import Testing

@testable import FPMacServices

extension InstallationIntegration {
    struct FontNameIndexTests {
        private struct DisabledRegistry: SystemFontRegistry {
            let face: RegisteredFaceInfo
            func registeredFontFiles() -> [RegisteredFontFile] { [] }
            func menuVisiblePostScriptNames() -> Set<String> { [] }
            func registeredFaces(includeDisabled: Bool) -> [RegisteredFaceInfo] { includeDisabled ? [face] : [] }
        }

        @Test(.enabled(if: TestEnv.appleFonts))
        func install3Install4Tooling7SystemNamesAreFoundWithoutNameMatching() throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let registry = CoreTextFontRegistry()
            let entries = SystemFontNameSource(
                registry: registry, folders: FontInstaller.defaultSystemFolders,
                userFontsFolder: f.fonts
            ).nameEntries()
            for family in ["Helvetica", "hELVETICA", "Times"] {
                #expect(
                    entries.contains {
                        $0.domain == .system && $0.familyKeys.contains(SystemFontNameSource.fold(family))
                    })
            }
            #expect(entries.contains { $0.domain == .system && $0.postscriptName == "Helvetica-Bold" })
            #expect(entries.contains { $0.domain == .system && $0.fullNameKeys.contains("helvetica bold") })
            let menu = registry.menuVisiblePostScriptNames()
            for (ps, family) in [("PingFangSC-Regular", "苹方-简"), ("STSongti-SC-Regular", "宋体-简")] {
                if menu.contains(ps) {
                    #expect(
                        entries.contains {
                            $0.domain == .system && $0.familyKeys.contains(SystemFontNameSource.fold(family))
                        })
                } else {
                    print("WP-403 localized system assertion skipped: \(ps) is not installed")
                }
            }
        }

        @Test func disabledFaceWithNoPathRetainsItsFamilyAndBlocks() throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let registry = DisabledRegistry(
                face: .init(
                    postscriptName: "Disabled-Regular", path: nil,
                    priority: 1000, enabled: false, familyName: " Disabled Family "))
            let entries = SystemFontNameSource(registry: registry, folders: [], userFontsFolder: f.fonts).nameEntries()
            let entry = try #require(entries.first)
            #expect(entries.count == 1 && entry.path == nil && entry.domain == .other)
            #expect(entry.familyKeys == ["disabled family"] && entry.postscriptName == "Disabled-Regular")
            let query = InstallQuery(family: "DISABLED FAMILY", style: "Regular", postscriptName: "New-Regular")
            #expect(
                ConflictChecker.decide(query: query, entries: entries, ours: { _ in nil }, fileExists: { _ in false })
                    == .block(.youHave(name: "DISABLED FAMILY")))
        }

        @Test func disabledFileAndFolderAliasesAreIndexedOnce() throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let source = try f.source()
            let alias = f.root.appendingPathComponent("Alias")
            try FileManager.default.createSymbolicLink(
                at: alias, withDestinationURL: source.deletingLastPathComponent())
            let registry = DisabledRegistry(
                face: .init(
                    postscriptName: f.query.postscriptName, path: source.path,
                    priority: 1000, enabled: false, familyName: f.family))
            let entries = SystemFontNameSource(registry: registry, folders: [(alias, .local)], userFontsFolder: f.fonts)
                .nameEntries()
            let hits = entries.filter { $0.postscriptName == f.query.postscriptName }
            #expect(hits.count == 1 && hits.first?.domain == .local)
            #expect(SystemFontNameSource.fold("  CAFÉ\n") == SystemFontNameSource.fold("cafe\u{301}"))
        }

        @Test func indexRebuildsAfterFolderChange() throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let index = FontNameIndex(source: .init(registry: EmptyRegistry(), folders: [], userFontsFolder: f.fonts))
            #expect(index.entries().isEmpty)
            try FileManager.default.copyItem(at: f.source(), to: f.fonts.appendingPathComponent("new.ttf"))
            #expect(index.entries().contains { $0.postscriptName == f.query.postscriptName })
            index.invalidate()
            #expect(index.entries().contains { $0.postscriptName == f.query.postscriptName })
        }

        @Test(.enabled(if: TestEnv.appleFonts)) func indexBudgets() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let installer = f.installer(
                registry: CoreTextFontRegistry(), systemFolders: FontInstaller.defaultSystemFolders)
            let start = ContinuousClock.now
            #expect(try await installer.conflict(for: f.query) == .noConflict)
            let cold = start.duration(to: .now)
            var warm: [Duration] = []
            for _ in 0..<20 {
                let start = ContinuousClock.now
                #expect(try await installer.conflict(for: f.query) == .noConflict)
                warm.append(start.duration(to: .now))
            }
            let median = warm.sorted()[warm.count / 2]
            print("WP-403 name index cold=\(cold), warm median=\(median)")
            #expect(cold <= .seconds(1.5))
            #expect(median <= .milliseconds(50))
        }
    }
}
