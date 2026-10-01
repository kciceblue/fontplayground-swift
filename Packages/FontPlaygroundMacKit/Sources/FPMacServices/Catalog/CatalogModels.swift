import FPCore
import Foundation

public enum FaceOrigin: String, Codable, Sendable, CaseIterable {
    case system, systemAsset = "system_asset", local, user, activated, extraFolder = "extra_folder"
    public static func classify(path: String, isInsideUserFolder: Bool, isRegistered: Bool) -> Self {
        if isInsideUserFolder { return .user }
        if path.hasPrefix("/System/Library/AssetsV2/") { return .systemAsset }
        if path.hasPrefix("/System/Library/") || path.hasPrefix("/Library/Apple/") { return .system }
        if path.hasPrefix("/Library/Fonts/") { return .local }
        return isRegistered ? .activated : .extraFolder
    }
}
public struct FaceAnnotation: Hashable, Sendable {
    public var origin: FaceOrigin
    public var hiddenFromMenus: Bool
    public var disabledInFontBook: Bool
    public init(origin: FaceOrigin, hiddenFromMenus: Bool, disabledInFontBook: Bool) {
        self.origin = origin; self.hiddenFromMenus = hiddenFromMenus; self.disabledInFontBook = disabledInFontBook
    }
}
public enum SkipReason: String, Hashable, Sendable, Codable {
    case appleDouble = "apple_double", unsupportedFormat = "unsupported_format", hiddenFile = "hidden_file"
}
public enum CatalogIssue: Hashable, Sendable {
    case unreadable(path: String, code: String, message: String)
    case skipped(path: String, reason: SkipReason)
    case duplicate(kept: FaceKey, dropped: FaceKey, postscriptName: String)
    case noAccess(folder: String)
    case folderMissing(folder: String)
    case folderUnreadable(folder: String, message: String)
    case disabledUnlocated(postscriptName: String)

    public var englishText: String {
        switch self {
        case .noAccess(let folder): "Font Playground has no access to “\(folder)”."
        case .unreadable(let path, _, let message): "\(path): \(message)"
        case .skipped(let path, let reason): "\(path): \(reason.rawValue)"
        case .duplicate(_, let dropped, let name): "\(dropped): duplicate \(name)"
        case .folderMissing(let folder): "The font folder is missing: \(folder)"
        case .folderUnreadable(let folder, let message): "\(folder): \(message)"
        case .disabledUnlocated(let name): "Disabled font could not be located: \(name)"
        }
    }
    var sortKey: String {
        switch self {
        case .unreadable(let path, _, _), .skipped(let path, _): path
        case .duplicate(_, let key, _): key.description
        case .noAccess(let folder), .folderMissing(let folder), .folderUnreadable(let folder, _): folder
        case .disabledUnlocated(let name): name
        }
    }
}
public struct CatalogCounts: Hashable, Sendable {
    public var files = 0, faces = 0, hiddenFaces = 0, duplicateFaces = 0, unreadableFiles = 0, skippedFiles = 0
    public var disabledFaces = 0, disabledUnlocated = 0, inaccessibleFolders = 0
    public init() {}
}
public enum RefreshMode: Sendable, Equatable { case incremental, full }
public struct CatalogProgress: Hashable, Sendable {
    public var filesDone: Int
    public var filesTotal: Int
    public init(filesDone: Int, filesTotal: Int) { self.filesDone = filesDone; self.filesTotal = filesTotal }
    public var fraction: Double { filesTotal == 0 ? 1 : Double(filesDone) / Double(filesTotal) }
}
public enum CatalogActivity: Hashable, Sendable { case idle, refreshing(CatalogProgress) }
public struct CatalogSnapshot: Sendable {
    public var generation: Int
    public var faces: [FaceRecord]
    public var annotations: [FaceKey: FaceAnnotation]
    public var counts: CatalogCounts
    public var issues: [CatalogIssue]
    public var isComplete: Bool
    public var activity: CatalogActivity
    public init(
        generation: Int, faces: [FaceRecord], annotations: [FaceKey: FaceAnnotation], counts: CatalogCounts,
        issues: [CatalogIssue], isComplete: Bool, activity: CatalogActivity
    ) {
        self.generation = generation; self.faces = faces; self.annotations = annotations; self.counts = counts
        self.issues = issues; self.isComplete = isComplete; self.activity = activity
    }
    public func face(postscriptName: String) -> FaceRecord? { faces.first { $0.postscriptName == postscriptName } }
    public static let empty = CatalogSnapshot(
        generation: 0, faces: [], annotations: [:], counts: .init(), issues: [],
        isComplete: false, activity: .idle)
}
public enum CatalogError: Error, Equatable, LocalizedError {
    case engineUnavailable(String)
    public var englishText: String {
        switch self {
        case .engineUnavailable(let message): "Font Playground couldn't start its font reader: \(message)"
        }
    }
    public var errorDescription: String? { englishText }
}
