import CoreText
import Darwin
import Foundation

struct InstallerFileStat: Hashable, Sendable {
    struct Identity: Hashable, Sendable { let device: Int32; let inode: UInt64 }
    let identity: Identity
    let size: Int64
    let modifiedSeconds: Int
    let modifiedNanos: Int
    init?(_ path: String) {
        var value = stat()
        guard stat(path, &value) == 0 else { return nil }
        identity = .init(device: value.st_dev, inode: value.st_ino)
        size = value.st_size; modifiedSeconds = value.st_mtimespec.tv_sec; modifiedNanos = value.st_mtimespec.tv_nsec
    }
    static func directlyInside(_ file: URL, folder: URL) -> Bool {
        guard let parent = Self(file.deletingLastPathComponent().path), let target = Self(folder.path) else {
            return false
        }
        return parent.identity == target.identity
    }
    static func inside(_ file: URL, folder: URL) -> Bool {
        guard Self(file.path) != nil, let target = Self(folder.path) else { return false }
        var ancestor = file.deletingLastPathComponent()
        while true {
            guard let identity = Self(ancestor.path)?.identity else { return false }
            if identity == target.identity { return true }
            let parent = ancestor.deletingLastPathComponent()
            if parent.path == ancestor.path { return false }
            ancestor = parent
        }
    }
}

public struct SystemFontNameSource: FontNameSource {
    let registry: any SystemFontRegistry
    let folders: [(URL, FontDomain)]
    let userFontsFolder: URL
    public init(registry: any SystemFontRegistry, folders: [(URL, FontDomain)], userFontsFolder: URL) {
        self.registry = registry; self.folders = folders; self.userFontsFolder = userFontsFolder
    }
    public static func fold(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: nil)
    }
    public func nameEntries() -> [FontNameEntry] {
        let registered = registry.registeredFontFiles()
        let faces = registry.registeredFaces(includeDisabled: true)
        let registeredIDs = Set(registered.compactMap { InstallerFileStat($0.path)?.identity })
        var urls = registered.map { URL(fileURLWithPath: $0.path) }
        urls += faces.compactMap { $0.path.map { URL(fileURLWithPath: $0) } }
        for folder in folders.map(\.0) + [userFontsFolder] {
            guard
                let walk = FileManager.default.enumerator(
                    at: folder, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { continue }
            for case let url as URL in walk
            where MacServicesConstants.fontExtensions.contains(url.pathExtension.lowercased()) { urls.append(url) }
        }
        var seen: Set<InstallerFileStat.Identity> = []
        var tables: [Data: (families: Set<String>, fullNames: Set<String>)] = [:]
        var result: [FontNameEntry] = []
        // All faces in one directory share identity-based containment; cache only for this snapshot.
        var containment: [String: (user: Bool, injected: FontDomain?)] = [:]
        for url in urls {
            guard let identity = InstallerFileStat(url.path)?.identity, seen.insert(identity).inserted else { continue }
            let parent = url.deletingLastPathComponent().path
            let location: (user: Bool, injected: FontDomain?)
            if let cached = containment[parent] {
                location = cached
            } else {
                location = (
                    InstallerFileStat.inside(url, folder: userFontsFolder),
                    folders.first { InstallerFileStat.inside(url, folder: $0.0) }?.1
                )
                containment[parent] = location
            }
            let domain = FontDomain.classify(
                path: url.standardizedFileURL.path,
                isInsideUserFolder: location.user,
                injectedDomain: location.injected,
                isRegistered: registeredIDs.contains(identity))
            for descriptor in CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? [] {
                func string(_ key: CFString) -> String {
                    CTFontDescriptorCopyAttribute(descriptor, key) as? String ?? ""
                }
                let font = CTFontCreateWithFontDescriptor(descriptor, 0, nil)
                let data = CTFontCopyTable(font, CTFontTableTag(kCTFontTableName), []) as Data?
                var keys: (families: Set<String>, fullNames: Set<String>) = ([], [])
                if let data {
                    if let cached = tables[data] {
                        keys = cached
                    } else {
                        if let table = try? NameTable(data: data) {
                            keys.families = Set(
                                [1, 16, 21].flatMap { table.strings(nameID: UInt16($0)) }.map(Self.fold).filter {
                                    !$0.isEmpty
                                })
                            keys.fullNames = Set(table.strings(nameID: 4).map(Self.fold).filter { !$0.isEmpty })
                        }
                        tables[data] = keys
                    }
                }
                let family = string(kCTFontFamilyNameAttribute); let full = string(kCTFontDisplayNameAttribute)
                let familyKey = Self.fold(family); let fullKey = Self.fold(full)
                if !familyKey.isEmpty { keys.families.insert(familyKey) }
                if !fullKey.isEmpty { keys.fullNames.insert(fullKey) }
                result.append(
                    .init(
                        path: url.path, domain: domain, postscriptName: string(kCTFontNameAttribute),
                        familyKeys: keys.families, fullNameKeys: keys.fullNames,
                        displayFamily: family, displayStyle: string(kCTFontStyleNameAttribute), displayFullName: full))
            }
        }
        for face in faces where !face.enabled && face.path == nil {
            let family = Self.fold(face.familyName)
            result.append(
                .init(
                    path: nil, domain: .other, postscriptName: face.postscriptName,
                    familyKeys: family.isEmpty ? [] : [family], fullNameKeys: [], displayFamily: face.familyName,
                    displayStyle: "", displayFullName: ""))
        }
        return result
    }
    func fingerprint() -> [String] {
        let snapshot: (paths: [String], disabledNames: [String])
        if let coreText = registry as? CoreTextFontRegistry {
            snapshot = coreText.fingerprintSnapshot()
        } else {
            snapshot = (
                registry.registeredFontFiles().map(\.path),
                registry.registeredFaces(includeDisabled: true).filter { !$0.enabled }.map(\.postscriptName)
            )
        }
        let files = snapshot.paths.map { path in
            let stat = InstallerFileStat(path)
            return "\(path)|\(stat?.size ?? -1)|\(stat?.modifiedSeconds ?? -1)|\(stat?.modifiedNanos ?? -1)"
        }.sorted()
        let roots = (folders.map(\.0) + [userFontsFolder]).map { url in
            let stat = InstallerFileStat(url.path)
            return "\(url.path)|\(stat?.modifiedSeconds ?? -1)|\(stat?.modifiedNanos ?? -1)"
        }
        let disabled = snapshot.disabledNames.sorted()
        return files + roots + disabled
    }
}
