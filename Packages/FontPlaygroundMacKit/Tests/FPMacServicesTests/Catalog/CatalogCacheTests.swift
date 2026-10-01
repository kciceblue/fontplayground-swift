import Darwin
import FPCore
import Foundation
import Testing

@testable import FPMacServices

struct CatalogCacheTests {
    @Test func cacheFileFormatAndRejection() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }
        let a = try f.stub("A.ttf"), b = try f.stub("B.ttf")
        _ = try await (await f.store()).refresh(.incremental)
        let original = try f.cacheObject()
        #expect(original["format"] as? String == "fontplayground-catalog-cache")
        #expect(original["schema"] as? Int == 1); #expect(original["face_reader_version"] as? Int == 1)
        let entries = try f.entries()
        let entry = try #require(entries[a.path] as? [String: Any])
        #expect(Set(entry.keys) == ["size", "mtime", "device", "inode", "faces", "error"])
        let old = f.cache.appendingPathComponent("catalog-v0.json"); try Data("{}".utf8).write(to: old)
        await f.engine.setReaderVersion(2); await f.engine.resetCalls()
        let refreshed = try await (await f.store()).refresh(.incremental)
        #expect(await f.engine.calls.flatMap { $0 }.count == 2); #expect(refreshed.counts.unreadableFiles == 0)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        await f.engine.setReaderVersion(1)
        for invalid in [
            Data("not json".utf8), try JSONSerialization.data(withJSONObject: entries),
            try JSONSerialization.data(withJSONObject: original.merging(["schema": 2]) { _, new in new }),
        ] {
            try invalid.write(to: f.cache.appendingPathComponent("catalog-v1.json")); await f.engine.resetCalls()
            _ = try await (await f.store()).refresh(.incremental)
            #expect(await f.engine.calls.flatMap { $0 }.count == 2)
        }
        var damaged = original, damagedEntries = entries, damagedEntry = entry
        damagedEntry["faces"] = [["family": "missing path"]]; damagedEntries[a.path] = damagedEntry;
        damaged["entries"] = damagedEntries
        try f.writeCache(damaged); await f.engine.resetCalls()
        let repaired = try await (await f.store()).refresh(.incremental)
        #expect(await f.engine.calls == [[a.path]]); #expect(repaired.counts.unreadableFiles == 0)
        #expect(repaired.faces.contains { $0.path == b.path })
    }
    @Test func cacheHitUntilSizeOrMtimeChanges() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }
        let a = try f.stub("A.ttf"), broken = try f.stub("broken.ttf")
        await f.engine.scriptError(.init(path: broken.path, code: .ioError, message: "broken"))
        let store = await f.store(), first = try await store.refresh(.incremental)
        await f.engine.resetCalls()
        #expect(try await store.refresh(.incremental).faces == first.faces)
        #expect(await f.engine.calls.isEmpty)
        let newStore = await f.store()
        #expect(try await newStore.refresh(.incremental).faces == first.faces)
        #expect(await f.engine.calls.isEmpty)
        let stamp = try #require(DiscoveredFileStamp(a.path))
        var times = [
            timeval(tv_sec: Int(stamp.mtime) + 100, tv_usec: 0), timeval(tv_sec: Int(stamp.mtime) + 100, tv_usec: 0),
        ]
        #expect(utimes(a.path, &times) == 0)
        _ = try await newStore.refresh(.incremental)
        #expect(await f.engine.calls == [[a.path]])
        await f.engine.resetCalls(); _ = try await newStore.refresh(.full)
        #expect(Set(await f.engine.calls.flatMap { $0 }) == [a.path, broken.path])
    }
    @Test func catalog7Crit6PruneVanishedPathsAfterCompleteRefreshOnly() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }
        let old = try f.stub("assets/aaaa.asset/AssetData/X.ttc"),
            new = f.fonts.appendingPathComponent("assets/bbbb.asset/AssetData/X.ttc")
        await f.engine.script([FakeEngine.face(old.path, name: "X-Regular")], path: old.path)
        let store = await f.store(); _ = try await store.refresh(.incremental)
        try FileManager.default.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: old, to: new)
        await f.engine.script([FakeEngine.face(new.path, name: "X-Regular")], path: new.path)
        let snapshot = try await store.refresh(.incremental)
        #expect(snapshot.face(postscriptName: "X-Regular")?.path == new.path)
        #expect(Set(try f.entries().keys) == [new.path])
    }
    @Test func catalogM3CacheLivesInCachesAndIsWrittenAtomically() async throws {
        let standard = CatalogConfiguration.standard().cacheDirectory
        let before = FileManager.default.fileExists(atPath: standard.path)
        #expect(
            CatalogConfiguration.standard().cacheDirectory.path.hasSuffix(
                "/Library/Caches/io.github.kciceblue.fontplayground"))
        #expect(FileManager.default.fileExists(atPath: standard.path) == before)
        let f = try CatalogFixture(); defer { f.cleanup() }; _ = try f.stub("A.ttf")
        _ = try await (await f.store()).refresh(.incremental)
        var cache = CatalogCache(directory: f.cache, readerVersion: 1); cache.load()
        let original = try Data(contentsOf: cache.url)
        cache.entries = [:]; cache.beforeRename = { _ in throw FakeEngine.Failure() }
        #expect(throws: FakeEngine.Failure.self) { try cache.save() }
        #expect(try Data(contentsOf: cache.url) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.cache.path).allSatisfy { !$0.hasSuffix(".tmp") })
        cache.beforeRename = nil; try cache.save()
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.cache.path).allSatisfy { !$0.hasSuffix(".tmp") })
    }
    @Test func changedDuringScanAndNoFacesAreNeverCached() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }; let a = try f.stub("A.ttf"), b = try f.stub("B.ttf")
        var changed = FakeEngine.face(a.path); changed.size += 1
        await f.engine.script([changed], path: a.path); await f.engine.script([], path: b.path)
        let snapshot = try await (await f.store()).refresh(.incremental)
        #expect(snapshot.faces == [changed]); #expect(snapshot.counts.unreadableFiles == 1)
        #expect(try f.entries().isEmpty)
    }
}
