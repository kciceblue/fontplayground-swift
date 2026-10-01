import Foundation

public struct AppSettings: Codable, Sendable, Equatable {
    public enum Appearance: String, Codable, Sendable, CaseIterable { case system, light, dark }
    public static let previewPointSizes = 10...96
    public static let defaultPreviewPointSize = 30
    public var appearance: Appearance = .system
    public var extraFolders: [String] = []
    public var previewPointSize = 30
    public var colourByFont = false
    public var lastSaveDirectory: String?
    public var legacyImportDone = false
    public init() {}

    public func normalized(using probe: any FileSystemProbe) -> (settings: AppSettings, issues: [SettingsIssue]) {
        var result = self, issues: [SettingsIssue] = [], seen = Set<String>()
        result.extraFolders = []
        for folder in extraFolders {
            switch FolderCheck.check(folder, using: probe) {
            case .success(let accepted):
                if seen.insert(accepted.path).inserted { result.extraFolders.append(accepted.path) }
            case .failure(let reason): issues.append(.droppedFolder(folder, reason))
            }
        }
        if !Self.previewPointSizes.contains(previewPointSize) {
            result.previewPointSize = Self.defaultPreviewPointSize
            issues.append(.previewSizeReset(previewPointSize))
        }
        if let directory = lastSaveDirectory {
            switch FolderCheck.check(directory, using: probe) {
            case .success(let accepted): result.lastSaveDirectory = accepted.path
            case .failure(let reason):
                result.lastSaveDirectory = nil
                issues.append(.lastSaveDirectoryDropped(directory, reason))
            }
        }
        return (result, issues)
    }
}

public enum SettingsIssue: Sendable, Equatable {
    case droppedFolder(String, FolderCheck.Failure)
    case previewSizeReset(Int)
    case lastSaveDirectoryDropped(String, FolderCheck.Failure)
}
