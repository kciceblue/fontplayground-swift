import FPCore
import Foundation
import Testing

@testable import FPEngineClient

enum RepoPaths {
    static var root: URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: url.appendingPathComponent("spec/protocol").path) {
            precondition(url.path != "/", "Repository root not found")
            url.deleteLastPathComponent()
        }
        return url
    }
    static func example(_ name: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("spec/protocol/examples/\(name).jsonl"))
    }
}

final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func read() -> Value { lock.withLock { value } }
    func update(_ work: (inout Value) -> Void) { lock.withLock { work(&value) } }
}

struct TestArea {
    let root: URL
    let record: URL
    let temporary: URL
    let output: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("FPEngineClientTests-\(UUID())")
        record = root.appendingPathComponent("record")
        temporary = root.appendingPathComponent("tmp")
        output = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func configuration(_ scenario: String) -> EngineConfiguration {
        EngineConfiguration(
            launch: .init(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: [
                    Bundle.module.url(forResource: "fake-fpengine", withExtension: "sh", subdirectory: "Resources")!
                        .path
                ],
                environment: ["FAKE_SCENARIO": scenario, "FAKE_RECORD": record.path, "FAKE_OUTDIR": output.path]
            ), temporaryDirectory: temporary
        )
    }
    func request() -> ForgeRequest { .init(spec: .init(), outputPath: output.appendingPathComponent("out.ttf").path) }
    func recorded() -> String { (try? String(contentsOf: record, encoding: .utf8)) ?? "" }
}

func collect<Element: Sendable>(_ stream: AsyncThrowingStream<Element, any Error>) async throws -> [Element] {
    var result: [Element] = []
    for try await element in stream { result.append(element) }
    return result
}

func eventually(_ condition: @Sendable () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !condition() {
        guard ContinuousClock.now < deadline else { throw EngineError.launchFailed("Test condition timed out") }
        try await Task.sleep(for: .milliseconds(5))
    }
}
