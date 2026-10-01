import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct EngineErrorTextTests {
    @Test func reasonsAreShortAndSpecific() async throws {
        let rows: [(any Error, String)] = [
            (EngineError.helperNotFound(searched: []), "its files are missing from the app"),
            (EngineError.launchFailed("detail"), "it couldn't be started"),
            (
                EngineError.incompatibleHelper(reported: 2, supported: 1),
                "it's a different version (protocol 2, expected 1)"
            ), (EngineError.timedOut(after: .seconds(1), stderrTail: "secret"), "it didn't answer in time"),
            (EngineError.crashed(exitCode: 1, signal: nil, stderrTail: "detail"), "it stopped unexpectedly"),
            (EngineError.interrupted(exitCode: nil, signal: 15, stderrTail: ""), "it stopped unexpectedly"),
            (EngineError.protocolViolation("bad", stderrTail: ""), "it stopped unexpectedly"),
            (EngineError.helperFailed(.init(code: .validate, message: "human message")), "human message"),
            (CatalogError.engineUnavailable("catalog message"), "catalog message"), (ShellTestError("other"), "other"),
        ]
        for (error, text) in rows { #expect(EngineErrorText.reason(error) == text) }
        let unavailable = UnavailableEngine(error: EngineError.launchFailed("missing"))
        await #expect(throws: EngineError.launchFailed("missing")) { try await unavailable.hello() }
        await #expect(throws: EngineError.launchFailed("missing")) {
            for try await _ in unavailable.scan(files: []) { Issue.record("Unavailable engine emitted an event") }
        }
    }
}
