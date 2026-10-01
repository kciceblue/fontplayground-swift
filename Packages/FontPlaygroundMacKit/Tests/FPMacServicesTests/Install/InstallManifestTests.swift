import Foundation
import Testing

@testable import FPMacServices

struct InstallManifestTests {
    @Test func manifestIsAtomicVersionedAndRecovers() async throws {
        let f = try InstallFixture(); defer { f.cleanup() }
        let source = try f.source(); let installer = f.installer()
        let font = try await installer.install(source, expecting: f.query)
        let before = try Data(contentsOf: f.manifest)
        let interrupted = PosixInstallFileSystem(beforeRename: { _ in throw POSIXError(.EIO) })
        #expect(throws: POSIXError.self) { try interrupted.writeAtomically(Data("interrupted".utf8), to: f.manifest) }
        #expect(try Data(contentsOf: f.manifest) == before)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: f.manifest.deletingLastPathComponent().path) == [
                "installed.json"
            ])
        let future = Data(#"{"format":"fontplayground-installed-fonts","version":2,"fonts":{"new":"schema"}}"#.utf8)
        try PosixInstallFileSystem().writeAtomically(future, to: f.manifest)
        await #expect(throws: InstallError.manifestUnsupported) {
            try await installer.install(source, expecting: f.query)
        }
        await #expect(throws: InstallError.manifestUnsupported) { try await installer.uninstall(font) }
        #expect(try Data(contentsOf: f.manifest) == future)
        #expect(try await installer.conflict(for: f.query) == .block(.youHave(name: f.family)))
        let corrupt = Data("invalid JSON".utf8)
        try PosixInstallFileSystem().writeAtomically(corrupt, to: f.manifest)
        #expect(try await installer.installedFonts().isEmpty)
        let backups = try FileManager.default.contentsOfDirectory(
            at: f.manifest.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        let backup = try #require(backups.first { $0.lastPathComponent.hasPrefix("installed.json.corrupt-") })
        #expect(try Data(contentsOf: backup) == corrupt && FileManager.default.fileExists(atPath: font.fileURL.path))
        var object = try #require(JSONSerialization.jsonObject(with: before) as? [String: Any])
        object["future_field"] = ["ignored": true]
        try PosixInstallFileSystem().writeAtomically(JSONSerialization.data(withJSONObject: object), to: f.manifest)
        #expect(try await installer.installedFonts() == [font])
    }

    @Test func exclusivePlacementCannotOverwriteAndCopyHashMatches() throws {
        let root = try TestEnv.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let fs = PosixInstallFileSystem(); let source = root.appendingPathComponent("source")
        let staged = root.appendingPathComponent("staged"); let target = root.appendingPathComponent("target")
        let data = Data(repeating: 0xA5, count: 1_048_583)
        try data.write(to: source); try Data("foreign".utf8).write(to: target)
        let result = try fs.copyAndSync(from: source, to: staged)
        #expect(try result.size == data.count && result.sha256 == fs.sha256(of: source))
        #expect(throws: POSIXError(.EEXIST)) { try fs.renameExclusive(staged, to: target) }
        #expect(try Data(contentsOf: target) == Data("foreign".utf8) && Data(contentsOf: staged) == data)
        try fs.removeFile(staged); try fs.removeFile(staged)
    }
}
