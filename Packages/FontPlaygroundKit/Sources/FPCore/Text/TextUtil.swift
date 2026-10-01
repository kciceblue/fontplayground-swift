import Foundation

public enum TextUtil {
    public static let ignorableRanges: [ClosedRange<UInt32>] = [
        0x200B...0x200F, 0x2028...0x202E, 0x2060...0x206F, 0xFE00...0xFE0F, 0xFEFF...0xFEFF,
        0x00AD...0x00AD, 0xE0100...0xE01EF, 0x180B...0x180E, 0x034F...0x034F,
    ]

    public static func isIgnorable(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isWhitespace || ignorableRanges.contains(where: { $0.contains(scalar.value) }) {
            return true
        }
        switch scalar.properties.generalCategory {
        case .format, .control, .unassigned: return true
        default: return false
        }
    }

    public static func visibleScalars(in text: String) -> [Unicode.Scalar] {
        Set(text.unicodeScalars.filter { !isIgnorable($0) }).sorted { $0.value < $1.value }
    }
}
