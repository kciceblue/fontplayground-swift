import CoreText
import Darwin
import Foundation
import Testing

@testable import FPMacServices

extension InstallationIntegration {
    @Suite(.serialized)
    struct FontInstallerTests {
        @Test("INSTALL-1/9/12: install and Trash use temporary folders")
        func install1Install9Install12RoundTripInTemporaryFolder() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let source = try f.source(); let installer = f.installer()
            let font = try await installer.install(source, expecting: f.query)
            #expect(font.fileURL.lastPathComponent == "\(f.family)-Regular.ttf")
            #expect(try Data(contentsOf: source) == Data(contentsOf: font.fileURL))
            #expect(try await installer.installedFonts() == [font])
            let entry = try #require(f.manifestFonts().first)
            #expect(entry["sha256"] as? String == font.sha256 && entry["size"] as? Int64 == font.size)
            #expect(entry["file_name"] as? String == font.fileURL.lastPathComponent)
            try ProcessScopeFonts.register(font.fileURL)
            #expect((CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []).contains(f.family))
            ProcessScopeFonts.unregister(font.fileURL)
            let outcome = try await installer.uninstall(font)
            guard case .movedToTrash(let url) = outcome else { Issue.record("Expected Trash"); return }
            #expect(url != nil && f.trash.moves.count == 1)
            #expect(try f.manifestFonts().isEmpty)
            #expect(try await installer.uninstall(font) == .notInstalled)
            #expect(try f.files().isEmpty)
        }
        @Test("INSTALL-M3: validate before changing the fonts folder")
        func installM3ValidatesWithCoreTextFirst() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let installer = f.installer(); let junk = f.root.appendingPathComponent("junk.ttf")
            try Data("not a font".utf8).write(to: junk)
            await #expect(throws: InstallError.unreadable) { try await installer.install(junk, expecting: f.query) }
            let different = InstallQuery(
                family: f.family, style: "Regular", postscriptName: "Different-\(TestEnv.tag())")
            let other = try f.source(query: different)
            await #expect(
                throws: InstallError.unexpectedName(expected: f.query.postscriptName, found: different.postscriptName)
            ) {
                try await installer.install(other, expecting: f.query)
            }
            let ordinary = try f.source(forged: false, file: "ordinary.ttf")
            await #expect(throws: InstallError.notForged) { try await installer.install(ordinary, expecting: f.query) }
            await #expect(throws: InstallError.sourceMissing) {
                try await installer.install(f.root.appendingPathComponent("missing.ttf"), expecting: f.query)
            }
            #expect(try f.files().isEmpty && !FileManager.default.fileExists(atPath: f.manifest.path))
        }
        @Test("INSTALL-M1: foreign and untracked files are never touched")
        func installM1NeverTouchesFilesThatAreNotOurs() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            for forged in [false, true] {
                let query = InstallQuery(
                    family: f.family + (forged ? " F" : " N"), style: "Regular",
                    postscriptName: "Foreign\(TestEnv.tag())")
                let source = try f.source(query: query, forged: forged, file: "\(forged).ttf")
                let destination = f.fonts.appendingPathComponent(source.lastPathComponent)
                try FileManager.default.copyItem(at: source, to: destination)
                let stamp = InstallerFileStat(destination.path); let bytes = try Data(contentsOf: destination)
                let font = InstalledFont(
                    fileURL: destination, family: query.family, style: query.style, fullName: query.fullName,
                    postscriptName: query.postscriptName, sha256: "", size: 0, installedAt: Date())
                let installer = f.installer()
                let built = try f.source(query: query, file: "built-\(forged).ttf")
                await #expect(throws: InstallError.conflict(.block(.youHave(name: query.family)))) {
                    try await installer.install(built, expecting: query)
                }
                await #expect(throws: InstallError.notOurs(name: query.fullName)) {
                    try await installer.uninstall(font)
                }
                #expect(InstallerFileStat(destination.path)?.identity == stamp?.identity)
                #expect(try Data(contentsOf: destination) == bytes)
            }
        }
        @Test("INSTALL-8/9, TOOLING-2: place new bytes before trashing the old copy")
        func install8Install9Tooling2UpdateWritesANewFileThenTrashesTheOld() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let installer = f.installer(); let source = try f.source()
            let old = try await installer.install(source, expecting: f.query)
            let bytes = try Data(contentsOf: old.fileURL); let inode = InstallerFileStat(old.fileURL.path)?.identity
            let replacement = try f.source(chars: "abcd", file: "new.ttf")
            let new = try await installer.install(replacement, expecting: f.query, confirmed: .replaceOurs(old))
            #expect(new.fileURL.lastPathComponent == "\(f.family)-Regular-1.ttf")
            let trash = try #require(f.trash.moves.first?.1)
            #expect(try Data(contentsOf: trash) == bytes && InstallerFileStat(trash.path)?.identity == inode)
            #expect(try f.manifestFonts().count == 1 && f.files() == [new.fileURL.lastPathComponent])
            let again = try await installer.install(source, expecting: f.query, confirmed: .replaceOurs(new))
            #expect(try again.fileURL == old.fileURL && f.files().count == 1)
        }
        @Test("INSTALL-M2: placement failure preserves the old copy; Trash failure can be retried")
        func installM2OldCopySurvivesAFailedPlacement() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let source = try f.source(); let installer = f.installer()
            let old = try await installer.install(source, expecting: f.query)
            let bytes = try Data(contentsOf: old.fileURL); let manifest = try Data(contentsOf: f.manifest)
            let broken = f.installer(fileSystem: FailingFileSystem(failPlacement: true))
            await #expect(throws: InstallError.self) {
                try await broken.install(source, expecting: f.query, confirmed: .replaceOurs(old))
            }
            #expect(try Data(contentsOf: old.fileURL) == bytes && Data(contentsOf: f.manifest) == manifest)
            #expect(try f.files() == [old.fileURL.lastPathComponent])
            f.trash.fail([old.fileURL.lastPathComponent])
            do {
                _ = try await installer.install(source, expecting: f.query, confirmed: .replaceOurs(old));
                Issue.record("Expected Trash failure")
            } catch InstallError.previousCopyNotRemoved(let installed, let previous, _) {
                #expect(previous == old && FileManager.default.fileExists(atPath: installed.fileURL.path))
            }
            #expect(try f.files().count == 2 && f.manifestFonts().count == 2)
            f.trash.fail([])
            let conflict = try await installer.conflict(for: f.query)
            _ = try await installer.install(source, expecting: f.query, confirmed: conflict)
            #expect(try f.files().count == 1 && f.manifestFonts().count == 1)
        }
        @Test func manifestFailureRollsBackOnlyTheNewCopy() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let source = try f.source(); let old = try await f.installer().install(source, expecting: f.query)
            let bytes = try Data(contentsOf: f.manifest)
            await #expect(throws: InstallError.self) {
                try await f.installer(fileSystem: FailingFileSystem(failManifest: true)).install(
                    source, expecting: f.query, confirmed: .replaceOurs(old))
            }
            #expect(try f.files() == [old.fileURL.lastPathComponent] && Data(contentsOf: f.manifest) == bytes)
        }
        @Test func reusedFileNameReplacesAStaleManifestEntry() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let installer = f.installer()
            let first = try await installer.install(try f.source(), expecting: f.query)
            let stale = try f.manifestFonts()
            let second = try await installer.install(
                try f.source(chars: "abcd", file: "second.ttf"), expecting: f.query, confirmed: .replaceOurs(first))
            // As left by an update whose pruning write failed: the trashed copy's entry is still listed first.
            var document = try #require(
                try JSONSerialization.jsonObject(with: Data(contentsOf: f.manifest)) as? [String: Any])
            document["fonts"] = stale + (try f.manifestFonts())
            try JSONSerialization.data(withJSONObject: document).write(to: f.manifest)
            let conflict = try await installer.conflict(for: f.query)
            let third = try await installer.install(
                try f.source(chars: "abcde", file: "third.ttf"), expecting: f.query, confirmed: conflict)
            #expect(third.fileURL == first.fileURL && second.fileURL != first.fileURL)
            let names = try f.manifestFonts().compactMap { $0["file_name"] as? String }
            #expect(names == [first.fileURL.lastPathComponent])
            #expect(try await installer.installedFonts().map(\.fileURL) == [third.fileURL])
            guard case .movedToTrash = try await installer.uninstall(third) else {
                Issue.record("The new copy should be ours and go to the Trash")
                return
            }
        }
        @Test func foreignFileHoldingTheNameGetsANumberedName() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let source = try f.source(); let name = "\(f.family)-Regular.ttf"
            let foreign = try FixtureFonts.build(
                [.init(file: name, family: "Other " + TestEnv.tag())], in: f.fonts)[0]
            let foreignBytes = try Data(contentsOf: foreign)
            let installed = try await f.installer().install(source, expecting: f.query)
            #expect(installed.fileURL.lastPathComponent == "\(f.family)-Regular-1.ttf")
            #expect(try Data(contentsOf: foreign) == foreignBytes)
            _ = try await f.installer().uninstall(installed)
            for n in 1..<100 {
                try Data("foreign".utf8).write(to: f.fonts.appendingPathComponent("\(f.family)-Regular-\(n).ttf"))
            }
            await #expect(throws: InstallError.noFreeFileName(stem: "\(f.family)-Regular")) {
                try await f.installer().install(source, expecting: f.query)
            }
            #expect(try f.files().count == 100)
        }
        @Test func confirmationIsRequiredAndMustBeCurrent() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let source = try f.source(); let installer = f.installer()
            let old = try await installer.install(source, expecting: f.query)
            await #expect(throws: InstallError.conflict(.replaceOurs(old))) {
                try await installer.install(source, expecting: f.query)
            }
            var stale = old; stale.sha256 = "stale"
            await #expect(throws: InstallError.conflict(.replaceOurs(old))) {
                try await installer.install(source, expecting: f.query, confirmed: .replaceOurs(stale))
            }
            #expect(try f.files().count == 1 && f.trash.moves.isEmpty)
            let downloadable = try InstallFixture(); defer { downloadable.cleanup() }
            let query = downloadable.query
            let names = FixedNames(entries: [
                .init(
                    path: nil, domain: .downloadable, postscriptName: query.postscriptName,
                    familyKeys: [SystemFontNameSource.fold(query.family)], fullNameKeys: [],
                    displayFamily: query.family,
                    displayStyle: query.style, displayFullName: query.fullName)
            ])
            let downloaderConflict = InstallConflict.ask(.appleOffersDownload(name: query.family))
            let downloadInstaller = downloadable.installer(extraNames: names)
            let built = try downloadable.source()
            await #expect(throws: InstallError.conflict(downloaderConflict)) {
                try await downloadInstaller.install(built, expecting: query)
            }
            await #expect(throws: InstallError.conflict(downloaderConflict)) {
                try await downloadInstaller.install(built, expecting: query, confirmed: .replaceOurs(old))
            }
            #expect(try downloadable.files().isEmpty)
            _ = try await downloadInstaller.install(built, expecting: query, confirmed: downloaderConflict)
            var systemNames = names
            systemNames.entries[0].domain = .system
            let block = InstallConflict.block(.systemHas(name: query.family))
            await #expect(throws: InstallError.conflict(block)) {
                try await downloadable.installer(extraNames: systemNames).install(
                    built, expecting: query, confirmed: block)
            }
        }
        @Test("INSTALL-14: read-only folder errors use plain POSIX wording")
        func install14ReadOnlyFontsFolderFailsPlainly() async throws {
            let f = try InstallFixture(); defer { chmod(f.fonts.path, 0o755); f.cleanup() }
            let source = try f.source(); chmod(f.fonts.path, 0o555)
            await #expect(throws: InstallError.fileSystem(operation: "stage", message: "Permission denied")) {
                try await f.installer().install(source, expecting: f.query)
            }
            #expect(try f.files().isEmpty && !FileManager.default.fileExists(atPath: f.manifest.path))
        }
        @Test func staleStagingFilesAreSwept() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let old = ".old.\(String(repeating: "a", count: 32)).fpinstall"
            let young = ".young.\(String(repeating: "b", count: 32)).fpinstall"
            for name in [old, young, ".DS_Store", "._A.ttf"] {
                try Data().write(to: f.fonts.appendingPathComponent(name))
            }
            let appleDouble = f.fonts.appendingPathComponent("._A.ttf")
            let originalStamp = try #require(InstallerFileStat(appleDouble.path))
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-3600)],
                ofItemAtPath: f.fonts.appendingPathComponent(old).path)
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-60)],
                ofItemAtPath: f.fonts.appendingPathComponent(young).path)
            _ = try await f.installer().install(f.source(), expecting: f.query)
            let names = try f.files()
            #expect(!names.contains(old))
            #expect(names.contains(young))
            // Foundation may hide AppleDouble sidecars from directory listings; inspect the file itself.
            #expect(InstallerFileStat(appleDouble.path) == originalStamp)
            #expect(try Data(contentsOf: appleDouble).isEmpty)
            #expect(names.contains(".DS_Store"))
        }
        @Test("INSTALL-11, TOOLING-7: folder identity survives symlinks")
        func install11Tooling7UserFolderIsRecognisedThroughSymlinks() async throws {
            let root = URL(fileURLWithPath: "/private/tmp/fpmac-\(UUID())")
            let f = try InstallFixture(root: root); defer { f.cleanup() }
            let installer = f.installer(registry: CoreTextFontRegistry())
            let old = try await installer.install(f.source(), expecting: f.query)
            try ProcessScopeFonts.register(old.fileURL); defer { ProcessScopeFonts.unregister(old.fileURL) }
            #expect(try await installer.conflict(for: f.query) == .replaceOurs(old))
            ProcessScopeFonts.unregister(old.fileURL)
            let link = root.appendingPathComponent("link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.fonts)
            let throughLink = f.installer(fontsFolder: link)
            let fonts = try await throughLink.installedFonts()
            #expect(fonts.count == 1)
            _ = try await throughLink.uninstall(#require(fonts.first))
            #expect(try f.files().isEmpty)
        }
        @Test func installingFromTheFontsFolderIsANoOp() async throws {
            let f = try InstallFixture(); defer { f.cleanup() }
            let installer = f.installer(); let old = try await installer.install(f.source(), expecting: f.query)
            let bytes = try Data(contentsOf: f.manifest); let inode = InstallerFileStat(old.fileURL.path)?.identity
            #expect(try await installer.install(old.fileURL, expecting: f.query) == old)
            #expect(try Data(contentsOf: f.manifest) == bytes && InstallerFileStat(old.fileURL.path)?.identity == inode)
            #expect(try f.files() == [old.fileURL.lastPathComponent] && f.trash.moves.isEmpty)
        }
    }
}
