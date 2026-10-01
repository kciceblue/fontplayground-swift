import FPMacServices
import Foundation
import Testing
import os

struct FontBookLauncherTests {
    private final class RecordingOpener: ApplicationOpening {
        struct State { var identifiers: [String] = []; var opened: [URL] = [] }
        private let state = OSAllocatedUnfairLock(initialState: State())
        let resolved: URL?
        let failure: CocoaError?
        init(resolved: URL?, failure: CocoaError? = nil) { self.resolved = resolved; self.failure = failure }
        var identifiers: [String] { state.withLock { $0.identifiers } }
        var opened: [URL] { state.withLock { $0.opened } }
        func applicationURL(bundleIdentifier: String) -> URL? {
            state.withLock { $0.identifiers.append(bundleIdentifier) }
            return resolved
        }
        func openApplication(at url: URL) async throws {
            state.withLock { $0.opened.append(url) }
            if let failure { throw failure }
        }
    }

    @Test("CATALOG-5: Font Book is opened by bundle identifier") func catalog5OpensFontBookByBundleIdentifier()
        async throws
    {
        let url = URL(fileURLWithPath: "/Fake Applications/Font Book.app")
        let opener = RecordingOpener(resolved: url)
        try await FontBookLauncher(opener: opener).open()
        #expect(opener.identifiers == ["com.apple.FontBook"])
        #expect(opener.opened == [url])
        let missing = RecordingOpener(resolved: nil)
        await #expect(throws: FontBookError.fontBookMissing) { try await FontBookLauncher(opener: missing).open() }
        #expect(missing.identifiers == ["com.apple.FontBook"] && missing.opened.isEmpty)
        #expect(FontBookError.fontBookMissing.englishText == "Font Book isn't available on this Mac.")
        #expect(FontBookError.fontBookMissing.errorDescription == FontBookError.fontBookMissing.englishText)
    }

    @Test func fontBookResolvesOnThisMac() throws {
        let url = try #require(WorkspaceApplicationOpener().applicationURL(bundleIdentifier: "com.apple.FontBook"))
        #expect(url.lastPathComponent == "Font Book.app")
    }

    @Test func launchFailureIsReported() async {
        let failure = CocoaError(.fileReadNoPermission)
        let opener = RecordingOpener(
            resolved: URL(fileURLWithPath: "/Fake Applications/Font Book.app"), failure: failure)
        await #expect(throws: failure) { try await FontBookLauncher(opener: opener).open() }
        #expect(opener.opened.count == 1)
    }
}
