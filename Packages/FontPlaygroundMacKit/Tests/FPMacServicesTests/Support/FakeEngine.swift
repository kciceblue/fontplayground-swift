import FPCore
import FPEngineClient
import Foundation

actor FakeEngine: EngineRunning {
    struct Failure: Error {}
    var readerVersion = 1
    var helloError: (any Error)?
    var throwAtStart: (any Error)?
    var throwWhenBatchContains: Set<String> = []
    var delayPerBatch: Duration = .zero
    var scriptedFaces: [String: [FaceRecord]] = [:]
    var scriptedErrors: [String: ScanFileError] = [:]
    private(set) var helloCalls = 0
    private(set) var calls: [[String]] = []
    private(set) var peak = 0
    private(set) var cancelled: [Int] = []
    private var concurrent = 0
    private var blockedCall: Int?
    func blockNextScan() { blockedCall = calls.count }
    func blockScan(_ index: Int) { blockedCall = index }
    func release() { blockedCall = nil }
    func setReaderVersion(_ value: Int) { readerVersion = value }
    func setHelloError(_ value: (any Error)?) { helloError = value }
    func setThrowAtStart(_ value: (any Error)?) { throwAtStart = value }
    func setFailures(_ paths: Set<String>) { throwWhenBatchContains = paths }
    func setDelay(_ duration: Duration) { delayPerBatch = duration }
    func script(_ faces: [FaceRecord], path: String) { scriptedFaces[path] = faces }
    func scriptError(_ error: ScanFileError) { scriptedErrors[error.path] = error }
    func resetCalls() { calls = []; peak = 0 }
    func hello() throws -> EngineHello {
        helloCalls += 1
        if let helloError { throw helloError }
        return try JSONDecoder().decode(
            EngineHello.self,
            from: Data(
                """
                {"protocol":1,"face_reader_version":\(readerVersion),"fpengine_version":"test","python":"test",
                "fonttools":"test","platform":"darwin","capabilities":["scan"]}
                """.utf8))
    }
    nonisolated func scan(files: [String]) -> AsyncThrowingStream<ScanEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { await self.run(files, continuation: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    private func run(_ files: [String], continuation: AsyncThrowingStream<ScanEvent, any Error>.Continuation) async {
        let index = calls.count; calls.append(files); concurrent += 1; peak = max(peak, concurrent)
        defer { concurrent -= 1 }
        do {
            while blockedCall == index { try await Task.sleep(for: .milliseconds(5)) }
            if delayPerBatch > .zero { try await Task.sleep(for: delayPerBatch) }
            try Task.checkCancellation()
            if let throwAtStart { throw throwAtStart }
            var faceCount = 0, errors = 0
            for (i, path) in files.enumerated() {
                if throwWhenBatchContains.contains(path) { throw Failure() }
                if let error = scriptedErrors[path] {
                    continuation.yield(.fileError(error)); errors += 1
                } else {
                    let faces = scriptedFaces[path] ?? [Self.face(path)]
                    for face in faces { continuation.yield(.face(face)); faceCount += 1 }
                }
                continuation.yield(
                    .progress(
                        .init(
                            stage: .scan, fraction: Double(i + 1) / Double(files.count), done: i + 1, total: files.count
                        )))
            }
            continuation.yield(
                .finished(.init(files: files.count, faces: faceCount, fileErrors: errors, duplicates: 0)))
            continuation.finish()
        } catch {
            if error is CancellationError { cancelled.append(index) }
            continuation.finish(throwing: error)
        }
    }
    nonisolated static func face(_ path: String, name: String? = nil) -> FaceRecord {
        let url = URL(fileURLWithPath: path)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 1
        return FaceRecord(
            path: path, family: "Stub " + url.lastPathComponent, coverage: CodepointSet(ranges: [0x61...0x63]),
            size: size, postscriptName: name ?? "Stub-" + url.deletingPathExtension().lastPathComponent)
    }
    nonisolated func forge(_ request: ForgeRequest) -> AsyncThrowingStream<ForgeEvent, any Error> {
        AsyncThrowingStream { $0.finish(throwing: Failure()) }
    }
}
