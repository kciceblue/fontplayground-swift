import Foundation

public enum LanguageID: String, CaseIterable, Codable, Sendable {
    case latin, chineseSimplified = "chinese_s", chineseTraditional = "chinese_t", japanese, korean, greek, cyrillic
    case armenianGeorgian = "armenian_georgian", hebrew, arabic, indic, southeastAsian = "southeast_asian", symbols, any
}
