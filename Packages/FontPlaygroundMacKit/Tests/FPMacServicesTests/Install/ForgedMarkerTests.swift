import Foundation
import Testing

@testable import FPMacServices

struct ForgedMarkerTests {
    @Test func isForgedReadsNameID0() throws {
        let fixture = try InstallFixture()
        defer { fixture.cleanup() }
        #expect(ForgedMarker.isForged(fileAt: try fixture.source()))
        #expect(!ForgedMarker.isForged(fileAt: try fixture.source(forged: false, file: "ordinary.ttf")))
        #expect(!ForgedMarker.isForged(fileAt: fixture.root.appendingPathComponent("missing.ttf")))
        let junk = fixture.root.appendingPathComponent("junk.ttf")
        try Data("not a font".utf8).write(to: junk, options: .atomic)
        #expect(!ForgedMarker.isForged(fileAt: junk))
        let embedded = try FixtureFonts.build(
            [
                .init(
                    file: "embedded.ttf", family: "FPEmbedded" + TestEnv.tag(),
                    notice: "Not " + MacServicesConstants.forgedNotice)
            ], in: fixture.root)[0]
        #expect(!ForgedMarker.isForged(fileAt: embedded))
    }
}
