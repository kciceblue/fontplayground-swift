import Darwin
import Foundation

struct DiscoveredFile: Hashable, Sendable {
    var path: String
    var origin: FaceOrigin
    var stamp: DiscoveredFileStamp
    var registeredPostscriptNames: [String]
}
struct DiscoveryResult: Sendable {
    var files: [DiscoveredFile] = []
    var skipped: [(path: String, reason: SkipReason)] = []
    var issues: [CatalogIssue] = []
    var registeredFaces: [RegisteredFaceInfo] = []
    var menuVisible: Set<String> = []
}
struct FontDiscovery: Sendable {
    let registry: any SystemFontRegistry
    let configuration: CatalogConfiguration
    func discover(extraFolders: [URL]) -> DiscoveryResult {
        let registered = registry.registeredFontFiles()
        let faces = registry.registeredFaces(includeDisabled: true)
        var result = DiscoveryResult(registeredFaces: faces, menuVisible: registry.menuVisiblePostScriptNames())
        var candidates: [(URL, [String])] = registered.map { (URL(fileURLWithPath: $0.path), $0.postscriptNames) }
        candidates += faces.filter { !$0.enabled }.compactMap { face in face.path.map { (URL(fileURLWithPath: $0), []) }
        }
        let registeredIDs = Set(candidates.compactMap { DiscoveredFileStamp($0.0.path)?.identity })
        let walker = FolderWalker(homeDirectory: configuration.homeDirectory)
        for (folder, report) in configuration.standardFolders.map({ ($0, false) }) + extraFolders.map({ ($0, true) }) {
            let walked = walker.walk(folder, reportMissingRoot: report)
            candidates += walked.files.map { ($0, []) }
            result.skipped += walked.skipped.map { ($0.url.path, $0.reason) }
            result.issues += walked.issues
        }
        var positions: [DiscoveredFileStamp.Identity: Int] = [:]
        var locations: [String: Bool] = [:]
        var failed: Set<String> = []
        for (url, names) in candidates {
            var statValue = stat()
            let status = stat(url.path, &statValue), error = errno
            guard status == 0, statValue.st_mode & S_IFMT == S_IFREG, let stamp = DiscoveredFileStamp(url.path) else {
                // A listed path can vanish, lose access or stop being a file before this stat; a refresh must say
                // so rather than prune its faces silently.
                if failed.insert(url.path).inserted {
                    result.issues.append(Self.discoveryFailure(url.path, status: status, errno: error))
                }
                continue
            }
            if let index = positions[stamp.identity] {
                var seen = Set(result.files[index].registeredPostscriptNames)
                result.files[index].registeredPostscriptNames += names.filter { seen.insert($0).inserted }
                continue
            }
            let parent = url.deletingLastPathComponent().path
            let user = locations[parent] ?? DiscoveredFileStamp.inside(url, folder: configuration.userFontsFolder)
            locations[parent] = user
            positions[stamp.identity] = result.files.count
            result.files.append(
                .init(
                    path: url.path,
                    origin: .classify(
                        path: url.path, isInsideUserFolder: user, isRegistered: registeredIDs.contains(stamp.identity)),
                    stamp: stamp, registeredPostscriptNames: names))
        }
        // Aliased roots may report the same skipped entry more than once.
        var skipped: Set<String> = []
        result.skipped = result.skipped.filter { skipped.insert($0.path + "|" + $0.reason.rawValue).inserted }
        return result
    }
    static func discoveryFailure(_ path: String, status: Int32, errno error: Int32) -> CatalogIssue {
        if status != 0 && error == ENOENT {
            return .unreadable(path: path, code: "not_found", message: "File not found.")
        }
        if status == 0 { return .unreadable(path: path, code: "io_error", message: "Not a regular file.") }
        return .unreadable(path: path, code: "io_error", message: String(cString: strerror(error)) + ".")
    }
    enum FormatProbe: Equatable, Sendable {
        case sfnt, other
        case unreadable(errno: Int32)
    }
    /// Sniffs the first four bytes. A file that cannot be opened or read gets no format verdict (review M2): calling a
    /// font the user cannot read "unsupported" would send them looking at the wrong problem.
    static func probeFormat(_ path: String) -> FormatProbe {
        let descriptor = open(path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return .unreadable(errno: errno) }
        defer { close(descriptor) }
        var bytes: [UInt8] = [0, 0, 0, 0]
        var count = 0
        while count < bytes.count {
            let got = bytes.withUnsafeMutableBytes { read(descriptor, $0.baseAddress! + count, 4 - count) }
            if got > 0 {
                count += got
            } else if got == 0 {
                break
            } else {
                let code = errno
                if code != EINTR { return .unreadable(errno: code) }
            }
        }
        // Shorter than any sfnt header: not a font, whatever its extension says.
        guard count == bytes.count else { return .other }
        let magic = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return MacServicesConstants.sfntMagics.contains(magic) ? .sfnt : .other
    }
}
