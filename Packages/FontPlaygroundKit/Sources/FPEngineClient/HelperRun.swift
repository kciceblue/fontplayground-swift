import Foundation

/// Pipe owners run on dedicated threads; all shared lifecycle state is under one lock.
final class HelperRun: @unchecked Sendable {
    private let lock = NSLock()
    private let finished = DispatchGroup()
    private let configuration: EngineConfiguration
    private let command: String
    private let request: Data
    private let outputDirectory: URL?
    private let onEvent: @Sendable (DecodedEvent) -> Void
    private let onSkippedEvent: @Sendable () -> Void
    private let onFinish: @Sendable (Result<EngineHello?, EngineError>, Int) -> Void
    private var process: Process?
    private var started = false
    private var exited = false
    private var exitCode: Int32?
    private var signal: Int32?
    private var stdoutEOF = false
    private var stderrEOF = false
    private var partialLine = false
    private var completed = false
    private var terminal = false
    private var hello: EngineHello?
    private var failure: EngineError?
    private var cancelled = false
    private var timedOut: Duration?
    private var terminating = false
    private var stderr: StderrRing
    private var deadline: Task<Void, Never>?
    private var timers: [Task<Void, Never>] = []

    init(
        configuration: EngineConfiguration, command: String, request: Data, outputDirectory: URL? = nil,
        onEvent: @escaping @Sendable (DecodedEvent) -> Void,
        onSkippedEvent: @escaping @Sendable () -> Void = {},
        onFinish: @escaping @Sendable (Result<EngineHello?, EngineError>, Int) -> Void
    ) {
        self.configuration = configuration
        self.command = command
        self.request = request
        self.outputDirectory = outputDirectory
        self.onEvent = onEvent
        self.onSkippedEvent = onSkippedEvent
        self.onFinish = onFinish
        stderr = StderrRing(capacity: configuration.stderrCapacity)
        finished.enter()
    }

    func start() {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        started = true
        let child = Process()
        let input = Pipe(), output = Pipe(), errors = Pipe()
        child.executableURL = configuration.launch.executableURL
        child.arguments = configuration.launch.arguments + [command]
        child.currentDirectoryURL = URL(fileURLWithPath: "/")
        var environment = ProcessInfo.processInfo.environment.merging(configuration.launch.environment) { _, new in new
        }
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        do {
            if let directory = configuration.temporaryDirectory {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                environment["TMPDIR"] = directory.path
            }
            child.environment = environment
            child.standardInput = input
            child.standardOutput = output
            child.standardError = errors
            child.terminationHandler = { [weak self] process in self?.didExit(process) }
            process = child
            try child.run()
            configuration.processObserver?(.launched(pid: child.processIdentifier, command: command))
            resetDeadlineLocked()
            lock.unlock()
        } catch {
            failure = .launchFailed(String(describing: error))
            exited = true
            stdoutEOF = true
            stderrEOF = true
            lock.unlock()
            finishIfReady()
            return
        }
        // Foundation owns the child-side pipe ends. Only each reader closes its own end.
        thread("fpengine-stdin") { [self] in
            defer { try? input.fileHandleForWriting.close() }
            do { try input.fileHandleForWriting.write(contentsOf: request) } catch { log("stdin closed: \(error)") }
        }
        thread("fpengine-stdout") { [self] in readStdout(output.fileHandleForReading) }
        thread("fpengine-stderr") { [self] in readStderr(errors.fileHandleForReading) }
    }

    func cancel() {
        lock.withLock {
            guard !completed, !terminal else { return }
            cancelled = true
            if !started { exited = true; stdoutEOF = true; stderrEOF = true }
            terminateLocked()
        }
        finishIfReady()
        // NATIVE-7: onTermination must not release the caller before the child and leftovers are gone.
        finished.wait()
    }

    private func thread(_ name: String, _ work: @escaping @Sendable () -> Void) {
        let thread = Thread(block: work)
        thread.name = name
        thread.start()
    }

    private func readStdout(_ handle: FileHandle) {
        defer { try? handle.close() }
        var framer = LineFramer()
        while true {
            let data = handle.availableData
            if data.isEmpty { break }
            if lock.withLock({ completed || terminal || failure != nil || cancelled || timedOut != nil }) { continue }
            do {
                let lines = try framer.append(data)
                lock.withLock { partialLine = framer.hasPartialLine }
                for line in lines { receive(line) }
            } catch {
                reject(.protocolViolation("line longer than 32 MiB", stderrTail: ""))
            }
        }
        lock.withLock {
            if !terminal { partialLine = framer.finish() != nil }
            stdoutEOF = true
        }
        finishIfReady()
    }

    private func readStderr(_ handle: FileHandle) {
        defer { try? handle.close() }
        var pending = Data()
        let logChunkBytes = 65_536
        while true {
            let data = handle.availableData
            if data.isEmpty { break }
            if lock.withLock({ completed }) { continue }
            lock.withLock { stderr.append(data) }
            if let log = configuration.logHandler {
                pending.append(data)
                while !pending.isEmpty {
                    if let newline = pending.prefix(logChunkBytes).firstIndex(of: 10) {
                        log(String(decoding: pending[..<newline], as: UTF8.self))
                        pending.removeSubrange(...newline)
                    } else if pending.count >= logChunkBytes {
                        log(String(decoding: pending.prefix(logChunkBytes), as: UTF8.self))
                        pending.removeFirst(logChunkBytes)
                    } else {
                        break
                    }
                }
            }
        }
        if !pending.isEmpty { configuration.logHandler?(String(decoding: pending, as: UTF8.self)) }
        lock.withLock { stderrEOF = true }
        finishIfReady()
    }

    private func receive(_ line: Data) {
        let ignore = lock.withLock {
            if completed || terminal || cancelled || failure != nil || timedOut != nil { return true }
            if command == "scan" { resetDeadlineLocked() }
            return false
        }
        if ignore { return }
        do {
            guard let event = try EventDecoder().decode(line, command: command) else {
                // Skipped for forward compatibility, but always counted: the log handler is optional.
                onSkippedEvent()
                log("ignored unknown event type")
                return
            }
            lock.withLock {
                switch event {
                case .hello(let value): hello = value
                case .result, .error:
                    terminal = true
                    partialLine = false
                    if case .error(let value) = event { failure = .helperFailed(value) }
                    deadline?.cancel()
                    timers.append(
                        after(configuration.timeouts.terminationGrace) { [weak self] in
                            self?.lock.withLock { self?.terminateLocked() }
                        })
                default: break
                }
            }
            onEvent(event)
        } catch let error as EngineError { reject(error) } catch {
            reject(.protocolViolation(String(describing: error), stderrTail: ""))
        }
    }

    private func reject(_ error: EngineError) {
        lock.withLock {
            guard !completed, !terminal, failure == nil else { return }
            failure = error
            terminateLocked()
        }
    }

    private func didExit(_ child: Process) {
        lock.withLock {
            if child.terminationReason == .uncaughtSignal {
                signal = child.terminationStatus
            } else {
                exitCode = child.terminationStatus
            }
            configuration.processObserver?(.exited(pid: child.processIdentifier, exitCode: exitCode, signal: signal))
            exited = true
            timers.append(after(.seconds(1)) { [weak self] in self?.finishIfReady(force: true) })
        }
        finishIfReady()
    }

    private func resetDeadlineLocked() {
        deadline?.cancel()
        let duration =
            command == "scan"
            ? configuration.timeouts.scanIdle
            : command == "hello" ? configuration.timeouts.hello : configuration.timeouts.forge
        deadline = after(duration) { [weak self] in
            guard let self else { return }
            lock.withLock {
                guard !completed, !terminal, !cancelled else { return }
                timedOut = duration
                terminateLocked()
            }
        }
    }

    private func terminateLocked() {
        guard !terminating, !exited, let process else { return }
        terminating = true
        Signals.send(Signals.terminate, to: process.processIdentifier)
        timers.append(
            after(configuration.timeouts.terminationGrace) { [weak self] in
                guard let self else { return }
                lock.withLock {
                    if !exited, let process = self.process {
                        Signals.send(Signals.forceKill, to: process.processIdentifier)
                    }
                }
            })
    }

    private func after(_ duration: Duration, _ work: @escaping @Sendable () -> Void) -> Task<Void, Never> {
        Task {
            do { try await Task.sleep(for: duration) } catch { return }
            work()
        }
    }

    private func finishIfReady(force: Bool = false) {
        lock.lock()
        guard !completed, exited, force || (stdoutEOF && stderrEOF) else { lock.unlock(); return }
        completed = true
        deadline?.cancel()
        timers.forEach { $0.cancel() }
        let tail = stderr.tail, byteCount = stderr.byteCount
        var error: EngineError?
        if terminal {
            error = failure
        } else if cancelled {
            error = nil
        } else if let duration = timedOut {
            error = .timedOut(after: duration, stderrTail: tail)
        } else if let failure {
            error = failure
        } else if partialLine {
            error = .protocolViolation("truncated line", stderrTail: tail)
        } else if exitCode == 0 {
            error = .protocolViolation("helper exited without a result", stderrTail: tail)
        } else if exitCode == 143 || exitCode == 130 || signal.map(Signals.interrupted.contains) == true {
            error = .interrupted(exitCode: exitCode, signal: signal, stderrTail: tail)
        } else {
            error = .crashed(exitCode: exitCode, signal: signal, stderrTail: tail)
        }
        if case .protocolViolation(let message, _) = error { error = .protocolViolation(message, stderrTail: tail) }
        let result: Result<EngineHello?, EngineError> = error.map(Result.failure) ?? .success(hello)
        let pid = process?.processIdentifier
        let shouldClean = !terminal
        let mismatch = terminal && (signal != nil || (exitCode != 0 && failure == nil))
        lock.unlock()
        if shouldClean, let pid {
            _ = Leftovers.remove(
                temporaryDirectory: configuration.temporaryDirectory,
                outputDirectories: outputDirectory.map { [$0] } ?? [],
                pid: pid, log: configuration.logHandler
            )
        }
        if mismatch { log("terminal event takes precedence over helper exit status") }
        // Cancellation owns the stream's task lock until its handler returns.
        // Release cleanup waiters before finishing that same continuation.
        finished.leave()
        onFinish(result, byteCount)
    }

    private func log(_ message: String) { configuration.logHandler?("[EngineClient] \(message)") }
}
