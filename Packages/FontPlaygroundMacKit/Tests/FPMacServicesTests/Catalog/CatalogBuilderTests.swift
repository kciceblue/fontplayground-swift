import FPCore
import Foundation
import Testing

@testable import FPMacServices

struct CatalogBuilderTests {
    @Test func catalog2HiddenFacesAreDroppedAndCounted() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }; let file = try f.stub("A.ttc")
        var last = FakeEngine.face(file.path, name: ".LastResort"); last.family = ".LastResort"; last.hidden = true
        var system = last; system.index = 1; system.family = "System Font"; system.postscriptName = ".SFNS-Regular"
        var helvetica = FakeEngine.face(file.path, name: "Helvetica"); helvetica.index = 2;
        helvetica.family = "Helvetica"
        await f.engine.script([last, system, helvetica], path: file.path)
        let snapshot = try await (await f.store()).refresh(.incremental)
        #expect(snapshot.faces == [helvetica]); #expect(snapshot.counts.hiddenFaces == 2)
        let entry = try #require(f.entries()[file.path] as? [String: Any])
        #expect((entry["faces"] as? [Any])?.count == 3)
    }
    @Test func catalogM1DedupeTieBreak() throws {
        let f = try CatalogFixture(); defer { f.cleanup() }
        let a = try f.stub("A.ttf"), b = try f.stub("B.ttf")
        let stampA = try #require(DiscoveredFileStamp(a.path)), stampB = try #require(DiscoveredFileStamp(b.path))
        func build(_ files: [DiscoveredFile], infos: [RegisteredFaceInfo] = [], unnamed: Bool = false)
            -> CatalogSnapshot
        {
            let faces = Dictionary(
                uniqueKeysWithValues: files.map { file in
                    var face = FakeEngine.face(file.path, name: "Shared"); if unnamed { face.postscriptName = nil }
                    return (file.path, [face])
                })
            return CatalogBuilder.build(
                files: files, faces: faces, errors: [:], skipped: [], folderIssues: [], menuVisible: [],
                registeredFaces: infos, generation: 1, isComplete: true, activity: .idle)
        }
        let first = DiscoveredFile(path: a.path, origin: .extraFolder, stamp: stampA, registeredPostscriptNames: [])
        let second = DiscoveredFile(path: b.path, origin: .extraFolder, stamp: stampB, registeredPostscriptNames: [])
        var rows: [([DiscoveredFile], [RegisteredFaceInfo], String)] = []
        var registered = second; registered.registeredPostscriptNames = ["Shared"]
        rows.append(([first, registered], [], b.path))
        // Registry paths use the same file identities while the candidates model CoreText's system spellings.
        var asset = first; asset.path = "/System/Library/AssetsV2/x.asset/AssetData/PingFang.ttc";
        asset.origin = .systemAsset
        var privateFont = second;
        privateFont.path = "/System/Library/PrivateFrameworks/FontServices.framework/PingFangUI.ttc";
        privateFont.origin = .system
        rows.append(
            (
                [privateFont, asset],
                [
                    .init(postscriptName: "Shared", path: a.path, priority: 60000, enabled: true),
                    .init(postscriptName: "Shared", path: b.path, priority: 10000, enabled: true),
                ], asset.path
            ))
        rows.append(
            ([first, second], [.init(postscriptName: "Shared", path: a.path, priority: 0, enabled: false)], b.path))
        rows.append(([privateFont, first], [], first.path))
        var systemOrigin = second; systemOrigin.origin = .system
        rows.append(([first, systemOrigin], [], b.path))
        rows.append(([second, first], [], a.path))
        for (files, infos, expected) in rows {
            let result = build(files, infos: infos)
            #expect(result.faces.map(\.path) == [expected]); #expect(result.counts.duplicateFaces == 1)
            #expect(result.counts.disabledFaces == infos.filter { !$0.enabled }.count)
            #expect(
                result.issues.contains {
                    if case .duplicate(let kept, _, "Shared") = $0 { return kept.path == expected }; return false
                })
        }
        #expect(build([first, second], unnamed: true).faces.count == 2)
        var indexed = FakeEngine.face(a.path, name: "Shared"); indexed.index = 3
        let other = FakeEngine.face(a.path, name: "Shared")
        let result = CatalogBuilder.build(
            files: [first], faces: [a.path: [indexed, other]], errors: [:], skipped: [], folderIssues: [],
            menuVisible: [], registeredFaces: [], generation: 0, isComplete: true, activity: .idle)
        #expect(result.faces.first?.index == 0)
    }
    @Test func facesHiddenFromMenusAreMarkedNotDropped() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }; let file = try f.stub("A.ttf")
        let user = try await (await f.store()).refresh(.incremental)
        #expect(user.annotations.values.first?.hiddenFromMenus == true)
        var config = f.configuration; config.userFontsFolder = f.root.appendingPathComponent("different")
        let extra = try await (await f.store(config: config)).refresh(.incremental)
        #expect(extra.faces.first?.path == file.path); #expect(extra.annotations.values.first?.hiddenFromMenus == false)
    }
    @Test func crit9FontBookDisabledFontsAreMarked() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }
        let outside = try f.stub("outside/Disabled.ttf", in: f.root), walked = try f.stub("Walked.ttf")
        f.registry.faces = [
            .init(postscriptName: "Stub-Disabled", path: outside.path, priority: 1, enabled: false),
            .init(postscriptName: "Stub-Walked", path: nil, priority: 1, enabled: false),
            .init(postscriptName: "Unlocated", path: nil, priority: 1, enabled: false),
        ]
        let snapshot = try await (await f.store()).refresh(.incremental)
        #expect(Set(snapshot.faces.map(\.path)) == [outside.path, walked.path])
        #expect(snapshot.counts.disabledFaces == 2); #expect(snapshot.counts.disabledUnlocated == 1)
        #expect(snapshot.annotations.values.allSatisfy { $0.disabledInFontBook })
        #expect(snapshot.issues.contains(.disabledUnlocated(postscriptName: "Unlocated")))
    }
    @Test func everyDuplicateNamesTheFinalWinner() throws {
        let f = try CatalogFixture(); defer { f.cleanup() }
        let urls = try ["C.ttf", "B.ttf", "A.ttf"].map { try f.stub($0) }
        let files = try urls.map {
            DiscoveredFile(
                path: $0.path, origin: .extraFolder, stamp: try #require(DiscoveredFileStamp($0.path)),
                registeredPostscriptNames: [])
        }
        let snapshot = CatalogBuilder.build(
            files: files,
            faces: Dictionary(uniqueKeysWithValues: files.map { ($0.path, [FakeEngine.face($0.path, name: "Same")]) }),
            errors: [:], skipped: [], folderIssues: [], menuVisible: [], registeredFaces: [], generation: 0,
            isComplete: true, activity: .idle)
        #expect(
            snapshot.issues.allSatisfy {
                if case .duplicate(let kept, _, _) = $0 { return kept.path == urls[2].path }; return false
            })
    }
}
