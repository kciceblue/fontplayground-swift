import CoreText
import Foundation
import Testing

@testable import FPMacServices

struct VariationPinTests {
    func fixture() throws -> RenderFixture {
        try RenderFixture([
            .init(
                file: "Var.ttf", family: "FPVar" + TestEnv.tag(),
                axes: [
                    .init(tag: "wght", min: 100, default: 400, max: 900),
                    .init(tag: "opsz", min: 8, default: 28, max: 144),
                ])
        ])
    }

    @Test func nativeM3OpticalSizeIsPinnedToTheEngineDefault() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let renderer = FontRenderer()
        var heights: [CGFloat] = []
        for size: CGFloat in [12, 28, 96] {
            let font = try renderer.font(for: .init(face: fixture.face(), pointSize: size))
            #expect(variation(font.ctFont, tag: "opsz") == nil || variation(font.ctFont, tag: "opsz") == 28)
            let path = try #require(CTFontCreatePathForGlyph(font.ctFont, 1, nil))
            heights.append(path.boundingBoxOfPath.height / size)
        }
        #expect(try #require(heights.max()) - #require(heights.min()) < 0.001)
        let descriptors = try #require(
            CTFontManagerCreateFontDescriptorsFromURL(fixture.urls[0] as CFURL) as? [CTFontDescriptor])
        let plain = CTFontCreateWithFontDescriptor(try #require(descriptors.first), 96, nil)
        #expect(variation(plain, tag: "opsz") == 96)
        let autoHeight = try #require(CTFontCreatePathForGlyph(plain, 1, nil)).boundingBoxOfPath.height / 96
        #expect(abs(autoHeight - heights[0]) > 0.001)
    }

    @Test func weightIsClampedLikeTheEngine() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let renderer = FontRenderer()
        for (weight, expected) in [(700, 700.0), (1200, 900.0), (50, 100.0)] {
            let font = try renderer.font(for: .init(face: fixture.face(), pointSize: 30, weight: weight))
            #expect(variation(font.ctFont, tag: "wght") == expected)
            #expect(font.variation == ["wght": expected, "opsz": 28])
            #expect(font.syntheticBold == nil && font.weightNote == nil)
        }
        let font = try renderer.font(for: .init(face: fixture.face(), pointSize: 30))
        #expect(variation(font.ctFont, tag: "wght") == nil || variation(font.ctFont, tag: "wght") == 400)
        #expect(font.variation == ["wght": 400, "opsz": 28])
    }

    @Test func variableFaceWithoutWeightAxisUsesSyntheticBold() throws {
        let fixture = try RenderFixture([
            .init(
                file: "Opsz.ttf", family: "FPOpsz" + TestEnv.tag(),
                axes: [
                    .init(tag: "opsz", min: 8, default: 28, max: 144)
                ])
        ])
        defer { fixture.remove() }
        let font = try FontRenderer().font(for: .init(face: fixture.face(), pointSize: 30, weight: 700))
        #expect(font.syntheticBold?.delta == 300)
        #expect(font.variation == ["opsz": 28])
    }
}
