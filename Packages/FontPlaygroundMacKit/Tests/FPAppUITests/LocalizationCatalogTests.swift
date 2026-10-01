import Foundation
import Testing

@testable import FPAppUI

@MainActor enum LocalizationSource {
    static var package: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }
    static var sources: URL { package.appending(path: "Sources/FPAppUI") }
    static func files() -> [URL] {
        FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!.compactMap { $0 as? URL }.filter {
            $0.pathExtension == "swift"
        }
    }
    static func keys(in text: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: #"String\s*\(\s*localized:\s*\"((?:\\.|[^\"\\])*)\""#)
        let source = SourceLintTests.withoutComments(text) as NSString
        return expression.matches(in: source as String, range: NSRange(location: 0, length: source.length)).map {
            source.substring(with: $0.range(at: 1))
        }
    }
    /// The key Foundation looks up for a source literal: with interpolation, a literal "%" becomes "%%" (F7).
    static func runtimeKey(_ sourceKey: String) -> String {
        guard sourceKey.contains("\\(") else { return sourceKey }
        let chars = Array(sourceKey); var result = "", index = 0
        while index < chars.count {
            if chars[index] == "\\", index + 1 < chars.count, chars[index + 1] == "(" {
                var depth = 1; result += "\\("; index += 2
                while index < chars.count && depth > 0 {
                    if chars[index] == "(" { depth += 1 }; if chars[index] == ")" { depth -= 1 }
                    result.append(chars[index]); index += 1
                }
            } else {
                result += chars[index] == "%" ? "%%" : String(chars[index]); index += 1
            }
        }
        return result
    }
    static func normalized(_ key: String) throws -> String {
        let chars = Array(key); var result = "", index = 0
        while index < chars.count {
            if chars[index] == "\\", index + 1 < chars.count, chars[index + 1] == "(" {
                var depth = 1; index += 2
                while index < chars.count && depth > 0 {
                    if chars[index] == "(" { depth += 1 }; if chars[index] == ")" { depth -= 1 }; index += 1
                }
                result += "{value}"
            } else if chars[index] == "\\", index + 1 < chars.count {
                index += 1
                switch chars[index] {
                case "n": result += "\n";
                case "t": result += "\t";
                case "r": result += "\r";
                default: result.append(chars[index])
                }
                index += 1
            } else {
                result.append(chars[index]); index += 1
            }
        }
        result = result.replacingOccurrences(of: "%%", with: "{percent}")
        let expression = try NSRegularExpression(
            pattern: #"%(?:\d+\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|ll|[hlLzjtq])?[@diuoxXfFeEgGaAcCsSp]"#)
        return expression.stringByReplacingMatches(
            in: result, range: NSRange(location: 0, length: (result as NSString).length), withTemplate: "{value}")
    }
    static func catalog(at url: URL? = nil) throws -> [String: Any] {
        let url = url ?? sources.appending(path: "Resources/Localizable.xcstrings")
        return try #require(
            (JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])?["strings"] as? [String: Any])
    }
}
@MainActor struct LocalizationCatalogTests {
    @Test func everyKeyExistsAndIsUsed() throws {
        var used = Set<String>()
        for file in LocalizationSource.files() {
            for key in try LocalizationSource.keys(in: String(contentsOf: file, encoding: .utf8)) {
                used.insert(try LocalizationSource.normalized(LocalizationSource.runtimeKey(key)))
            }
        }
        let catalog = try Set(LocalizationSource.catalog().keys.map(LocalizationSource.normalized))
        #expect(used.subtracting(catalog).isEmpty, "Missing: \(used.subtracting(catalog).sorted())")
        #expect(catalog.subtracting(used).isEmpty, "Stale: \(catalog.subtracting(used).sorted())")
        #expect(
            try LocalizationSource.normalized(#"\(joinAnd(shown)) and \(count)"#)
                == LocalizationSource.normalized("%1$@ and %2$lld"))
        // F7: an interpolated literal "%" is looked up as "%%"; a plain literal keeps its "%".
        let percent = try LocalizationSource.normalized(LocalizationSource.runtimeKey(#"\(value) %"#))
        #expect(try percent == LocalizationSource.normalized("%lld %%"))
        #expect(try percent != LocalizationSource.normalized("%lld %"))
        #expect(LocalizationSource.runtimeKey("100 % keeps") == "100 % keeps")
    }
    @Test func everyEntryIsTranslatedEnglish() throws {
        for (key, entry) in try LocalizationSource.catalog() {
            let unit = ((entry as? [String: Any])?["localizations"] as? [String: Any])?["en"] as? [String: Any]
            let string = unit?["stringUnit"] as? [String: Any]
            #expect(string?["state"] as? String == "translated", "\(key)")
            #expect((string?["value"] as? String)?.isEmpty == false, "\(key)")
        }
    }
    @Test func infoPlistCatalogHasTheBundleStrings() throws {
        let root = LocalizationSource.package.deletingLastPathComponent().deletingLastPathComponent()
        let strings = try LocalizationSource.catalog(at: root.appending(path: "App/Resources/InfoPlist.xcstrings"))
        let keys = [
            "CFBundleDisplayName", "CFBundleName", "NSDocumentsFolderUsageDescription",
            "NSDesktopFolderUsageDescription", "NSDownloadsFolderUsageDescription",
            "NSRemovableVolumesUsageDescription", "NSNetworkVolumesUsageDescription",
        ]
        #expect(Set(keys).isSubset(of: Set(strings.keys)))
        for key in keys {
            let entry = strings[key] as? [String: Any],
                en = (entry?["localizations"] as? [String: Any])?["en"] as? [String: Any]
            let unit = en?["stringUnit"] as? [String: String]
            #expect(unit?["state"] == "translated" && unit?["value"]?.isEmpty == false)
        }
    }
    @Test("UI-6: strings use Mac key names") func ui6NoPCKeyNamesInStrings() throws {
        let forbidden = try Regex(#"\bCtrl\b|\bAlt\b|\bEnter\b|Windows|Explorer|Show file|admin rights|right-click"#)
        for (key, entry) in try LocalizationSource.catalog() {
            let en = ((entry as? [String: Any])?["localizations"] as? [String: Any])?["en"] as? [String: Any]
            if let value = (en?["stringUnit"] as? [String: String])?["value"] {
                #expect(value.firstMatch(of: forbidden) == nil, "\(key)")
            }
        }
        #expect(PreviewText.sampleHelp.contains("⌘Z"))
        #expect(
            PickerText.trialBanner(family: "Fixture", languageID: nil, replacedFamily: nil, first: true).contains(
                "Return"))
    }
}

// WP-508: Simplified Chinese (docs/specs/localisation.md).
@MainActor enum ChineseCatalog {
    static var repository: URL { LocalizationSource.package.deletingLastPathComponent().deletingLastPathComponent() }
    static var catalogs: [URL] {
        [
            LocalizationSource.sources.appending(path: "Resources/Localizable.xcstrings"),
            repository.appending(path: "App/Resources/InfoPlist.xcstrings"),
            repository.appending(path: "App/Resources/Localizable.xcstrings"),
        ]
    }
    static func value(_ entry: Any?, _ language: String) -> String? {
        (((entry as? [String: Any])?["localizations"] as? [String: Any])?[language] as? [String: Any]).flatMap {
            ($0["stringUnit"] as? [String: Any])?["value"] as? String
        }
    }
    static func pairs(_ url: URL? = nil) throws -> [(key: String, en: String, zh: String?)] {
        try LocalizationSource.catalog(at: url).map { key, entry in
            (key, value(entry, "en") ?? key, value(entry, "zh-Hans"))
        }
    }
    /// §L3 table 3: values that stay English in Chinese.
    static let keptValues: Set<String> = ["weight.light", "Regular", "Medium", "Semibold", "Bold", "Heavy"]
    static let keptTokens = [
        "OpenType", "TrueType", "PostScript", "AAT", "Unicode", "fontTools", "Python", "fpengine", ".fontrecipe",
        ".ttf", "Return", "Esc", "⌘", "⌥", "⇧", "⌃",
    ]
    /// Format specifiers in order: (explicit position or nil, type such as "@" or "lld"). "%%" is a literal.
    static func specifiers(_ text: String) throws -> [(position: Int?, type: String)] {
        let expression = try NSRegularExpression(
            pattern: #"%(?:(\d+)\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?((?:hh|ll|[hlLzjtq])?[@diuoxXfFeEgGaAcCsSp])"#)
        let stripped = text.replacingOccurrences(of: "%%", with: "") as NSString
        return expression.matches(in: stripped as String, range: NSRange(location: 0, length: stripped.length)).map {
            let position = $0.range(at: 1).location == NSNotFound ? nil : Int(stripped.substring(with: $0.range(at: 1)))
            return (position, stripped.substring(with: $0.range(at: 2)))
        }
    }
    /// §L5: the same types in the same order, or all positional with each position's type matching English.
    static func placeholdersMatch(en: String, zh: String) throws -> Bool {
        let english = try specifiers(en), chinese = try specifiers(zh)
        guard english.count == chinese.count else { return false }
        var types = english.map(\.type)
        if english.allSatisfy({ $0.position != nil }) {
            types = english.sorted { $0.position! < $1.position! }.map(\.type)
        }
        if chinese.allSatisfy({ $0.position == nil }) { return chinese.map(\.type) == types }
        guard chinese.allSatisfy({ $0.position != nil }),
            Set(chinese.map(\.position!)) == Set(1...max(1, chinese.count)), chinese.count == types.count
        else { return false }
        return chinese.allSatisfy { types[$0.position! - 1] == $0.type }
    }
    static func resolve(_ key: String.LocalizationValue, _ language: String) -> String {
        var resource = LocalizedStringResource(key, bundle: .atURL(LocalizationSupport.bundleURL))
        resource.locale = Locale(identifier: language)
        return String(localized: resource)
    }
}
extension LocalizationCatalogTests {
    @Test("CRIT-10: every entry has Simplified Chinese") func everyEntryHasSimplifiedChinese() throws {
        let latin = try Regex(#"[A-Za-z]"#)
        for url in ChineseCatalog.catalogs {
            for (key, en, zh) in try ChineseCatalog.pairs(url) {
                let value = try #require(zh, "\(url.lastPathComponent): \(key)")
                #expect(!value.isEmpty, "\(key)")
                let letters = en.replacingOccurrences(
                    of: #"%(?:\d+\$)?(?:ll)?[@d]"#, with: "", options: .regularExpression)
                if value == en && !ChineseCatalog.keptValues.contains(key) {
                    #expect(letters.firstMatch(of: latin) == nil, "untranslated: \(key)")
                }
            }
        }
    }
    @Test func placeholdersMatchAcrossLanguages() throws {
        #expect(try ChineseCatalog.placeholdersMatch(en: "%@ can't shape %@", zh: "%2$@ 无法由 %1$@ 塑形"))
        #expect(try !ChineseCatalog.placeholdersMatch(en: "%@ and %lld more", zh: "%lld 个以及 %@"))
        #expect(try ChineseCatalog.placeholdersMatch(en: "%lld %%", zh: "%lld%%"))
        for url in ChineseCatalog.catalogs {
            for (key, en, zh) in try ChineseCatalog.pairs(url) {
                #expect(try ChineseCatalog.placeholdersMatch(en: en, zh: zh ?? ""), "\(key)")
            }
        }
    }
    @Test("CRIT-10: Chinese uses Apple's Mac terms") func zhUsesMacTerms() throws {
        let table = [
            "Show in Finder": "在访达中显示", "Show Settings Folder in Finder": "在访达中显示设置文件夹",
            "Open in Font Book": "在字体册中打开", "Get More Fonts…": "获取更多字体…", "Save a Copy…": "存储副本…",
            "Install": "安装", "Update Installed Font": "更新已安装的字体", "Replace": "替换", "Remove": "移除",
            "Cancel": "取消", "Quit": "退出", "Keep Building": "继续生成", "Undo": "撤销", "Rescan Fonts": "重新扫描字体",
            "Add Font Folder…": "添加字体文件夹…", "Add Font Folder": "添加字体文件夹", "Start Over": "重新开始",
            "Show Advanced": "显示高级选项", "Hide Advanced": "隐藏高级选项", "Appearance": "外观", "System": "跟随系统",
            "Light": "浅色", "Dark": "深色", "Preview": "预览", "Sample Text": "示例文本", "Colour by Font": "按字体着色",
        ]
        let catalog = try LocalizationSource.catalog()
        for (key, expected) in table {
            #expect(ChineseCatalog.value(catalog[key], "zh-Hans") == expected, "\(key)")
        }
        let forbidden = try Regex(#"Finder|Font Book|Trash|Ctrl|\bAlt\b|Enter|Windows|资源管理器|右键|右击|管理员|回车|控制面板|注册表|您"#)
        for url in ChineseCatalog.catalogs {
            for (key, _, zh) in try ChineseCatalog.pairs(url) {
                #expect((zh ?? "").firstMatch(of: forbidden) == nil, "\(key)")
            }
        }
    }
    @Test func keptTermsStayEnglish() throws {
        let catalog = try LocalizationSource.catalog()
        for key in ChineseCatalog.keptValues {
            #expect(ChineseCatalog.value(catalog[key], "zh-Hans") == ChineseCatalog.value(catalog[key], "en"), "\(key)")
        }
        for (key, en, zh) in try ChineseCatalog.pairs() {
            for token in ChineseCatalog.keptTokens where en.contains(token) {
                #expect((zh ?? "").contains(token), "\(key): \(token)")
            }
        }
    }
    @Test func sharedKeysAreReviewed() throws {
        let call = try NSRegularExpression(
            pattern: #"String\s*\(\s*localized:\s*\"((?:\\.|[^\"\\])*)\"(.*?)comment:\s*\"([^\"]*)\""#,
            options: [.dotMatchesLineSeparators])
        var comments: [String: Set<String>] = [:]
        for file in LocalizationSource.files() {
            let text = SourceLintTests.withoutComments(try String(contentsOf: file, encoding: .utf8)) as NSString
            for match in call.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
                let key = try LocalizationSource.normalized(
                    LocalizationSource.runtimeKey(text.substring(with: match.range(at: 1))))
                comments[key, default: []].insert(text.substring(with: match.range(at: 3)))
            }
        }
        let reviewed = try Set(
            [
                "Cancel", "Style", "Latin", "%@ isn't on this Mac. Use %@ instead?", "Main font", "%", "Undo",
                "Install",
                "Save a Copy…", "Show in Finder", "Open in Font Book", "Regular", "Colour by Font", "Sample Text",
                "Use %@", "Size", "%@: %@",
            ].map(LocalizationSource.normalized))
        let shared = Set(comments.filter { $0.value.count > 1 }.keys)
        #expect(
            shared == reviewed,
            "Unreviewed: \(shared.subtracting(reviewed).sorted()); no longer shared: \(reviewed.subtracting(shared).sorted())"
        )
        let contextKey = try Regex(#"^[a-z]+(\.[A-Za-z]+)+$"#)
        #expect(
            try LocalizationSource.catalog().keys.filter { $0.wholeMatch(of: contextKey) != nil } == ["weight.light"])
        #expect(ChineseCatalog.resolve("Light", "zh-Hans") == "浅色")
        #expect(ChineseCatalog.resolve("weight.light", "zh-Hans") == "Light")
        #expect(
            ChineseCatalog.resolve("Light", "en") == "Light" && ChineseCatalog.resolve("weight.light", "en") == "Light")
        #expect(ShellText.weightLight == "Light" && ShellText.light == "Light")
    }
    @Test func listSeparatorsAreLocalized() throws {
        let catalog = try LocalizationSource.catalog()
        #expect(ChineseCatalog.value(catalog[", "], "zh-Hans") == "、")
        #expect(ChineseCatalog.value(catalog[" and "], "zh-Hans") == "和")
        #expect(ChineseCatalog.value(catalog[" & "], "zh-Hans") == "和")
        #expect(ModelText.listSeparator == ", ")
        // F7: interpolated keys with a literal "%" resolve in both languages.
        #expect(ChineseCatalog.resolve("\(80) %", "zh-Hans") == "80%")
        #expect(ChineseCatalog.resolve("\(80) %", "en") == "80 %")
        #expect(
            ChineseCatalog.resolve(
                "Draw this font's characters larger or smaller (100 % keeps them as they are)", "zh-Hans")
                == "把这个字体的字符放大或缩小（100 % 表示保持原样）")
    }
    @Test("CRIT-10: tests assert English, so they must resolve English") func testsResolveEnglish() throws {
        let bundle = try #require(Bundle(url: LocalizationSupport.bundleURL))
        #expect(
            bundle.preferredLocalizations.first == "en",
            "FPAppUI tests assert English text. Run them with make mac-test, whose host has no Chinese localisation (localisation.md F2)."
        )
    }
}
