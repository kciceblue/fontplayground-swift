import FPEngineClient
import Foundation

enum FontFolders {
    private static let extensions: Set<String> = ["ttf", "otf", "ttc", "otc"]
    /// AppleDouble files, archive metadata and Trash folders met while walking a folder. Paths the user names are
    /// never filtered: a file reaches the helper, which reports it, and a folder is walked (no silent drops).
    private static func ignored(name: String) -> Bool {
        name.hasPrefix("._") || name == "__MACOSX" || name == ".Trashes"
    }
    struct ScanInput {
        var files: [String]
        var errors: [ScanFileError] = []
    }
    typealias Enumeration = (URL, @escaping (URL, any Error) -> Bool) -> FileManager.DirectoryEnumerator?
    static func files(
        in paths: [String], fileManager: FileManager = .default, enumerate: Enumeration? = nil
    ) -> ScanInput {
        let enumerate =
            enumerate ?? { url, handler in
                fileManager.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], errorHandler: handler)
            }
        var result = ScanInput(files: [])
        for path in paths {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                // Explicit files, including missing ones, reach the helper so it reports their failures.
                result.files.append(path)
                continue
            }
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            let previousErrorCount = result.errors.count
            let walk = enumerate(folder) { url, error in
                result.errors.append(
                    .init(path: url.standardizedFileURL.path, code: .ioError, message: error.localizedDescription))
                return true
            }
            guard let walk else {
                if result.errors.count == previousErrorCount {
                    result.errors.append(.init(path: path, code: .ioError, message: "Couldn't read this folder."))
                }
                continue
            }
            var files: [String] = []
            for case let url as URL in walk {
                if ignored(name: url.lastPathComponent) { walk.skipDescendants(); continue }
                guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                do {
                    if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory != true {
                        files.append(url.standardizedFileURL.path)
                    }
                } catch {
                    result.errors.append(
                        .init(path: url.standardizedFileURL.path, code: .ioError, message: error.localizedDescription))
                }
            }
            result.files += files.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        }
        return result
    }
    static func defaults(environment: [String: String], fileManager: FileManager = .default) -> [String] {
        var paths = ["/System/Library/Fonts", "/Library/Fonts"]
        if let home = environment["HOME"], !home.isEmpty {
            paths.append(URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Library/Fonts").path)
        }
        let assets = "/System/Library/AssetsV2"
        let folders = (try? fileManager.contentsOfDirectory(atPath: assets)) ?? []
        paths += folders.filter { $0.hasPrefix("com_apple_MobileAsset_Font") }
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            .map { assets + "/" + $0 }
        return paths.filter {
            var directory: ObjCBool = false
            return fileManager.fileExists(atPath: $0, isDirectory: &directory) && directory.boolValue
        }
    }
}
