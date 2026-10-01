import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct SourceLintTests {
    struct LintRule {
        let id: String
        let pattern: Regex<AnyRegexOutput>
        let allowedFiles: Set<String>
        let positive: String
        let negative: String
    }
    static var rules: [LintRule] {
        get throws {
            [
                LintRule(
                    id: "L1",
                    pattern: try Regex(
                        #"\b(?:Text|Button|Label|Toggle|Picker|TextField|Section|Menu|Stepper|LabeledContent|Link|CommandMenu)\(\s*\"|\.(?:help|accessibilityLabel|accessibilityHint|accessibilityValue|alert|confirmationDialog)\(\s*\""#
                    ), allowedFiles: [], positive: #"Text("Hello")"#, negative: #"Text(verbatim: "data")"#),
                LintRule(
                    id: "L2",
                    pattern: try Regex(
                        #"NSLocalizedString\s*\(|String\s*\(\s*localized:(?!(?:\"(?:\\.|[^\"\\])*\"|[^\"()])*?\bbundle\s*:\s*\.module\b)"#
                    ), allowedFiles: [], positive: #"String(localized: "Hello", comment: "hello")"#,
                    negative: #"String(localized: "Hello", bundle: .module, comment: "hello")"#),
                LintRule(
                    id: "L4",
                    pattern: try Regex(
                        #"Image\s*\(\s*systemName:(?!(?:[^\n]*\n){0,3}[^\n]*\.(?:accessibilityLabel\s*\(|accessibilityHidden\s*\(\s*true\s*\)))"#
                    ), allowedFiles: ["Shared/Symbols.swift"], positive: #"Image(systemName: name)"#,
                    negative: #"Image(systemName: name).accessibilityHidden(true)"#),
                LintRule(
                    id: "L8",
                    pattern: try Regex(#"IconButton\s*\((?:\"(?:\\.|[^\"\\])*\"|[^\"()])*?\blabel\s*:\s*\"\""#),
                    allowedFiles: [], positive: #"IconButton(symbol: "xmark", label: "") {}"#,
                    negative: #"IconButton(symbol: "xmark", label: ShellText.dismiss) {}"#),
                LintRule(
                    id: "L9", pattern: try Regex(#"\bEnglishText\s*\.|\.englishText\b"#), allowedFiles: [],
                    positive: "EnglishText.groupLabel(.latin)", negative: "ModelText.groupLabel(.latin)"),
                LintRule(
                    id: "L10", pattern: try Regex(#"joined\(separator:\s*", "\)"#),
                    allowedFiles: ["SelfTest/SelfTestRunner.swift"], positive: #"names.joined(separator: ", ")"#,
                    negative: "names.joined(separator: ModelText.listSeparator)"),
                LintRule(
                    id: "L5", pattern: try Regex(#"NSCursor|\.pointerStyle\s*\("#), allowedFiles: [],
                    positive: "NSCursor.pointingHand", negative: "IconButton(symbol: name, label: label) {}"),
                LintRule(
                    id: "L6",
                    pattern: try Regex(
                        #"#[0-9A-Fa-f]{6}\b|0x[0-9A-Fa-f]{6}\b|\b(?:Color|NSColor)\s*\(\s*(?:red|srgbRed|calibratedRed)\s*:"#
                    ), allowedFiles: ["Editing/EditingShared.swift"], positive: "Color(red: 1, green: 0, blue: 0)",
                    negative: "Color.primary"),
                LintRule(
                    id: "L7",
                    pattern: try Regex(
                        #"NSFont\s*\(\s*name\s*:|Font\.custom\s*\(|CTFontCreateWithName|CTFontDescriptorCreateWithNameAndSize|CTFontDescriptorCreateMatchingFontDescriptor|NSFontDescriptor\s*\(\s*name\s*:"#
                    ), allowedFiles: [], positive: "CTFontCreateWithName(name, 14, nil)",
                    negative: "CTFontCreateWithFontDescriptor(descriptor, 14, nil)"),
            ]
        }
    }
    @Test func patternsDetectTheirPositiveAndNegativeExamples() throws {
        for rule in try Self.rules {
            #expect(Self.matches(rule, text: rule.positive));
            #expect(!Self.matches(rule, text: rule.negative))
        }
        #expect(
            Self.withoutComments(#"let text = "https://example.com" // NSCursor"#)
                == #"let text = "https://example.com" "#)
        #expect(Self.withoutComments("/* NSCursor */ Color.primary") == " Color.primary")
    }
    @Test func shellUsesNativeCursorsColoursAndURLFonts() throws {
        var package = URL(fileURLWithPath: #filePath); for _ in 0..<3 { package.deleteLastPathComponent() }
        let sources = package.appending(path: "Sources/FPAppUI"),
            files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        for case let url as URL in files where url.pathExtension == "swift" {
            let path = String(url.path.dropFirst(sources.path.count + 1)),
                text = Self.withoutComments(try String(contentsOf: url, encoding: .utf8))
            for rule in try Self.rules where !rule.allowedFiles.contains(path) {
                #expect(!Self.matches(rule, text: text), "\(rule.id): \(path)")
            }
        }
    }
    @Test func labelledImagesUseTheirContainingLabel() throws {
        let rule = try #require(Self.rules.first { $0.id == "L4" })
        #expect(!Self.matches(rule, text: #"Label(title: { Text(title) }, icon: { Image(systemName: name) })"#))
        #expect(!Self.matches(rule, text: #"Label { Text(title) } icon: { Image(systemName: name) }"#))
        #expect(
            Self.matches(
                rule, text: #"Label { Text(title) } icon: { Image(systemName: name) }; Image(systemName: other)"#))
        #expect(
            Self.matches(
                rule, text: "Image(systemName: name)\n.padding()\n.padding()\n.padding()\n.accessibilityHidden(true)"))
    }
    @Test func emptyIconLabelsCannotHideBehindNestedArguments() throws {
        let rule = try #require(Self.rules.first { $0.id == "L8" })
        #expect(Self.matches(rule, text: #"IconButton(symbol: chooseSymbol(), label: "") {}"#))
        #expect(!Self.matches(rule, text: #"IconButton(symbol: chooseSymbol(), label: ShellText.dismiss) {}"#))
    }
    static func matches(_ rule: LintRule, text: String) -> Bool {
        if rule.id == "L8" {
            let call = try! Regex(#"\bIconButton\s*\("#)
            let label = try! Regex(#"\blabel\s*:\s*"""#)
            let chars = Array(text)
            return text.matches(of: call).contains { match in
                let start = text.distance(from: text.startIndex, to: match.range.upperBound) - 1
                var index = start, depth = 0, quoted = false, escaped = false
                repeat {
                    let ch = chars[index]
                    if quoted {
                        if escaped {
                            escaped = false
                        } else if ch == "\\" {
                            escaped = true
                        } else if ch == "\"" {
                            quoted = false
                        }
                    } else if ch == "\"" {
                        quoted = true
                    } else if ch == "(" {
                        depth += 1
                    } else if ch == ")" {
                        depth -= 1
                    }
                    index += 1
                } while index < chars.count && depth > 0
                return String(chars[start..<index]).firstMatch(of: label) != nil
            }
        }
        let source = rule.id == "L4" ? withoutLabelImages(text) : text
        return source.firstMatch(of: rule.pattern) != nil
    }
    /// Label owns its icon's accessible name, including the trailing icon closure form.
    static func withoutLabelImages(_ text: String) -> String {
        var chars = Array(text)
        let pattern = try! Regex(#"\bLabel\s*(?=[({])"#)
        for match in text.matches(of: pattern).reversed() {
            var index = text.distance(from: text.startIndex, to: match.range.upperBound)
            let start = index
            while index < chars.count, chars[index] == "(" || chars[index] == "{" {
                var stack: [Character] = [], quoted = false, escaped = false
                repeat {
                    let ch = chars[index]
                    if quoted {
                        if escaped {
                            escaped = false
                        } else if ch == "\\" {
                            escaped = true
                        } else if ch == "\"" {
                            quoted = false
                        }
                    } else if ch == "\"" {
                        quoted = true
                    } else if ch == "(" {
                        stack.append(")")
                    } else if ch == "{" {
                        stack.append("}")
                    } else if ch == stack.last {
                        stack.removeLast()
                    }
                    index += 1
                } while index < chars.count && !stack.isEmpty
                while index < chars.count && chars[index].isWhitespace { index += 1 }
                if String(chars[index...]).hasPrefix("icon:") {
                    index += 5
                    while index < chars.count && chars[index].isWhitespace { index += 1 }
                }
            }
            let region = String(chars[start..<index]).replacingOccurrences(of: "Image", with: "_mage")
            chars.replaceSubrange(start..<index, with: region)
        }
        return String(chars)
    }
    static func withoutComments(_ text: String) -> String {
        let chars = Array(text);
        var output = "", index = 0, quoted = false, escaped = false, blockDepth = 0, lineComment = false
        while index < chars.count {
            let ch = chars[index], next = index + 1 < chars.count ? chars[index + 1] : "\0"
            if lineComment { if ch == "\n" { lineComment = false; output.append(ch) }; index += 1; continue }
            if blockDepth > 0 {
                if ch == "/" && next == "*" {
                    blockDepth += 1; index += 2
                } else if ch == "*" && next == "/" {
                    blockDepth -= 1; index += 2
                } else {
                    if ch == "\n" { output.append(ch) }; index += 1
                }
                continue
            }
            if !quoted && ch == "/" && next == "/" { lineComment = true; index += 2; continue }
            if !quoted && ch == "/" && next == "*" { blockDepth = 1; index += 2; continue }
            output.append(ch)
            if quoted {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    quoted = false
                }
            } else if ch == "\"" {
                quoted = true
            }
            index += 1
        }
        return output
    }
}
