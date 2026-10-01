import CoreFoundation
import FPCore
import Foundation
import Observation

@MainActor @Observable public final class SettingsStore {
    public private(set) var value: AppSettings
    public private(set) var loadIssues: [SettingsIssue]
    public var inspectorPresented: Bool {
        didSet { if oldValue != inspectorPresented { defaults.set(inspectorPresented, forKey: "inspectorPresented") } }
    }
    public var showAllScriptGroups: Bool {
        didSet {
            if oldValue != showAllScriptGroups { defaults.set(showAllScriptGroups, forKey: "showAllScriptGroups") }
        }
    }
    /// Set once the one-time donation offer has been shown; never cleared, so it can't show twice.
    public var donationOffered: Bool {
        didSet { if oldValue != donationOffered { defaults.set(donationOffered, forKey: "donationOffered") } }
    }
    private let defaults: UserDefaults
    public init(defaults: UserDefaults, probe: any FileSystemProbe) {
        self.defaults = defaults
        func bool(_ key: String) -> Bool {
            guard let n = defaults.object(forKey: key) as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else {
                return false
            }
            return n.boolValue
        }
        _ = defaults.object(forKey: "settingsVersion")
        var raw = AppSettings()
        raw.appearance =
            (defaults.object(forKey: "appearance") as? String).flatMap(AppSettings.Appearance.init(rawValue:))
            ?? .system
        raw.extraFolders = defaults.object(forKey: "extraFontFolders") as? [String] ?? []
        if let n = defaults.object(forKey: "previewPointSize") as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
            n.doubleValue == Double(n.intValue)
        {
            raw.previewPointSize = n.intValue
        }
        raw.colourByFont = bool("colourByFont")
        raw.lastSaveDirectory = defaults.object(forKey: "lastSaveDirectory") as? String
        raw.legacyImportDone = bool("legacyImportDone")
        inspectorPresented = bool("inspectorPresented")
        showAllScriptGroups = bool("showAllScriptGroups")
        donationOffered = bool("donationOffered")
        let normalized = raw.normalized(using: probe)
        value = normalized.settings; loadIssues = normalized.issues
        persist(value, comparedTo: nil)
        defaults.set(1, forKey: "settingsVersion")
        defaults.set(inspectorPresented, forKey: "inspectorPresented")
        defaults.set(showAllScriptGroups, forKey: "showAllScriptGroups")
    }
    public func update(_ change: (inout AppSettings) -> Void) {
        let old = value; change(&value); persist(value, comparedTo: old)
    }
    private func persist(_ value: AppSettings, comparedTo old: AppSettings?) {
        if old?.appearance != value.appearance { defaults.set(value.appearance.rawValue, forKey: "appearance") }
        if old?.extraFolders != value.extraFolders { defaults.set(value.extraFolders, forKey: "extraFontFolders") }
        if old?.previewPointSize != value.previewPointSize {
            defaults.set(value.previewPointSize, forKey: "previewPointSize")
        }
        if old?.colourByFont != value.colourByFont { defaults.set(value.colourByFont, forKey: "colourByFont") }
        if old == nil || old?.lastSaveDirectory != value.lastSaveDirectory {
            defaults.set(value.lastSaveDirectory, forKey: "lastSaveDirectory")
        }
        if old?.legacyImportDone != value.legacyImportDone {
            defaults.set(value.legacyImportDone, forKey: "legacyImportDone")
        }
    }
}
