import Foundation
import Testing

@testable import FPMacServices

@Suite(.serialized)
struct InstallationIntegration {}

extension InstallationIntegration {
    @Suite(.serialized)
    struct ConflictTests {
        @Test func noConflictForANewName() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            #expect(try await f.installer().conflict(for: f.query) == .noConflict)
        }
        @Test(.enabled(if: TestEnv.appleFonts)) func systemFontFamilyBlocks() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let q = InstallQuery(family: "hELVETICA", style: "Regular", postscriptName: f.query.postscriptName)
            #expect(
                try await f.installer(
                    registry: CoreTextFontRegistry(), systemFolders: FontInstaller.defaultSystemFolders
                )
                .conflict(for: q) == .block(.systemHas(name: "hELVETICA")))
        }
        @Test func localFolderBlocks() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let url = try f.source()
            #expect(
                try await f.installer(systemFolders: [(url.deletingLastPathComponent(), .local)])
                    .conflict(for: f.query) == .block(.installedForEveryone(name: f.family)))
        }
        @Test func activatedElsewhereBlocks() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let url = try f.source()
            try ProcessScopeFonts.register(url); defer { ProcessScopeFonts.unregister(url) }
            #expect(
                try await f.installer(registry: CoreTextFontRegistry()).conflict(for: f.query)
                    == .block(.youHave(name: f.family)))
        }
        @Test func localizedFamilyBlocks() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let localized = "测试" + TestEnv.tag()
            let url = try FixtureFonts.build(
                [
                    .init(
                        file: "Localized.ttf", family: f.family,
                        localizedFamily: ["0x0804": localized])
                ], in: f.root)[0]
            try ProcessScopeFonts.register(url); defer { ProcessScopeFonts.unregister(url) }
            let q = InstallQuery(family: localized, style: "Regular", postscriptName: "Unique" + TestEnv.tag())
            #expect(
                try await f.installer(registry: CoreTextFontRegistry()).conflict(for: q)
                    == .block(.youHave(name: localized)))
        }
        @Test func userNonForgedFontBlocks() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            try FileManager.default.copyItem(
                at: f.source(forged: false), to: f.fonts.appendingPathComponent("foreign.ttf"))
            #expect(try await f.installer().conflict(for: f.query) == .block(.youHave(name: f.family)))
        }
        @Test func userForgedButNotOursBlocks() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            try FileManager.default.copyItem(at: f.source(), to: f.fonts.appendingPathComponent("unlisted.ttf"))
            #expect(try await f.installer().conflict(for: f.query) == .block(.youHave(name: f.family)))
        }
        @Test func install10ChangedBytesAreNotOurs() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let installer = f.installer()
            let font = try await installer.install(f.source(), expecting: f.query)
            var bytes = try Data(contentsOf: font.fileURL)
            bytes[bytes.count - 1] ^= 1
            try bytes.write(to: font.fileURL, options: .atomic)
            #expect(try await installer.conflict(for: f.query) == .block(.youHave(name: f.family)))
        }
        @Test func oursSameFullNameAsksToReplace() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let installer = f.installer()
            let font = try await installer.install(f.source(), expecting: f.query)
            #expect(try await installer.conflict(for: f.query) == .replaceOurs(font))
        }
        @Test func oursOtherStyleIsNoConflict() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let installer = f.installer()
            let bold = InstallQuery(family: f.family, style: "Bold", postscriptName: "Bold" + TestEnv.tag())
            _ = try await installer.install(f.source(query: bold), expecting: bold)
            #expect(try await installer.conflict(for: f.query) == .noConflict)
        }
        @Test func vanishedFileIsNoConflict() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let installer = f.installer()
            let font = try await installer.install(f.source(), expecting: f.query)
            _ = try await installer.conflict(for: f.query)
            try FileManager.default.removeItem(at: font.fileURL)
            #expect(try await installer.conflict(for: f.query) == .noConflict)
        }
        @Test func install5PostScriptNameOfYourOtherFontBlocks() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let installer = f.installer()
            let first = InstallQuery(family: "甲" + TestEnv.tag(), style: "Regular", postscriptName: "X" + TestEnv.tag())
            _ = try await installer.install(f.source(query: first), expecting: first)
            let second = InstallQuery(
                family: "乙" + TestEnv.tag(), style: "Regular", postscriptName: first.postscriptName)
            #expect(
                try await installer.conflict(for: second)
                    == .block(
                        .internalNameUsedByYourFont(
                            postscriptName: first.postscriptName, fullName: first.fullName)))
        }
        @Test(.enabled(if: TestEnv.appleFonts)) func postscriptNameOfAnotherFontBlocks() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let q = InstallQuery(family: f.family, style: "Regular", postscriptName: "Helvetica")
            #expect(
                try await f.installer(
                    registry: CoreTextFontRegistry(), systemFolders: FontInstaller.defaultSystemFolders
                )
                .conflict(for: q) == .block(.internalNameInUse(postscriptName: "Helvetica")))
        }
        @Test func hiddenNameBlocks() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            for q in [
                InstallQuery(family: " .F", style: "Regular", postscriptName: "F-Regular"),
                InstallQuery(family: "F", style: "Regular", postscriptName: " .F-Regular"),
            ] {
                #expect(try await f.installer().conflict(for: q) == .block(.hiddenName))
            }
        }
        @Test func downloadableNameAsks() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let entry = FontNameEntry(
                path: nil, domain: .downloadable, postscriptName: "Other",
                familyKeys: [SystemFontNameSource.fold(f.family)], fullNameKeys: [], displayFamily: f.family,
                displayStyle: "Regular", displayFullName: f.query.fullName)
            #expect(
                try await f.installer(extraNames: FixedNames(entries: [entry])).conflict(for: f.query)
                    == .ask(.appleOffersDownload(name: f.family)))
        }
        @Test func install10OursDetectedFromManifestAfterRestart() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let font = try await f.installer().install(f.source(), expecting: f.query)
            #expect(try await f.installer().conflict(for: f.query) == .replaceOurs(font))
        }

        @Test func domainPriorityFullNameHitsAndLatestReplacement() {
            let query = InstallQuery(family: "F", style: "Regular", postscriptName: "P")
            func entry(_ domain: FontDomain, path: String = "/temporary/a", family: Bool = true) -> FontNameEntry {
                .init(
                    path: path, domain: domain, postscriptName: "P", familyKeys: family ? ["f"] : [],
                    fullNameKeys: ["f regular"], displayFamily: "F", displayStyle: "Regular",
                    displayFullName: "F Regular")
            }
            #expect(
                ConflictChecker.decide(
                    query: query, entries: [entry(.local), entry(.system)], ours: { _ in nil },
                    fileExists: { _ in true }) == .block(.systemHas(name: "F")))
            #expect(
                ConflictChecker.decide(
                    query: query, entries: [entry(.other, family: false)], ours: { _ in nil },
                    fileExists: { _ in true }) == .block(.youHave(name: "F Regular")))
            func installed(_ path: String, date: TimeInterval) -> InstalledFont {
                .init(
                    fileURL: URL(fileURLWithPath: path), family: "F", style: "Regular", fullName: "F Regular",
                    postscriptName: "P", sha256: "hash", size: 1, installedAt: Date(timeIntervalSince1970: date))
            }
            let old = installed("/temporary/a", date: 1)
            let new = installed("/temporary/b", date: 2)
            #expect(
                ConflictChecker.decide(
                    query: query, entries: [entry(.user), entry(.user, path: new.fileURL.path)],
                    ours: { $0 == old.fileURL.path ? old : new }, fileExists: { _ in true }) == .replaceOurs(new))
        }
    }
}
