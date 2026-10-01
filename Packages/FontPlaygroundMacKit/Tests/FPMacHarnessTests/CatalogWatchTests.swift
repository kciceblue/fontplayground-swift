import FPCore
import FPMacServices
import Foundation
import Testing
import os

@testable import FPMacHarness

struct CatalogWatchTests {
    @Test func reportsOnlyCompletedChangesByFaceKey() async {
        let old = FaceRecord(path: "/fixtures/a.ttf", family: "A", coverage: .empty, postscriptName: "A-Regular")
        var renamed = old; renamed.family = "A changed"
        let added = FaceRecord(path: "/fixtures/b.ttf", family: "B", coverage: .empty, postscriptName: "B-Regular")
        let unnamed = FaceRecord(path: "/fixtures/c.ttf", family: "C", coverage: .empty)
        let initial = snapshot([old])
        let catalog = WatchCatalog(
            initial: initial,
            later: [
                snapshot([], complete: false), snapshot([renamed, added]), snapshot([added, unnamed]),
            ], finishes: true)
        let output = Lines()
        #expect(await CatalogWatch.run(catalog: catalog, after: initial, output: output.append) == false)
        #expect(output.values == ["+ B\tRegular\tB-Regular", "+ C\tRegular\t", "- A changed\tRegular\tA-Regular"])
        #expect(await catalog.started == 1)
        #expect(await catalog.stopped == 1)
        #expect(await catalog.cancelled == 1)
    }

    @Test func cancellationStopsObservationAndAnyRefresh() async throws {
        let catalog = WatchCatalog(initial: snapshot([]), later: [], finishes: false)
        let task = Task { await CatalogWatch.run(catalog: catalog, after: snapshot([]), output: { _ in }) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await catalog.started == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await catalog.started == 1)
        task.cancel()
        #expect(await task.value)
        #expect(await catalog.stopped == 1)
        #expect(await catalog.cancelled == 1)
    }
}

private func snapshot(_ faces: [FaceRecord], complete: Bool = true) -> CatalogSnapshot {
    .init(
        generation: 1, faces: faces, annotations: [:], counts: .init(), issues: [], isComplete: complete,
        activity: .idle)
}

private actor WatchCatalog: FontCataloging {
    let initial: CatalogSnapshot
    let later: [CatalogSnapshot]
    let finishes: Bool
    let stream: AsyncStream<CatalogSnapshot>
    let continuation: AsyncStream<CatalogSnapshot>.Continuation
    var started = 0, stopped = 0, cancelled = 0
    init(initial: CatalogSnapshot, later: [CatalogSnapshot], finishes: Bool) {
        self.initial = initial; self.later = later; self.finishes = finishes
        (stream, continuation) = AsyncStream.makeStream()
    }
    func currentSnapshot() -> CatalogSnapshot { initial }
    func snapshots() -> AsyncStream<CatalogSnapshot> { continuation.yield(initial); return stream }
    func refresh(_ mode: RefreshMode) -> CatalogSnapshot { initial }
    func cancelRefresh() { cancelled += 1 }
    func extraFolders() -> [URL] { [] }
    func setExtraFolders(_ folders: [URL]) {}
    func noteInstalled(_ fileURL: URL) -> CatalogSnapshot { initial }
    func noteRemoved(_ fileURL: URL) -> CatalogSnapshot { initial }
    func startObservingSystemChanges() {
        started += 1
        for snapshot in later { continuation.yield(snapshot) }
        if finishes { continuation.finish() }
    }
    func stopObservingSystemChanges() { stopped += 1 }
}

final class Lines: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [String]())
    var values: [String] { storage.withLock { $0 } }
    func append(_ value: String) { storage.withLock { $0.append(value) } }
}
