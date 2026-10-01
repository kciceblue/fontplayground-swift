import Foundation
import Testing

@testable import FPMacServices

struct FolderWalkerTests {
    @Test func crit5MacFileSystemConventions() throws {
        let f = try CatalogFixture(); defer { f.cleanup() }
        let home = f.root.appendingPathComponent("home")
        for path in [
            "._A.ttf", "sub/._B.ttf", "__MACOSX/._C.ttf", ".Trashes/501/D.ttf", "Pkg.app/Contents/Resources/E.ttf",
            "notes.txt", ".hidden.ttf", "Library/Containers/x/G.ttf", "Library/Group Containers/x/H.ttf",
        ] {
            _ = try f.stub(path, in: home)
        }
        let outside = f.root.appendingPathComponent("outside")
        _ = try f.stub("F.ttf", in: outside)
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("linked"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(
            atPath: home.appendingPathComponent("sub/loop").path, withDestinationPath: "..")
        let result = FolderWalker(homeDirectory: home).walk(home, reportMissingRoot: true)
        #expect(result.files.map(\.lastPathComponent) == ["F.ttf"])
        #expect(result.skipped.filter { $0.reason == .appleDouble }.count == 2)
        #expect(result.skipped.filter { $0.reason == .hiddenFile }.count == 1)
        #expect(result.issues.isEmpty)
        let package = FolderWalker(homeDirectory: home).walk(
            home.appendingPathComponent("Pkg.app"), reportMissingRoot: true)
        #expect(package.files.map(\.lastPathComponent) == ["E.ttf"])
    }
    @Test func findsFontsInSubfoldersOnly() throws {
        let f = try CatalogFixture(); defer { f.cleanup() }
        let font = try f.stub("sub/real.ttf"); _ = try f.stub("sub/junk.fon"); _ = try f.stub("notes.txt")
        let result = FolderWalker(homeDirectory: f.root).walk(f.fonts, reportMissingRoot: true)
        #expect(result.files == [font]); #expect(result.skipped.count == 1)
    }
    @Test func failedSymlinkStatIsReportedExceptForBrokenLinks() throws {
        let f = try CatalogFixture(); defer { f.cleanup() }; _ = try f.stub("A.ttf")
        let loop = f.fonts.appendingPathComponent("loop.ttf")
        try FileManager.default.createSymbolicLink(at: loop, withDestinationURL: loop)
        try FileManager.default.createSymbolicLink(
            atPath: f.fonts.appendingPathComponent("broken.ttf").path, withDestinationPath: "missing.ttf")
        let result = FolderWalker(homeDirectory: f.root).walk(f.fonts, reportMissingRoot: true)
        #expect(result.files.count == 1)
        #expect(result.issues.count == 1)
        #expect(
            result.issues.contains {
                if case .folderUnreadable(loop.path, _) = $0 { return true }; return false
            })
    }

}
