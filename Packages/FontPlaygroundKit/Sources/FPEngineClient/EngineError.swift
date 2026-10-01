import Foundation

public enum EngineError: Error, Sendable, Equatable {
    case helperNotFound(searched: [String])
    case launchFailed(String)
    case incompatibleHelper(reported: Int, supported: Int)
    case helperFailed(HelperFailure)
    case protocolViolation(String, stderrTail: String)
    case interrupted(exitCode: Int32?, signal: Int32?, stderrTail: String)
    case crashed(exitCode: Int32?, signal: Int32?, stderrTail: String)
    case timedOut(after: Duration, stderrTail: String)
}
