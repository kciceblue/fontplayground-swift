import Foundation
import Testing

@testable import FPMacServices

struct FontDiscoveryTests {
    @Test func catalog1CoreTextFilesOutsideTheFoldersAreDiscovered() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }
        let outside = try f.stub("outside/A.ttf", in: f.root)
        f.registry.files = [.init(path: outside.path, postscriptNames: ["A"])]
        let store = await f.store()
        let snapshot = try await store.refresh(.incremental)
        #expect(snapshot.faces.map(\.path) == [outside.path])
        #expect(snapshot.annotations.values.first?.origin == .activated)
        let alias = f.root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: outside.deletingLastPathComponent())
        let discovered = FontDiscovery(registry: f.registry, configuration: f.configuration).discover(extraFolders: [
            alias
        ])
        #expect(discovered.files.map(\.path) == [outside.path])
    }
    @Test func originClassificationFollowsTheTable() throws {
        let rows: [(String, Bool, FaceOrigin)] = [
            (
                "/System/Library/AssetsV2/com_apple_MobileAsset_Font8/x.asset/AssetData/PingFang.ttc", false,
                .systemAsset
            ),
            ("/System/Library/Fonts/Helvetica.ttc", false, .system),
            (
                "/System/Library/PrivateFrameworks/FontServices.framework/Resources/Reserved/PingFangUI.ttc", false,
                .system
            ),
            ("/Library/Fonts/A.ttf", false, .local), ("/elsewhere/A.ttf", true, .activated),
            ("/elsewhere/A.ttf", false, .extraFolder),
        ]
        for (path, registered, expected) in rows {
            #expect(FaceOrigin.classify(path: path, isInsideUserFolder: false, isRegistered: registered) == expected)
        }
        let f = try CatalogFixture(); defer { f.cleanup() }
        _ = try f.stub("A.ttf")
        let alias = f.root.appendingPathComponent("user-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: f.fonts)
        let result = FontDiscovery(registry: f.registry, configuration: f.configuration).discover(extraFolders: [alias])
        #expect(result.files.first?.origin == .user)
    }
    @Test func catalog9DedupeByFileIdentity() throws {
        let f = try CatalogFixture(); defer { f.cleanup() }
        let nfc = f.root.appendingPathComponent("ゴシック"),
            nfd = f.root.appendingPathComponent("ゴシック".decomposedStringWithCanonicalMapping)
        let file = try f.stub("A.ttf", in: nfc)
        let alias = f.root.appendingPathComponent("alias"), hard = f.root.appendingPathComponent("hard")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: nfc)
        try FileManager.default.createDirectory(at: hard, withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: file, to: hard.appendingPathComponent("B.ttf"))
        var config = f.configuration; config.standardFolders = [nfc]
        let discovery = FontDiscovery(registry: f.registry, configuration: config)
        let result = discovery.discover(extraFolders: [alias, hard, nfd])
        #expect(result.files.map(\.path) == [file.path])
        _ = try f.stub("C.ttf", in: nfc, bytes: Data(contentsOf: file))
        #expect(discovery.discover(extraFolders: [alias, hard, nfd]).files.count == 2)
    }
    @Test func registeredPathsThatFailDiscoveryAreReported() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }
        let gone = f.root.appendingPathComponent("gone.ttf").path
        let folder = f.root.appendingPathComponent("folder.ttf")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        f.registry.files = [
            .init(path: gone, postscriptNames: ["Gone"]), .init(path: folder.path, postscriptNames: []),
        ]
        let discovered = FontDiscovery(registry: f.registry, configuration: f.configuration).discover(extraFolders: [])
        #expect(
            discovered.issues == [
                .unreadable(path: gone, code: "not_found", message: "File not found."),
                .unreadable(path: folder.path, code: "io_error", message: "Not a regular file."),
            ])
        let snapshot = try await (await f.store()).refresh(.incremental)
        #expect(snapshot.counts.unreadableFiles == 2 && snapshot.counts.files == 0)
    }
    @Test func catalog10UnsupportedFormatsAreCountedNotFailed() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }
        let dfont = try f.stub("A.dfont", bytes: Data("dfont data".utf8)); _ = try f.stub("B.pfb")
        let type1 = try f.stub("extensionless", bytes: Data("%!PS".utf8))
        _ = try f.stub("junk.ttf", bytes: Data("not a font".utf8)); _ = try f.stub("short.ttf", bytes: Data([0, 1]))
        f.registry.files = [.init(path: type1.path, postscriptNames: []), .init(path: dfont.path, postscriptNames: [])]
        let snapshot = try await (await f.store()).refresh(.incremental)
        #expect(snapshot.counts.skippedFiles == 5); #expect(snapshot.counts.unreadableFiles == 0)
        #expect(snapshot.counts.files == 0); #expect(await f.engine.calls.isEmpty)
    }
}
