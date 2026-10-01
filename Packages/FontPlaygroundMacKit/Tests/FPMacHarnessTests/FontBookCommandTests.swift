import FPMacServices
import Foundation
import Testing

@testable import FPMacHarness

struct FontBookCommandTests {
    @Test func fontBookCommandReportsSuccessWithoutStartingAnEngine() async {
        let out = Lines(), err = Lines(), calls = Lines()
        let opener = CommandOpener(url: URL(fileURLWithPath: "/test/Font Book.app"), calls: calls)
        #expect(
            await MacHarness.run(
                arguments: ["fontbook"], environment: [:], fontBook: .init(opener: opener),
                output: out.append, errorOutput: err.append) == 0)
        #expect(out.values == ["opened Font Book"])
        #expect(err.values.isEmpty)
        #expect(calls.values == ["com.apple.FontBook", "/test/Font Book.app"])
    }

    @Test func fontBookCommandReportsMissingApplicationAndRejectsExtraArguments() async {
        let out = Lines(), err = Lines(), calls = Lines()
        let opener = CommandOpener(url: nil, calls: calls)
        #expect(
            await MacHarness.run(
                arguments: ["fontbook"], environment: [:], fontBook: .init(opener: opener),
                output: out.append, errorOutput: err.append) == 1)
        #expect(err.values == [FontBookError.fontBookMissing.englishText])
        #expect(out.values.isEmpty)
        #expect(calls.values == ["com.apple.FontBook"])
        #expect(
            await MacHarness.run(
                arguments: ["fontbook", "--watch"], environment: [:], fontBook: .init(opener: opener),
                output: out.append, errorOutput: err.append) == 2)
        #expect(calls.values == ["com.apple.FontBook"])
    }
}

private struct CommandOpener: ApplicationOpening {
    let url: URL?
    let calls: Lines
    func applicationURL(bundleIdentifier: String) -> URL? { calls.append(bundleIdentifier); return url }
    func openApplication(at url: URL) async throws { calls.append(url.path) }
}
