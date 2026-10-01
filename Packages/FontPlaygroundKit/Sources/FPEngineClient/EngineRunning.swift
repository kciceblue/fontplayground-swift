import FPCore
import Foundation

public protocol EngineRunning: Sendable {
    func hello() async throws -> EngineHello
    func scan(files: [String]) -> AsyncThrowingStream<ScanEvent, any Error>
    func forge(_ request: ForgeRequest) -> AsyncThrowingStream<ForgeEvent, any Error>
}

public enum ScanEvent: Sendable, Equatable {
    case progress(EngineProgress)
    case face(FaceRecord)
    case fileError(ScanFileError)
    case finished(ScanSummary)
}

public enum ForgeEvent: Sendable, Equatable {
    case progress(EngineProgress)
    case finished(ForgeReport)
}
