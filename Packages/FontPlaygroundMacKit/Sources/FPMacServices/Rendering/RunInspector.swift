import CoreText
import Foundation

public enum RunInspector {
    public struct Run: Hashable, Sendable {
        public var range: NSRange
        public var postscriptName: String
        public var fileURL: URL?
        public var glyphs: [CGGlyph]
        public var stringIndices: [Int]
    }

    public static func runs(of string: NSAttributedString) -> [Run] {
        let line = CTLineCreateWithAttributedString(string)
        return (CTLineGetGlyphRuns(line) as! [CTRun]).map { run in
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let font = attributes[kCTFontAttributeName] as! CTFont
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            let range = CTRunGetStringRange(run)
            return Run(
                range: NSRange(location: range.location, length: range.length),
                postscriptName: CTFontCopyPostScriptName(font) as String,
                fileURL: CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL,
                glyphs: glyphs, stringIndices: indices)
        }
    }
}
