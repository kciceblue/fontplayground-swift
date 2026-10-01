import Darwin
import FPCore
import FPEngineClient
import Foundation
import Testing

@testable import FPMacServices

actor CountingCatalogEngine: EngineRunning {
    let base: any EngineRunning
    private(set) var scanCalls = 0
    init(_ base: any EngineRunning) { self.base = base }
    func hello() async throws -> EngineHello { try await base.hello() }
    private func count() { scanCalls += 1 }
    nonisolated func scan(files: [String]) -> AsyncThrowingStream<ScanEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.count()
                do {
                    for try await event in base.scan(files: files) { continuation.yield(event) }; continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    nonisolated func forge(_ request: ForgeRequest) -> AsyncThrowingStream<ForgeEvent, any Error> {
        base.forge(request)
    }
}
enum CatalogProcessMetrics {
    static func children() -> Set<pid_t> {
        var pids = [pid_t](repeating: 0, count: 4096)
        let bytes = proc_listchildpids(getpid(), &pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard bytes > 0 else { return [] }
        return Set(pids.prefix(Int(bytes) / MemoryLayout<pid_t>.stride).filter { $0 > 0 })
    }
    static func footprint() throws -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        #expect(result == KERN_SUCCESS)
        return info.phys_footprint
    }
}
actor CatalogChildMonitor {
    private(set) var seen: Set<pid_t> = []
    func sample() { seen.formUnion(CatalogProcessMetrics.children()) }
    func exited(excluding before: Set<pid_t>) -> Bool {
        seen.subtracting(before).allSatisfy { kill($0, 0) == -1 && errno == ESRCH }
    }
}
extension InstallationIntegration {
    struct CatalogIntegrationTests {
        @Test(.enabled(if: TestEnv.enginePython != nil)) func realHelperScansFixturesAndLeavesNoChildren() async throws
        {
            let f = try CatalogFixture(); defer { f.cleanup() }
            let tag = TestEnv.tag()
            let specs: [FontSpec] = [
                .init(file: "Static.ttf", family: "Catalog Static \(tag)", postscriptName: "CatStatic-\(tag)"),
                .init(
                    file: "Collection.ttc", family: "Catalog TTC \(tag)",
                    faces: [
                        .init(file: "", family: "Catalog TTC One \(tag)", postscriptName: "CatTTC1-\(tag)"),
                        .init(file: "", family: "Catalog TTC Two \(tag)", postscriptName: "CatTTC2-\(tag)"),
                    ]),
                .init(
                    file: "Variable.ttf", family: "Catalog Variable \(tag)", postscriptName: "CatVariable-\(tag)",
                    axes: [.init(tag: "wght", min: 100, default: 400, max: 900)]),
                .init(file: "NoOS2.ttf", family: "Catalog NoOS2 \(tag)", postscriptName: "CatNoOS2-\(tag)", os2: false),
                .init(
                    file: "Forged.ttf", family: "Catalog Forged \(tag)", postscriptName: "CatForged-\(tag)",
                    notice: MacServicesConstants.forgedNotice),
                .init(
                    file: "Localized.ttf", family: "Catalog Local \(tag)", postscriptName: "CatLocal-\(tag)",
                    localizedFamily: ["0411": "カタログ \(tag)"]),
            ]
            _ = try FixtureFonts.build(specs, in: f.fonts)
            let engine = try realCatalogEngine(temporary: f.root.appendingPathComponent("helper"))
            let store = CatalogStore(engine: engine, registry: f.registry, configuration: f.configuration)
            await store.setExtraFolders([f.fonts])
            let before = CatalogProcessMetrics.children(), monitor = CatalogChildMonitor()
            let poll = Task {
                while !Task.isCancelled { await monitor.sample(); try? await Task.sleep(for: .milliseconds(10)) }
            }
            defer { poll.cancel() }
            let snapshot = try await store.refresh(.incremental); await monitor.sample(); poll.cancel()
            #expect(snapshot.counts.files == 6); #expect(snapshot.faces.count == 7);
            #expect(snapshot.counts.unreadableFiles == 0)
            #expect(
                Set(snapshot.faces.compactMap(\.postscriptName))
                    == Set(
                        ["CatStatic", "CatTTC1", "CatTTC2", "CatVariable", "CatNoOS2", "CatForged", "CatLocal"].map {
                            $0 + "-" + tag
                        }))
            #expect(snapshot.face(postscriptName: "CatForged-" + tag)?.isForged == true)
            #expect(snapshot.face(postscriptName: "CatVariable-" + tag)?.isVariable == true)
            #expect(snapshot.face(postscriptName: "CatLocal-" + tag)?.localNames.contains("カタログ " + tag) == true)
            try await eventually(timeout: .seconds(3)) { await monitor.exited(excluding: before) }
        }
    }
    struct CatalogRealFontsTests {
        @Test(.enabled(if: TestEnv.appleFonts && TestEnv.enginePython != nil)) func coldWarmBudgetsAndContent()
            async throws
        {
            let f = try CatalogFixture(); defer { f.cleanup() }
            var configuration = CatalogConfiguration.standard(); configuration.cacheDirectory = f.cache
            let registry = CoreTextFontRegistry(),
                engine = CountingCatalogEngine(
                    try realCatalogEngine(temporary: f.root.appendingPathComponent("helper")))
            let store = CatalogStore(engine: engine, registry: registry, configuration: configuration)
            let beforeChildren = CatalogProcessMetrics.children(), memoryBefore = try CatalogProcessMetrics.footprint(),
                monitor = CatalogChildMonitor()
            let poll = Task {
                while !Task.isCancelled { await monitor.sample(); try? await Task.sleep(for: .milliseconds(10)) }
            }
            defer { poll.cancel() }
            let start = ContinuousClock.now, snapshot = try await store.refresh(.incremental),
                cold = start.duration(to: .now)
            let memoryAfter = try CatalogProcessMetrics.footprint(); await monitor.sample(); poll.cancel()
            try await eventually(timeout: .seconds(3)) { await monitor.exited(excluding: beforeChildren) }
            #expect(cold <= .seconds(15)); #expect(memoryAfter <= memoryBefore + 200 * 1024 * 1024)
            let warmEngine = CountingCatalogEngine(
                try realCatalogEngine(temporary: f.root.appendingPathComponent("helper-warm")))
            let warmStore = CatalogStore(engine: warmEngine, registry: registry, configuration: configuration)
            let warmStart = ContinuousClock.now, warmSnapshot = try await warmStore.refresh(.incremental),
                warm = warmStart.duration(to: .now)
            print(
                "WP-401 catalog: files=\(snapshot.counts.files), faces=\(snapshot.faces.count), cold=\(cold), warm=\(warm), footprintDelta=\(Int64(memoryAfter) - Int64(memoryBefore)), warmScans=\(await warmEngine.scanCalls)"
            )
            #expect(warm <= .seconds(1.5)); #expect(await warmEngine.scanCalls == 0)
            #expect(warmSnapshot.faces == snapshot.faces)
            #expect(CatalogReport.check(snapshot, menuVisible: registry.menuVisiblePostScriptNames()).isEmpty)
            if FileManager.default.fileExists(atPath: "/System/Library/Fonts/Times.ttc") {
                let times = try #require(snapshot.face(postscriptName: "Times-Roman"))
                #expect(snapshot.annotations[times.key]?.hiddenFromMenus == true)
            }
        }
    }
}
