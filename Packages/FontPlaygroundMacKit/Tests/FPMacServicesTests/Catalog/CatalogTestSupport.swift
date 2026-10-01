import FPCore
import FPEngineClient
import Foundation
import Testing

@testable import FPMacServices

struct CatalogFixture: Sendable {
    let root: URL
    let engine = FakeEngine()
    let registry = FakeRegistry()
    var fonts: URL { root.appendingPathComponent("fonts") }
    var cache: URL { root.appendingPathComponent("cache") }
    var configuration: CatalogConfiguration {
        var value = CatalogConfiguration(
            cacheDirectory: cache, userFontsFolder: fonts,
            homeDirectory: root.appendingPathComponent("home"), maxConcurrentScans: 2)
        value.publishInterval = .milliseconds(20)
        return value
    }
    init() throws { root = try TestEnv.temporaryDirectory() }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    func stub(_ name: String, in folder: URL? = nil, bytes: Data? = nil) throws -> URL {
        let url = (folder ?? fonts).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (bytes ?? Data([0, 1, 0, 0]) + Data(name.utf8)).write(to: url)
        return url
    }
    func store(config: CatalogConfiguration? = nil) async -> CatalogStore {
        let store = CatalogStore(engine: engine, registry: registry, configuration: config ?? configuration)
        await store.setExtraFolders([fonts]); return store
    }
    func cacheObject() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: cache.appendingPathComponent("catalog-v1.json")))
            as! [String: Any]
    }
    func entries() throws -> [String: Any] { try cacheObject()["entries"] as! [String: Any] }
    func writeCache(_ object: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: object).write(to: cache.appendingPathComponent("catalog-v1.json"))
    }
}
struct CatalogTimeout: Error {}
func eventually(timeout: Duration = .seconds(3), _ predicate: @escaping @Sendable () async -> Bool) async throws {
    let start = ContinuousClock.now
    while !(await predicate()) {
        if start.duration(to: .now) > timeout {
            Issue.record("Timed out waiting for catalog state"); throw CatalogTimeout()
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
func realCatalogEngine(temporary: URL) throws -> EngineClient {
    let python = try #require(TestEnv.enginePython)
    return EngineClient(
        configuration: .init(
            launch: try EngineLaunch.resolve(environment: ["FP_ENGINE_PYTHON": python], bundleURL: nil),
            temporaryDirectory: temporary))
}
