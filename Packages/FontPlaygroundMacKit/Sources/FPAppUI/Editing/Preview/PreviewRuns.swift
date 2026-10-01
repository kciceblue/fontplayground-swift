import FPCore
import Foundation

public enum PreviewRuns {
    public static func sources(_ paragraph: Substring.UnicodeScalarView, source: (Unicode.Scalar) -> Int?) -> [Int?] {
        var result: [Int?] = [], before: Int?
        for scalar in paragraph {
            if TextUtil.isIgnorable(scalar) {
                if before == nil { before = paragraph.first(where: { !TextUtil.isIgnorable($0) }).flatMap(source) ?? 0 }
                result.append(before)
            } else {
                let current = source(scalar); result.append(current); before = current ?? 0
            }
        }
        return result
    }
    public static func runs(_ paragraph: Substring, source: (Unicode.Scalar) -> Int?) -> [(
        range: NSRange, source: Int?
    )] {
        let indices = sources(paragraph.unicodeScalars, source: source)
        var result: [(range: NSRange, source: Int?)] = [], position = 0
        for (scalar, index) in zip(paragraph.unicodeScalars, indices) {
            let length = scalar.value > 0xFFFF ? 2 : 1
            if let previous = result.last, previous.source == index {
                result[result.count - 1].range.length += length
            } else {
                result.append((NSRange(location: position, length: length), index))
            }
            position += length
        }
        return result
    }
}
public enum PreviewZoom {
    public static let range = 10...96
    public static let steps = [10, 12, 14, 18, 24, 30, 36, 48, 64, 72, 96]
    public static let defaultSize = 30
    public static func size(from start: Int, magnification: Double) -> Int {
        min(96, max(10, Int((Double(start) * (1 + magnification)).rounded())))
    }
    public static func scrollSteps(delta: Double, precise: Bool, carry: inout Double) -> Int {
        carry += delta; let unit = precise ? 8.0 : 1.0, steps = Int(carry / unit); carry -= Double(steps) * unit;
        return steps
    }
    public static func next(after size: Int) -> Int { steps.first { $0 > size } ?? 96 }
    public static func previous(before size: Int) -> Int { steps.last { $0 < size } ?? 10 }
}
