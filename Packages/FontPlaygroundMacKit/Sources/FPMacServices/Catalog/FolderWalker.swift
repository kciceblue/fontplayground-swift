import Darwin
import Foundation

struct DiscoveredFileStamp: Hashable, Codable, Sendable {
    var size: Int64
    var mtime: Double
    var device: UInt64
    var inode: UInt64
    struct Identity: Hashable, Sendable { var device: UInt64; var inode: UInt64 }
    var identity: Identity { .init(device: device, inode: inode) }
    init?(_ path: String) {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        size = info.st_size
        mtime = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9
        device = UInt64(UInt32(bitPattern: info.st_dev)); inode = info.st_ino
    }
    static func inside(_ file: URL, folder: URL) -> Bool {
        guard let target = Self(folder.path)?.identity else { return false }
        var parent = file.deletingLastPathComponent()
        while true {
            guard let stamp = Self(parent.path) else { return false }
            if stamp.identity == target { return true }
            let next = parent.deletingLastPathComponent()
            if next.path == parent.path { return false }
            parent = next
        }
    }
}
struct WalkResult: Sendable {
    var files: [URL] = []
    var skipped: [(url: URL, reason: SkipReason)] = []
    var issues: [CatalogIssue] = []
}
struct FolderWalker: Sendable {
    let homeDirectory: URL
    var maxDepth: Int = 32
    private let packages: Set<String> = [
        "app", "bundle", "framework", "photoslibrary", "plugin", "kext", "xpc", "appex",
    ]
    func walk(_ root: URL, reportMissingRoot: Bool) -> WalkResult {
        var result = WalkResult()
        guard root.path.hasPrefix("/") else {
            if reportMissingRoot { result.issues.append(.folderMissing(folder: root.path)) }
            return result
        }
        var info = stat()
        if stat(root.path, &info) != 0 {
            let code = errno
            if code == EACCES || code == EPERM {
                result.issues.append(.noAccess(folder: root.path))
            } else if code == ENOENT || code == ENOTDIR {
                if reportMissingRoot { result.issues.append(.folderMissing(folder: root.path)) }
            } else {
                result.issues.append(.folderUnreadable(folder: root.path, message: String(cString: strerror(code))))
            }
            return result
        }
        guard info.st_mode & S_IFMT == S_IFDIR else {
            if reportMissingRoot { result.issues.append(.folderMissing(folder: root.path)) }
            return result
        }
        let excluded = ["Library/Containers", "Library/Group Containers"].map {
            homeDirectory.appendingPathComponent($0)
        }
        let excludedIDs = Set(excluded.compactMap { DiscoveredFileStamp($0.path)?.identity })
        var visited: Set<DiscoveredFileStamp.Identity> = []
        func descend(_ directory: URL, depth: Int) {
            guard depth <= maxDepth, let stamp = DiscoveredFileStamp(directory.path),
                !excludedIDs.contains(stamp.identity),
                !excluded.contains(where: { directory.standardizedFileURL.path == $0.standardizedFileURL.path }),
                visited.insert(stamp.identity).inserted
            else { return }
            // CRIT-5: Foundation hides AppleDouble sidecars; POSIX entries let us count them explicitly.
            guard let handle = opendir(directory.path) else {
                let code = errno
                result.issues.append(
                    code == EACCES || code == EPERM
                        ? .noAccess(folder: directory.path)
                        : .folderUnreadable(folder: directory.path, message: String(cString: strerror(code))))
                return
            }
            defer { closedir(handle) }
            var names: [String] = []
            errno = 0
            while let entry = readdir(handle) {
                let name = withUnsafeBytes(of: entry.pointee.d_name) { bytes in
                    String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
                }
                if name != "." && name != ".." { names.append(name) }
                errno = 0
            }
            if errno != 0 {
                result.issues.append(
                    .folderUnreadable(folder: directory.path, message: String(cString: strerror(errno))))
            }
            for name in names.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
                let url = directory.appendingPathComponent(name)
                if name.hasPrefix("._") { result.skipped.append((url, .appleDouble)); continue }
                var info = stat()
                guard stat(url.path, &info) == 0 else {
                    let code = errno
                    if code == EACCES || code == EPERM {
                        result.issues.append(.noAccess(folder: url.path))
                    } else if code != ENOENT {
                        result.issues.append(
                            .folderUnreadable(folder: url.path, message: String(cString: strerror(code))))
                    }
                    continue
                }
                let isDirectory = info.st_mode & S_IFMT == S_IFDIR
                let ext = url.pathExtension.lowercased()
                if name.hasPrefix(".") {
                    if !isDirectory && MacServicesConstants.fontExtensions.contains(ext) {
                        result.skipped.append((url, .hiddenFile))
                    }
                    continue
                }
                if isDirectory {
                    guard name != "__MACOSX", !packages.contains(ext),
                        (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) != true
                    else { continue }
                    descend(url, depth: depth + 1)
                } else if info.st_mode & S_IFMT == S_IFREG {
                    if MacServicesConstants.fontExtensions.contains(ext) {
                        result.files.append(url)
                    } else if MacServicesConstants.unsupportedFontExtensions.contains(ext) {
                        result.skipped.append((url, .unsupportedFormat))
                    }
                }
            }
        }
        descend(root, depth: 0)
        return result
    }
}
