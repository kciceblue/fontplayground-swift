import FPCore
import FPEngineClient

public struct UnavailableEngine: EngineRunning {
    public let error: any Error
    public init(error: any Error) { self.error = error }
    public func hello() async throws -> EngineHello { throw error }
    public func scan(files: [String]) -> AsyncThrowingStream<ScanEvent, any Error> {
        AsyncThrowingStream { $0.finish(throwing: error) }
    }
    public func forge(_ request: ForgeRequest) -> AsyncThrowingStream<ForgeEvent, any Error> {
        AsyncThrowingStream { $0.finish(throwing: error) }
    }
}
