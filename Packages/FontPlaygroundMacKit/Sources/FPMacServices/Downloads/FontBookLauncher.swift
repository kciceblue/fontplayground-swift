import AppKit
import Foundation

public protocol ApplicationOpening: Sendable {
    func applicationURL(bundleIdentifier: String) -> URL?
    func openApplication(at url: URL) async throws
}

public struct WorkspaceApplicationOpener: ApplicationOpening {
    public init() {}

    public func applicationURL(bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    public func openApplication(at url: URL) async throws {
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

public enum FontBookError: Error, Hashable, LocalizedError {
    case fontBookMissing
    public var englishText: String { "Font Book isn't available on this Mac." }
    public var errorDescription: String? { englishText }
}

public struct FontBookLauncher: Sendable {
    public static let bundleIdentifier = MacServicesConstants.fontBookBundleIdentifier
    private let opener: any ApplicationOpening

    public init(opener: any ApplicationOpening = WorkspaceApplicationOpener()) { self.opener = opener }

    public func open() async throws {
        // CATALOG-5: let Font Book manage downloads; never match downloadable font names or read private assets.
        guard let url = opener.applicationURL(bundleIdentifier: Self.bundleIdentifier) else {
            throw FontBookError.fontBookMissing
        }
        try await opener.openApplication(at: url)
    }
}
