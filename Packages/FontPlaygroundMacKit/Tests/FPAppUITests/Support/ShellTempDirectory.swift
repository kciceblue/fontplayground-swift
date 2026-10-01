import AppKit
import Foundation
import Testing

@testable import FPAppUI

@MainActor final class ShellTempDirectory {
    let url: URL
    let defaults: UserDefaults
    private let suite: String
    init() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        url = FileManager.default.temporaryDirectory.appending(path: "fp-shell-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        suite = "fp-test-" + UUID().uuidString; defaults = UserDefaults(suiteName: suite)!
    }
    deinit {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite);
        try? FileManager.default.removeItem(at: url)
    }
    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true);
        try Data(text.utf8).write(to: url)
    }
}
@MainActor func shellEventually(_ predicate: () async -> Bool) async {
    for _ in 0..<1000 { if await predicate() { return }; try? await Task.sleep(for: .milliseconds(2)) }
    Issue.record("The shell did not reach the expected state")
}
