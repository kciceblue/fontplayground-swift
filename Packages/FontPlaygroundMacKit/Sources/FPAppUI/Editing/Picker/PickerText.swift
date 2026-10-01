import FPCore
import Foundation

// Catalog-backed wording stays separate from the picker state and its row identities.
enum PickerText {
    static func rowAccessibilityLabel(
        family: String, nativeName: String, inRecipe: Bool, unavailableReason: String? = nil
    ) -> String {
        var parts = [family, nativeName]
        if inRecipe { parts.append(inYourFont) }
        if let unavailableReason { parts.append(unavailableLabel(unavailableReason)) }
        return parts.filter { !$0.isEmpty }.joined(separator: ModelText.listSeparator)
    }
    static func headerAccessibilityLabel(_ title: String) -> String {
        title.replacingOccurrences(of: " · ", with: ", ")
    }

    static let searchAccessibilityLabel = String(
        localized: "Search fonts", bundle: .module, comment: "picker.search.label")
    static let tableLabel = String(localized: "Fonts", bundle: .module, comment: "picker.table.label")
    static let languageLabel = String(localized: "Show fonts for", bundle: .module, comment: "picker.language.label")
    static let filterNote = String(
        localized: "Only fonts that draw it well", bundle: .module, comment: "picker.filter.note")
    static let suggested = String(localized: "Suggested for your text", bundle: .module, comment: "picker.suggested")
    static let inYourFont = String(localized: "in your font", bundle: .module, comment: "picker.in.recipe")
    static let back = String(localized: "Back", bundle: .module, comment: "picker.back")
    static let cancel = String(localized: "Cancel", bundle: .module, comment: "picker.cancel")
    static let style = String(localized: "Style", bundle: .module, comment: "picker.style")
    static func number(_ value: Int, locale: Locale) -> String { value.formatted(.number.locale(locale)) }
    static func title(language: Language, main: FaceRecord?, replaced: String?) -> String {
        if let replaced {
            return String(localized: "Replace \(replaced)", bundle: .module, comment: "picker.title.replace")
        }
        if main == nil {
            return String(localized: "Choose your main font", bundle: .module, comment: "picker.title.main")
        }
        if language.id == .any {
            return String(localized: "Choose a font", bundle: .module, comment: "picker.title.any")
        }
        let name = ModelText.languageShortLabel(language.id)
        return String(localized: "Choose a font for \(name)", bundle: .module, comment: "picker.title.language")
    }
    static func placeholder(_ count: Int, locale: Locale) -> String {
        if count == 1 {
            return String(
                localized: "Search 1 font — English or native name", bundle: .module, comment: "picker.search.one")
        }
        let n = number(count, locale: locale)
        return String(
            localized: "Search \(n) fonts — English or native name", bundle: .module, comment: "picker.search.many")
    }
    static func all(language: Language, count: Int, locale: Locale) -> String {
        let n = number(count, locale: locale)
        if language.id == .any {
            return String(localized: "All fonts · \(n)", bundle: .module, comment: "picker.section.any")
        }
        let name =
            language.id == .latin
            ? String(localized: "Latin", bundle: .module, comment: "picker.section.latin")
            : ModelText.languageShortLabel(language.id)
        return String(localized: "All \(name) fonts · \(n)", bundle: .module, comment: "picker.section.language")
    }
    static func unshapable(language: Language, count: Int, locale: Locale, checkbox: Bool) -> String {
        let name = ModelText.languageShortLabel(language.id), n = number(count, locale: locale)
        if checkbox {
            return String(
                localized: "Show fonts that can't shape \(name) (\(n))", bundle: .module,
                comment: "picker.unshapable.toggle")
        }
        return String(localized: "Can't shape \(name) · \(n)", bundle: .module, comment: "picker.unshapable.section")
    }
    static func unavailable(_ language: Language) -> String {
        let name = ModelText.languageShortLabel(language.id)
        return String(
            localized: "Can't shape \(name): its shaping is Apple-only", bundle: .module,
            comment: "picker.unshapable.reason")
    }
    static func use(_ family: String?) -> String {
        guard let family else { return String(localized: "Use", bundle: .module, comment: "picker.use.empty") }
        let name = family.count > 24 ? String(family.prefix(23)) + "…" : family
        return String(localized: "Use \(name)", bundle: .module, comment: "picker.use.font")
    }
    static func status(
        scanning: Bool, done: Int, total: Int, empty: Bool, query: String, language: Language, count: Int,
        unreadable: Int, locale: Locale
    ) -> String {
        if scanning {
            if total == 0 {
                return String(localized: "Looking for fonts…", bundle: .module, comment: "picker.scan.start")
            }
            let done = number(done, locale: locale), total = number(total, locale: locale)
            return String(
                localized: "Looking for fonts… \(done) / \(total)", bundle: .module, comment: "picker.scan.progress")
        }
        if empty && !query.isEmpty {
            return String(localized: "No fonts match “\(query)”.", bundle: .module, comment: "picker.no.match")
        }
        if empty && language.id != .any {
            let name = ModelText.languageLabel(language.id)
            return String(
                localized: "None of your fonts draw \(name) well.", bundle: .module, comment: "picker.no.language")
        }
        let n = number(count, locale: locale), k = number(unreadable, locale: locale)
        let fonts =
            count == 1
            ? String(localized: "1 font", bundle: .module, comment: "picker.count.one")
            : String(localized: "\(n) fonts", bundle: .module, comment: "picker.count.many")
        if unreadable == 0 { return fonts }
        let failures =
            unreadable == 1
            ? String(localized: "1 file couldn't be read", bundle: .module, comment: "picker.error.one")
            : String(localized: "\(k) files couldn't be read", bundle: .module, comment: "picker.error.many")
        return String(localized: "\(fonts) · \(failures)", bundle: .module, comment: "picker.count.errors")
    }
    static func statusHelp(
        unreadable: [CatalogStatus.Unreadable], hidden: Int, duplicates: Int, locale: Locale = .current
    ) -> String {
        var lines = unreadable.map { "\($0.path): \($0.message)" }
        if hidden + duplicates > 0 {
            let h = number(hidden, locale: locale), d = number(duplicates, locale: locale)
            let hiddenText =
                hidden == 1
                ? String(localized: "1 hidden system font", bundle: .module, comment: "picker.hidden.one")
                : String(localized: "\(h) hidden system fonts", bundle: .module, comment: "picker.hidden.many")
            let duplicateText =
                duplicates == 1
                ? String(localized: "1 duplicate", bundle: .module, comment: "picker.duplicate.one")
                : String(localized: "\(d) duplicates", bundle: .module, comment: "picker.duplicate.many")
            lines.append(
                String(
                    localized: "\(hiddenText) and \(duplicateText) aren't listed.", bundle: .module,
                    comment: "picker.hidden.help"))
        }
        return lines.joined(separator: "\n")
    }
    static func trialBanner(family: String, languageID: String?, replacedFamily: String?, first: Bool) -> String {
        let prefix: String
        if first {
            prefix = String(
                localized: "Trying \(family) as your main font", bundle: .module, comment: "picker.trial.main")
        } else if let replacedFamily {
            prefix = String(
                localized: "Trying \(family) instead of \(replacedFamily)", bundle: .module,
                comment: "picker.trial.replace")
        } else if let languageID, let language = Languages.language(rawID: languageID), language.id != .any {
            let name = ModelText.languageShortLabel(language.id)
            prefix = String(
                localized: "Trying \(family) for \(name)", bundle: .module, comment: "picker.trial.language")
        } else {
            prefix = String(localized: "Trying \(family)", bundle: .module, comment: "picker.trial.any")
        }
        return String(
            localized: "\(prefix) — ↑ ↓ try the next font, Return uses it.", bundle: .module,
            comment: "picker.trial.hint")
    }
    static func sampleHelp(_ sample: String) -> String {
        String(localized: "Sample: \(sample)", bundle: .module, comment: "picker.sample.help")
    }
    static func unavailableLabel(_ reason: String) -> String {
        String(localized: "unavailable: \(reason)", bundle: .module, comment: "picker.unavailable.label")
    }
}
