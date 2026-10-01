import Foundation

public enum InstallFileName {
    public static func stem(family: String, style: String) -> String {
        let f = strip(family); let s = strip(style)
        let raw = "\(f.isEmpty ? "Forged" : f)-\(s.isEmpty ? "Regular" : s)"
        var result = ""
        var replacing = false
        for scalar in raw.unicodeScalars {
            if scalar.value <= 0x1F || "<>:\"/\\|?*".unicodeScalars.contains(scalar) {
                if !replacing { result += "-" }
                replacing = true
            } else {
                result.unicodeScalars.append(scalar); replacing = false
            }
        }
        while result.first == "." { result.removeFirst() }
        while let scalar = result.unicodeScalars.first, whitespace.contains(scalar) {
            result.unicodeScalars.removeFirst()
        }
        return result.isEmpty ? "Forged-Regular" : result
    }
    private static let whitespace = CharacterSet(
        charactersIn:
            "\u{9}\u{A}\u{B}\u{C}\u{D}\u{1C}\u{1D}\u{1E}\u{1F} \u{85}\u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}"
    )
    private static func strip(_ string: String) -> String { string.trimmingCharacters(in: whitespace) }
}
