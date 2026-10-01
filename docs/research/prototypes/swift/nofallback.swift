// Native preview honesty: can CoreText be stopped from borrowing glyphs (Qt: QFont::NoFontMerging)?
import CoreText
import Foundation
func runs(_ font: CTFont, _ text: String) -> [String] {
    let s = CFAttributedStringCreate(nil, text as CFString, [kCTFontAttributeName: font] as CFDictionary)!
    return (CTLineGetGlyphRuns(CTLineCreateWithAttributedString(s)) as! [CTRun]).map { run in
        let f = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
        return "\(CTFontCopyPostScriptName(f) as String)x\(CTRunGetGlyphCount(run))"
    }
}
let text = "Hamburg 你好"
let georgia = CTFontCreateWithName("Georgia" as CFString, 30, nil)
print("default cascade   :", runs(georgia, text))
let last = CTFontDescriptorCreateWithNameAndSize("LastResort" as CFString, 30)
let d = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(georgia),
          [kCTFontCascadeListAttribute: [last]] as CFDictionary)
let strict = CTFontCreateWithFontDescriptor(d, 30, nil)
print("cascade=LastResort:", runs(strict, text))
// a font file loaded without registering it anywhere (what a picker row or a trial needs)
let url = URL(fileURLWithPath: "/System/Library/Fonts/Hiragino Sans GB.ttc") as CFURL
let descs = CTFontManagerCreateFontDescriptorsFromURL(url) as! [CTFontDescriptor]
let hira = CTFontCreateWithFontDescriptor(descs[0], 30, nil)
print("unregistered file :", CTFontCopyFamilyName(hira) as String, runs(hira, "Aä你好"))
