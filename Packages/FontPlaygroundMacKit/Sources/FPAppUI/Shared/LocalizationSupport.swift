import Foundation

/// FPAppUI's resource bundle, for tests that resolve catalog values in a chosen language (localisation.md §L7).
enum LocalizationSupport {
    static var bundleURL: URL { Bundle.module.bundleURL }
    /// The language FPAppUI's strings resolve to in this process.
    static var runningLanguage: String { Bundle.module.preferredLocalizations.first ?? "en" }
}
