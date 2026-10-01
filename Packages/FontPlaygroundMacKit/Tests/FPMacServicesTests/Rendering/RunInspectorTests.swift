import Foundation
import Testing

@testable import FPMacServices

struct RunInspectorTests {
    @Test func runsReportFontFileAndGlyphs() throws {
        let fixture = try RenderFixture([.init(file: "A.ttf", family: "FPTestA" + TestEnv.tag())])
        defer { fixture.remove() }
        let font = try FontRenderer().font(for: .init(face: fixture.face(), pointSize: 20))
        let runs = renderedRuns("ab永", font: font)
        #expect(runs.count == 2)
        let first = try #require(runs.first)
        let last = try #require(runs.last)
        #expect(first.postscriptName == font.postscriptName)
        #expect(first.range == NSRange(location: 0, length: 2))
        #expect(first.glyphs.count == 2 && first.glyphs.allSatisfy { $0 != 0 })
        #expect(first.fileURL?.standardizedFileURL == fixture.urls[0])
        #expect(last.postscriptName == "LastResort")
        #expect(last.range == NSRange(location: 2, length: 1))
        #expect(last.fileURL?.path == "/System/Library/Fonts/LastResort.otf")
        #expect(RunInspector.runs(of: NSAttributedString(string: "")).isEmpty)
    }
}
