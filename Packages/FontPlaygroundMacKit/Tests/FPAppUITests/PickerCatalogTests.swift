import Foundation
import Testing

@testable import FPAppUI

struct PickerCatalogTests {
    @Test func everyPickerStringIsInTheStringCatalog() throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = package.appending(path: "Sources/FPAppUI")
        let text = try String(contentsOf: sources.appending(path: "Editing/Picker/PickerText.swift"), encoding: .utf8)
        let data = try Data(contentsOf: sources.appending(path: "Resources/Localizable.xcstrings"))
        let catalog = try #require(
            (JSONSerialization.jsonObject(with: data) as? [String: Any])?["strings"] as? [String: Any])
        let literal = try NSRegularExpression(pattern: #"String\(\s*localized:\s*"((?:\\.|[^"\\])*)""#)
        // Every picker interpolation is a String, which the catalog key spells as %@.
        let interpolation = try NSRegularExpression(pattern: #"\\\([^)]*\)"#)
        let keys = literal.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            let raw = (text as NSString).substring(with: match.range(at: 1))
            return interpolation.stringByReplacingMatches(
                in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "%@")
        }
        let missing = keys.filter { catalog[$0] == nil }
        #expect(!keys.isEmpty && missing.isEmpty, "Missing: \(missing)")
    }
}
