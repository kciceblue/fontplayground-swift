import Darwin
import FPCore
import FPEngineClient
import Foundation
import Testing

@testable import FPMacServices

actor SnapshotLog {
    var values: [(ContinuousClock.Instant, CatalogSnapshot)] = []
    func record(_ snapshot: CatalogSnapshot) { values.append((.now, snapshot)) }
}
struct CatalogStoreTests {
    @Test func scanRunsInBoundedBatchesWithProgress() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }
        for i in 0..<100 { _ = try f.stub(String(format: "%03d.ttf", i)) }
        await f.engine.setDelay(.milliseconds(100))
        let store = await f.store(), log = SnapshotLog(), stream = await store.snapshots()
        let reader = Task { for await snapshot in stream { await log.record(snapshot) } }; defer { reader.cancel() }
        let snapshot = try await store.refresh(.incremental)
        try await eventually { await log.values.last?.1.isComplete == true }
        #expect(await f.engine.calls.map(\.count).sorted() == [4, 48, 48]); #expect(await f.engine.peak == 2)
        #expect(snapshot.counts.faces == 100); #expect(snapshot.isComplete); #expect(snapshot.activity == .idle)
        let intermediate = await log.values.filter {
            if case .refreshing = $0.1.activity { return true }; return false
        }
        let fractions = intermediate.compactMap {
            if case .refreshing(let p) = $0.1.activity { return p.fraction }; return nil
        }
        #expect(fractions == fractions.sorted()); #expect(fractions.last == 1)
        #expect(intermediate.allSatisfy { !$0.1.isComplete })
        for (a, b) in zip(intermediate, intermediate.dropFirst()) {
            #expect(a.0.duration(to: b.0) >= .milliseconds(18))
        }
    }
    @Test func scanReportsFacesFailuresAndProgress() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }
        for name in ["A.ttf", "B.otf", "C.ttf", "K.ttf", "V.ttf", "T.ttc", "broken.ttf"] { _ = try f.stub(name) }
        let t = f.fonts.appendingPathComponent("T.ttc").path
        var second = FakeEngine.face(t, name: "T-Second"); second.index = 1
        await f.engine.script([FakeEngine.face(t), second], path: t)
        let broken = f.fonts.appendingPathComponent("broken.ttf").path
        await f.engine.scriptError(.init(path: broken, code: .ioError, message: "broken"))
        let store = await f.store(), log = SnapshotLog(), stream = await store.snapshots()
        let reader = Task { for await value in stream { await log.record(value) } }; defer { reader.cancel() }
        let snapshot = try await store.refresh(.incremental)
        try await eventually { await log.values.last?.1.isComplete == true }
        #expect(snapshot.faces.count == 7);
        #expect(snapshot.issues == [.unreadable(path: broken, code: "io_error", message: "broken")])
        #expect(await log.values.contains { $0.1.activity == .refreshing(.init(filesDone: 7, filesTotal: 7)) })
    }
    @Test func helperFailuresAreIsolated() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }
        for i in 0..<9 { _ = try f.stub("good\(i).ttf") }
        let bad = try f.stub("bad.ttf"); await f.engine.setFailures([bad.path])
        let store = await f.store(), snapshot = try await store.refresh(.incremental)
        #expect(snapshot.faces.count == 9);
        #expect(
            snapshot.issues.contains {
                if case .unreadable(bad.path, "helper_failed", _) = $0 { return true }; return false
            })
        #expect(try f.entries()[bad.path] == nil)
        let before = try Data(contentsOf: f.cache.appendingPathComponent("catalog-v1.json"))
        await f.engine.setHelloError(FakeEngine.Failure())
        let unavailable = await f.store()
        await #expect(throws: CatalogError.self) { try await unavailable.refresh(.incremental) }
        #expect(await unavailable.currentSnapshot().faces.isEmpty)
        #expect(try Data(contentsOf: f.cache.appendingPathComponent("catalog-v1.json")) == before)
        await f.engine.setHelloError(nil); await f.engine.setThrowAtStart(EngineError.launchFailed("x"))
        await #expect(throws: CatalogError.self) { try await store.refresh(.incremental) }
        #expect(await store.currentSnapshot().faces == snapshot.faces)
        #expect(try Data(contentsOf: f.cache.appendingPathComponent("catalog-v1.json")) == before)
        await f.engine.setThrowAtStart(FakeEngine.Failure())
        let failed = try await store.refresh(.full)
        #expect(failed.counts.unreadableFiles == 10); #expect(failed.faces.isEmpty)
    }
    @Test func refreshRequestsAreCoalesced() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }; _ = try f.stub("A.ttf")
        await f.engine.blockNextScan()
        let store = await f.store(), first = Task { try await store.refresh(.incremental) }
        try await eventually { await f.engine.calls.count == 1 }
        let second = Task { try await store.refresh(.incremental) }, third = Task { try await store.refresh(.full) },
            fourth = Task { try await store.refresh(.incremental) }
        try await Task.sleep(for: .milliseconds(50)); await f.engine.release()
        let initial = try await first.value, next = try await second.value, full = try await third.value,
            last = try await fourth.value
        #expect(initial.generation < next.generation); #expect(next.generation == full.generation);
        #expect(full.generation == last.generation)
        #expect(await store.refreshCount == 2); #expect(await f.engine.calls.count == 2)
    }
    @Test func cancelKeepsCompletedWorkAndDoesNotPrune() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }; let old = try f.stub("old.ttf")
        var config = f.configuration; config.batchMaxFiles = 1; config.maxConcurrentScans = 1
        let store = await f.store(config: config); _ = try await store.refresh(.incremental)
        try FileManager.default.removeItem(at: old)
        let a = try f.stub("A.ttf"); _ = try f.stub("B.ttf"); _ = try f.stub("C.ttf")
        await f.engine.resetCalls(); await f.engine.blockScan(1)
        let first = Task { try await store.refresh(.incremental) }
        try await eventually { await f.engine.calls.count == 2 }
        let queued = Task { try await store.refresh(.full) }
        try await Task.sleep(for: .milliseconds(20)); await store.cancelRefresh()
        await #expect(throws: CancellationError.self) { try await first.value }
        await #expect(throws: CancellationError.self) { try await queued.value }
        try await eventually { await f.engine.cancelled.contains(1) }
        try await eventually { await store.currentSnapshot().activity == .idle }
        #expect(!(await store.currentSnapshot().isComplete)); #expect(await f.engine.calls.count == 2)
        #expect(Set(try f.entries().keys) == [old.path, a.path])
    }
    @Test func cancelledFirstScanKeepsTheCurrentDiscovery() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }
        _ = try f.stub("A.ttf"); _ = try f.stub("B.ttf")
        let gone = f.root.appendingPathComponent("gone.ttf").path
        f.registry.menuVisible = ["Stub-A", "Stub-B"]
        f.registry.files = [.init(path: gone, postscriptNames: ["Gone"])]
        var config = f.configuration; config.batchMaxFiles = 1; config.maxConcurrentScans = 1
        await f.engine.blockScan(1)
        let store = await f.store(config: config)
        let first = Task { try await store.refresh(.incremental) }
        try await eventually { await f.engine.calls.count == 2 }
        await store.cancelRefresh()
        await #expect(throws: CancellationError.self) { try await first.value }
        try await eventually { await store.currentSnapshot().activity == .idle }
        let snapshot = await store.currentSnapshot()
        let face = try #require(snapshot.face(postscriptName: "Stub-A"))
        #expect(!snapshot.isComplete && snapshot.annotations[face.key]?.hiddenFromMenus == false)
        #expect(snapshot.issues.contains(.unreadable(path: gone, code: "not_found", message: "File not found.")))
    }
    @Test func callerCancellationDoesNotCancelSharedRefresh() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }; _ = try f.stub("A.ttf")
        await f.engine.blockNextScan(); let store = await f.store()
        let first = Task { try await store.refresh(.incremental) }
        try await eventually { await f.engine.calls.count == 1 }
        first.cancel(); await #expect(throws: CancellationError.self) { try await first.value }
        #expect(await f.engine.cancelled.isEmpty)
        await f.engine.release(); try await eventually { await store.currentSnapshot().isComplete }
        #expect(await store.currentSnapshot().faces.count == 1)
    }
    @Test func install6IncrementalUpdateAfterOwnInstall() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }; let old = try f.stub("old.ttf")
        let store = await f.store(); _ = try await store.refresh(.incremental)
        let new = try f.stub("new.ttf"); await f.engine.resetCalls(); f.registry.resetCalls()
        let snapshot = try await store.noteInstalled(new)
        #expect(await f.engine.calls == [[new.path]]); #expect(f.registry.calls.isEmpty)
        let face = try #require(snapshot.face(postscriptName: "Stub-new"))
        #expect(snapshot.annotations[face.key]?.origin == .user);
        #expect(snapshot.annotations[face.key]?.hiddenFromMenus == false)
        #expect(Set(try f.entries().keys) == [old.path, new.path])
        await f.engine.resetCalls(); _ = await store.noteRemoved(new)
        #expect(await f.engine.calls.isEmpty); #expect(f.registry.calls.isEmpty)
        #expect(Set(try f.entries().keys) == [old.path]); #expect(await store.currentSnapshot().faces.count == 1)
    }
    @Test func extraFoldersAddRemoveAndReportAccess() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }
        let a = try f.stub("A/A.ttf"), b = try f.stub("B/B.ttf")
        var config = f.configuration; config.standardFolders = [f.root.appendingPathComponent("missing-standard")]
        let store = CatalogStore(engine: f.engine, registry: f.registry, configuration: config)
        await store.setExtraFolders([a.deletingLastPathComponent(), b.deletingLastPathComponent()])
        #expect(await f.engine.calls.isEmpty)
        #expect(try await store.refresh(.incremental).faces.count == 2)
        await store.setExtraFolders([a.deletingLastPathComponent()]); _ = try await store.refresh(.incremental)
        #expect(Set(try f.entries().keys) == [a.path])
        let missing = f.root.appendingPathComponent("missing")
        await store.setExtraFolders([missing, URL(string: "relative")!])
        let result = try await store.refresh(.incremental)
        #expect(result.issues.count == 2)
        #expect(result.issues.contains(.folderMissing(folder: missing.path)))
        let denied = a.deletingLastPathComponent(); #expect(chmod(denied.path, 0) == 0)
        defer { chmod(denied.path, 0o700) }
        await store.setExtraFolders([denied]); let inaccessible = try await store.refresh(.incremental)
        #expect(inaccessible.counts.inaccessibleFolders == 1);
        #expect(inaccessible.issues.contains(.noAccess(folder: denied.path)))
    }
    @Test func ownInstallPreservesUnnamedRegisteredOrigin() async throws {
        let f = try CatalogFixture(); defer { f.cleanup() }
        let file = try f.stub("Activated.ttf", in: f.root.appendingPathComponent("outside"))
        f.registry.files = [.init(path: file.path, postscriptNames: [])]
        let store = await f.store(); _ = try await store.refresh(.incremental)
        f.registry.resetCalls(); await f.engine.resetCalls()
        let snapshot = try await store.noteInstalled(file)
        #expect(snapshot.annotations.values.first?.origin == .activated)
        #expect(f.registry.calls.isEmpty); #expect(await f.engine.calls.isEmpty)
    }

}
