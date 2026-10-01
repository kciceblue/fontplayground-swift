import Foundation

/// A clock that moves only when a test calls `advance(by:)`. Debounce and throttle tests use it to check
/// "not yet" and "never" by construction: a loaded runner stretches wall-clock sleeps past the deadline under test.
final class ManualClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { .init(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }
    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }
    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var sleepers: [Sleeper] = []
    private var sleeps = 0
    private var cancellations = 0

    var now: Instant { lock.withLock { current } }
    var minimumResolution: Duration { .zero }
    /// Time left on each sleep that is waiting for the clock, soonest first.
    var waiting: [Duration] { lock.withLock { sleepers.map { current.duration(to: $0.deadline) }.sorted() } }
    /// Sleeps that ended because their task was cancelled, whether before or while waiting.
    var cancelled: Int { lock.withLock { cancellations } }

    func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let id = lock.withLock {
            sleeps += 1; return sleeps
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // Checking cancellation under the lock closes the race with `onCancel` running first.
                let result: Result<Void, any Error>? = lock.withLock {
                    if Task.isCancelled { cancellations += 1; return .failure(CancellationError()) }
                    if deadline <= current { return .success(()) }
                    sleepers.append(.init(id: id, deadline: deadline, continuation: continuation))
                    return nil
                }
                if let result { continuation.resume(with: result) }
            }
        } onCancel: {
            let sleeper: Sleeper? = lock.withLock {
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                cancellations += 1; return sleepers.remove(at: index)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }
    /// Moves time forward and wakes every sleep whose deadline has passed, soonest first.
    func advance(by duration: Duration) {
        let due: [Sleeper] = lock.withLock {
            current = current.advanced(by: duration)
            let due = sleepers.filter { $0.deadline <= current }.sorted { $0.deadline < $1.deadline }
            sleepers.removeAll { $0.deadline <= current }
            return due
        }
        for sleeper in due { sleeper.continuation.resume() }
    }
}
