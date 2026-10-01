import CoreText
import Foundation

struct BuiltFontCheck: Sendable {
    var postScriptName: String
    var mappedCharacters: Int
    var hasForgedMarker: Bool

    static func read(_ url: URL, postScriptName: String, sample: String) throws -> BuiltFontCheck {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
            descriptors.count == 1
        else { throw SelfTestFailure("output must contain exactly one font descriptor") }
        let descriptor = descriptors[0]
        guard let actual = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String,
            actual == postScriptName
        else { throw SelfTestFailure("output PostScript name does not match the report") }
        let font = CTFontCreateWithFontDescriptor(descriptor, 24, nil)
        let characters = Array(sample.filter { $0 != " " }.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count), !glyphs.contains(0) else {
            throw SelfTestFailure("output does not map every sample character")
        }
        guard let table = CTFontCopyTable(font, CTFontTableTag(kCTFontTableName), []) as Data?,
            let marker = "Forged with Font Playground".data(using: .utf16BigEndian), table.range(of: marker) != nil
        else { throw SelfTestFailure("output lacks the Font Playground name-table marker") }
        return BuiltFontCheck(postScriptName: actual, mappedCharacters: characters.count, hasForgedMarker: true)
    }
}
