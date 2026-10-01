import CoreText
import FPCore
import Foundation

@testable import FPMacServices

struct RenderFixture {
    let directory: URL
    let urls: [URL]
    let specs: [FontSpec]

    init(_ specs: [FontSpec]) throws {
        directory = try TestEnv.temporaryDirectory()
        self.specs = specs
        do { urls = try FixtureFonts.build(specs, in: directory) } catch {
            try? FileManager.default.removeItem(at: directory); throw error
        }
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }

    func face(_ index: Int = 0) -> FaceRecord {
        let spec = specs[index]
        return FaceRecord(
            path: urls[index].path, family: spec.family, coverage: CodepointSet(scalarsOf: spec.chars),
            weightClass: spec.weightClass,
            axes: spec.axes.map { .init(tag: $0.tag, min: $0.min, default: $0.default, max: $0.max) },
            postscriptName: spec.postscriptName ?? spec.family.replacingOccurrences(of: " ", with: "") + "-"
                + spec.style)
    }
}

func renderedRuns(_ text: String, font: RenderedFont) -> [RunInspector.Run] {
    RunInspector.runs(
        of: NSAttributedString(
            string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font.ctFont]))
}

func scalar(_ value: UInt32) -> Unicode.Scalar { Unicode.Scalar(value)! }

func variation(_ font: CTFont, tag: String) -> Double? {
    let key = NSNumber(value: tag.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
    return (CTFontCopyVariation(font) as? [NSNumber: NSNumber])?[key]?.doubleValue
}

func nominalGlyph(_ codepoint: UInt32, font: CTFont) -> CGGlyph {
    let units = Array(String(scalar(codepoint)).utf16)
    var glyphs = [CGGlyph](repeating: 0, count: units.count)
    _ = CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count)
    return glyphs[0]
}
