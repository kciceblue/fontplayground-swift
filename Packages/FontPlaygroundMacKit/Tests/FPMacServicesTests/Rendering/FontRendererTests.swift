import CoreText
import Darwin
import FPCore
import Foundation
import Testing

@testable import FPMacServices

struct FontRendererTests {
    @Test func nativeM2CollectionFacesMapByPostScriptName() throws {
        let family = "FPColl" + TestEnv.tag()
        let fixture = try RenderFixture([
            .init(
                file: "Collection.ttc", family: family,
                faces: [
                    .init(file: "regular.ttf", family: family, chars: "ab"),
                    .init(file: "bold.ttf", family: family, style: "Bold", chars: "abc", weightClass: 700),
                ])
        ])
        defer { fixture.remove() }
        let renderer = FontRenderer()
        for name in [family + "-Bold", nil] {
            let face = FaceRecord(
                path: fixture.urls[0].path, index: 1, family: family,
                coverage: .empty, postscriptName: name)
            let font = try renderer.font(for: .init(face: face, pointSize: 20))
            #expect(renderer.hasGlyph(for: "c", in: font))
            #expect(renderedRuns("c", font: font).map(\.postscriptName) == [family + "-Bold"])
        }
        let invalid = FaceRecord(
            path: fixture.urls[0].path, index: 5, family: family,
            coverage: .empty, postscriptName: "unknown")
        #expect(throws: RenderError.faceNotFound(path: fixture.urls[0].path, index: 5, postscriptName: "unknown")) {
            try renderer.font(for: .init(face: invalid, pointSize: 20))
        }
    }

    @Test(.enabled(if: TestEnv.appleFonts)) func nativeM2RealHelveticaCollectionNames() throws {
        let renderer = FontRenderer()
        let urls = CTFontManagerCopyAvailableFontURLs() as? [URL] ?? []
        let faces = urls.filter { $0.path == "/System/Library/Fonts/Helvetica.ttc" }
        #expect(!faces.isEmpty)
        for url in faces {
            let name = try #require(
                URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment?
                    .replacingOccurrences(of: "postscript-name=", with: ""))
            let face = FaceRecord(path: url.path, family: "Helvetica", coverage: .empty, postscriptName: name)
            #expect(try renderer.font(for: .init(face: face, pointSize: 20)).postscriptName == name)
        }
    }

    @Test func fontsAreBuiltAtTheQuantizedSizeTheyAreCachedUnder() throws {
        let fixture = try RenderFixture([.init(file: "A.ttf", family: "FPTestA" + TestEnv.tag())])
        defer { fixture.remove() }
        let renderer = FontRenderer()
        // 12.20 pt and 12.21 pt share the 12.203125 pt key; both must get that size whichever is asked first.
        let first = try renderer.font(for: .init(face: fixture.face(), pointSize: 10, weight: 700, scale: 1.22))
        let second = try renderer.font(for: .init(face: fixture.face(), pointSize: 11, weight: 700, scale: 1.11))
        #expect(first.ctFont === second.ctFont)
        for font in [first, second] {
            #expect(font.pointSize == 12.203125 && CTFontGetSize(font.ctFont) == 12.203125)
            #expect(abs(try #require(font.syntheticBold).extraAdvance - 0.06 * 12.203125) < 0.0001)
        }
        let built = try renderer.builtFont(at: fixture.urls[0], pointSize: 12.21)
        #expect(built.pointSize == 12.203125 && CTFontGetSize(built.ctFont) == 12.203125)
    }

    @Test func syntheticBoldHintFollowsTheEngineRule() throws {
        let fixture = try RenderFixture([.init(file: "A.ttf", family: "FPTestA" + TestEnv.tag())])
        defer { fixture.remove() }
        let renderer = FontRenderer()
        func render(_ weight: Int?, scale: Double = 1) throws -> RenderedFont {
            try renderer.font(for: .init(face: fixture.face(), pointSize: 30, weight: weight, scale: scale))
        }
        let bold = try #require(render(700).syntheticBold)
        #expect(bold.delta == 300 && bold.strokeWidthPercent == 6)
        #expect(abs(bold.extraAdvance - 1.8) < 0.0001)
        #expect(abs(try #require(render(700, scale: 0.8).syntheticBold).extraAdvance - 1.44) < 0.0001)
        #expect(try render(430).syntheticBold == nil)
        #expect(try render(nil).syntheticBold == nil)
        #expect(try render(1000).syntheticBold?.delta == 500)
        #expect(try render(1000).syntheticBold?.strokeWidthPercent == 10)
        #expect(try render(300).weightNote == .cannotLighten)
        #expect(try render(300).syntheticBold == nil)
        #expect(try render(450).syntheticBold?.delta == 50)
        #expect(try render(350).weightNote == .cannotLighten)
        #expect(try render(351).weightNote == nil)
    }

    @Test func builtFontIsLoadedByURLOnly() throws {
        let fixture = try RenderFixture([
            .init(file: "A.ttf", family: "FPTestA" + TestEnv.tag()),
            .init(
                file: "Collection.ttc", family: "FPColl" + TestEnv.tag(),
                faces: [
                    .init(file: "r.ttf", family: "FPR" + TestEnv.tag()),
                    .init(file: "b.ttf", family: "FPB" + TestEnv.tag()),
                ]),
        ])
        defer { fixture.remove() }
        let renderer = FontRenderer()
        let font = try renderer.builtFont(at: fixture.urls[0], pointSize: 24)
        #expect(font.fileURL == fixture.urls[0])
        #expect(font.variation.isEmpty && font.syntheticBold == nil && font.weightNote == nil)
        #expect(CTFontManagerGetScopeForURL(fixture.urls[0] as CFURL) == .none)
        #expect(throws: RenderError.builtFontInvalid(path: fixture.urls[1].path, faceCount: 2)) {
            try renderer.builtFont(at: fixture.urls[1], pointSize: 24)
        }
        let junk = fixture.directory.appendingPathComponent("junk.ttf")
        try Data("not a font".utf8).write(to: junk, options: .atomic)
        #expect(throws: RenderError.unreadable(path: junk.path)) { try renderer.builtFont(at: junk, pointSize: 24) }
        let missing = fixture.directory.appendingPathComponent("missing.ttf")
        #expect(throws: RenderError.fileMissing(path: missing.path)) {
            try renderer.builtFont(at: missing, pointSize: 24)
        }
    }

    @Test func cacheFollowsFileIdentity() throws {
        let family = "FPCache" + TestEnv.tag()
        let old = try RenderFixture([.init(file: "A.ttf", family: family, chars: "ab")])
        defer { old.remove() }
        let newer = try RenderFixture([.init(file: "A.ttf", family: family, chars: "abc")])
        defer { newer.remove() }
        let renderer = FontRenderer()
        let request = FaceRenderRequest(face: old.face(), pointSize: 20)
        let first = try renderer.font(for: request)
        #expect(first.ctFont === (try renderer.font(for: request)).ctFont)
        #expect(!renderer.hasGlyph(for: "c", in: first))
        #expect(rename(newer.urls[0].path, old.urls[0].path) == 0)
        let replaced = try renderer.font(for: request)
        #expect(renderer.hasGlyph(for: "c", in: replaced))
        #expect(first.ctFont !== replaced.ctFont)
        renderer.invalidate(path: old.urls[0].path)
        let invalidated = try renderer.font(for: request)
        #expect(replaced.ctFont !== invalidated.ctFont)
        renderer.invalidateAll()
        #expect(invalidated.ctFont !== (try renderer.font(for: request)).ctFont)
    }

    @Test func glyphPresenceAndCoverage() throws {
        let fixture = try RenderFixture([.init(file: "Han.ttf", family: "FPHan" + TestEnv.tag(), chars: "a永𠀀")])
        defer { fixture.remove() }
        let renderer = FontRenderer()
        let font = try renderer.font(for: .init(face: fixture.face(), pointSize: 20))
        #expect(renderer.missingScalars(in: "ab永😀𠀀", for: font) == Array("b😀".unicodeScalars))
        #expect(renderer.missingScalars(in: " b😀b\n😀 ", for: font) == Array("b😀".unicodeScalars))
        #expect(renderer.hasGlyph(for: scalar(0x20000), in: font))
        let coverage = renderer.coverage(of: font)
        #expect(coverage.contains(UInt32(0x61)))
        #expect(coverage.contains(UInt32(0x6C38)))
        #expect(coverage.contains(UInt32(0x20000)))
        #expect(!coverage.contains(UInt32(0x62)))
    }

    @Test func concurrentRequestsAreSafe() async throws {
        let fixture = try RenderFixture(
            (0..<6).map {
                .init(
                    file: "A\($0).ttf", family: "FPConcurrent\($0)" + TestEnv.tag(),
                    axes: [.init(tag: "wght", min: 100, default: 400, max: 900)])
            })
        defer { fixture.remove() }
        let renderer = FontRenderer(descriptorCacheCapacity: 3, fontCacheCapacity: 13)
        let faces = (0..<6).map { fixture.face($0) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for task in 0..<8 {
                group.addTask {
                    var seed = UInt64(task + 1)
                    for _ in 0..<200 {
                        seed = seed &* 6_364_136_223_846_793_005 &+ 1
                        let face = faces[Int((seed >> 32) % 6)]
                        let weight = Int((seed >> 16) % 9 + 1) * 100
                        let request = FaceRenderRequest(face: face, pointSize: CGFloat(seed % 40 + 12), weight: weight)
                        let first = try renderer.font(for: request)
                        let second = try renderer.font(for: request)
                        #expect(first.fileURL.path == face.path)
                        #expect(first.variation == ["wght": Double(weight)])
                        #expect(first.postscriptName == second.postscriptName && first.variation == second.variation)
                    }
                }
            }
            try await group.waitForAll()
        }
    }
}
