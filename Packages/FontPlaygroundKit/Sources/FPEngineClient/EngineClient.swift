import FPCore
import Foundation

public final class EngineClient: EngineRunning {
    public static let supportedProtocol = 1
    private let configuration: EngineConfiguration
    private let gate = HelloGate()
    private let diagnostics = Diagnostics()
    var lastStderrByteCount: Int { diagnostics.read() }
    /// Events of a type this client does not know, skipped for forward compatibility since the client was created.
    /// A newer helper on the same protocol version can send them; the count keeps each skip visible without a
    /// log handler.
    public var skippedUnknownEventCount: Int { diagnostics.skippedEvents() }

    public init(configuration: EngineConfiguration) {
        Signals.ignoreSIGPIPE()
        self.configuration = configuration
    }

    public convenience init(temporaryDirectory: URL? = nil) throws {
        self.init(configuration: .init(launch: try EngineLaunch.resolve(), temporaryDirectory: temporaryDirectory))
    }

    public func hello() async throws -> EngineHello {
        let value = try await performHello()
        await gate.record(value)
        return value
    }

    fileprivate func performHello() async throws -> EngineHello {
        let control = RunControl()
        let value: EngineHello? = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let run = HelperRun(
                    configuration: configuration, command: "hello", request: Data("{}".utf8), onEvent: { _ in },
                    onSkippedEvent: { [diagnostics] in diagnostics.recordSkippedEvent() }
                ) {
                    [diagnostics] result, count in
                    diagnostics.record(count)
                    continuation.resume(with: result.mapError { $0 as any Error })
                }
                control.install(run)
                run.start()
            }
        } onCancel: {
            control.cancel()
        }
        try Task.checkCancellation()
        guard let value else {
            throw EngineError.protocolViolation("hello ended without a hello event", stderrTail: "")
        }
        return value
    }

    public func scan(files: [String]) -> AsyncThrowingStream<ScanEvent, any Error> {
        struct Request: Encodable {
            let files: [String]
            enum CodingKeys: String, CodingKey { case files }
        }
        return stream(
            command: "scan",
            encode: {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.withoutEscapingSlashes]
                return try encoder.encode(Request(files: files))
            }
        ) { event in
            switch event {
            case .progress(let value): return .progress(value)
            case .face(let value): return .face(value)
            case .fileError(let value): return .fileError(value)
            case .result(_, let summary?, _): return .finished(summary)
            default: return nil
            }
        }
    }

    public func forge(_ request: ForgeRequest) -> AsyncThrowingStream<ForgeEvent, any Error> {
        stream(
            command: "forge", outputDirectory: URL(fileURLWithPath: request.outputPath).deletingLastPathComponent(),
            encode: { try request.encodedJSON() }
        ) { event in
            switch event {
            case .progress(let value): return .progress(value)
            case .result(_, _, let report?): return .finished(report)
            default: return nil
            }
        }
    }

    private func stream<Event: Sendable>(
        command: String, outputDirectory: URL? = nil, encode: @escaping @Sendable () throws -> Data,
        map: @escaping @Sendable (DecodedEvent) -> Event?
    ) -> AsyncThrowingStream<Event, any Error> {
        AsyncThrowingStream { continuation in
            let control = RunControl()
            continuation.onTermination = { termination in
                if case .cancelled = termination { control.cancel() }
            }
            let worker = Task { [self] in
                do {
                    try await gate.verify(self)
                    guard !Task.isCancelled else { continuation.finish(); return }
                    let data: Data
                    do { data = try encode() } catch {
                        throw EngineError.launchFailed("could not encode the request: \(error)")
                    }
                    let run = HelperRun(
                        configuration: configuration, command: command, request: data, outputDirectory: outputDirectory,
                        onEvent: { event in if let value = map(event) { continuation.yield(value) } },
                        onSkippedEvent: { [diagnostics] in diagnostics.recordSkippedEvent() }
                    ) { [diagnostics] result, count in
                        diagnostics.record(count)
                        switch result {
                        case .success: continuation.finish()
                        case .failure(let error): continuation.finish(throwing: error)
                        }
                    }
                    control.install(run)
                    run.start()
                } catch {
                    if Task.isCancelled { continuation.finish() } else { continuation.finish(throwing: error) }
                }
            }
            control.install(worker)
        }
    }

    @discardableResult
    public static func sweepLeftovers(
        temporaryDirectory: URL, outputDirectories: [URL] = [], now: Date = Date(), fileManager: FileManager = .default
    ) -> Int {
        Leftovers.remove(
            temporaryDirectory: temporaryDirectory, outputDirectories: outputDirectories, now: now,
            fileManager: fileManager
        )
    }
}

private actor HelloGate {
    private struct Flight {
        let id: UUID
        let task: Task<EngineHello, any Error>
        var waiters: Set<UUID>
    }
    private var cached: Result<EngineHello, EngineError>?
    private var inFlight: Flight?

    func record(_ hello: EngineHello) { cached = .success(hello) }

    func verify(_ client: EngineClient) async throws {
        try Task.checkCancellation()
        let hello: EngineHello
        if let cached {
            hello = try cached.get()
        } else {
            let waiter = UUID()
            let flight: Flight
            if var current = inFlight {
                current.waiters.insert(waiter)
                inFlight = current
                flight = current
            } else {
                flight = Flight(id: UUID(), task: Task { try await client.performHello() }, waiters: [waiter])
                inFlight = flight
            }
            do {
                hello = try await withTaskCancellationHandler {
                    try await flight.task.value
                } onCancel: {
                    Task { await self.cancel(waiter: waiter, flight: flight.id) }
                }
                if inFlight?.id == flight.id {
                    cached = .success(hello)
                    inFlight = nil
                }
                try Task.checkCancellation()
            } catch {
                // A previous flight's waiter must not clear a retry that has already started.
                if inFlight?.id == flight.id {
                    inFlight = nil
                    if let error = error as? EngineError, case .incompatibleHelper = error { cached = .failure(error) }
                }
                throw error
            }
        }
        for capability in ["scan", "forge"] where !hello.capabilities.contains(capability) {
            let error = EngineError.protocolViolation("helper lacks capability '\(capability)'", stderrTail: "")
            cached = .failure(error)
            throw error
        }
    }

    private func cancel(waiter: UUID, flight id: UUID) {
        guard var current = inFlight, current.id == id else { return }
        current.waiters.remove(waiter)
        if current.waiters.isEmpty {
            inFlight = nil
            current.task.cancel()
        } else {
            inFlight = current
        }
    }
}

private final class RunControl: @unchecked Sendable {
    private let lock = NSLock()
    private var run: HelperRun?
    private var worker: Task<Void, Never>?
    private var cancelled = false
    func install(_ value: HelperRun) {
        let shouldCancel = lock.withLock {
            run = value; return cancelled
        }
        if shouldCancel { value.cancel() }
    }
    func install(_ value: Task<Void, Never>) {
        let shouldCancel = lock.withLock {
            worker = value; return cancelled
        }
        if shouldCancel { value.cancel() }
    }
    func cancel() {
        let values = lock.withLock {
            cancelled = true; return (run, worker)
        }
        values.1?.cancel()
        values.0?.cancel()
    }
}

private final class Diagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var byteCount = 0
    private var skipped = 0
    func record(_ value: Int) { lock.withLock { byteCount = value } }
    func read() -> Int { lock.withLock { byteCount } }
    func recordSkippedEvent() { lock.withLock { skipped += 1 } }
    func skippedEvents() -> Int { lock.withLock { skipped } }
}
