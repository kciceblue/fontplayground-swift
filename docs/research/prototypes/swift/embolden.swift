// Can CoreGraphics replace skia-pathops for synthetic bold (engine/synth_bold.py)?
import CoreText
import CoreGraphics
import Foundation

func census(_ p: CGPath) -> (move: Int, line: Int, quad: Int, cubic: Int) {
    var c = (move: 0, line: 0, quad: 0, cubic: 0)
    p.applyWithBlock { e in
        switch e.pointee.type {
        case .moveToPoint: c.move += 1
        case .addLineToPoint: c.line += 1
        case .addQuadCurveToPoint: c.quad += 1
        case .addCurveToPoint: c.cubic += 1
        default: break
        }
    }
    return c
}
let font = CTFontCreateWithName("Georgia" as CFString, 2048, nil)   // em = 2048 units
var chars: [UniChar] = Array("a&".utf16); var glyphs = [CGGlyph](repeating: 0, count: 2)
CTFontGetGlyphsForCharacters(font, &chars, &glyphs, 2)
let w: CGFloat = 0.3 * 0.2 * 2048   // stroke_width(+300, 2048) in synth_bold.py
for g in glyphs {
    let path = CTFontCreatePathForGlyph(font, g, nil)!
    let t = Date()
    let stroked = path.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 4)
    let bold = path.union(stroked, using: .winding)          // macOS 13+ boolean ops
    let dt = Date().timeIntervalSince(t) * 1000
    print("glyph \(g): source \(census(path)) -> bold \(census(bold)) in \(String(format: "%.2f", dt)) ms; bbox \(path.boundingBoxOfPath.width.rounded()) -> \(bold.boundingBoxOfPath.width.rounded())")
}
