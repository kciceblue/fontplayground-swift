import Foundation

public struct InstallQuery: Hashable, Sendable {
    public var family: String
    public var style: String
    public var postscriptName: String
    public var fullName: String
    public init(family: String, style: String, postscriptName: String, fullName: String? = nil) {
        self.family = family; self.style = style; self.postscriptName = postscriptName
        self.fullName = fullName ?? "\(family) \(style)".trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct InstalledFont: Hashable, Sendable, Codable {
    public var fileURL: URL
    public var family: String
    public var style: String
    public var fullName: String
    public var postscriptName: String
    public var sha256: String
    public var size: Int64
    public var installedAt: Date
    public init(
        fileURL: URL, family: String, style: String, fullName: String, postscriptName: String,
        sha256: String, size: Int64, installedAt: Date
    ) {
        self.fileURL = fileURL; self.family = family; self.style = style; self.fullName = fullName
        self.postscriptName = postscriptName; self.sha256 = sha256; self.size = size; self.installedAt = installedAt
    }
}

public enum ConflictReason: Hashable, Sendable {
    case systemHas(name: String), installedForEveryone(name: String), youHave(name: String)
    case internalNameInUse(postscriptName: String), internalNameUsedByYourFont(postscriptName: String, fullName: String)
    case hiddenName, appleOffersDownload(name: String)
    public var englishText: String {
        switch self {
        case .systemHas(let name): "macOS already has a font called “\(name)” — choose another name."
        case .installedForEveryone(let name):
            "A font called “\(name)” is already installed for everyone on this Mac — choose another name."
        case .youHave(let name): "You already have a font called “\(name)” installed — choose another name."
        case .internalNameInUse(let name):
            "Another installed font already uses the internal name “\(name)” — choose another name."
        case .internalNameUsedByYourFont(let name, let fullName):
            "Your font “\(fullName)” already uses the internal name “\(name)” — choose another name."
        case .hiddenName: "Names that start with “.” are hidden by macOS — choose another name."
        case .appleOffersDownload(let name):
            "macOS can download a font called “\(name)”. Install yours under this name anyway?"
        }
    }
}
public enum InstallConflict: Hashable, Sendable {
    case noConflict, replaceOurs(InstalledFont), ask(ConflictReason), block(ConflictReason)
    public var englishText: String {
        switch self {
        case .noConflict: "nothing is in the way"
        case .replaceOurs(let font): "Replace the “\(font.fullName)” you installed earlier?"
        case .ask(let reason), .block(let reason): reason.englishText
        }
    }
}
public enum InstallError: Error, Hashable, LocalizedError {
    case invalidQuery, sourceMissing, unreadable, unexpectedName(expected: String, found: String), notForged
    case conflict(InstallConflict), noFreeFileName(stem: String), notOurs(name: String)
    case previousCopyNotRemoved(installed: InstalledFont, previous: InstalledFont, message: String)
    case manifestUnsupported, fileSystem(operation: String, message: String)
    public var errorDescription: String? { englishText }
    public var englishText: String {
        switch self {
        case .invalidQuery: "the font needs a name"
        case .sourceMissing: "the built font file is missing"
        case .unreadable: "macOS can't read this font file"
        case .unexpectedName(let expected, let found): "its internal name is “\(found)”, not “\(expected)”"
        case .notForged: "it wasn't made by Font Playground"
        case .conflict(let conflict): conflict.englishText
        case .noFreeFileName(let stem): "there's no free file name for “\(stem)” in your Fonts folder"
        case .notOurs(let name): "Font Playground didn't install “\(name)”, so it won't remove it"
        case .previousCopyNotRemoved(let installed, let previous, let message):
            "Installed “\(installed.fullName)”, but couldn't remove “\(previous.fullName)”: \(message)"
        case .manifestUnsupported: "the list of fonts Font Playground installed was written by a newer version"
        case .fileSystem(_, let message): message
        }
    }
}
public enum UninstallOutcome: Hashable, Sendable {
    case movedToTrash(URL?), notInstalled
    public var englishText: String {
        switch self {
        case .movedToTrash: "Removed from your fonts — it's in the Trash."
        case .notInstalled: "That font was no longer installed."
        }
    }
}
public enum FontDomain: String, Codable, Sendable {
    case system, local, user, other, downloadable
    public static func classify(path: String, isInsideUserFolder: Bool, injectedDomain: FontDomain?, isRegistered: Bool)
        -> FontDomain
    {
        if isInsideUserFolder { return .user }
        if let injectedDomain { return injectedDomain }
        if path.hasPrefix("/System/Library/") || path.hasPrefix("/Library/Apple/") { return .system }
        if path.hasPrefix("/Library/Fonts/") { return .local }
        return .other
    }
}
public struct FontNameEntry: Hashable, Sendable {
    public var path: String?
    public var domain: FontDomain
    public var postscriptName: String
    public var familyKeys: Set<String>
    public var fullNameKeys: Set<String>
    public var displayFamily: String
    public var displayStyle: String
    public var displayFullName: String
    public init(
        path: String?, domain: FontDomain, postscriptName: String, familyKeys: Set<String>, fullNameKeys: Set<String>,
        displayFamily: String, displayStyle: String, displayFullName: String
    ) {
        self.path = path; self.domain = domain; self.postscriptName = postscriptName
        self.familyKeys = familyKeys; self.fullNameKeys = fullNameKeys; self.displayFamily = displayFamily
        self.displayStyle = displayStyle; self.displayFullName = displayFullName
    }
}
public protocol FontNameSource: Sendable { func nameEntries() -> [FontNameEntry] }
public protocol FontInstalling: Sendable {
    func conflict(for query: InstallQuery) async throws -> InstallConflict
    func install(_ source: URL, expecting query: InstallQuery, confirmed: InstallConflict?) async throws
        -> InstalledFont
    func uninstall(_ font: InstalledFont) async throws -> UninstallOutcome
    func installedFonts() async throws -> [InstalledFont]
}
extension FontInstalling {
    public func install(_ source: URL, expecting query: InstallQuery) async throws -> InstalledFont {
        try await install(source, expecting: query, confirmed: nil)
    }
}
