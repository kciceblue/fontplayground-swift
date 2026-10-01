import Foundation

public enum Naming {
    public static let vendorWords: Set<String> = ["microsoft", "ms", "adobe", "google"]
    public static let maxFamilyName = 31
    public static let forgedSuffix = "Forged"

    public static func cleanName(_ s: String) -> String {
        let scalars = s.unicodeScalars
        let start = scalars.firstIndex { !isPythonWhitespace($0) } ?? scalars.endIndex
        let end = scalars.lastIndex { !isPythonWhitespace($0) }.map { scalars.index(after: $0) } ?? start
        return String(scalars[start..<end])
    }

    public static func stripVendor(_ family: String) -> String {
        var words = family.unicodeScalars.split(whereSeparator: isPythonWhitespace).map(String.init)
        while words.count > 1 && vendorWords.contains(words[0].lowercased()) { words.removeFirst() }
        return words.isEmpty ? cleanName(family) : words.joined(separator: " ")
    }

    public static func defaultFamilyName(_ faces: [FaceRecord]) -> String {
        // ENGINE-10 / UI-M3: proposed names must not inherit a hidden face's leading dots.
        let families = faces.map { String(stripVendor($0.family).unicodeScalars.drop(while: { $0 == "." })) }
            .filter { !$0.isEmpty }
        guard let main = families.first else { return forgedSuffix }
        // Python compares scalar sequences, including canonically equivalent spellings.
        if let second = families.dropFirst().first(where: {
            !$0.utf8.elementsEqual(main.utf8)
        }) {
            let pair = main + " " + second
            if pair.unicodeScalars.count <= maxFamilyName { return pair }
        }
        return main + " " + forgedSuffix
    }

    public static func defaultStyle(_ main: FaceRecord?) -> String {
        guard let main, !cleanName(main.style).isEmpty else { return "Regular" }
        return main.style
    }

    public static func fileName(family: String, style: String) -> String {
        let family = cleanName(family), style = cleanName(style)
        let stem = (family.isEmpty ? forgedSuffix : family) + "-" + (style.isEmpty ? "Regular" : style)
        var result = "", previousUnsafe = false
        for scalar in stem.unicodeScalars {
            let unsafe = scalar.value <= 0x1F || "<>:\"/\\|?*".unicodeScalars.contains(scalar)
            if unsafe {
                if !previousUnsafe { result.append("-") }
            } else {
                result.unicodeScalars.append(scalar)
            }
            previousUnsafe = unsafe
        }
        result = cleanName(String(result.unicodeScalars.drop(while: { $0 == "." })))
        return (result.isEmpty ? "Forged-Regular" : result) + ".ttf"
    }

    private static func isPythonWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x1C...0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A,
            0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
            true
        default: false
        }
    }
}
