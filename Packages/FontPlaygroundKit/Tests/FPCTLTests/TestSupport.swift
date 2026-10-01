import FPCore
import FPEngineClient
import Foundation
import Testing

@testable import fpctl

final class CapturedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: (out: [String], err: [String]) = ([], [])
    var output: CommandOutput {
        .init(
            out: { [self] line in lock.withLock { lines.out.append(line) } },
            err: { [self] line in lock.withLock { lines.err.append(line) } })
    }
    var out: String { lock.withLock { lines.out.joined(separator: "\n") } }
    var err: String { lock.withLock { lines.err.joined(separator: "\n") } }
}
struct CLIArea {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fpctl-tests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func file(_ name: String) -> URL { root.appendingPathComponent(name) }
    func fonts() throws -> URL {
        let python = try #require(ProcessInfo.processInfo.environment["FP_ENGINE_PYTHON"])
        let folder = file("fonts")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-I", "-B", "-m", "fpengine.testing.make_fonts", folder.path]
        process.standardOutput = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        return folder
    }
    func recipe(_ faces: [FaceRecord], name: String = "recipe.fontrecipe") throws -> String {
        var recipe = Recipe()
        for face in faces { _ = recipe.add(face) }
        try AtomicFile.write(RecipeDocument(recipe: recipe).encoded(), to: file(name).path)
        return file(name).path
    }
}
let cliRepo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

final class FakeCLIEngine: EngineRunning, @unchecked Sendable {
    enum Mode: Sendable { case success, fail, wait, noResult }
    let faces: [FaceRecord]
    let mode: Mode
    private let lock = NSLock()
    private var requests: [ForgeRequest] = []
    private var scanned: [[String]] = []
    var forges: [ForgeRequest] { lock.withLock { requests } }
    var scans: [[String]] { lock.withLock { scanned } }
    init(faces: [FaceRecord] = [], mode: Mode = .success) { self.faces = faces; self.mode = mode }
    func hello() async throws -> EngineHello {
        .init(
            fpengineVersion: "0.1.0", python: "3.12", fonttools: "4", platform: "fake", capabilities: ["scan", "forge"])
    }
    func scan(files: [String]) -> AsyncThrowingStream<ScanEvent, any Error> {
        lock.withLock { scanned.append(files) }
        return AsyncThrowingStream { stream in
            for face in faces { stream.yield(.face(face)) }
            stream.yield(.finished(.init(files: files.count, faces: faces.count, fileErrors: 0, duplicates: 0)))
            stream.finish()
        }
    }
    func forge(_ request: ForgeRequest) -> AsyncThrowingStream<ForgeEvent, any Error> {
        lock.withLock { requests.append(request) }
        return AsyncThrowingStream { continuation in
            switch mode {
            case .success:
                for stage in [EngineStage.validate, .prepare, .prepare, .done] {
                    continuation.yield(
                        .progress(
                            .init(
                                stage: stage, fraction: stage == .done ? 1 : 0,
                                materialIndex: stage == .prepare ? 0 : nil)))
                }
                continuation.yield(.finished(.init(outputPath: request.outputPath, totalCodepoints: 3, totalGlyphs: 4)))
                continuation.finish()
            case .fail:
                continuation.finish(
                    throwing: EngineError.helperFailed(
                        .init(
                            code: .unsupportedFont, stage: .validate, message: "cannot use this font",
                            detail: "verbose details")))
            case .noResult: continuation.finish()
            case .wait:
                continuation.yield(.progress(.init(stage: .prepare, fraction: 0.2)))
                continuation.onTermination = { _ in }
            }
        }
    }
    var handle: EngineHandle { .init(engine: self, helper: "fake", temporaryDirectory: nil) }
}
