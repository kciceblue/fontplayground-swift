import CoreText
import Darwin
import Foundation
import os

public actor FontInstaller: FontInstalling {
    public static let defaultSystemFolders: [(URL, FontDomain)] = [
        (URL(fileURLWithPath: "/System/Library/Fonts"), .system), (URL(fileURLWithPath: "/Library/Fonts"), .local),
    ]
    private let fontsFolder: URL
    private let manifestURL: URL
    private let extraNames: (any FontNameSource)?
    private let fileSystem: any InstallFileSystem
    private let trash: any TrashCan
    private let now: @Sendable () -> Date
    private let index: FontNameIndex
    private var hashes: [String: (InstallerFileStat, String)] = [:]
    private let logger = Logger(subsystem: MacServicesConstants.bundleIdentifier, category: "FontInstaller")

    public init(
        fontsFolder: URL, manifestURL: URL, registry: any SystemFontRegistry = CoreTextFontRegistry(),
        systemFolders: [(URL, FontDomain)] = FontInstaller.defaultSystemFolders,
        extraNames: (any FontNameSource)? = nil, fileSystem: any InstallFileSystem = PosixInstallFileSystem(),
        trash: any TrashCan = FinderTrash(), now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fontsFolder = fontsFolder.standardizedFileURL; self.manifestURL = manifestURL
        self.extraNames = extraNames; self.fileSystem = fileSystem; self.trash = trash; self.now = now
        index = FontNameIndex(
            source: SystemFontNameSource(registry: registry, folders: systemFolders, userFontsFolder: fontsFolder))
    }
    public static func standard() -> FontInstaller {
        let manager = FileManager.default
        return .init(
            fontsFolder: manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Fonts"),
            manifestURL: manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(MacServicesConstants.bundleIdentifier).appendingPathComponent("installed.json"))
    }
    private func mapped(_ error: Error, operation: String) -> InstallError {
        if let error = error as? InstallError { return error }
        if let posix = error as? POSIXError {
            return .fileSystem(operation: operation, message: String(cString: strerror(posix.code.rawValue)))
        }
        return .fileSystem(operation: operation, message: error.localizedDescription)
    }
    private func readManifest() throws -> InstallManifest {
        do { return try InstallManifest.read(manifestURL, now: now()) } catch { throw mapped(error, operation: "read") }
    }
    private func writeManifest(_ manifest: InstallManifest) throws {
        do { try manifest.write(to: manifestURL, fileSystem: fileSystem) } catch {
            throw mapped(error, operation: "manifest")
        }
    }
    private func ours(_ path: String, manifest: InstallManifest) -> InstalledFont? {
        let url = URL(fileURLWithPath: path)
        // INSTALL-M1/10/11: ownership requires folder identity, manifest, bytes, marker and internal name.
        guard InstallerFileStat.directlyInside(url, folder: fontsFolder),
            let entry = manifest.fonts.first(where: {
                $0.fileName.precomposedStringWithCanonicalMapping
                    == url.lastPathComponent.precomposedStringWithCanonicalMapping
            }),
            let font = entry.font(in: fontsFolder), let stamp = InstallerFileStat(path), stamp.size == entry.size
        else { return nil }
        let hash: String
        if let cached = hashes[path], cached.0 == stamp {
            hash = cached.1
        } else {
            guard let digest = try? fileSystem.sha256(of: url) else { return nil }
            hashes[path] = (stamp, digest); hash = digest
        }
        guard hash == entry.sha256, ForgedMarker.isForged(fileAt: url),
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
            descriptors.count == 1,
            CTFontDescriptorCopyAttribute(descriptors[0], kCTFontNameAttribute) as? String == entry.postscriptName
        else { return nil }
        return font
    }
    private func validateQuery(_ query: InstallQuery) throws {
        guard !query.family.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !query.postscriptName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw InstallError.invalidQuery }
    }
    private func conflict(for query: InstallQuery, manifest: InstallManifest) throws -> InstallConflict {
        try validateQuery(query)
        return ConflictChecker.decide(
            query: query, entries: index.entries() + (extraNames?.nameEntries() ?? []),
            ours: { ours($0, manifest: manifest) }, fileExists: { FileManager.default.fileExists(atPath: $0) })
    }
    public func conflict(for query: InstallQuery) throws -> InstallConflict {
        let manifest: InstallManifest
        do { manifest = try readManifest() } catch InstallError.manifestUnsupported { manifest = .init() }
        return try conflict(for: query, manifest: manifest)
    }
    private func validateSource(_ source: URL, query: InstallQuery) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { throw InstallError.sourceMissing }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(source as CFURL) as? [CTFontDescriptor],
            descriptors.count == 1
        else { throw InstallError.unreadable }
        let found = CTFontDescriptorCopyAttribute(descriptors[0], kCTFontNameAttribute) as? String ?? ""
        guard found == query.postscriptName else {
            throw InstallError.unexpectedName(expected: query.postscriptName, found: found)
        }
        guard ForgedMarker.isForged(fileAt: source) else { throw InstallError.notForged }
    }
    private func sweepStaging() throws {
        guard FileManager.default.fileExists(atPath: fontsFolder.path) else { return }
        let expression = try NSRegularExpression(pattern: "^\\..+\\.[0-9a-f]{32}\\.fpinstall$")
        for url in try FileManager.default.contentsOfDirectory(
            at: fontsFolder, includingPropertiesForKeys: [.contentModificationDateKey])
        {
            let name = url.lastPathComponent
            guard expression.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil,
                let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                now().timeIntervalSince(date) > 600
            else { continue }
            try fileSystem.removeFile(url)
        }
    }
    public func install(_ source: URL, expecting query: InstallQuery, confirmed: InstallConflict?) throws
        -> InstalledFont
    {
        var manifest = try readManifest()
        try validateQuery(query)
        do { try sweepStaging() } catch { throw mapped(error, operation: "stage") }
        try validateSource(source, query: query)
        if let current = ours(source.path, manifest: manifest), current.family == query.family,
            current.style == query.style, current.fullName == query.fullName,
            current.postscriptName == query.postscriptName
        {
            return current
        }
        let conflict = try conflict(for: query, manifest: manifest)
        switch conflict {
        case .block: throw InstallError.conflict(conflict)
        case .replaceOurs, .ask: guard confirmed == conflict else { throw InstallError.conflict(conflict) }
        case .noConflict: break
        }
        let stem = InstallFileName.stem(family: query.family, style: query.style)
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let staged = fontsFolder.appendingPathComponent(".\(stem).\(token).fpinstall")
        defer {
            do { try fileSystem.removeFile(staged) } catch {
                logger.error(
                    "Could not clean installation staging file: \(error.localizedDescription, privacy: .public)")
            }
        }
        let copied: (size: Int64, sha256: String)
        do {
            try FileManager.default.createDirectory(at: fontsFolder, withIntermediateDirectories: true)
            copied = try fileSystem.copyAndSync(from: source, to: staged)
        } catch { throw mapped(error, operation: "stage") }
        var placed: URL?
        for number in 0..<100 {
            let candidate = fontsFolder.appendingPathComponent("\(stem)\(number == 0 ? "" : "-\(number)").ttf")
            do { try fileSystem.renameExclusive(staged, to: candidate); placed = candidate; break } catch let error
                as POSIXError where error.code == .EEXIST
            { continue } catch { throw mapped(error, operation: "place") }
        }
        guard let placed else { throw InstallError.noFreeFileName(stem: stem) }
        let font = InstalledFont(
            fileURL: placed, family: query.family, style: query.style, fullName: query.fullName,
            postscriptName: query.postscriptName, sha256: copied.sha256, size: copied.size,
            installedAt: Date(timeIntervalSince1970: floor(now().timeIntervalSince1970)))
        // The exclusive rename proves no file held this name, so an entry for it is stale (a pruning write that
        // failed after an update). `ours` takes the first match, so a stale entry would disown the new copy.
        let placedName = placed.lastPathComponent.precomposedStringWithCanonicalMapping
        manifest.fonts.removeAll { $0.fileName.precomposedStringWithCanonicalMapping == placedName }
        manifest.fonts.append(.init(font))
        do { try writeManifest(manifest) } catch {
            do { try fileSystem.removeFile(placed) } catch {
                logger.error(
                    "Could not roll back an untracked installation: \(error.localizedDescription, privacy: .public)")
            }
            index.invalidate()
            throw error
        }
        var firstFailure: (InstalledFont, String)?
        if case .replaceOurs = conflict {
            for entry in manifest.fonts where entry.fileName != placed.lastPathComponent {
                guard let previous = entry.font(in: fontsFolder),
                    SystemFontNameSource.fold(previous.fullName) == SystemFontNameSource.fold(query.fullName),
                    ours(previous.fileURL.path, manifest: manifest) != nil
                else { continue }
                do { _ = try trash.moveToTrash(previous.fileURL) } catch {
                    if firstFailure == nil { firstFailure = (previous, error.localizedDescription) }
                }
            }
        }
        manifest.fonts.removeAll { entry in
            guard let font = entry.font(in: fontsFolder) else { return false }
            return !FileManager.default.fileExists(atPath: font.fileURL.path)
        }
        do { try writeManifest(manifest) } catch {
            logger.error("Could not prune the installed-font manifest: \(error.localizedDescription, privacy: .public)")
        }
        index.invalidate()
        if let failure = firstFailure {
            throw InstallError.previousCopyNotRemoved(installed: font, previous: failure.0, message: failure.1)
        }
        return font
    }
    public func uninstall(_ font: InstalledFont) throws -> UninstallOutcome {
        var manifest = try readManifest()
        if !FileManager.default.fileExists(atPath: font.fileURL.path) {
            manifest.fonts.removeAll { $0.fileName == font.fileURL.lastPathComponent }
            try writeManifest(manifest); index.invalidate()
            return .notInstalled
        }
        guard ours(font.fileURL.path, manifest: manifest) != nil else {
            throw InstallError.notOurs(name: font.fullName)
        }
        let destination: URL?
        do { destination = try trash.moveToTrash(font.fileURL) } catch { throw mapped(error, operation: "trash") }
        manifest.fonts.removeAll { $0.fileName == font.fileURL.lastPathComponent }
        index.invalidate()
        try writeManifest(manifest)
        return .movedToTrash(destination)
    }
    public func installedFonts() throws -> [InstalledFont] {
        let manifest = try readManifest()
        return manifest.fonts.compactMap { $0.font(in: fontsFolder) }.compactMap {
            ours($0.fileURL.path, manifest: manifest)
        }
        .sorted { $0.fullName < $1.fullName }
    }
}
