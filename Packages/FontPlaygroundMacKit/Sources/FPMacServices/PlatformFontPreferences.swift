import CoreText
import Foundation

public enum PlatformFontPreferences {
    public static let languageTags: [String: String] = [
        "chinese_s": "zh-Hans", "chinese_t": "zh-Hant", "japanese": "ja", "korean": "ko", "greek": "el",
        "cyrillic": "ru", "armenian_georgian": "hy", "hebrew": "he", "arabic": "ar", "indic": "hi",
        "southeast_asian": "th",
    ]
    public static func lookUp(probes: [String: String]) async -> [String: String] {
        await Task.detached {
            // CATALOG-11: the document UI font resolves to public installed faces; .system returns private UI faces.
            guard let base = CTFontCreateUIFontForLanguage(.user, 13, nil) else { return [:] }
            var names: [String: String] = [:]
            for (id, probe) in probes {
                guard let tag = languageTags[id], !probe.isEmpty else { continue }
                let font = CTFontCreateForStringWithLanguage(
                    base, probe as CFString,
                    CFRange(location: 0, length: probe.utf16.count), tag as CFString)
                let name = CTFontCopyPostScriptName(font) as String
                if !name.hasPrefix(".") { names[id] = name }
            }
            return names
        }.value
    }
}
