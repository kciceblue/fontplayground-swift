import Foundation

extension Naming {
    public static func fnv1a64(_ bytes: [UInt8]) -> UInt64 {
        bytes.reduce(0xcbf29ce484222325) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
    }

    public static func asciiAlnum(_ s: String) -> String {
        String(
            String.UnicodeScalarView(
                s.unicodeScalars.filter {
                    (0x30...0x39).contains($0.value) || (0x41...0x5A).contains($0.value)
                        || (0x61...0x7A).contains($0.value)
                }))
    }

    public static func nameTag(family: String, style: String) -> String {
        let hash = fnv1a64(Array(cleanName(family).utf8) + [0] + Array(cleanName(style).utf8))
        return "FP" + String(format: "%08x", UInt32(truncatingIfNeeded: (hash >> 32) ^ (hash & 0xFFFF_FFFF)))
    }

    public static func postscriptName(family: String, style: String) -> String {
        let family = cleanName(family), style = cleanName(style)
        let tag = nameTag(family: family, style: style)
        let asciiStyle = asciiAlnum(style), asciiFamily = asciiAlnum(family)
        let shortStyle = String((asciiStyle.isEmpty ? "Regular" : asciiStyle).prefix(20))
        let shortFamily = String(
            (asciiFamily.isEmpty ? "Forged" : asciiFamily).prefix(63 - 1 - shortStyle.count - tag.count))
        return shortFamily + tag + "-" + shortStyle
    }
}
