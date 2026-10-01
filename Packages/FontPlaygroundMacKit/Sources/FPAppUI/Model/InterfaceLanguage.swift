import Foundation

/// The Settings › Language choice (localisation.md D5). It is stored as `AppleLanguages` in the app's own defaults
/// domain, the key System Settings' per-app language also writes, and takes effect at the next launch.
public enum InterfaceLanguage: String, CaseIterable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public static let supported = ["en", "zh-Hans"]

    /// The language this choice gives at the next launch; `.system` resolves like the system does (F5).
    public func resolved(systemLanguages: [String]) -> String {
        switch self {
        case .system: Bundle.preferredLocalizations(from: Self.supported, forPreferences: systemLanguages).first ?? "en"
        case .english, .simplifiedChinese: rawValue
        }
    }

    /// What a stored `AppleLanguages` override means. Only its first language counts.
    public init(override: [String]?) {
        guard let first = override?.first else { self = .system; return }
        if first == "en" || first.hasPrefix("en-") {
            self = .english
        } else if first == "zh-Hans" || first.hasPrefix("zh-Hans-") || first == "zh-CN" || first == "zh-SG" {
            self = .simplifiedChinese
        } else {
            self = .system
        }
    }

    /// The value to store; nil removes the override.
    public var override: [String]? { self == .system ? nil : [rawValue] }

    /// Language names are shown in their own language, whatever the interface language (§L4).
    public var title: String {
        switch self {
        case .system: ShellText.system
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    /// The title of the language a resolved code stands for.
    static func title(ofResolved code: String) -> String {
        (InterfaceLanguage(rawValue: code) ?? .english).title
    }
}
