import CoreText
import Foundation
import Testing

@testable import FPMacServices

@Suite(.serialized)
struct RenderHonestyTests {
    @Test func missingCharactersShowLastResortNeverAnotherFont() throws {
        let fixture = try RenderFixture([.init(file: "A.ttf", family: "FPTestA" + TestEnv.tag())])
        defer { fixture.remove() }
        let renderer = FontRenderer()
        let font = try renderer.font(for: .init(face: fixture.face(), pointSize: 20))
        let text = "ab永한ب😀Ж"
        let runs = renderedRuns(text, font: font)
        #expect(Set(runs.map(\.postscriptName)) == [font.postscriptName, "LastResort"])
        var offset = 0
        for character in text.unicodeScalars {
            if !renderer.hasGlyph(for: character, in: font) {
                let covering = runs.filter { NSLocationInRange(offset, $0.range) }
                #expect(!covering.isEmpty && covering.allSatisfy { $0.postscriptName == "LastResort" })
            }
            offset += character.utf16.count
        }
    }

    @Test func catalog4FileIsDrawnNotTheSameNamedInstalledFont() throws {
        let family = "FPDuplicate" + TestEnv.tag()
        let fixture = try RenderFixture([
            .init(file: "old.ttf", family: family, chars: "ab"),
            .init(file: "new.ttf", family: family, chars: "abc"),
        ])
        defer { fixture.remove() }
        try ProcessScopeFonts.register(fixture.urls[0])
        defer { ProcessScopeFonts.unregister(fixture.urls[0]) }
        let renderer = FontRenderer()
        for font in [
            try renderer.font(for: .init(face: fixture.face(1), pointSize: 20)),
            try renderer.builtFont(at: fixture.urls[1], pointSize: 20),
        ] {
            #expect(renderer.hasGlyph(for: "c", in: font))
            let run = try #require(renderedRuns("c", font: font).first)
            #expect(run.fileURL?.standardizedFileURL == fixture.urls[1])
            #expect(run.glyphs.count == 1 && run.glyphs[0] != 0)
        }
        let old = try renderer.font(for: .init(face: fixture.face(), pointSize: 20))
        let runs = renderedRuns("abc", font: old)
        #expect(runs.first?.fileURL?.standardizedFileURL == fixture.urls[0])
        #expect(runs.last?.postscriptName == "LastResort")
    }

    @Test func nativeM1PreviewShapesExactlyLikeCoreText() throws {
        let fixture = try RenderFixture([
            .init(
                file: "ArLatn.ttf", family: "FPArLatn" + TestEnv.tag(), chars: "بغدﺑﻐﺪab",
                fea:
                    "languagesystem DFLT dflt; languagesystem latn dflt; feature aalt { sub uni0061 from [uni0061 uni0062]; } aalt;"
            ),
            .init(file: "ArNoGSUB.ttf", family: "FPArNoGSUB" + TestEnv.tag(), chars: "بغدﺑﻐﺪab"),
        ])
        defer { fixture.remove() }
        let renderer = FontRenderer()
        for index in 0...1 {
            let font = try renderer.font(for: .init(face: fixture.face(index), pointSize: 24))
            let runs = renderedRuns("بغد", font: font)
            #expect(runs.count == 1)
            let run = try #require(runs.first)
            #expect(run.postscriptName == font.postscriptName)
            #expect(run.stringIndices == [2, 1, 0])
            let expected: [UInt32] = index == 0 ? [0x628, 0x63A, 0x62F] : [0xFE91, 0xFED0, 0xFEAA]
            for (glyph, stringIndex) in zip(run.glyphs, run.stringIndices) {
                #expect(glyph == nominalGlyph(expected[stringIndex], font: font.ctFont))
                if index == 0 {
                    #expect(![0xFE91, 0xFED0, 0xFEAA].map { nominalGlyph($0, font: font.ctFont) }.contains(glyph))
                }
            }
        }
    }
}
