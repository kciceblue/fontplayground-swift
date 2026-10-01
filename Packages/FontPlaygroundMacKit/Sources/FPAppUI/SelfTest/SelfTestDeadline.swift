import Foundation

struct SelfTestDeadline: Error {}

/// A task group waits for cancelled children. A watchdog must finish even if a dependency never resumes.
func selfTestDeadline<Value: Sendable>(
    _ duration: Duration, operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    let race = SelfTestRace<Value>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            race.install(continuation)
            let worker = Task.detached {
                do { race.finish(.success(try await operation())) } catch { race.finish(.failure(error)) }
            }
            let timer = Task.detached {
                do {
                    try await Task.sleep(for: duration)
                    race.finish(.failure(SelfTestDeadline()))
                } catch {}
            }
            race.install([worker, timer])
        }
    } onCancel: {
        race.finish(.failure(CancellationError()))
    }
}

/// Synchronous CoreText and filesystem calls must not monopolize the coordinator actor.
func selfTestDetached<Value: Sendable>(_ operation: @escaping @Sendable () throws -> Value) async throws -> Value {
    let worker = Task.detached { try operation() }
    return try await withTaskCancellationHandler {
        try await worker.value
    } onCancel: {
        worker.cancel()
    }
}

private final class SelfTestRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?
    private var result: Result<Value, any Error>?
    private var tasks: [Task<Void, Never>] = []

    func install(_ continuation: CheckedContinuation<Value, any Error>) {
        let finished: Result<Value, any Error>? = lock.withLock {
            if let result { return result }
            self.continuation = continuation
            return nil
        }
        if let finished { continuation.resume(with: finished) }
    }
    func install(_ tasks: [Task<Void, Never>]) {
        let finished = lock.withLock {
            guard result == nil else { return true }
            self.tasks = tasks
            return false
        }
        if finished { tasks.forEach { $0.cancel() } }
    }
    func finish(_ result: Result<Value, any Error>) {
        let pending = lock.withLock { () -> (CheckedContinuation<Value, any Error>?, [Task<Void, Never>]) in
            guard self.result == nil else { return (nil, []) }
            self.result = result
            let pending = (continuation, tasks)
            continuation = nil; tasks = []
            return pending
        }
        pending.1.forEach { $0.cancel() }
        pending.0?.resume(with: result)
    }
}
