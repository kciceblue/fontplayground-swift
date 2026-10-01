import FPEngineClient
import Foundation
import Testing

@testable import fpctl

struct FolderErrorTests {
    @Test func traversalErrorsAreCountedAlongsideScannedFiles() async throws {
        let area = try CLIArea(); defer { area.remove() }
        try Data().write(to: area.file("a.ttf"))
        let blocked = area.file("blocked")
        let enumerate = failingEnumeration(path: blocked, returnsNil: false)
        let input = FontFolders.files(in: [area.root.path], enumerate: enumerate)
        #expect(input.files == [area.file("a.ttf").path])
        #expect(input.errors.count == 1)
        #expect(input.errors.first?.path == blocked.path)
        #expect(input.errors.first?.code == .ioError)
        let output = CapturedOutput(), engine = FakeCLIEngine()
        let result = try await FPCTL.scan(input, engine: engine, output: output.output)
        #expect(engine.scans == [[area.file("a.ttf").path]])
        #expect(result.summary == ScanSummary(files: 2, faces: 0, fileErrors: 1, duplicates: 0))
        #expect(result.fileErrors == input.errors)
        #expect(output.err.contains(blocked.path))
        #expect(output.err.contains("(io_error)"))
        try output.output.json(result)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(output.out.utf8)) as? [String: Any])
        let errors = try #require(json["file_errors"] as? [[String: String]])
        #expect(errors.count == 1)
        #expect(errors.first?["code"] == "io_error")
        #expect((json["summary"] as? [String: Int])?["file_errors"] == 1)
    }

    @Test func failedRootEnumerationReportsExactlyOneError() throws {
        let area = try CLIArea(); defer { area.remove() }
        for callsHandler in [true, false] {
            let input = FontFolders.files(
                in: [area.root.path],
                enumerate: failingEnumeration(path: callsHandler ? area.root : nil, returnsNil: true))
            #expect(input.files.isEmpty)
            #expect(input.errors.count == 1)
            #expect(input.errors.first?.path == area.root.path)
            #expect(input.errors.first?.code == .ioError)
        }
    }
}

private func failingEnumeration(path: URL?, returnsNil: Bool) -> FontFolders.Enumeration {
    { url, handler in
        if let path { _ = handler(path, CocoaError(.fileReadNoPermission)) }
        return returnsNil
            ? nil
            : FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], errorHandler: handler)
    }
}
