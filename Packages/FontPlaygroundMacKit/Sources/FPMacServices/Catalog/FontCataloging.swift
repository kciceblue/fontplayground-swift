import FPEngineClient
import Foundation

public protocol FontCataloging: Sendable {
    func currentSnapshot() async -> CatalogSnapshot
    func snapshots() async -> AsyncStream<CatalogSnapshot>
    func refresh(_ mode: RefreshMode) async throws -> CatalogSnapshot
    func cancelRefresh() async
    func extraFolders() async -> [URL]
    func setExtraFolders(_ folders: [URL]) async
    func noteInstalled(_ fileURL: URL) async throws -> CatalogSnapshot
    func noteRemoved(_ fileURL: URL) async -> CatalogSnapshot
    func startObservingSystemChanges() async
    func stopObservingSystemChanges() async
}
public struct CatalogConfiguration: Sendable {
    public var cacheDirectory: URL
    public var standardFolders: [URL]
    public var userFontsFolder: URL
    public var homeDirectory: URL
    public var maxConcurrentScans: Int
    public var batchMaxFiles: Int = 48
    public var batchMaxBytes: Int64 = 256 << 20
    public var changeDebounce: Duration = .milliseconds(1500)
    public var publishInterval: Duration = .milliseconds(300)
    public init(
        cacheDirectory: URL, standardFolders: [URL] = [], userFontsFolder: URL, homeDirectory: URL,
        maxConcurrentScans: Int? = nil
    ) {
        self.cacheDirectory = cacheDirectory
        self.standardFolders = standardFolders
        self.userFontsFolder = userFontsFolder
        self.homeDirectory = homeDirectory
        self.maxConcurrentScans = max(
            1, maxConcurrentScans ?? min(3, max(1, ProcessInfo.processInfo.activeProcessorCount / 4)))
    }
    public static func standard() -> Self {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let userFonts = home.appendingPathComponent("Library/Fonts")
        return Self(
            cacheDirectory: home.appendingPathComponent("Library/Caches/" + MacServicesConstants.bundleIdentifier),
            standardFolders: [
                URL(fileURLWithPath: "/System/Library/Fonts"), URL(fileURLWithPath: "/Library/Fonts"), userFonts,
            ],
            userFontsFolder: userFonts, homeDirectory: home)
    }
}
