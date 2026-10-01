import Foundation
import Testing

@testable import FPMacServices

struct EmptyRegistry: SystemFontRegistry {
    func registeredFontFiles() -> [RegisteredFontFile] { [] }
    func menuVisiblePostScriptNames() -> Set<String> { [] }
    func registeredFaces(includeDisabled: Bool) -> [RegisteredFaceInfo] { [] }
}
struct FixedNames: FontNameSource { var entries: [FontNameEntry]; func nameEntries() -> [FontNameEntry] { entries } }
struct FailingFileSystem: InstallFileSystem {
    var failPlacement = false
    var failManifest = false
    let base = PosixInstallFileSystem()
    func copyAndSync(from source: URL, to staged: URL) throws -> (size: Int64, sha256: String) {
        try base.copyAndSync(from: source, to: staged)
    }
    func renameExclusive(_ from: URL, to: URL) throws {
        if failPlacement { throw POSIXError(.EXDEV) }
        try base.renameExclusive(from, to: to)
    }
    func removeFile(_ url: URL) throws { try base.removeFile(url) }
    func writeAtomically(_ data: Data, to url: URL) throws {
        if failManifest { throw POSIXError(.EIO) }
        try base.writeAtomically(data, to: url)
    }
    func sha256(of url: URL) throws -> String { try base.sha256(of: url) }
}
struct InstallFixture {
    let root: URL
    let fonts: URL
    let manifest: URL
    let trash: RecordingTrash
    let family: String
    var query: InstallQuery {
        .init(
            family: family, style: "Regular",
            postscriptName: "\(family.replacingOccurrences(of: " ", with: ""))-Regular")
    }
    init(root: URL? = nil) throws {
        self.root = try root ?? TestEnv.temporaryDirectory()
        fonts = self.root.appendingPathComponent("Fonts");
        manifest = self.root.appendingPathComponent("Support/installed.json")
        trash = RecordingTrash(directory: self.root.appendingPathComponent("Trash"));
        family = "FP Install \(TestEnv.tag())"
        try FileManager.default.createDirectory(at: fonts, withIntermediateDirectories: true)
    }
    func installer(
        registry: any SystemFontRegistry = EmptyRegistry(), systemFolders: [(URL, FontDomain)] = [],
        extraNames: (any FontNameSource)? = nil, fileSystem: any InstallFileSystem = PosixInstallFileSystem(),
        fontsFolder: URL? = nil
    ) -> FontInstaller {
        .init(
            fontsFolder: fontsFolder ?? fonts, manifestURL: manifest, registry: registry, systemFolders: systemFolders,
            extraNames: extraNames, fileSystem: fileSystem, trash: trash)
    }
    func source(query: InstallQuery? = nil, forged: Bool = true, chars: String = "abc", file: String = "source.ttf")
        throws -> URL
    {
        let query = query ?? self.query
        return try FixtureFonts.build(
            [
                .init(
                    file: file, family: query.family, style: query.style, postscriptName: query.postscriptName,
                    fullName: query.fullName, chars: chars,
                    notice: forged ? MacServicesConstants.forgedNotice + " from: fixture" : nil)
            ],
            in: root.appendingPathComponent("Sources"))[0]
    }
    func files() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: fonts.path).sorted() }
    func manifestFonts() throws -> [[String: Any]] {
        (try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])?["fonts"]
            as? [[String: Any]] ?? []
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
