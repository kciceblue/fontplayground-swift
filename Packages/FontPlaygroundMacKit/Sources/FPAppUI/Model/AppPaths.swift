import FPCore
import Foundation

public struct AppPaths: Equatable, Sendable {
    public var applicationSupport: URL
    public var caches: URL
    public var userFonts: URL
    public var documents: URL
    public var legacyFolder: URL
    public var builds: URL { caches.appending(path: "builds") }
    public var helperTemp: URL { caches.appending(path: "tmp") }
    public var lastRecipe: URL { applicationSupport.appending(path: "last.fontrecipe") }
    public var installedManifest: URL { applicationSupport.appending(path: "installed.json") }
    public static func live(fileManager: FileManager = .default) -> AppPaths {
        let home = fileManager.homeDirectoryForCurrentUser
        return AppPaths(
            applicationSupport: home.appending(path: "Library/Application Support/\(AppLog.subsystem)"),
            caches: home.appending(path: "Library/Caches/\(AppLog.subsystem)"),
            userFonts: home.appending(path: "Library/Fonts"), documents: home.appending(path: "Documents"),
            legacyFolder: URL(fileURLWithPath: LegacyImport.legacyFolder(home: home.path)))
    }
    public static func rooted(at root: URL) -> AppPaths {
        AppPaths(
            applicationSupport: root.appending(path: "support"), caches: root.appending(path: "caches"),
            userFonts: root.appending(path: "fonts"), documents: root.appending(path: "documents"),
            legacyFolder: root.appending(path: "legacy"))
    }
}
